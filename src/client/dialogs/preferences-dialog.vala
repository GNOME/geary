/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class PreferencesDialog : Object {
    private static PreferencesDialog? preferences_dialog = null;
    
    private Gtk.Dialog dialog;
    private Gtk.CheckButton autoselect;
    private Gtk.CheckButton display_preview;
    private Gtk.CheckButton spell_check;
    private Gtk.CheckButton play_sounds;
    private Gtk.CheckButton show_notifications;
    private Gtk.Button close_button;
    private Configuration config;
    
    private PreferencesDialog(Configuration config) {
        this.config = config;
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        // Get all of the dialog elements.
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        autoselect = builder.get_object("autoselect") as Gtk.CheckButton;
        display_preview = builder.get_object("display_preview") as Gtk.CheckButton;
        spell_check = builder.get_object("spell_check") as Gtk.CheckButton;
        play_sounds = builder.get_object("play_sounds") as Gtk.CheckButton;
        show_notifications = builder.get_object("show_notifications") as Gtk.CheckButton;
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        populate_preference_options();
        
        // Connect to element signals.
        autoselect.toggled.connect(on_autoselect_toggled);
        display_preview.toggled.connect(on_display_preview_toggled);
        spell_check.toggled.connect(on_spell_check_toggled);
        play_sounds.toggled.connect(on_play_sounds_toggled);
        show_notifications.toggled.connect(on_show_notifications_toggled);
        
        dialog.delete_event.connect(on_delete);
        dialog.response.connect(on_close);
    }
    
    public void populate_preference_options() {
        autoselect.active = config.autoselect;
        display_preview.active = config.display_preview;
        spell_check.active = config.spell_check;
        play_sounds.active = config.play_sounds;
        show_notifications.active = config.show_notifications;    
    }
    
    public static void show_instance() {
        if (preferences_dialog == null) 
            preferences_dialog = new PreferencesDialog(GearyApplication.instance.config);
        
        preferences_dialog.populate_preference_options();
        preferences_dialog.dialog.show_all();
        preferences_dialog.dialog.present();
    }
    
    private bool on_delete() {
        return dialog.hide_on_delete(); //prevent widgets from getting destroyed
    }
    
    private void on_close() {
        dialog.hide();
    }
    
    private void on_autoselect_toggled() {
        config.autoselect = autoselect.active;
    }
    
    private void on_display_preview_toggled() {
        config.display_preview = display_preview.active;
    }
    
    private void on_spell_check_toggled() {
        config.spell_check = spell_check.active;
    }

    private void on_play_sounds_toggled() {
        config.play_sounds = play_sounds.active;
    }

    private void on_show_notifications_toggled() {
        config.show_notifications = show_notifications.active;
    }
}

