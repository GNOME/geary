/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class PreferencesDialog : Object {
    private Gtk.Dialog dialog;
    private Gtk.CheckButton autoselect;
    private Gtk.CheckButton display_preview;
    private Gtk.Button close_button;
    private Configuration config;
    
    public PreferencesDialog(Configuration config) {
        this.config = config;
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        // Get all of the dialog elements.
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        autoselect = builder.get_object("autoselect") as Gtk.CheckButton;
        display_preview = builder.get_object("display_preview") as Gtk.CheckButton;
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        // Populate the dialog with our current settings.
        autoselect.active = config.autoselect;
        display_preview.active = config.display_preview;
        
        // Connect to element signals.
        autoselect.toggled.connect(on_autoselect_toggled);
        display_preview.toggled.connect(on_display_preview_toggled);
    }
    
    public void run() {
        dialog.run();
        dialog.destroy();
    }
    
    private void on_autoselect_toggled() {
        config.autoselect = autoselect.active;
    }
    
    private void on_display_preview_toggled() {
        config.display_preview = display_preview.active;
    }
}
