/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
 
/**
 * Displays a dialog for collecting the user's password, without allowing them to change their
 * other data.
 */
public class PasswordDialog {
    private Gtk.Dialog dialog;
    private Gtk.Entry password_entry;
    private Gtk.CheckButton remember_password_checkbutton;
    private Gtk.Button ok_button;
    
    public string password { get; private set; default = ""; }
    
    public bool remember_password { get; private set; }
    
    public PasswordDialog(Geary.AccountInformation account_information) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("password-dialog.glade");
        
        // Load dialog
        dialog = (Gtk.Dialog)builder.get_object("PasswordDialog");
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        // Load editable widgets
        password_entry = (Gtk.Entry)builder.get_object("password_entry");
        remember_password_checkbutton = (Gtk.CheckButton)builder.get_object("remember_password_checkbutton");
        
        // Load non-editable widgets
        Gtk.Label email_label = (Gtk.Label)builder.get_object("email_label");
        Gtk.Label real_name_label = (Gtk.Label)builder.get_object("real_name_label");
        Gtk.Label service_label = (Gtk.Label)builder.get_object("service_label");
        
        // Load default values
        email_label.set_text(account_information.credentials.user ?? "");
        password_entry.set_text(account_information.credentials.pass ?? "");
        remember_password_checkbutton.active = account_information.remember_password;
        real_name_label.set_text(account_information.real_name ?? "");
        service_label.set_text(account_information.service_provider.display_name() ?? "");
        
        // Add action buttons
        Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        ok_button.can_default = true;
        dialog.add_action_widget(cancel_button, Gtk.ResponseType.CANCEL);
        dialog.add_action_widget(ok_button, Gtk.ResponseType.OK);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        // Setup listeners
        refresh_ok_button_sensitivity();
        password_entry.changed.connect(refresh_ok_button_sensitivity);
    }
    
    private void refresh_ok_button_sensitivity() {
        ok_button.sensitive = !Geary.String.is_null_or_whitespace(password_entry.get_text());
        
    }
    
    public bool run() {
        dialog.show();
        dialog.get_action_area().show_all();
        
        Gtk.ResponseType response = (Gtk.ResponseType)dialog.run();
        if (response != Gtk.ResponseType.OK) {
            dialog.destroy();
            return false;
        }
        
        password = password_entry.get_text();
        remember_password = remember_password_checkbutton.active;
        
        dialog.destroy();
        return true;
    }
}

