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
    // We can't keep these in the glade file, because Gnome doesn't want markup in translatable
    // strings, and Glade doesn't support the "larger" size attribute. See this bug report for
    // details: https://bugzilla.gnome.org/show_bug.cgi?id=679006
    private const string PRIMARY_TEXT_MARKUP = "<span weight=\"bold\" size=\"larger\">%s</span>";
    private const string PRIMARY_TEXT_FIRST_TRY = _("Please enter your email password");
    private const string PRIMARY_TEXT_REPEATED_TRY = _("Unable to login to email server");
    
    private Gtk.Dialog dialog;
    private Gtk.Entry entry_imap_password;
    private Gtk.CheckButton check_remember_password;
    private Gtk.Entry entry_smtp_password;
    private Gtk.Button ok_button;
    private Gtk.Grid grid_imap;
    private Gtk.Grid grid_smtp;
    private PasswordTypeFlag password_flags;
    
    public string imap_password { get; private set; default = ""; }
    public string smtp_password { get; private set; default = ""; }
    public bool remember_password { get; private set; }
    
    public PasswordDialog(Geary.AccountInformation account_information, bool first_try,
        PasswordTypeFlag password_flags) {
        this.password_flags = password_flags;
        Gtk.Builder builder = GearyApplication.instance.create_builder("password-dialog.glade");
        
        // Load dialog
        dialog = (Gtk.Dialog) builder.get_object("PasswordDialog");
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        // Load editable widgets
        entry_imap_password = (Gtk.Entry) builder.get_object("entry: imap password");
        entry_smtp_password = (Gtk.Entry) builder.get_object("entry: smtp password");
        check_remember_password = (Gtk.CheckButton) builder.get_object("check: remember_password");
        
        // Load non-editable widgets
        Gtk.Label label_real_name = (Gtk.Label) builder.get_object("label: real_name");
        Gtk.Label label_service = (Gtk.Label) builder.get_object("label: service");
        
        grid_imap = (Gtk.Grid) builder.get_object("grid: imap");
        Gtk.Label label_imap_username = (Gtk.Label) builder.get_object("label: imap username");
        Gtk.Label label_imap_server = (Gtk.Label) builder.get_object("label: imap server");
        Gtk.Label label_imap_port = (Gtk.Label) builder.get_object("label: imap port");
        Gtk.Label label_imap_encryption = (Gtk.Label) builder.get_object("label: imap encryption");
        
        grid_smtp = (Gtk.Grid) builder.get_object("grid: smtp");
        Gtk.Label label_smtp_username = (Gtk.Label) builder.get_object("label: smtp username");
        Gtk.Label label_smtp_server = (Gtk.Label) builder.get_object("label: smtp server");
        Gtk.Label label_smtp_port = (Gtk.Label) builder.get_object("label: smtp port");
        Gtk.Label label_smtp_encryption = (Gtk.Label) builder.get_object("label: smtp encryption");
        
        // Load translated text for labels with markup unsupported by glade.
        Gtk.Label primary_text_label = (Gtk.Label) builder.get_object("primary_text_label");
        primary_text_label.set_markup(get_primary_text_markup(first_try));

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
        string smtp_server_host = smtp_endpoint.host_specifier;
        uint16 smtp_server_port = smtp_endpoint.default_port;
        
        // Load initial values
        label_real_name.set_text(account_information.real_name ?? "");
        label_service.set_text(account_information.service_provider.display_name() ?? "");
        
        label_imap_username.set_text(account_information.imap_credentials.user ?? "");
        entry_imap_password.set_text(account_information.imap_credentials.pass ?? "");
        label_imap_server.set_text(imap_server_host);
        label_imap_port.set_text(imap_server_port.to_string());
        label_imap_encryption.set_text(get_security_status(imap_endpoint.flags));
        
        label_smtp_username.set_text(account_information.smtp_credentials.user ?? "");
        entry_smtp_password.set_text(account_information.smtp_credentials.pass ?? "");
        label_smtp_server.set_text(smtp_server_host);
        label_smtp_port.set_text(smtp_server_port.to_string());
        label_smtp_encryption.set_text(get_security_status(smtp_endpoint.flags));
        
        check_remember_password.active = account_information.imap_remember_password;
        
        // Add action buttons
        Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        ok_button.can_default = true;
        dialog.add_action_widget(cancel_button, Gtk.ResponseType.CANCEL);
        dialog.add_action_widget(ok_button, Gtk.ResponseType.OK);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        // Setup listeners
        refresh_ok_button_sensitivity();
        entry_imap_password.changed.connect(refresh_ok_button_sensitivity);
        entry_smtp_password.changed.connect(refresh_ok_button_sensitivity);
    }
    
    private string get_primary_text_markup(bool first_try) {
        return PRIMARY_TEXT_MARKUP.printf(first_try ? PRIMARY_TEXT_FIRST_TRY : PRIMARY_TEXT_REPEATED_TRY);
    }
    
    private void refresh_ok_button_sensitivity() {
        ok_button.sensitive = !Geary.String.is_empty_or_whitespace(entry_imap_password.get_text()) ||
            !Geary.String.is_empty_or_whitespace(entry_smtp_password.get_text());
    }
    
    private string get_security_status(Geary.Endpoint.Flags flags) {
        if (flags.is_all_set(Geary.Endpoint.Flags.SSL))
            return _("SSL");
        else if (flags.is_all_set(Geary.Endpoint.Flags.STARTTLS))
            return _("STARTTLS");
        
        return _("None");
    }
    
    public bool run() {
        dialog.show();
        dialog.get_action_area().show_all();
        
        if (!password_flags.has_imap()) {
            grid_imap.hide();
            entry_smtp_password.grab_focus();
        }
        
        if (!password_flags.has_smtp()) {
            grid_smtp.hide();
            entry_imap_password.grab_focus();
        }
        
        Gtk.ResponseType response = (Gtk.ResponseType) dialog.run();
        if (response == Gtk.ResponseType.OK) {
            imap_password = entry_imap_password.get_text();
            smtp_password = entry_smtp_password.get_text();
            remember_password = check_remember_password.active;
        }
        
        dialog.destroy();
        
        return (response == Gtk.ResponseType.OK);
    }
}

