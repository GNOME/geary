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
        File? desktop_file = GearyApplication.instance.get_desktop_file();
        if (desktop_file == null) {
            debug("Unable to setup Unity Launcher support: desktop file not found");
            
            return;
        }
        
        this.monitor = monitor;
        
        //entry = Unity.LauncherEntry.get_for_desktop_file(desktop_file.get_path());
        entry = Unity.LauncherEntry.get_for_desktop_id("geary.desktop");
        set_count(0);
        
        monitor.notify["count"].connect(on_new_messages_changed);
    }
    
    ~UnityLauncher() {
        monitor.notify["count"].disconnect(on_new_messages_changed);
    }
    
    private void set_count(int count) {
        entry.count = count;
        entry.count_visible = (count != 0);
        debug("set unity launcher entry count to %s", entry.count.to_string());
    }
    
    private void on_new_messages_changed() {
        set_count(monitor.count);
    }
#else
    public UnityLauncher(NewMessagesMonitor monitor) {
    }
#endif
}

