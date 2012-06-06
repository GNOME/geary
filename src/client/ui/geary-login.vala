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
    
    private Gtk.Alignment other_info;
    private Gtk.Entry entry_imap_host;
    private Gtk.Entry entry_imap_port;
    private Gtk.CheckButton check_imap_ssl;
    private Gtk.Entry entry_smtp_host;
    private Gtk.Entry entry_smtp_port;
    private Gtk.CheckButton check_smtp_ssl;
    
    private Gtk.Button ok_button;
    
    private bool edited_imap_port = false;
    private bool edited_smtp_port = false;
    
    public Geary.AccountInformation account_information { get; private set; }
    
    public LoginDialog.from_account_information(Geary.AccountInformation default_account_information) {
        this(default_account_information.real_name, default_account_information.credentials.user,
            default_account_information.credentials.pass, default_account_information.service_provider,
            default_account_information.imap_server_host, default_account_information.imap_server_port,
            default_account_information.imap_server_ssl, default_account_information.smtp_server_host,
            default_account_information.smtp_server_port, default_account_information.smtp_server_ssl);
    }
    
    public LoginDialog(string default_real_name, string? default_username = null,
        string? default_password = null, int default_service_provider = -1,string? default_imap_host = null,
        uint16 default_imap_port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL, bool default_imap_ssl = true,
        string? default_smtp_host = null, uint16 default_smtp_port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL,
        bool default_smtp_ssl = true) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("login.glade");
        
        dialog = builder.get_object("LoginDialog") as Gtk.Dialog;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);
        
        entry_real_name = builder.get_object("real_name") as Gtk.Entry;
        combo_service =  builder.get_object("service") as Gtk.ComboBoxText;
        entry_username = builder.get_object("username") as Gtk.Entry;
        entry_password = builder.get_object("password") as Gtk.Entry;
        
        other_info = builder.get_object("other_info") as Gtk.Alignment;
        entry_imap_host = builder.get_object("imap host") as Gtk.Entry;
        entry_imap_port = builder.get_object("imap port") as Gtk.Entry;
        check_imap_ssl = builder.get_object("imap ssl") as Gtk.CheckButton;
        entry_smtp_host = builder.get_object("smtp host") as Gtk.Entry;
        entry_smtp_port = builder.get_object("smtp port") as Gtk.Entry;
        check_smtp_ssl = builder.get_object("smtp ssl") as Gtk.CheckButton;
        
        combo_service.changed.connect(on_service_changed);
        
        foreach (Geary.ServiceProvider p in Geary.ServiceProvider.get_providers()) {
            combo_service.append_text(p.display_name());
            if (p == default_service_provider)
                combo_service.set_active(p);
        }
        
        if (combo_service.get_active() == -1)
            combo_service.set_active(0);
        
        // Set defaults (other than service provider, which is set above)
        entry_real_name.set_text(default_real_name ?? "");
        entry_username.set_text(default_username ?? "");
        entry_password.set_text(default_password ?? "");
        entry_imap_host.set_text(default_imap_host ?? "");
        entry_imap_port.set_text(default_imap_port.to_string());
        check_imap_ssl.active = default_imap_ssl;
        entry_smtp_host.set_text(default_smtp_host ?? "");
        entry_smtp_port.set_text(default_smtp_port.to_string());
        check_smtp_ssl.active = default_smtp_ssl;
        
        if (Geary.String.is_empty(entry_real_name.text))
            entry_real_name.grab_focus();
        else
            entry_username.grab_focus();
        
        entry_username.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        entry_real_name.changed.connect(on_changed);
        combo_service.changed.connect(on_changed);
        entry_imap_host.changed.connect(on_changed);
        entry_imap_port.changed.connect(on_changed);
        entry_smtp_host.changed.connect(on_changed);
        entry_smtp_port.changed.connect(on_changed);
        
        check_imap_ssl.toggled.connect(on_check_imap_ssl_toggled);
        check_smtp_ssl.toggled.connect(on_check_smtp_ssl_toggled);
        
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
        account_information.service_provider = get_service_provider();
        account_information.imap_server_host = entry_imap_host.text.strip();
        account_information.imap_server_port = (uint16) int.parse(entry_imap_port.text.strip());
        account_information.imap_server_ssl = check_imap_ssl.active;
        account_information.smtp_server_host = entry_smtp_host.text.strip();
        account_information.smtp_server_port = (uint16) int.parse(entry_smtp_port.text.strip());
        account_information.smtp_server_ssl = check_smtp_ssl.active;
        
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
    
    private void on_check_smtp_ssl_toggled() {
        if (edited_smtp_port)
            return;
        
        entry_smtp_port.text = (check_smtp_ssl.active ? Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL :
            Geary.Smtp.ClientConnection.DEFAULT_PORT).to_string();
        edited_smtp_port = false;
    }
    
    private Geary.ServiceProvider get_service_provider() {
        return (Geary.ServiceProvider) combo_service.get_active();
    }
    
    private bool is_complete() {
        if (Geary.String.is_empty(entry_username.text.strip()) || 
            Geary.String.is_empty(entry_password.text.strip()))
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
