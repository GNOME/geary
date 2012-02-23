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
    private Gtk.CheckButton check_imap_tls;
    private Gtk.Entry entry_smtp_host;
    private Gtk.Entry entry_smtp_port;
    private Gtk.CheckButton check_smtp_tls;
    
    private Gtk.ResponseType response;
    private Gtk.Button ok_button;
    
    private bool edited_imap_port = false;
    private bool edited_smtp_port = false;
    
    public string username { get; private set; default = ""; }
    public string password { get; private set; default = ""; }
    public string real_name { get; private set; default = ""; }
    public Geary.ServiceProvider provider { get; private set;
        default = Geary.ServiceProvider.GMAIL; }
    
    public string imap_host { get; private set; default = ""; }
    public uint16 imap_port { get; private set;
        default = Geary.Imap.ClientConnection.DEFAULT_PORT_TLS; }
    public bool imap_tls { get; private set; default = true; }
    public string smtp_host { get; private set; default = ""; }
    public uint16 smtp_port { get; private set;
        default = Geary.Smtp.ClientConnection.SECURE_SMTP_PORT; }
    public bool smtp_tls { get; private set; default = true; }
    
    public LoginDialog(string default_username = "", string default_password = "",
        Geary.AccountInformation? default_account_info = null) {
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
        check_imap_tls = builder.get_object("imap tls") as Gtk.CheckButton;
        entry_smtp_host = builder.get_object("smtp host") as Gtk.Entry;
        entry_smtp_port = builder.get_object("smtp port") as Gtk.Entry;
        check_smtp_tls = builder.get_object("smtp tls") as Gtk.CheckButton;
        
        combo_service.changed.connect(on_service_changed);
        
        foreach (Geary.ServiceProvider p in Geary.ServiceProvider.get_providers()) {
            combo_service.append_text(p.display_name());
            if (default_account_info != null && p == default_account_info.service_provider)
                combo_service.set_active(p);
        }
        
        if (combo_service.get_active() == -1)
            combo_service.set_active(0);
        
        entry_username.set_text(default_username);
        entry_password.set_text(default_password);
        
        if (default_account_info != null && !Geary.String.is_empty(default_account_info.real_name))
            entry_real_name.set_text(default_account_info.real_name);
        
        entry_real_name.grab_focus();
        
        entry_username.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        entry_real_name.changed.connect(on_changed);
        combo_service.changed.connect(on_changed);
        entry_imap_host.changed.connect(on_changed);
        entry_imap_port.changed.connect(on_changed);
        entry_smtp_host.changed.connect(on_changed);
        entry_smtp_port.changed.connect(on_changed);
        
        check_imap_tls.toggled.connect(on_check_imap_tls_toggled);
        check_smtp_tls.toggled.connect(on_check_smtp_tls_toggled);
        
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
    public void show() {
        dialog.show();
        dialog.get_action_area().show_all();
        on_service_changed(); // shows/hides server settings
        
        response = (Gtk.ResponseType) dialog.run();
        
        username = entry_username.text.strip();
        password = entry_password.text.strip();
        real_name = entry_real_name.text.strip();
        provider = get_service_provider();
        imap_host = entry_imap_host.text.strip();
        imap_port = (uint16) int.parse(entry_imap_port.text.strip());
        imap_tls = check_imap_tls.active;
        smtp_host = entry_smtp_host.text.strip();
        smtp_port = (uint16) int.parse(entry_smtp_port.text.strip());
        smtp_tls = check_smtp_tls.active;
        
        dialog.destroy();
    }
    
    // Call this after Show to get the response.  Will either be OK or cancel.
    public Gtk.ResponseType get_response() {
        return response;
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
    
    private void on_check_imap_tls_toggled() {
        if (edited_imap_port)
            return;
        
        entry_imap_port.text = (check_imap_tls.active ? Geary.Imap.ClientConnection.DEFAULT_PORT_TLS :
            Geary.Imap.ClientConnection.DEFAULT_PORT).to_string();
        edited_imap_port = false;
    }
    
    private void on_check_smtp_tls_toggled() {
        if (edited_smtp_port)
            return;
        
        entry_smtp_port.text = (check_smtp_tls.active ? Geary.Smtp.ClientConnection.SECURE_SMTP_PORT :
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
