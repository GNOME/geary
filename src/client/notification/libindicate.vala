/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Libindicate : NewMessagesIndicator {
#if HAVE_LIBINDICATE
    private Indicate.Server? indicator = null;
    private Indicate.Indicator? compose = null;
    private Gee.HashMap<Geary.Folder, Indicate.Indicator> folder_indicators
        = new Gee.HashMap<Geary.Folder, Indicate.Indicator>();
    
    public Libindicate(NewMessagesMonitor monitor) {
        base (monitor);
        
        // Find the desktop file this app instance is using (running from build dir vs. install dir)
        File? desktop_file = GearyApplication.instance.get_desktop_file();
        if (desktop_file == null) {
            debug("Unable to setup libindicate support: no desktop file found");
            
            return;
        }
        
        debug("Using libindicate for messaging menu support w/ .desktop file %s", desktop_file.get_path());
        
        indicator = Indicate.Server.ref_default();
        indicator.set_type("message.email");
        indicator.set_desktop_file(desktop_file.get_path());
        indicator.server_display.connect(on_display_server);
        
        // Create "Compose Message" option and always display it
        compose = new Indicate.Indicator.with_server(indicator);
        compose.set_property_variant("name", _("Compose Message"));
        compose.user_display.connect(on_activate_composer);
        compose.show();
        
        monitor.folder_added.connect(on_folder_added);
        monitor.folder_removed.connect(on_folder_removed);
        monitor.new_messages_arrived.connect(on_new_messages_changed);
        monitor.new_messages_retired.connect(on_new_messages_changed);
        
        indicator.show();
    }
    
    ~Libindicate() {
        if (indicator != null) {
            monitor.folder_added.disconnect(on_folder_added);
            monitor.folder_removed.disconnect(on_folder_removed);
            monitor.new_messages_arrived.disconnect(on_new_messages_changed);
            monitor.new_messages_retired.disconnect(on_new_messages_changed);
        }
    }
    
    private void on_folder_added(Geary.Folder folder) {
        // Create "New Messages" option which is only displayed if new messages are available
        Indicate.Indicator folder_indicator  = new Indicate.Indicator.with_server(indicator);
        folder_indicator.set_property_variant("name",
            _("%s - New Messages").printf(folder.account.information.nickname));
        
        // Use a lambda here (as opposed to an on_activate_inbox method) so we
        // can still get to the folder ref to pass to the signal.
        folder_indicator.user_display.connect(
            (timestamp) => { inbox_activated(folder, timestamp); });
        
        folder_indicators.set(folder, folder_indicator);
    }
    
    private void on_folder_removed(Geary.Folder folder) {
        Indicate.Indicator folder_indicator;
        folder_indicators.unset(folder, out folder_indicator);
        folder_indicator.hide();
    }
    
    private void on_new_messages_changed(Geary.Folder folder, int count) {
        Indicate.Indicator folder_indicator = folder_indicators.get(folder);
        
        if (count > 0) {
            if (!monitor.should_notify_new_messages(folder))
                return;
            
            // count is in fact a string property
            folder_indicator.set_property_variant("count", count.to_string());
            folder_indicator.set_property_bool("draw-attention", true);
            
            folder_indicator.show();
        } else {
            folder_indicator.hide();
        }
    }
    
    private void on_display_server(uint timestamp) {
        application_activated(timestamp);
    }
    
    private void on_activate_composer(uint timestamp) {
        composer_activated(timestamp);
    }
#else
    public Libindicate(NewMessagesMonitor monitor) {
        base (monitor);
    }
#endif
}

