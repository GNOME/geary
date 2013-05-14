/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// List of accounts.  Used with AccountDialog.
public class AccountDialogAccountListPane : AccountDialogPane {
    public enum Column {
        ACCOUNT_NICKNAME = 0,
        ACCOUNT_ADDRESS;
    }
    
    private Gtk.TreeView list_view;
    private Gtk.ListStore list_model = new Gtk.ListStore(2, typeof (string), typeof (string));
    private Gtk.Action edit_action;
    private Gtk.Action delete_action;
    
    public signal void add_account();
    
    public signal void edit_account(string email_address);
    
    public signal void delete_account(string email_address);
    
    public signal void close();
    
    public AccountDialogAccountListPane(Gtk.Notebook notebook) {
        base(notebook);
        Gtk.Builder builder = GearyApplication.instance.create_builder("account_list.glade");
        pack_end((Gtk.Box) builder.get_object("container"));
        Gtk.ActionGroup actions = (Gtk.ActionGroup) builder.get_object("account list actions");
        edit_action = actions.get_action("edit_account");
        delete_action = actions.get_action("delete_account");
        
        // Set up list.
        list_view = (Gtk.TreeView) builder.get_object("account_list");
        list_view.set_model(list_model);
        list_view.insert_column_with_attributes(-1, "Nickname", new Gtk.CellRendererText(), "text",
            Column.ACCOUNT_NICKNAME);
        list_view.get_column(Column.ACCOUNT_NICKNAME).set_expand(true);
        list_view.insert_column_with_attributes(-1, "Address", new Gtk.CellRendererText(), "text",
            Column.ACCOUNT_ADDRESS);
        list_view.get_column(Column.ACCOUNT_ADDRESS).set_expand(true);
        list_view.reorderable = true;
        
        // Get all accounts and add them to a list.
        Gee.LinkedList<Geary.AccountInformation> account_list =
            new Gee.LinkedList<Geary.AccountInformation>();
        try {
            account_list.insert_all(0, Geary.Engine.instance.get_accounts().values);
        } catch (Error e) {
            debug("Error enumerating accounts: %s", e.message);
        }
        
        // Sort accounts and add them to the UI.
        account_list.sort(Geary.AccountInformation.compare_ascending);
        foreach (Geary.AccountInformation account in account_list)
            on_account_added(account);
        
        // Hook up signals.
        actions.get_action("close").activate.connect(() => { close(); });
        actions.get_action("add_account").activate.connect(() => { add_account(); });
        edit_action.activate.connect(notify_edit_account);
        delete_action.activate.connect(notify_delete_account);
        list_view.get_selection().changed.connect(update_buttons);
        list_view.button_press_event.connect(on_button_press);
        list_model.row_deleted.connect(update_ordinals);
        
        // Theme hint: "join" the toolbar to the scrolled window above it.
        Gtk.Toolbar toolbar = (Gtk.Toolbar) builder.get_object("toolbar");
        Gtk.ScrolledWindow scroll = (Gtk.ScrolledWindow) builder.get_object("scrolledwindow");
        toolbar.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);
        scroll.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
        
        // Watch for accounts to be added/removed.
        Geary.Engine.instance.account_added.connect(on_account_added);
        Geary.Engine.instance.account_removed.connect(on_account_removed);
    }
    
    private void notify_edit_account() {
        string? account = get_selected_account();
        if (account != null)
            edit_account(account);
    }
    
    private void notify_delete_account() {
        string? account = get_selected_account();
        if (account != null)
            delete_account(account);
    }
    
    private bool on_button_press(Gdk.EventButton event) {
        if (event.type != Gdk.EventType.2BUTTON_PRESS)
            return false;
        
        // Get the path.
        int cell_x;
        int cell_y;
        Gtk.TreePath? path;
        list_view.get_path_at_pos((int) event.x, (int) event.y, out path, null, out cell_x, out cell_y);
        if (path == null)
            return false;
        
        // If the user didn't click on an element in the list, we've already returned.
        notify_edit_account();
        return true;
    }
    
    // Returns the email address of the selected account.  Returns null if no account is selected.
    private string? get_selected_account() {
        if (list_view.get_selection().count_selected_rows() != 1)
            return null;
        
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        Gtk.TreePath path = list_view.get_selection().get_selected_rows(out model).nth_data(0);
        if (!list_model.get_iter(out iter, path))
            return null;
        
        string? account = null;
        list_model.get(iter, Column.ACCOUNT_ADDRESS, out account);
        return account;
    }
    
    private void update_buttons() {
        edit_action.sensitive = get_selected_account() != null;
        delete_action.sensitive = edit_action.sensitive &&
            GearyApplication.instance.get_num_accounts() > 1;
    }
    
    private void on_account_added(Geary.AccountInformation account) {
        Gtk.TreeIter? iter = list_contains(account.email);
        if (iter != null)
            return; // Already listed.
        
        add_account_to_list(account.nickname, account.email);
        account.notify.connect(on_account_changed);
        update_buttons();
        update_ordinals();
    }
    
    private void on_account_removed(Geary.AccountInformation account) {
        remove_account_from_list(account.email);
        account.notify.disconnect(on_account_changed);
        update_buttons();
        update_ordinals();
    }
    
    // Adds an account to the list.
    // Note: does NOT check if the account is already listed.
    private void add_account_to_list(string nickname, string address) {
        Gtk.TreeIter iter;
        list_model.append(out iter);
        list_model.set(iter, Column.ACCOUNT_NICKNAME, nickname);
        list_model.set(iter, Column.ACCOUNT_ADDRESS, address);
    }
    
    // Removes an account on the list.
    private void remove_account_from_list(string address) {
        Gtk.TreeIter? iter = list_contains(address);
        if (iter == null)
            return;
        
        list_model.remove(iter);
    }
    
    private void on_account_changed(Object object, ParamSpec p) {
        Geary.AccountInformation account = (Geary.AccountInformation) object;
        
        Gtk.TreeIter? iter = list_contains(account.email);
        if (iter == null)
            return;
        
        // Since nickname is the only column that can change, just set it.
        list_model.set_value(iter, Column.ACCOUNT_NICKNAME, account.nickname);
    }
    
    // Returns TreeIter of the address in the account list, else null.
    private Gtk.TreeIter? list_contains(string address) {
        Gtk.TreeIter iter;
        
        if (!list_model.get_iter_first(out iter))
            return null;
        
        do {
            string list_address = "";
            list_model.get(iter, Column.ACCOUNT_ADDRESS, out list_address);
            if (list_address == address)
                return iter;
        } while (list_model.iter_next(ref iter));
        
        return null;
    }
    
    // Call this to update ordinals when rows are added or removed.
    private void update_ordinals() {
        Gtk.TreeIter iter;
        if (!list_model.get_iter_first(out iter))
            return;
        
        Gee.Map<string, Geary.AccountInformation> all_accounts;
        try {
            all_accounts = Geary.Engine.instance.get_accounts();
        } catch (Error e) {
            debug("Error enumerating accounts: %s", e.message);
            
            return;
        }
        
        int i = 0;
        do {
            string? list_address = null;
            list_model.get(iter, Column.ACCOUNT_ADDRESS, out list_address);
            if (list_address != null) {
                Geary.AccountInformation account = all_accounts.get(list_address);
                
                // To prevent unnecessary work, only set ordinal if there's a change.
                if (i != account.ordinal) {
                    account.ordinal = i;
                    account.store_async.begin(null);
                }
            }
            
            i++;
        } while (list_model.iter_next(ref iter));
    }
}

