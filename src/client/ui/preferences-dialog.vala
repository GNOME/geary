/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class PreferencesDialog : Object {
    private Gtk.Dialog dialog;
    private Gtk.CheckButton autoselect;
    private Gtk.Button close_button;
    private Configuration config;
    
    public PreferencesDialog(Configuration config) {
        this.config = config;
        Gtk.Builder builder = GearyApplication.instance.create_builder("preferences.glade");
        
        dialog = builder.get_object("dialog") as Gtk.Dialog;
        autoselect = builder.get_object("autoselect") as Gtk.CheckButton;
        close_button = builder.get_object("close_button") as Gtk.Button;
        
        autoselect.active = config.autoselect;
        
        autoselect.toggled.connect(on_autoselect_toggled);
        close_button.clicked.connect(on_close);
        dialog.close.connect(on_escape);
    }
    
    public void run() {
        dialog.run();
    }
    
    private void on_close() {
        dialog.destroy();
    }
    
    private void on_autoselect_toggled() {
        config.autoselect = autoselect.active;
    }
    
    private void on_escape() {
        dialog.hide();
    }
}
