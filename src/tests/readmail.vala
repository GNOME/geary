/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

MainLoop? main_loop = null;
Geary.Imap.ClientSession? sess = null;
string? user = null;
string? pass = null;
string? mailbox = null;
int msg_num = 0;

async void async_start() {
    try {
        yield sess.connect_async();
        yield sess.login_async(user, pass);
        yield sess.examine_async(mailbox);
        
        Geary.Imap.FetchCommand fetch = new Geary.Imap.FetchCommand(sess.generate_tag(),
            new Geary.Imap.MessageSet(msg_num), { Geary.Imap.FetchDataType.RFC822 });
        Geary.Imap.CommandResponse resp = yield sess.send_command_async(fetch);
        Geary.Imap.FetchResults[] results = Geary.Imap.FetchResults.decode(resp);
        
        assert(results.length == 1);
        Geary.RFC822.Full? full =
            results[0].get_data(Geary.Imap.FetchDataType.RFC822) as Geary.RFC822.Full;
        assert(full != null);
        
        DataInputStream dins = new DataInputStream(full.buffer.get_input_stream());
        dins.set_newline_type(DataStreamNewlineType.CR_LF);
        for (;;) {
            string? line = dins.read_line(null);
            if (line == null)
                break;
            
            stdout.printf("%s\n", line);
        }
        
        yield sess.close_mailbox_async();
        
        yield sess.logout_async();
        yield sess.disconnect_async();
    } catch (Error err) {
        debug("Error: %s", err.message);
    }
    
    main_loop.quit();
}

int main(string[] args) {
    if (args.length < 5) {
        stderr.printf("usage: readmail <user> <pass> <mailbox> <msg #>\n");
        
        return 1;
    }
    
    main_loop = new MainLoop();
    
    user = args[1];
    pass = args[2];
    mailbox = args[3];
    msg_num = int.parse(args[4]);
    
    sess = new Geary.Imap.ClientSession("imap.gmail.com", 993);
    async_start.begin();
    
    main_loop.run();
    
    return 0;
}

