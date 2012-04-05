/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class PreferencesDialog : Object {
    private Gtk.Dialog dialog;
    private Gtk.CheckButton autoselect;
    private Gtk.CheckButton display_preview;
    private Gtk.CheckButton spell_check;
    private Gtk.Button close_button;
    private Configuration config;
    
    public PreferencesDialog(Configuration config) {
        this.config = config;
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        // Get all of the dialog elements.
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        autoselect = builder.get_object("autoselect") as Gtk.CheckButton;
        display_preview = builder.get_object("display_preview") as Gtk.CheckButton;
        spell_check = builder.get_object("spell_check") as Gtk.CheckButton;
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        // Populate the dialog with our current settings.
        autoselect.active = config.autoselect;
        display_preview.active = config.display_preview;
        spell_check.active = config.spell_check;
        
        // Connect to element signals.
        autoselect.toggled.connect(on_autoselect_toggled);
        display_preview.toggled.connect(on_display_preview_toggled);
        spell_check.toggled.connect(on_spell_check_toggled);
        
        GearyApplication.instance.exiting.connect(on_exit);
    }
    
    public void run() {
        if (dialog.run() != Gtk.ResponseType.NONE) {
            dialog.destroy();
        }
    }
    
    private void on_exit(bool panicked) {
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
}

