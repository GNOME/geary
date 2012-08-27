/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Displays a dialog for collecting the user's login data.
public class LoginDialog {
    private Gtk.Dialog dialog;
    private Gtk.Entry entry_email;
    private Gtk.Label label_password;
    private Gtk.Entry entry_password;
    private Gtk.Entry entry_real_name;
    private Gtk.ComboBoxText combo_service;
    private Gtk.CheckButton check_remember_password;
    
    private Gtk.Alignment other_info;
    
    // IMAP info widgets
    private Gtk.Entry entry_imap_host;
    private Gtk.Entry entry_imap_port;
    private Gtk.Entry entry_imap_username;
    private Gtk.Entry entry_imap_password;
    private Gtk.CheckButton check_imap_remember_password;
    private Gtk.RadioButton radio_imap_none;
    private Gtk.RadioButton radio_imap_ssl;
    private Gtk.RadioButton radio_imap_starttls;
    
    // SMTP info widgets
    private Gtk.Entry entry_smtp_host;
    private Gtk.Entry entry_smtp_port;
    private Gtk.Entry entry_smtp_username;
    private Gtk.Entry entry_smtp_password;
    private Gtk.CheckButton check_smtp_remember_password;
    private Gtk.RadioButton radio_smtp_none;
    private Gtk.RadioButton radio_smtp_ssl;
    private Gtk.RadioButton radio_smtp_starttls;
    
    private Gtk.Button ok_button;
    
    private bool edited_imap_port = false;
    private bool edited_smtp_port = false;
    
    public Geary.AccountInformation account_information { get; private set; }
    
    // TODO: Update the login dialog to use email, imap_credentials, smtp_credentials,
    // imap_remember_password, and smtp_remember_password.
    public LoginDialog.from_account_information(Geary.AccountInformation initial_account_information) {
        this(initial_account_information.real_name,
            initial_account_information.email,
            initial_account_information.imap_credentials.user,
            initial_account_information.imap_credentials.pass,
            initial_account_information.imap_remember_password, 
            initial_account_information.smtp_credentials.user,
            initial_account_information.smtp_credentials.pass,
            initial_account_information.smtp_remember_password, 
            initial_account_information.service_provider,
            initial_account_information.default_imap_server_host,
            initial_account_information.default_imap_server_port,
            initial_account_information.default_imap_server_ssl,
            initial_account_information.default_imap_server_starttls,
            initial_account_information.default_smtp_server_host,
            initial_account_information.default_smtp_server_port,
            initial_account_information.default_smtp_server_ssl,
            initial_account_information.default_smtp_server_starttls);
    }
    
    public LoginDialog(
        string? initial_real_name = null,
        string? initial_email = null,
        string? initial_imap_username = null,
        string? initial_imap_password = null,
        bool initial_imap_remember_password = true,
        string? initial_smtp_username = null,
        string? initial_smtp_password = null,
        bool initial_smtp_remember_password = true,
        int initial_service_provider = -1,
        string? initial_default_imap_host = null,
        uint16 initial_default_imap_port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_imap_ssl = true,
        bool initial_default_imap_starttls = false,
        string? initial_default_smtp_host = null,
        uint16 initial_default_smtp_port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_smtp_ssl = true,
        bool initial_default_smtp_starttls = false) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("login.glade");
        
        dialog = builder.get_object("LoginDialog") as Gtk.Dialog;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        entry_real_name = builder.get_object("entry: real_name") as Gtk.Entry;
        combo_service =  builder.get_object("combo: service") as Gtk.ComboBoxText;
        entry_email = builder.get_object("entry: email") as Gtk.Entry;
        label_password = builder.get_object("label: password") as Gtk.Label;
        entry_password = builder.get_object("entry: password") as Gtk.Entry;
        check_remember_password = builder.get_object("check: remember_password") as Gtk.CheckButton;
        
        other_info = builder.get_object("container: other_info") as Gtk.Alignment;
        
        // IMAP info widgets.
        entry_imap_host = builder.get_object("entry: imap host") as Gtk.Entry;
        entry_imap_port = builder.get_object("entry: imap port") as Gtk.Entry;
        entry_imap_username = builder.get_object("entry: imap username") as Gtk.Entry;
        entry_imap_password = builder.get_object("entry: imap password") as Gtk.Entry;
        check_imap_remember_password = builder.get_object("check: imap remember_password") as Gtk.CheckButton;
        radio_imap_none = builder.get_object("radio: imap none") as Gtk.RadioButton;
        radio_imap_ssl = builder.get_object("radio: imap ssl") as Gtk.RadioButton;
        radio_imap_starttls = builder.get_object("radio: imap starttls") as Gtk.RadioButton;
        
        // SMTP info widgets.
        entry_smtp_host = builder.get_object("entry: smtp host") as Gtk.Entry;
        entry_smtp_port = builder.get_object("entry: smtp port") as Gtk.Entry;
        entry_smtp_username = builder.get_object("entry: smtp username") as Gtk.Entry;
        entry_smtp_password = builder.get_object("entry: smtp password") as Gtk.Entry;
        check_smtp_remember_password = builder.get_object("check: smtp remember_password") as Gtk.CheckButton;
        radio_smtp_none = builder.get_object("radio: smtp none") as Gtk.RadioButton;
        radio_smtp_ssl = builder.get_object("radio: smtp ssl") as Gtk.RadioButton;
        radio_smtp_starttls = builder.get_object("radio: smtp starttls") as Gtk.RadioButton;
        
        combo_service.changed.connect(on_service_changed);
        
        foreach (Geary.ServiceProvider p in Geary.ServiceProvider.get_providers()) {
            combo_service.append_text(p.display_name());
            if (p == initial_service_provider)
                combo_service.set_active(p);
        }
        
        if (combo_service.get_active() == -1)
            combo_service.set_active(0);
        
        // Set defaults (other than service provider, which is set above)
        entry_real_name.set_text(initial_real_name ?? "");
        entry_email.set_text(initial_email ?? "");
        bool use_imap_password = initial_imap_password == initial_smtp_password &&
            initial_imap_password != null;
        entry_password.set_text(use_imap_password ? initial_imap_password : "");
        check_remember_password.active = initial_imap_remember_password && initial_smtp_remember_password;
        
        // Set defaults for IMAP info
        entry_imap_host.set_text(initial_default_imap_host ?? "");
        entry_imap_port.set_text(initial_default_imap_port.to_string());
        entry_imap_username.set_text(initial_imap_username ?? "");
        entry_imap_password.set_text(initial_imap_password ?? "");
        check_imap_remember_password.active = initial_imap_remember_password;
        radio_imap_none.active = true;
        radio_imap_ssl.active = initial_default_imap_ssl;
        radio_imap_starttls.active = initial_default_imap_starttls;
        
        // Set defaults for SMTP info
        entry_smtp_host.set_text(initial_default_smtp_host ?? "");
        entry_smtp_port.set_text(initial_default_smtp_port.to_string());
        entry_smtp_username.set_text(initial_smtp_username ?? "");
        entry_smtp_password.set_text(initial_smtp_password ?? "");
        check_smtp_remember_password.active = initial_smtp_remember_password;
        radio_smtp_none.active = true;
        radio_smtp_ssl.active = initial_default_smtp_ssl;
        radio_smtp_starttls.active = initial_default_smtp_starttls;
        
        if (Geary.String.is_empty(entry_real_name.text))
            entry_real_name.grab_focus();
        else
            entry_email.grab_focus();
        
        entry_email.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        entry_real_name.changed.connect(on_changed);
        check_remember_password.toggled.connect(on_changed);
        combo_service.changed.connect(on_changed);
        entry_imap_host.changed.connect(on_changed);
        entry_imap_port.changed.connect(on_changed);
        entry_imap_username.changed.connect(on_changed);
        entry_imap_password.changed.connect(on_changed);
        entry_smtp_host.changed.connect(on_changed);
        entry_smtp_port.changed.connect(on_changed);
        entry_smtp_username.changed.connect(on_changed);
        entry_smtp_password.changed.connect(on_changed);
        
        entry_email.changed.connect(on_email_changed);
        entry_password.changed.connect(on_password_changed);
        check_remember_password.toggled.connect(on_remember_password_toggled);
        
        radio_imap_none.toggled.connect(on_radio_imap_toggled);
        radio_imap_ssl.toggled.connect(on_radio_imap_toggled);
        radio_imap_starttls.toggled.connect(on_radio_imap_toggled);
        
        radio_smtp_none.toggled.connect(on_radio_smtp_toggled);
        radio_smtp_ssl.toggled.connect(on_radio_smtp_toggled);
        radio_smtp_starttls.toggled.connect(on_radio_smtp_toggled);
        
        entry_imap_port.insert_text.connect(on_port_insert_text);
        entry_smtp_port.insert_text.connect(on_port_insert_text);
        
        dialog.add_action_widget(new Gtk.Button.from_stock(Gtk.Stock.CANCEL), Gtk.ResponseType.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        ok_button.can_default = true;
        ok_button.sensitive = is_complete();
        dialog.add_action_widget(ok_button, Gtk.ResponseType.OK);
        dialog.set_default_response(Gtk.ResponseType.OK);
    }
    
    // Runs the dialog.
    public bool show() {
        dialog.show();
        dialog.get_action_area().show_all();
        on_service_changed(); // shows/hides server settings
        
        Gtk.ResponseType response = (Gtk.ResponseType) dialog.run();
        if (response != Gtk.ResponseType.OK)
            return false;
        
        bool use_extra_info = get_service_provider() == Geary.ServiceProvider.OTHER;
        
        string email = entry_email.text.strip();
        string imap_username = use_extra_info ? entry_imap_username.text.strip() : email;
        string imap_password = (use_extra_info ? entry_imap_password : entry_password).text.strip();
        bool imap_remember_password = use_extra_info ? check_imap_remember_password.active :
            check_remember_password.active;
        Geary.Credentials imap_credentials = new Geary.Credentials(imap_username, imap_password);
        
        string smtp_username = use_extra_info ? entry_smtp_username.text.strip() : email;
        string smtp_password = (use_extra_info ? entry_smtp_password : entry_password).text.strip();
        bool smtp_remember_password = use_extra_info ? check_smtp_remember_password.active :
            check_remember_password.active;
        Geary.Credentials smtp_credentials = new Geary.Credentials(smtp_username, smtp_password);
        
        try {
            account_information = Geary.Engine.get_account_for_email(email);
        } catch (Error err) {
            debug("Unable to open account information for %s: %s", email, err.message);
            
            return false;
        }
        
        account_information.real_name = entry_real_name.text.strip();
        account_information.imap_credentials = imap_credentials;
        account_information.smtp_credentials = smtp_credentials;
        account_information.imap_remember_password = imap_remember_password;
        account_information.smtp_remember_password = smtp_remember_password;
        account_information.service_provider = get_service_provider();
        account_information.default_imap_server_host = entry_imap_host.text.strip();
        account_information.default_imap_server_port = (uint16) int.parse(entry_imap_port.text.strip());
        account_information.default_imap_server_ssl = radio_imap_ssl.active;
        account_information.default_imap_server_starttls = radio_imap_starttls.active;
        account_information.default_smtp_server_host = entry_smtp_host.text.strip();
        account_information.default_smtp_server_port = (uint16) int.parse(entry_smtp_port.text.strip());
        account_information.default_smtp_server_ssl = radio_smtp_ssl.active;
        account_information.default_smtp_server_starttls = radio_smtp_starttls.active;
        
        on_changed();
        
        dialog.destroy();
        return true;
    }
    
    // TODO: Only reset if not manually set by user.
    private void on_email_changed() {
        entry_imap_username.text = entry_email.text;
        entry_smtp_username.text = entry_email.text;
    }
    
    // TODO: Only reset if not manually set by user.
    private void on_password_changed() {
        entry_imap_password.text = entry_password.text;
        entry_smtp_password.text = entry_password.text;
    }
    
    // TODO: Only reset if not manually set by user.
    private void on_remember_password_toggled() {
        check_imap_remember_password.active = check_remember_password.active;
        check_smtp_remember_password.active = check_remember_password.active;
    }
    
    private void on_service_changed() {
        if (get_service_provider() == Geary.ServiceProvider.OTHER) {
            label_password.hide();
            entry_password.hide();
            check_remember_password.hide();
            other_info.show();
        } else {
            label_password.show();
            entry_password.show();
            check_remember_password.show();
            other_info.hide();
            dialog.resize(1, 1);
        }
    }
    
    private void on_changed() {
        ok_button.sensitive = is_complete();
    }
    
    private void on_port_insert_text(Gtk.Editable e, string text, int length, ref int position) {
        // Prevent non-numerical characters and ensure port is <= uint16.MAX
        if (!uint64.try_parse(text) || uint64.parse(((Gtk.Entry) e).text) > uint16.MAX) {
            Signal.stop_emission_by_name(e, "insert-text");
        } else {
            if (e == entry_imap_port)
                edited_imap_port = true;
            else if (e == entry_smtp_port)
                edited_smtp_port = true;
        }
    }
    
    private void on_radio_imap_toggled() {
        if (edited_imap_port)
            return;
        
        entry_imap_port.text = get_default_imap_port().to_string();
        edited_imap_port = false;
    }
    
    private uint16 get_default_imap_port() {
        if (radio_imap_ssl.active)
            return Geary.Imap.ClientConnection.DEFAULT_PORT_SSL;
        if (radio_imap_starttls.active)
            return Geary.Imap.ClientConnection.DEFAULT_PORT;
        
        return Geary.Imap.ClientConnection.DEFAULT_PORT;
    }
    
    private void on_radio_smtp_toggled() {
        if (edited_smtp_port)
            return;
        
        entry_smtp_port.text = get_default_smtp_port().to_string();
        edited_smtp_port = false;
    }
    
    private uint16 get_default_smtp_port() {
        if (radio_smtp_ssl.active)
            return Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL;
        if (radio_smtp_starttls.active)
            return Geary.Smtp.ClientConnection.DEFAULT_PORT_STARTTLS;
        
        return Geary.Smtp.ClientConnection.DEFAULT_PORT;
    }
    
    private Geary.ServiceProvider get_service_provider() {
        return (Geary.ServiceProvider) combo_service.get_active();
    }
    
    private bool is_valid_port(string text) {
        uint64 port;
        if (!uint64.try_parse(text, out port))
            return false;
        
        return (port <= uint16.MAX);
    }
    
    private bool is_complete() {
        switch (get_service_provider()) {
            case Geary.ServiceProvider.OTHER:
                if (Geary.String.is_empty_or_whitespace(entry_email.text) ||
                    Geary.String.is_empty_or_whitespace(entry_imap_host.text) ||
                    Geary.String.is_empty_or_whitespace(entry_imap_port.text) ||
                    Geary.String.is_empty_or_whitespace(entry_imap_username.text) ||
                    Geary.String.is_empty_or_whitespace(entry_imap_password.text) ||
                    Geary.String.is_empty_or_whitespace(entry_smtp_host.text) ||
                    Geary.String.is_empty_or_whitespace(entry_smtp_port.text) ||
                    Geary.String.is_empty_or_whitespace(entry_smtp_username.text) ||
                    Geary.String.is_empty_or_whitespace(entry_smtp_password.text) ||
                    !is_valid_port(entry_imap_port.text) ||
                    !is_valid_port(entry_smtp_port.text))
                    return false;
            break;
            
            // GMAIL and YAHOO
            default:
                if (Geary.String.is_empty_or_whitespace(entry_email.text) ||
                    Geary.String.is_empty_or_whitespace(entry_password.text))
                    return false;
            break;
        }
        
        return true;
    }
}

