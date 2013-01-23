/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AccountDialog : Gtk.Dialog {
    private const int MARGIN = 12;
    
    private Gtk.Notebook notebook = new Gtk.Notebook();
    private AccountDialogAccountListPane account_list_pane = new AccountDialogAccountListPane();
    private AccountDialogAddEditPane add_edit_pane = new AccountDialogAddEditPane();
    private AccountSpinnerPage spinner_pane = new AccountSpinnerPage();
    private int add_edit_page_number;
    private int account_list_page_number;
    private int spinner_page_number;
    
    public AccountDialog() {
        set_size_request(450, -1); // Sets min size.
        title = _("Accounts");
        get_content_area().margin_top = MARGIN;
        get_content_area().margin_left = MARGIN;
        get_content_area().margin_right = MARGIN;
        
        // Add pages to notebook.
        account_list_page_number = notebook.append_page(account_list_pane, null);
        add_edit_page_number = notebook.append_page(add_edit_pane, null);
        spinner_page_number = notebook.append_page(spinner_pane, null);
        
        // Connect signals from pages.
        account_list_pane.close.connect(on_close);
        account_list_pane.add_account.connect(on_add_account);
        add_edit_pane.ok.connect(on_add_or_edit_account);
        add_edit_pane.cancel.connect(on_cancel_add_edit);
        add_edit_pane.size_changed.connect(() => { resize(1, 1); });
        
        // Set default page.
        notebook.set_current_page(account_list_page_number);
        
        notebook.show_border = false;
        notebook.show_tabs = false;
        get_content_area().pack_start(notebook, true, true, 0);
        
        notebook.show_all(); // Required due to longstanding Gtk.Notebook bug
    }
    
    private void on_close() {
        response(Gtk.ResponseType.CLOSE);
    }
    
    private void on_add_account() {
        notebook.set_current_page(add_edit_page_number);
    }
    
    private void on_add_or_edit_account(Geary.AccountInformation info) {
        // TODO: Edit existing account.
        
        // Show the busy spinner.
        notebook.set_current_page(spinner_page_number);
        
        // Validate account.
        GearyApplication.instance.validate_async.begin(info, null, on_add_or_edit_account_completed);
    }
    
    private void on_add_or_edit_account_completed(Object? source, AsyncResult result) {
        // If account was successfully added return to the account list. Otherwise, go back to the
        // account add page so the user can try again.
        if (GearyApplication.instance.validate_async.end(result))
            notebook.set_current_page(account_list_page_number);
        else
            notebook.set_current_page(add_edit_page_number);
    }
    
    private void on_cancel_add_edit() {
        notebook.set_current_page(account_list_page_number);
    }
}

