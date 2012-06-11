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
    
    public PasswordDialog(Geary.AccountInformation account_information, bool first_try) {
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
        Gtk.Label imap_server_label = (Gtk.Label)builder.get_object("imap_server_label");
        Gtk.Label imap_port_label = (Gtk.Label)builder.get_object("imap_port_label");
        Gtk.Label imap_encryption_label = (Gtk.Label)builder.get_object("imap_encryption_label");
        Gtk.Label smtp_server_label = (Gtk.Label)builder.get_object("smtp_server_label");
        Gtk.Label smtp_port_label = (Gtk.Label)builder.get_object("smtp_port_label");
        Gtk.Label smtp_encryption_label = (Gtk.Label)builder.get_object("smtp_encryption_label");

        // Find server configuration information
        Geary.Endpoint imap_endpoint;
        Geary.Endpoint smtp_endpoint;
        try {
            imap_endpoint = account_information.get_imap_endpoint();
            smtp_endpoint = account_information.get_smtp_endpoint();
        } catch (Geary.EngineError err) {
            error("Error getting endpoints: %s", err.message);
        }

        string imap_server_host = imap_endpoint.host_specifier;
        uint16 imap_server_port = imap_endpoint.default_port;
        bool imap_server_ssl = (imap_endpoint.flags & Geary.Endpoint.Flags.SSL) != 0;
        string smtp_server_host = smtp_endpoint.host_specifier;
        uint16 smtp_server_port = smtp_endpoint.default_port;
        bool smtp_server_ssl= (smtp_endpoint.flags & Geary.Endpoint.Flags.SSL) != 0;

        // Load initial values
        email_label.set_text(account_information.credentials.user ?? "");
        password_entry.set_text(account_information.credentials.pass ?? "");
        remember_password_checkbutton.active = account_information.remember_password;
        real_name_label.set_text(account_information.real_name ?? "");
        service_label.set_text(account_information.service_provider.display_name() ?? "");
        imap_server_label.set_text(imap_server_host);
        imap_port_label.set_text(imap_server_port.to_string());
        imap_encryption_label.set_text(imap_server_ssl ? "on" : "off");
        smtp_server_label.set_text(smtp_server_host);
        smtp_port_label.set_text(smtp_server_port.to_string());
        smtp_encryption_label.set_text(smtp_server_ssl ? "on" : "off");

        // Set primary text
        Gtk.Label primary_text_label = (Gtk.Label)builder.get_object("primary_text_label");
        const string primary_markup_format = """<span weight="bold" size="larger">%s</span>""";
        string primary_markup_text = first_try ? _("Please enter your email password") :
            _("Unable to login to email server");
        primary_text_label.set_markup(primary_markup_format.printf(primary_markup_text));
        primary_text_label.use_markup = true;

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

