/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Libmessagingmenu : NewMessagesIndicator {
#if HAVE_LIBMESSAGINGMENU
    private MessagingMenu.App? app = null;
    
    public Libmessagingmenu(NewMessagesMonitor monitor) {
        base (monitor);
        
        File? desktop_file = GearyApplication.instance.get_desktop_file();
        if (desktop_file == null
            || !desktop_file.has_prefix(GearyApplication.instance.get_install_prefix_dir())) {
            debug("Only an installed version of Geary with its .desktop file installed can use Messaging Menu");
            
            return;
        }
        
        app = new MessagingMenu.App("geary.desktop");
        app.register();
        app.activate_source.connect(on_activate_source);
        
        monitor.folder_removed.connect(on_folder_removed);
        monitor.new_messages_arrived.connect(on_new_messages_changed);
        monitor.new_messages_retired.connect(on_new_messages_changed);
        
        debug("Registered messaging-menu indicator");
    }
    
    ~Libmessagingmenu() {
        if (app != null) {
            monitor.folder_removed.disconnect(on_folder_removed);
            monitor.new_messages_arrived.disconnect(on_new_messages_changed);
            monitor.new_messages_retired.disconnect(on_new_messages_changed);
        }
    }
    
    private string get_source_id(Geary.Folder folder) {
        return "new-messages-id-%s-%s".printf(folder.account.information.email, folder.path.to_string());
    }
    
    private void on_activate_source(string source_id) {
        foreach (Geary.Folder folder in monitor.get_folders()) {
            if (source_id == get_source_id(folder)) {
                inbox_activated(folder, now());
                break;
            }
        }
    }
    
    private void on_new_messages_changed(Geary.Folder folder, int count) {
        if (count > 0)
            show_new_messages_count(folder, count);
        else
            remove_new_messages_count(folder);
    }
    
    private void on_folder_removed(Geary.Folder folder) {
        remove_new_messages_count(folder);
    }
    
    private void show_new_messages_count(Geary.Folder folder, int count) {
        if (!GearyApplication.instance.config.show_notifications || !monitor.should_notify_new_messages(folder))
            return;
        
        string source_id = get_source_id(folder);
        
        if (app.has_source(source_id))
            app.set_source_count(source_id, count);
        else
            app.append_source_with_count(source_id, null,
                _("%s - New Messages").printf(folder.account.information.nickname), count);
        
        app.draw_attention(source_id);
    }
    
    private void remove_new_messages_count(Geary.Folder folder) {
        string source_id = get_source_id(folder);
        
        if (app.has_source(source_id)) {
            app.remove_attention(source_id);
            app.remove_source(source_id);
        }
    }
#else
    public Libmessagingmenu(NewMessagesMonitor monitor) {
        base (monitor);
    }
#endif
}

