/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class PreferencesDialog : Object {
    private Gtk.Dialog dialog;
    private Gtk.CheckButton autoselect;
    private Gtk.CheckButton display_preview;
    private Gtk.CheckButton spell_check;
    private Gtk.CheckButton play_sounds;
    private Gtk.CheckButton show_notifications;
    private Gtk.Button close_button;
    private Configuration config;
    
    public PreferencesDialog(Gtk.Window parent) {
        this.config = GearyApplication.instance.config;
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        // Get all of the dialog elements.
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        dialog.set_transient_for(parent);
        dialog.set_modal(true);
        
        autoselect = builder.get_object("autoselect") as Gtk.CheckButton;
        display_preview = builder.get_object("display_preview") as Gtk.CheckButton;
        spell_check = builder.get_object("spell_check") as Gtk.CheckButton;
        play_sounds = builder.get_object("play_sounds") as Gtk.CheckButton;
        show_notifications = builder.get_object("show_notifications") as Gtk.CheckButton;
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        autoselect.active = config.autoselect;
        display_preview.active = config.display_preview;
        spell_check.active = config.spell_check;
        play_sounds.active = config.play_sounds;
        show_notifications.active = config.show_notifications;
        
        // Connect to element signals.
        autoselect.toggled.connect(on_autoselect_toggled);
        display_preview.toggled.connect(on_display_preview_toggled);
        spell_check.toggled.connect(on_spell_check_toggled);
        play_sounds.toggled.connect(on_play_sounds_toggled);
        show_notifications.toggled.connect(on_show_notifications_toggled);
    }
    
    public void run() {
        dialog.show_all();
        dialog.run();
        dialog.destroy();
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

