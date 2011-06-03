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

void on_exists(int exists) {
    stdout.printf("EXISTS: %d\n", exists);
}

void on_expunged(Geary.Imap.MessageNumber expunged) {
    stdout.printf("EXPUNGED: %d\n", expunged.value);
}

void on_recent(int recent) {
    stdout.printf("RECENT: %d\n", recent);
}

async void async_start() {
    try {
        yield sess.connect_async();
        yield sess.login_async(user, pass);
        yield sess.examine_async(mailbox);
        
        sess.unsolicited_exists.connect(on_exists);
        sess.unsolicited_expunged.connect(on_expunged);
        sess.unsolicited_recent.connect(on_recent);
        
        sess.enable_keepalives(5);
    } catch (Error err) {
        debug("Error: %s", err.message);
    }
}

int main(string[] args) {
    if (args.length < 4) {
        stderr.printf("usage: watchmbox <user> <pass> <mailbox>\n");
        
        return 1;
    }
    
    main_loop = new MainLoop();
    
    user = args[1];
    pass = args[2];
    mailbox = args[3];
    
    sess = new Geary.Imap.ClientSession("imap.gmail.com", 993);
    async_start.begin();
    
    stdout.printf("Watching %s, Ctrl+C to exit...\n", mailbox);
    main_loop.run();
    
    return 0;
}

