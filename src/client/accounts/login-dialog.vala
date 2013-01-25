/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Displays a dialog for collecting the user's login data.
public class LoginDialog : Gtk.Dialog {
    private Gtk.Button ok_button;
    private Gtk.Button cancel_button;
    private AddEditPage page = new AddEditPage();
    private AccountSpinnerPage spinner_page = new AccountSpinnerPage();
    
    public LoginDialog() {
        Object();
        set_type_hint(Gdk.WindowTypeHint.DIALOG);
        set_size_request(450, -1); // Sets min width.
        
        page.margin = 5;
        spinner_page.margin = 5;
        get_content_area().pack_start(page, true, true, 0);
        get_content_area().pack_start(spinner_page, true, true, 0);
        spinner_page.visible = false;
        page.size_changed.connect(() => { resize(1, 1); });
        page.info_changed.connect(on_info_changed);
        
        cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
        add_action_widget(cancel_button, Gtk.ResponseType.CANCEL);
        ok_button = new Gtk.Button.from_stock(Gtk.Stock.ADD);
        ok_button.can_default = true;
        add_action_widget(ok_button, Gtk.ResponseType.OK);
        set_default_response(Gtk.ResponseType.OK);
        get_action_area().show_all();
        
        on_info_changed();
    }
    
    public LoginDialog.from_account_information(Geary.AccountInformation initial_account_information) {
        this();
        set_account_information(initial_account_information);
    }
    
    public void set_real_name(string name) {
        page.real_name = name;
    }
    
    public void set_account_information(Geary.AccountInformation info) {
        page.set_all_info(info.real_name,
            info.email,
            info.imap_credentials.user,
            info.imap_credentials.pass,
            info.imap_remember_password && info.smtp_remember_password,
            info.smtp_credentials.user,
            info.smtp_credentials.pass,
            info.service_provider,
            info.default_imap_server_host,
            info.default_imap_server_port,
            info.default_imap_server_ssl,
            info.default_imap_server_starttls,
            info.default_smtp_server_host,
            info.default_smtp_server_port,
            info.default_smtp_server_ssl,
            info.default_smtp_server_starttls);
    }
    
    public Geary.AccountInformation get_account_information() {
        return page.get_account_information();
    }

    private void on_info_changed() {
        if (!spinner_page.visible)
            ok_button.sensitive = page.is_complete();
        else
            ok_button.sensitive = false;
    }
    
    // Switches between the account page and the busy spinner.
    public void show_spinner(bool visible) {
        spinner_page.visible = visible;
        page.visible = !visible;
        cancel_button.sensitive = !visible;
        on_info_changed(); // sets OK button sensitivity
    }
}

