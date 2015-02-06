/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class UnityLauncher : Geary.BaseObject {
#if HAVE_LIBUNITY
    private NewMessagesMonitor? monitor = null;
    private Unity.LauncherEntry? entry = null;
    
    public UnityLauncher(NewMessagesMonitor monitor) {
        this.monitor = monitor;
        
        entry = Unity.LauncherEntry.get_for_desktop_id("geary.desktop");
        set_count(0);
        
        monitor.folder_removed.connect(on_folder_removed);
        monitor.new_messages_arrived.connect(on_new_messages_changed);
        monitor.new_messages_retired.connect(on_new_messages_changed);
    }
    
    ~UnityLauncher() {
        monitor.folder_removed.disconnect(on_folder_removed);
        monitor.new_messages_arrived.disconnect(on_new_messages_changed);
        monitor.new_messages_retired.disconnect(on_new_messages_changed);
    }
    
    private void update_count() {
        // This is the dead-simple approach.  It could be optimized, but
        // doesn't seem like it's worth too much effort.
        int count = 0;
        foreach (Geary.Folder folder in monitor.get_folders()) {
            if (monitor.should_notify_new_messages(folder))
                count += monitor.get_new_message_count(folder);
        }
        
        set_count(count);
    }
    
    private void set_count(int count) {
        entry.count = count;
        entry.count_visible = (count != 0);
        debug("set unity launcher entry count to %s", entry.count.to_string());
    }
    
    private void on_new_messages_changed() {
        update_count();
    }
    
    private void on_folder_removed() {
        update_count();
    }
#else
    public UnityLauncher(NewMessagesMonitor monitor) {
    }
#endif
}

