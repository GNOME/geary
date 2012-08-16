/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Libindicate : NewMessagesIndicator {
#if HAVE_LIBINDICATE
    private Indicate.Server indicator;
    private Indicate.Indicator compose;
    private Indicate.Indicator inbox;
    
    public Libindicate() {
        debug("Using libindicate for messaging menu support");
        
        indicator = Indicate.Server.ref_default();
        indicator.set_type("message.email");
        
        // Find the desktop file this app instance is using (running from build dir vs. install dir)
        File desktop_file = GearyApplication.instance.get_resource_directory().get_child("geary.desktop");
        if (!desktop_file.query_exists())
            desktop_file = File.new_for_path("/usr/share/applications/geary.desktop");
        
        indicator.set_desktop_file(desktop_file.get_path());
        indicator.server_display.connect(on_display_server);
        
        // Create "Compose Message" option and always display it
        compose = new Indicate.Indicator.with_server(indicator);
        compose.set_property_variant("name", _("Compose Message"));
        compose.user_display.connect(on_activate_composer);
        compose.show();
        
        // Create "New Messages" option which is only displayed if new messages are available
        inbox = new Indicate.Indicator.with_server(indicator);
        inbox.set_property_variant("name", _("New Messages"));
        inbox.user_display.connect(on_activate_inbox);
        
        notify["count"].connect(on_new_messages_changed);
        
        indicator.show();
    }
    
    private void on_new_messages_changed() {
        if (count > 0) {
            // count is in fact a string property
            inbox.set_property_variant("count", count.to_string());
            inbox.set_property_bool("draw-attention", true);
            
            inbox.show();
        } else {
            inbox.hide();
        }
    }
    
    private void on_display_server(uint timestamp) {
        application_activated(timestamp);
    }
    
    private void on_activate_composer(uint timestamp) {
        composer_activated(timestamp);
    }
    
    private void on_activate_inbox(uint timestamp) {
        inbox_activated(timestamp);
    }
#endif
}

