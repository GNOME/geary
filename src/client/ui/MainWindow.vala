/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MainWindow : Gtk.Window {
    private MessageListStore message_list_store = new MessageListStore();
    private MessageListView message_list_view;
    
    private Geary.Engine? engine = null;
    
    public MainWindow() {
        set_default_size(800, 600);
        
        message_list_view = new MessageListView(message_list_store);
        
        create_layout();
    }
    
    public void login(Geary.Engine engine, string user, string pass) {
        this.engine = engine;
        
        do_login.begin(user, pass);
    }
    
    private async void do_login(string user, string pass) {
        try {
            Geary.Account? account = yield engine.login("imap.gmail.com", user, pass);
            if (account == null)
                error("Unable to login");
            
            Geary.Folder folder = yield account.open("inbox");
            
            Geary.MessageStream? msg_stream = folder.read(1, 100);
            if (msg_stream == null)
                error("Unable to read from folder");
            
            Gee.List<Geary.Message>? msgs = yield msg_stream.read();
            if (msgs != null && msgs.size > 0) {
                foreach (Geary.Message msg in msgs)
                    message_list_store.append_message(msg);
            }
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public override void destroy() {
        GearyApplication.instance.exit();
        
        base.destroy();
    }
    
    private void create_layout() {
        Gtk.ScrolledWindow message_list_scrolled = new Gtk.ScrolledWindow(null, null);
        message_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_list_scrolled.add_with_viewport(message_list_view);
        
        add(message_list_scrolled);
    }
}

