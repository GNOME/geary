/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Libmessagingmenu : NewMessagesIndicator {
#if HAVE_LIBMESSAGINGMENU
    private const string NEW_MESSAGES_ID = "new-messages-id";
    
    private MessagingMenu.App? app = null;
    
    public Libmessagingmenu(NewMessagesMonitor monitor) {
        base (monitor);
        
        File? desktop_file = GearyApplication.instance.get_desktop_file();
        if (desktop_file == null
            || !desktop_file.get_parent().equal(GearyApplication.instance.system_desktop_file_directory)) {
            debug("Only an installed version of Geary with its .desktop file installed can use Messaging Menu");
            
            return;
        }
        
        app = new MessagingMenu.App("geary.desktop");
        app.register();
        app.activate_source.connect(on_activate_source);
        
        monitor.notify["count"].connect(on_new_messages_changed);
        
        debug("Registered messaging-menu indicator");
    }
    
    ~Libmessagingmenu() {
        if (app != null)
            monitor.notify["count"].disconnect(on_new_messages_changed);
    }
    
    private void on_activate_source(string source_id) {
        if (source_id == NEW_MESSAGES_ID)
            inbox_activated(now());
    }
    
    private void on_new_messages_changed() {
        if (monitor.count > 0)
            show_new_messages_count();
        else
            remove_new_messages_count();
    }
    
    private void show_new_messages_count() {
        if (app.has_source(NEW_MESSAGES_ID))
            app.set_source_count(NEW_MESSAGES_ID, monitor.count);
        else
            app.append_source_with_count(NEW_MESSAGES_ID, null, _("New Messages"), monitor.count);
        
        app.draw_attention(NEW_MESSAGES_ID);
    }
    
    private void remove_new_messages_count() {
        if (app.has_source(NEW_MESSAGES_ID)) {
            app.remove_attention(NEW_MESSAGES_ID);
            app.remove_source(NEW_MESSAGES_ID);
        }
    }
#else
    public Libmessagingmenu(NewMessagesMonitor monitor) {
        base (monitor);
    }
#endif
}

