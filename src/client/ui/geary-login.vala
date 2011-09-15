/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Displays a dialog for collecting the user's login data.
public class LoginDialog {
    private Gtk.Dialog dialog;
    private Gtk.Entry entry_username;
    private Gtk.Entry entry_password;
    private Gtk.ResponseType response;
    private Gtk.Button ok_button;
    
    public string username { get; private set; default = ""; }
    public string password { get; private set; default = ""; }
    
    public LoginDialog(string default_username = "", string default_password = "") {
        Gtk.Builder builder = YorbaApplication.instance.create_builder("login.glade");
        
        dialog = builder.get_object("LoginDialog") as Gtk.Dialog;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        entry_username = builder.get_object("username") as Gtk.Entry;
        entry_password = builder.get_object("password") as Gtk.Entry;
        
        entry_username.set_text(default_username);
        entry_password.set_text(default_password);
        
        entry_username.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        
        dialog.add_action_widget(new Gtk.Button.from_stock(Gtk.Stock.CANCEL), Gtk.ResponseType.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        ok_button.can_default = true;
        ok_button.sensitive = false;
        dialog.add_action_widget(ok_button, Gtk.ResponseType.OK);
        dialog.set_default_response(Gtk.ResponseType.OK);
    }
    
    // Runs the dialog.
    public void show() {
        dialog.show_all();
        response = (Gtk.ResponseType) dialog.run();
        username = entry_username.text.strip();
        password = entry_password.text.strip();
        dialog.destroy();
    }
    
    // Call this after Show to get the response.  Will either be OK or cancel.
    public Gtk.ResponseType get_response() {
        return response;
    }
    
    private void on_changed() {
        ok_button.sensitive = is_complete();
    }
    
    private bool is_complete() {
        return entry_username.text.strip() != "" && entry_password.text.strip() != "";
    }
}
