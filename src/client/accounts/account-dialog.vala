/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AccountDialog : Gtk.Dialog {
    private const int MARGIN = 12;
    
    private Gtk.Stack stack = new Gtk.Stack();
    private AccountDialogAccountListPane account_list_pane;
    private AccountDialogAddEditPane add_edit_pane;
    private AccountDialogSpinnerPane spinner_pane;
    private AccountDialogRemoveConfirmPane remove_confirm_pane;
    private AccountDialogRemoveFailPane remove_fail_pane;
    private Gtk.HeaderBar headerbar = new Gtk.HeaderBar();
    
    public AccountDialog(Gtk.Window parent) {
        set_size_request(450, -1); // Sets min size.
        headerbar.title = _("Accounts");
        headerbar.show_close_button = true;
        set_transient_for(parent);
        set_modal(true);
        set_titlebar (headerbar);
        get_content_area().margin_top = MARGIN;
        get_content_area().margin_left = MARGIN;
        get_content_area().margin_right = MARGIN;
        get_content_area().margin_bottom = MARGIN;
        
        // Add pages to stack.
        account_list_pane = new AccountDialogAccountListPane(stack);
        add_edit_pane = new AccountDialogAddEditPane(stack);
        spinner_pane = new AccountDialogSpinnerPane(stack);
        remove_confirm_pane = new AccountDialogRemoveConfirmPane(stack);
        remove_fail_pane = new AccountDialogRemoveFailPane(stack);
        
        // Connect signals from pages.
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
        
        get_content_area().pack_start(stack, true, true, 0);
        
        set_default_response(Gtk.ResponseType.OK);
        
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
            yield account.get_passwords_async(Geary.ServiceFlag.IMAP | Geary.ServiceFlag.SMTP);
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
        bool composer_widget_found = false;
        Gee.List<ComposerWidget>? widgets = 
            GearyApplication.instance.controller.get_composer_widgets_for_account(account);
        
        if (widgets != null) {
            foreach (ComposerWidget cw in widgets) {
                if (cw.account.information == account &&
                    cw.compose_type != ComposerWidget.ComposeType.NEW_MESSAGE) {
                    composer_widget_found = true;
                    
                    break;
                }
            }
        }
        
        if (composer_widget_found) {
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
        GearyApplication.instance.controller.remove_account_async.begin(account, null, () => {
            account_list_pane.present(); });
    }
    
    private void on_save_add_or_edit(Geary.AccountInformation info) {
        // Show the busy spinner.
        spinner_pane.present();
        
        // determine if editing an existing Account or adding a new one
        Geary.Engine.ValidationOption options = (add_edit_pane.get_mode() == AddEditPage.PageMode.EDIT)
            ? Geary.Engine.ValidationOption.UPDATING_EXISTING
            : Geary.Engine.ValidationOption.NONE;
        
        // For account edits, we only need to validate the connection if the credentials have changed.
        bool validate_connection = true;
        if (add_edit_pane.get_mode() == AddEditPage.PageMode.EDIT && info.is_copy()) {
            Geary.AccountInformation? real_info =
                GearyApplication.instance.controller.get_real_account_information(info);
            if (real_info != null) {
                validate_connection = !real_info.imap_credentials.equal_to(info.imap_credentials) ||
                    (info.smtp_credentials != null && !real_info.smtp_credentials.equal_to(info.smtp_credentials));
            }
        }
        
        if (validate_connection)
            options |= Geary.Engine.ValidationOption.CHECK_CONNECTIONS;
        
        // Validate account.
        do_save_or_edit_async.begin(info, options);
    }
    
    private async void do_save_or_edit_async(Geary.AccountInformation account_information,
        Geary.Engine.ValidationOption options) {
        Geary.Engine.ValidationResult validation_result = Geary.Engine.ValidationResult.OK;
        for (;;) {
            validation_result = yield GearyApplication.instance.controller.validate_async(
                account_information, options);
            
            // If account was successfully added return to the account list.
            if (validation_result == Geary.Engine.ValidationResult.OK) {
                account_list_pane.present();
                
                return;
            }
            
            // check for TLS warnings
            bool retry_required;
            validation_result = yield GearyApplication.instance.controller.validation_check_for_tls_warnings_async(
                account_information, validation_result, out retry_required);
            if (!retry_required)
                break;
        }
        
        // Otherwise, go back to the account add page so the user can try again.
        add_edit_pane.set_validation_result(validation_result);
        add_edit_pane.present();
    }
    
    private void on_cancel_back_to_list() {
        account_list_pane.present();
    }
}

