/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

MainLoop? main_loop = null;
Geary.Imap.ClientSessionManager? sess = null;
string? mailbox = null;
int start = 0;
int count = 0;

async void async_start() {
    try {
        Geary.Folder folder = yield sess.open(mailbox);
        
        bool ok = false;
        Gee.List<Geary.EmailHeader>? msgs = yield folder.read(start, count);
        if (msgs != null && msgs.size > 0) {
            foreach (Geary.EmailHeader msg in msgs)
                stdout.printf("%s\n", msg.to_string());
            
            ok = true;
        }
        
        if (!ok)
            debug("Unable to examine mailbox %s", mailbox);
    } catch (Error err) {
        debug("Error: %s", err.message);
    }
    
    main_loop.quit();
}

int main(string[] args) {
    if (args.length < 6) {
        stderr.printf("usage: lsmbox <user> <pass> <mailbox> <start #> <count>\n");
        
        return 1;
    }
    
    main_loop = new MainLoop();
    
    string user = args[1];
    string pass = args[2];
    mailbox = args[3];
    start = int.parse(args[4]);
    count = int.parse(args[5]);
    
    sess = new Geary.Imap.ClientSessionManager("imap.gmail.com", 993, user, pass);
    async_start.begin();
    
    main_loop.run();
    
    return 0;
}

