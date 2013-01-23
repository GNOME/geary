/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// List of accounts.  Used with AccountDialog.
public class AccountDialogAccountListPane : Gtk.Box {
    private Gtk.TreeView list_view;
    private Gtk.ListStore list_model = new Gtk.ListStore(1, typeof (string));
    private Gtk.ActionGroup actions;
    
    public signal void add_account();
    
    public signal void close();
    
    public AccountDialogAccountListPane() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("account_list.glade");
        pack_end((Gtk.Box) builder.get_object("container"));
        
        list_view = (Gtk.TreeView) builder.get_object("account_list");
        list_view.set_model(list_model);
        list_view.insert_column_with_attributes (-1, "Account", new Gtk.CellRendererText (), "text", 0);
        actions = (Gtk.ActionGroup) builder.get_object("account list actions");
        actions.get_action("close").activate.connect(() => { close(); });
        actions.get_action("add_account").activate.connect(() => { add_account(); });
        
        // Theme hint: "join" the toolbar to the scrolled window above it.
        Gtk.Toolbar toolbar = (Gtk.Toolbar) builder.get_object("toolbar");
        Gtk.ScrolledWindow scroll = (Gtk.ScrolledWindow) builder.get_object("scrolledwindow");
        toolbar.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);
        scroll.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
        
        // Add email accounts to the list.
        try {
            foreach (string address in Geary.Engine.instance.get_accounts().keys)
                add_account_to_list(address);
        } catch (Error e) {
            debug("Error enumerating accounts: %s", e.message);
        }
        
        // Watch for accounts to be added/removed.
        Geary.Engine.instance.account_added.connect(on_account_added);
        Geary.Engine.instance.account_removed.connect(on_account_removed);
    }
    
    private void on_account_added(Geary.AccountInformation account) {
        Gtk.TreeIter? iter = list_contains(account.email);
        if (iter != null)
            return; // Already listed.
        
        add_account_to_list(account.email);
    }
    
    private void on_account_removed(Geary.AccountInformation account) {
        remove_account_from_list(account.email);
    }
    
    // Adds an account to the list.
    // Note: does NOT check if the account is already listed.
    private void add_account_to_list(string address) {
        Gtk.TreeIter iter;
        list_model.append(out iter);
        list_model.set(iter, 0, address);
    }
    
    // Removes an account on the list.
    private void remove_account_from_list(string address) {
        Gtk.TreeIter? iter = list_contains(address);
        if (iter == null)
            return;
        
        list_model.remove(iter);
    }
    
    // Returns TreeIter of the address in the account list, else null.
    private Gtk.TreeIter? list_contains(string address) {
        Gtk.TreeIter iter;
        
        if (!list_model.get_iter_first(out iter))
            return null;
        
        do {
            string list_address = "";
            list_model.get(iter, 0, out list_address);
            if (list_address == address)
                return iter;
        } while (list_model.iter_next(ref iter));
        
        return null;
    }
}

