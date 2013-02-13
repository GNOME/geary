/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class UnityLauncher : Object {
#if HAVE_LIBUNITY
    private NewMessagesMonitor? monitor = null;
    private Unity.LauncherEntry? entry = null;
    
    public UnityLauncher(NewMessagesMonitor monitor) {
        this.monitor = monitor;
        
        entry = Unity.LauncherEntry.get_for_desktop_id("geary.desktop");
        set_count(0);
        
        monitor.notify["total-count"].connect(on_new_messages_changed);
    }
    
    ~UnityLauncher() {
        monitor.notify["total-count"].disconnect(on_new_messages_changed);
    }
    
    private void set_count(int count) {
        entry.count = count;
        entry.count_visible = (count != 0);
        debug("set unity launcher entry count to %s", entry.count.to_string());
    }
    
    private void on_new_messages_changed() {
        if (monitor.total_count == 0 || monitor.should_notify_new_messages())
            set_count(monitor.total_count);
    }
#else
    public UnityLauncher(NewMessagesMonitor monitor) {
    }
#endif
}

