/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FolderList.Tree : Sidebar.Tree, Geary.BaseInterface {
    public const Gtk.TargetEntry[] TARGET_ENTRY_LIST = {
        { "application/x-geary-mail", Gtk.TargetFlags.SAME_APP, 0 }
    };

    private const int INBOX_ORDINAL = -2; // First account branch is zero
    private const int SEARCH_ORDINAL = -1;

    public signal void folder_selected(Geary.Folder? folder);
    public signal void copy_conversation(Geary.Folder folder);
    public signal void move_conversation(Geary.Folder folder);

    public Geary.Folder? selected { get ; private set; default = null; }

    private Gee.HashMap<Geary.Account, AccountBranch> account_branches
        = new Gee.HashMap<Geary.Account, AccountBranch>();
    private InboxesBranch inboxes_branch = new InboxesBranch();
    private SearchBranch? search_branch = null;
    private Application.NotificationContext? monitor = null;

    public Tree() {
        base(TARGET_ENTRY_LIST, Gdk.DragAction.ASK, drop_handler);
        base_ref();
        entry_selected.connect(on_entry_selected);

        // GtkTreeView binds Ctrl+N to "move cursor to next".  Not so interested in that, so we'll
        // remove it.
        unowned Gtk.BindingSet? binding_set = Gtk.BindingSet.find("GtkTreeView");
        assert(binding_set != null);
        Gtk.BindingEntry.remove(binding_set, Gdk.Key.N, Gdk.ModifierType.CONTROL_MASK);

        this.visible = true;
    }

    ~Tree() {
        set_new_messages_monitor(null);
        base_unref();
    }

    private void drop_handler(Gdk.DragContext context, Sidebar.Entry? entry,
        Gtk.SelectionData data, uint info, uint time) {
    }

    private FolderEntry? get_folder_entry(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        return (account_branch == null ? null :
            account_branch.get_entry_for_path(folder.path));
    }

    public override bool accept_cursor_changed() {
        bool can_switch = true;
        var parent = get_toplevel() as Application.MainWindow;
        if (parent != null) {
            can_switch = parent.close_composer(false);
        }
        return can_switch;
    }

    private void on_entry_selected(Sidebar.SelectableEntry selectable) {
        AbstractFolderEntry? abstract_folder_entry = selectable as AbstractFolderEntry;
        if (abstract_folder_entry != null) {
            this.selected = abstract_folder_entry.folder;
            folder_selected(abstract_folder_entry.folder);
        }
    }

    private void on_new_messages_changed(Geary.Folder folder, int count) {
        FolderEntry? entry = get_folder_entry(folder);
        if (entry != null)
            entry.set_has_new(count > 0);

        if (has_branch(inboxes_branch)) {
            InboxFolderEntry? inbox_entry = inboxes_branch.get_entry_for_account(folder.account);
            if (inbox_entry != null)
                inbox_entry.set_has_new(count > 0);
        }
    }

    public void set_new_messages_monitor(Application.NotificationContext? monitor) {
        if (this.monitor != null) {
            this.monitor.new_messages_arrived.disconnect(on_new_messages_changed);
            this.monitor.new_messages_retired.disconnect(on_new_messages_changed);
        }

        this.monitor = monitor;
        if (this.monitor != null) {
            this.monitor.new_messages_arrived.connect(on_new_messages_changed);
            this.monitor.new_messages_retired.connect(on_new_messages_changed);
        }
    }

    public void set_user_folders_root_name(Geary.Account account, string name) {
        if (account_branches.has_key(account))
            account_branches.get(account).user_folder_group.rename(name);
    }

    public void add_folder(Geary.Folder folder) {
        if (!account_branches.has_key(folder.account))
            account_branches.set(folder.account, new AccountBranch(folder.account));

        AccountBranch account_branch = account_branches.get(folder.account);
        if (!has_branch(account_branch))
            graft(account_branch, folder.account.information.ordinal);

        if (account_branches.size > 1 && !has_branch(inboxes_branch))
            graft(inboxes_branch, INBOX_ORDINAL); // The Inboxes branch comes first.
        if (folder.special_folder_type == Geary.SpecialFolderType.INBOX)
            inboxes_branch.add_inbox(folder);

        folder.account.information.notify["ordinal"].connect(on_ordinal_changed);
        account_branch.add_folder(folder);
    }

    public void remove_folder(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        assert(account_branch != null);
        assert(has_branch(account_branch));

        // If this is the current folder, unselect it.
        Sidebar.Entry? entry = account_branch.get_entry_for_path(folder.path);

        // if not found or found but not selected, see if the folder is in the Inboxes branch
        if (has_branch(inboxes_branch) && (entry == null || !is_selected(entry))) {
            InboxFolderEntry? inbox_entry = inboxes_branch.get_entry_for_account(folder.account);
            if (inbox_entry != null && inbox_entry.folder == folder)
                entry = inbox_entry;
        }

        // if found and selected, report nothing is selected in preparation for its removal
        if (entry != null && is_selected(entry)) {
            deselect_folder();
        }

        // if Inbox, remove from inboxes branch, selected or not
        if (folder.special_folder_type == Geary.SpecialFolderType.INBOX)
            inboxes_branch.remove_inbox(folder.account);

        account_branch.remove_folder(folder);
    }

    public void remove_account(Geary.Account account) {
        account.information.notify["ordinal"].disconnect(on_ordinal_changed);

        // If a folder on this account is selected, unselect it.
        if (this.selected != null &&
            this.selected.account == account) {
            deselect_folder();
        }

        AccountBranch? account_branch = account_branches.get(account);
        if (account_branch != null) {
            if (has_branch(account_branch))
                prune(account_branch);
            account_branches.unset(account);
        }

        inboxes_branch.remove_inbox(account);

        if (account_branches.size <= 1 && has_branch(inboxes_branch))
            prune(inboxes_branch);
    }

    public void select_folder(Geary.Folder to_select) {
        if (this.selected != to_select) {
            bool selected = false;
            if (to_select.special_folder_type == INBOX) {
                selected = select_inbox(to_select.account);
            }

            if (!selected) {
                FolderEntry? entry = get_folder_entry(to_select);
                if (entry != null) {
                    place_cursor(entry, false);
                }
            }
        }
    }

    public bool select_inbox(Geary.Account account) {
        if (!has_branch(inboxes_branch))
            return false;

        InboxFolderEntry? entry = inboxes_branch.get_entry_for_account(account);
        if (entry == null)
            return false;

        place_cursor(entry, false);
        return true;
    }

    public void deselect_folder() {
        Gtk.TreeModel model = get_model();
        Gtk.TreeIter iter;
        if (model.get_iter_first(out iter)) {
            Gtk.TreePath? first = model.get_path(iter);
            if (first != null) {
                set_cursor(first, null, false);
            }
        }

        get_selection().unselect_all();
        this.selected = null;
        folder_selected(null);
    }

    private void on_ordinal_changed() {
        if (account_branches.size <= 1)
            return;

        // Remove branches where the ordinal doesn't match the graft position.
        Gee.ArrayList<AccountBranch> branches_to_reorder = new Gee.ArrayList<AccountBranch>();
        foreach (AccountBranch branch in account_branches.values) {
            if (get_position_for_branch(branch) != branch.account.information.ordinal) {
                prune(branch);
                branches_to_reorder.add(branch);
            }
        }

        // Re-add branches with new positions.
        foreach (AccountBranch branch in branches_to_reorder)
            graft(branch, branch.account.information.ordinal);
    }

    public void set_search(Geary.Engine engine,
                           Geary.SearchFolder search_folder) {
        if (search_branch != null && has_branch(search_branch)) {
            // We already have a search folder.  If it's the same one, just
            // select it.  If it's a new search folder, remove the old one and
            // continue.
            if (search_folder == search_branch.get_search_folder()) {
                place_cursor(search_branch.get_root(), false);
                return;
            } else {
                remove_search();
            }
        }

        search_branch = new SearchBranch(search_folder, engine);
        graft(search_branch, SEARCH_ORDINAL);
        place_cursor(search_branch.get_root(), false);
    }

    public void remove_search() {
        if (search_branch != null) {
            prune(search_branch);
            search_branch = null;
        }
    }
}

