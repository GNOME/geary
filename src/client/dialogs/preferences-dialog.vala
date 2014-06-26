/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class PreferencesDialog : Object {
    private Gtk.Dialog dialog;
    
    public PreferencesDialog(Gtk.Window parent) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        // Get all of the dialog elements.
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        dialog.set_transient_for(parent);
        dialog.set_modal(true);
        
        Configuration config = GearyApplication.instance.config;
        config.bind(Configuration.AUTOSELECT_KEY, builder.get_object("autoselect"), "active");
        config.bind(Configuration.DISPLAY_PREVIEW_KEY, builder.get_object("display_preview"), "active");
        config.bind(Configuration.SPELL_CHECK_KEY, builder.get_object("spell_check"), "active");
        config.bind(Configuration.PLAY_SOUNDS_KEY, builder.get_object("play_sounds"), "active");
        config.bind(Configuration.SHOW_NOTIFICATIONS_KEY, builder.get_object("show_notifications"), "active");
        config.bind(Configuration.STARTUP_NOTIFICATIONS_KEY, builder.get_object("startup_notifications"), "active");
    }
    
    public void run() {
        // Sync startup notification option with file state
        GearyApplication.instance.controller.autostart_manager.sync_with_config();
        dialog.show_all();
        dialog.run();
        dialog.destroy();
    }
}

