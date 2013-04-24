/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AccountDialog : Gtk.Dialog {
    private const int MARGIN = 12;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private AccountDialogAccountListPane account_list_pane;
    private AccountDialogAddEditPane add_edit_pane;
    private AccountDialogSpinnerPane spinner_pane;
    private AccountDialogRemoveConfirmPane remove_confirm_pane;
    private AccountDialogRemoveFailPane remove_fail_pane;
    
    public AccountDialog() {
        set_size_request(450, -1); // Sets min size.
        title = _("Accounts");
        get_content_area().margin_top = MARGIN;
        get_content_area().margin_left = MARGIN;
        get_content_area().margin_right = MARGIN;
        
        // Add pages to notebook.
        account_list_pane = new AccountDialogAccountListPane(notebook);
        add_edit_pane = new AccountDialogAddEditPane(notebook);
        spinner_pane = new AccountDialogSpinnerPane(notebook);
        remove_confirm_pane = new AccountDialogRemoveConfirmPane(notebook);
        remove_fail_pane = new AccountDialogRemoveFailPane(notebook);
        
        // Connect signals from pages.
        account_list_pane.close.connect(on_close);
        account_list_pane.add_account.connect(on_add_account);
        account_list_pane.edit_account.connect(on_edit_account);
        account_list_pane.delete_account.connect(on_delete_account);
        add_edit_pane.ok.connect(on_save_add_or_edit);
        add_edit_pane.cancel.connect(on_cancel_back_to_list);
        add_edit_pane.size_changed.connect(() => { resize(1, 1); });
        remove_confirm_pane.ok.connect(on_delete_account_confirmed);
        remove_confirm_pane.cancel.connect(on_cancel_back_to_list);
        remove_fail_pane.ok.connect(on_cancel_back_to_list);
        
        // Set default page.
        account_list_pane.present();
        
        notebook.show_border = false;
        notebook.show_tabs = false;
        get_content_area().pack_start(notebook, true, true, 0);
        
        set_default_response(Gtk.ResponseType.OK);
        
        notebook.show_all(); // Required due to longstanding Gtk.Notebook bug
    }
    
    private void on_close() {
        destroy();
    }
    
    private void on_add_account() {
        add_edit_pane.reset_all();
        add_edit_pane.set_mode(AddEditPage.PageMode.ADD);
        add_edit_pane.present();
    }
    
    // Grab the account info.  While the addresses passed into this method should *always* be
    // available in Geary, we double-check to be defensive.
    private Geary.AccountInformation? get_account_info_for_email(string email_address) {
    Gee.Map<string, Geary.AccountInformation> accounts;
        try {
            accounts = Geary.Engine.instance.get_accounts();
        } catch (Error e) {
            debug("Error getting account info: %s", e.message);
            
            return null;
        }
        
        if (!accounts.has_key(email_address)) {
            debug("Unable to get account info for: %s", email_address);
            
            return null;
        }
        
        return accounts.get(email_address);
    }
    
    private void on_edit_account(string email_address) {
        on_edit_account_async.begin(email_address);
    }
    
    private async void on_edit_account_async(string email_address) {
        Geary.AccountInformation? account = get_account_info_for_email(email_address);
        if (account == null)
            return;
        
        try {
            yield account.get_passwords_async(Geary.CredentialsMediator.ServiceFlag.IMAP |
                Geary.CredentialsMediator.ServiceFlag.SMTP);
        } catch (Error err) {
            debug("Unable to fetch password(s) for account: %s", err.message);
        }
        
        add_edit_pane.set_mode(AddEditPage.PageMode.EDIT);
        add_edit_pane.set_account_information(account);
        add_edit_pane.present();
    }
    
    private void on_delete_account(string email_address) {
        Geary.AccountInformation? account = get_account_info_for_email(email_address);
        if (account == null)
            return;
        
        // Check for open composer windows.
        bool composer_window_found = false;
        Gee.List<ComposerWindow>? windows = 
            GearyApplication.instance.get_composer_windows_for_account(account);
        
        if (windows != null) {
            foreach (ComposerWindow cw in windows) {
                if (cw.account.information == account &&
                    cw.compose_type != ComposerWindow.ComposeType.NEW_MESSAGE) {
                    composer_window_found = true;
                    
                    break;
                }
            }
        }
        
        if (composer_window_found) {
            // Warn user that account cannot be deleted until composer is closed.
            remove_fail_pane.present();
        } else {
            // Send user to confirmation screen.
            remove_confirm_pane.set_account(account);
            remove_confirm_pane.present();
        }
    }
    
    private void on_delete_account_confirmed(Geary.AccountInformation? account) {
        assert(account != null); // Should not be able to happen since we checked earlier.
        
        // Remove account, then set the page back to the account list.
        GearyApplication.instance.remove_account_async.begin(account, null, () => {
            account_list_pane.present(); });
    }
    
    private void on_save_add_or_edit(Geary.AccountInformation info) {
        // Show the busy spinner.
        spinner_pane.present();
        
        // For account edits, we only need to validate the connection if the credentials have changed.
        bool validate_connection = true;
        if (add_edit_pane.get_mode() == AddEditPage.PageMode.EDIT && info.is_copy()) {
            Geary.AccountInformation? real_info =
                GearyApplication.instance.get_real_account_information(info);
            if (real_info != null) {
                validate_connection = !real_info.imap_credentials.equals(info.imap_credentials) ||
                    (info.smtp_credentials != null && !real_info.smtp_credentials.equals(info.smtp_credentials));
            }
        }
        
        // Validate account.
        GearyApplication.instance.validate_async.begin(info, validate_connection, null,
            on_save_add_or_edit_completed);
    }
    
    private void on_save_add_or_edit_completed(Object? source, AsyncResult result) {
        Geary.Engine.ValidationResult validation_result =
            GearyApplication.instance.validate_async.end(result);
        
        // If account was successfully added return to the account list. Otherwise, go back to the
        // account add page so the user can try again.
        if (validation_result == Geary.Engine.ValidationResult.OK) {
            account_list_pane.present();
        } else {
            add_edit_pane.set_validation_result(validation_result);
            add_edit_pane.present();
        }
    }
    
    private void on_cancel_back_to_list() {
        account_list_pane.present();
    }
}

