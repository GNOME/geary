/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Displays a dialog for collecting the user's login data.
public class LoginDialog {
    private Gtk.Dialog dialog;
    private Gtk.Entry entry_username;
    private Gtk.Entry entry_password;
    private Gtk.Entry entry_real_name;
    private Gtk.ComboBoxText combo_service;
    private Gtk.CheckButton check_remember_password;
    
    private Gtk.Alignment other_info;
    private Gtk.Entry entry_imap_host;
    private Gtk.Entry entry_imap_port;
    private Gtk.CheckButton check_imap_ssl;
    private Gtk.Entry entry_smtp_host;
    private Gtk.Entry entry_smtp_port;
    private Gtk.RadioButton radio_smtp_none;
    private Gtk.RadioButton radio_smtp_ssl;
    private Gtk.RadioButton radio_smtp_starttls;
    private Gtk.Button ok_button;
    
    private bool edited_imap_port = false;
    private bool edited_smtp_port = false;
    
    public Geary.AccountInformation account_information { get; private set; }
    
    public LoginDialog.from_account_information(Geary.AccountInformation initial_account_information) {
        this(initial_account_information.real_name, initial_account_information.credentials.user,
            initial_account_information.credentials.pass, initial_account_information.remember_password, 
            initial_account_information.service_provider, initial_account_information.default_imap_server_host,
            initial_account_information.default_imap_server_port, initial_account_information.default_imap_server_ssl,
            initial_account_information.default_smtp_server_host, initial_account_information.default_smtp_server_port,
            initial_account_information.default_smtp_server_ssl, initial_account_information.default_smtp_server_starttls);
    }
    
    public LoginDialog(string? initial_real_name = null, string? initial_username = null,
        string? initial_password = null, bool initial_remember_password = true,
        int initial_service_provider = -1, string? initial_default_imap_host = null,
        uint16 initial_default_imap_port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_imap_ssl = true, string? initial_default_smtp_host = null,
        uint16 initial_default_smtp_port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_smtp_ssl = true, bool initial_default_smtp_starttls = false) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("login.glade");
        
        dialog = builder.get_object("LoginDialog") as Gtk.Dialog;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        entry_real_name = builder.get_object("real_name") as Gtk.Entry;
        combo_service =  builder.get_object("service") as Gtk.ComboBoxText;
        entry_username = builder.get_object("username") as Gtk.Entry;
        entry_password = builder.get_object("password") as Gtk.Entry;
        check_remember_password = builder.get_object("remember_password") as Gtk.CheckButton;
        
        other_info = builder.get_object("other_info") as Gtk.Alignment;
        entry_imap_host = builder.get_object("imap host") as Gtk.Entry;
        entry_imap_port = builder.get_object("imap port") as Gtk.Entry;
        check_imap_ssl = builder.get_object("imap ssl") as Gtk.CheckButton;
        entry_smtp_host = builder.get_object("smtp host") as Gtk.Entry;
        entry_smtp_port = builder.get_object("smtp port") as Gtk.Entry;
        radio_smtp_none = builder.get_object("smtp none") as Gtk.RadioButton;
        radio_smtp_ssl = builder.get_object("smtp ssl") as Gtk.RadioButton;
        radio_smtp_starttls = builder.get_object("smtp starttls") as Gtk.RadioButton;
        
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
        entry_username.set_text(initial_username ?? "");
        entry_password.set_text(initial_password ?? "");
        check_remember_password.active = initial_remember_password;
        entry_imap_host.set_text(initial_default_imap_host ?? "");
        entry_imap_port.set_text(initial_default_imap_port.to_string());
        check_imap_ssl.active = initial_default_imap_ssl;
        entry_smtp_host.set_text(initial_default_smtp_host ?? "");
        entry_smtp_port.set_text(initial_default_smtp_port.to_string());
        radio_smtp_none.active = true;
        radio_smtp_ssl.active = initial_default_smtp_ssl;
        radio_smtp_starttls.active = initial_default_smtp_starttls;
        
        if (Geary.String.is_empty(entry_real_name.text))
            entry_real_name.grab_focus();
        else
            entry_username.grab_focus();
        
        entry_username.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        entry_real_name.changed.connect(on_changed);
        check_remember_password.toggled.connect(on_changed);
        combo_service.changed.connect(on_changed);
        entry_imap_host.changed.connect(on_changed);
        entry_imap_port.changed.connect(on_changed);
        entry_smtp_host.changed.connect(on_changed);
        entry_smtp_port.changed.connect(on_changed);
        
        check_imap_ssl.toggled.connect(on_check_imap_ssl_toggled);
        
        radio_smtp_none.toggled.connect(on_radio_smtp_toggled);
        radio_smtp_ssl.toggled.connect(on_radio_smtp_toggled);
        radio_smtp_starttls.toggled.connect(on_radio_smtp_toggled);
        
        entry_imap_port.insert_text.connect(on_port_insert_text);
        entry_smtp_port.insert_text.connect(on_port_insert_text);
        
        dialog.add_action_widget(new Gtk.Button.from_stock(Gtk.Stock.CANCEL), Gtk.ResponseType.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.OK);
        ok_button.can_default = true;
        ok_button.sensitive = false;
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
        
        Geary.Credentials credentials = new Geary.Credentials(entry_username.text.strip(),
            entry_password.text.strip());
        account_information = new Geary.AccountInformation(credentials);
        
        account_information.real_name = entry_real_name.text.strip();
        account_information.remember_password = check_remember_password.active;
        account_information.service_provider = get_service_provider();
        account_information.default_imap_server_host = entry_imap_host.text.strip();
        account_information.default_imap_server_port = (uint16) int.parse(entry_imap_port.text.strip());
        account_information.default_imap_server_ssl = check_imap_ssl.active;
        account_information.default_smtp_server_host = entry_smtp_host.text.strip();
        account_information.default_smtp_server_port = (uint16) int.parse(entry_smtp_port.text.strip());
        account_information.default_smtp_server_ssl = radio_smtp_ssl.active;
        account_information.default_smtp_server_starttls = radio_smtp_starttls.active;
        
        on_changed();
        
        dialog.destroy();
        return true;
    }
    
    private void on_service_changed() {
        if (get_service_provider() == Geary.ServiceProvider.OTHER) {
            other_info.show();
        } else {
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
    
    private void on_check_imap_ssl_toggled() {
        if (edited_imap_port)
            return;
        
        entry_imap_port.text = (check_imap_ssl.active ? Geary.Imap.ClientConnection.DEFAULT_PORT_SSL :
            Geary.Imap.ClientConnection.DEFAULT_PORT).to_string();
        edited_imap_port = false;
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
    
    private bool is_complete() {
        if (Geary.String.is_null_or_whitespace(entry_username.text.strip()) ||
            Geary.String.is_null_or_whitespace(entry_password.text.strip()))
            return false;
        
        // For "other" providers, check server settings.
        if (get_service_provider() == Geary.ServiceProvider.OTHER) {
            if (Geary.String.is_empty(entry_imap_host.text.strip()) ||
                Geary.String.is_empty(entry_imap_port.text) ||
                Geary.String.is_empty(entry_smtp_host.text.strip()) ||
                Geary.String.is_empty(entry_smtp_port.text) ||
                int.parse(entry_imap_port.text) > uint16.MAX ||
                int.parse(entry_smtp_port.text) > uint16.MAX)
                return false;
        }
        
        return true;
    }
}
