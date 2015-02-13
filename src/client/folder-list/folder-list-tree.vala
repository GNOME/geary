/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FolderList.Tree : Gtk.Box {
    public const Gtk.TargetEntry[] TARGET_ENTRY_LIST = {
        { "application/x-geary-mail", Gtk.TargetFlags.SAME_APP, 0 }
    };
    
    private class FolderTree : Sidebar.Tree {
        
        public FolderTree(Gtk.TargetEntry[] target_entries, Gdk.DragAction actions,
            Sidebar.Tree.ExternalDropHandler drop_handler, Gtk.IconTheme? theme = null) {
            base(target_entries, actions, drop_handler, theme);
        }
        
        public override bool accept_cursor_changed() {
            return GearyApplication.instance.controller.can_switch_conversation_view();
        }
    }
    
    private const int INBOX_ORDINAL = -2; // First account branch is zero
    private const int SEARCH_ORDINAL = -1;
    
    private const int FOLDER_LIST_WIDTH = 100;
    
    public signal void folder_selected(Geary.Folder? folder);
    public signal void copy_conversation(Geary.Folder folder);
    public signal void move_conversation(Geary.Folder folder);
    
    private Gee.HashMap<Geary.Account, AccountBranch> account_branches
        = new Gee.HashMap<Geary.Account, AccountBranch>();
    private InboxesBranch inboxes_branch = new InboxesBranch();
    private SearchBranch? search_branch = null;
    private NewMessagesMonitor? monitor = null;
    private Sidebar.Tree tree;
    private bool switching_folders = false;
    
    public Tree() {
        Object(orientation: Gtk.Orientation.VERTICAL);
        
        tree = new FolderTree(new Gtk.TargetEntry[0], Gdk.DragAction.ASK, drop_handler);
        tree.entry_selected.connect(on_entry_selected);

        // Set self as a drag destination.
        Gtk.drag_dest_set(tree, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            TARGET_ENTRY_LIST, Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        
        // GtkTreeView binds Ctrl+N to "move cursor to next".  Not so interested in that, so we'll
        // remove it.
        unowned Gtk.BindingSet? binding_set = Gtk.BindingSet.find("GtkTreeView");
        assert(binding_set != null);
        Gtk.BindingEntry.remove(binding_set, Gdk.Key.N, Gdk.ModifierType.CONTROL_MASK);
        
        // folder list
        Gtk.ScrolledWindow folder_list_scrolled = new Gtk.ScrolledWindow(null, null);
        folder_list_scrolled.set_size_request(FOLDER_LIST_WIDTH, -1);
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add(tree);
        Gtk.Frame folder_frame = new Gtk.Frame(null);
        folder_frame.shadow_type = Gtk.ShadowType.IN;
        folder_frame.get_style_context().add_class("folder_frame");
        folder_frame.add(folder_list_scrolled);
        
        Gtk.ComboBox combo = new Gtk.ComboBox.with_model(tree.store);
        Gtk.CellRendererText renderer = new Gtk.CellRendererText();
        combo.pack_start(renderer, true);
        combo.add_attribute(renderer, "markup", Sidebar.Tree.Columns.NAME);
        Gtk.TreeSelection select = tree.get_selection();
        select.changed.connect((selection) => {
            Gtk.TreeModel model;
            Gtk.TreeIter? iter = null;
            if (!switching_folders && selection.get_selected(out model, out iter)) {
                switching_folders = true;
                combo.set_active_iter(iter);
                switching_folders = false;
            }
        });
        combo.changed.connect(() => {
            Gtk.TreeIter? iter = null;
            if (!switching_folders && combo.get_active_iter(out iter)) {
                switching_folders = true;
                tree.set_cursor(tree.store.get_path(iter), null, false);
                switching_folders = false;
            }
        });
        
        pack_start(combo, false, false);
        pack_start(folder_frame);
        
        size_allocate.connect((allocation) => {
            if (allocation.height > 40) {
                folder_frame.show();
                combo.hide();
            } else {
                folder_frame.hide();
                combo.show();
            }
        });
    }
    
    ~Tree() {
        set_new_messages_monitor(null);
    }
    
    private void drop_handler(Gdk.DragContext context, Sidebar.Entry? entry,
        Gtk.SelectionData data, uint info, uint time) {
    }
    
    private FolderEntry? get_folder_entry(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        return (account_branch == null ? null :
            account_branch.get_entry_for_path(folder.path));
    }
    
    private void on_entry_selected(Sidebar.SelectableEntry selectable) {
        AbstractFolderEntry? abstract_folder_entry = selectable as AbstractFolderEntry;
        if (abstract_folder_entry != null)
            folder_selected(abstract_folder_entry.folder);
    }

    private void on_new_messages_changed(Geary.Folder folder, int count) {
        FolderEntry? entry = get_folder_entry(folder);
        if (entry != null)
            entry.set_has_new(count > 0);
        
        if (tree.has_branch(inboxes_branch)) {
            InboxFolderEntry? inbox_entry = inboxes_branch.get_entry_for_account(folder.account);
            if (inbox_entry != null)
                inbox_entry.set_has_new(count > 0);
        }
    }
    
    public void set_new_messages_monitor(NewMessagesMonitor? monitor) {
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
        if (!tree.has_branch(account_branch))
            tree.graft(account_branch, folder.account.information.ordinal);
        
        if (account_branches.size > 1 && !tree.has_branch(inboxes_branch))
            tree.graft(inboxes_branch, INBOX_ORDINAL); // The Inboxes branch comes first.
        if (folder.special_folder_type == Geary.SpecialFolderType.INBOX)
            inboxes_branch.add_inbox(folder);
        
        folder.account.information.notify["ordinal"].connect(on_ordinal_changed);
        account_branch.add_folder(folder);
    }

    public void remove_folder(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        assert(account_branch != null);
        assert(tree.has_branch(account_branch));
        
        // If this is the current folder, unselect it.
        Sidebar.Entry? entry = account_branch.get_entry_for_path(folder.path);
        
        // if not found or found but not selected, see if the folder is in the Inboxes branch
        if (tree.has_branch(inboxes_branch) && (entry == null || !tree.is_selected(entry))) {
            InboxFolderEntry? inbox_entry = inboxes_branch.get_entry_for_account(folder.account);
            if (inbox_entry != null && inbox_entry.folder == folder)
                entry = inbox_entry;
        }
        
        // if found and selected, report nothing is selected in preparation for its removal
        if (entry != null && tree.is_selected(entry))
            folder_selected(null);
        
        // if Inbox, remove from inboxes branch, selected or not
        if (folder.special_folder_type == Geary.SpecialFolderType.INBOX)
            inboxes_branch.remove_inbox(folder.account);
        
        account_branch.remove_folder(folder);
    }
    
    public void remove_account(Geary.Account account) {
        account.information.notify["ordinal"].disconnect(on_ordinal_changed);
        AccountBranch? account_branch = account_branches.get(account);
        if (account_branch != null) {
            // If a folder on this account is selected, unselect it.
            foreach (FolderEntry entry in account_branch.folder_entries.values) {
                if (tree.is_selected(entry)) {
                    folder_selected(null);
                    break;
                }
            }
            
            if (tree.has_branch(account_branch))
                tree.prune(account_branch);
            account_branches.unset(account);
        }
        
        Sidebar.Entry? entry = inboxes_branch.get_entry_for_account(account);
        if (entry != null && tree.is_selected(entry))
            folder_selected(null);
        
        inboxes_branch.remove_inbox(account);
        
        if (account_branches.size <= 1 && tree.has_branch(inboxes_branch))
            tree.prune(inboxes_branch);
    }
    
    public void select_folder(Geary.Folder folder) {
        FolderEntry? entry = get_folder_entry(folder);
        if (entry != null)
            tree.place_cursor(entry, false);
    }
    
    public bool select_inbox(Geary.Account account) {
        if (!tree.has_branch(inboxes_branch))
            return false;
        
        InboxFolderEntry? entry = inboxes_branch.get_entry_for_account(account);
        if (entry == null)
            return false;
        
        tree.place_cursor(entry, false);
        return true;
    }
    
    public override bool drag_motion(Gdk.DragContext context, int x, int y, uint time) {
        // Run the base version first.
        bool ret = base.drag_motion(context, x, y, time);

        // Update the cursor for copy or move.
        Gdk.ModifierType mask;
        double[] axes = new double[2];
        context.get_device().get_state(context.get_dest_window(), axes, out mask);
        if ((mask & Gdk.ModifierType.CONTROL_MASK) != 0) {
            Gdk.drag_status(context, Gdk.DragAction.COPY, time);
        } else {
            Gdk.drag_status(context, Gdk.DragAction.MOVE, time);
        }
        return ret;
    }
    
    private void on_ordinal_changed() {
        if (account_branches.size <= 1)
            return;
        
        // Remove branches where the ordinal doesn't match the graft position.
        Gee.ArrayList<AccountBranch> branches_to_reorder = new Gee.ArrayList<AccountBranch>();
        foreach (AccountBranch branch in account_branches.values) {
            if (tree.get_position_for_branch(branch) != branch.account.information.ordinal) {
                tree.prune(branch);
                branches_to_reorder.add(branch);
            }
        }
        
        // Re-add branches with new positions.
        foreach (AccountBranch branch in branches_to_reorder)
            tree.graft(branch, branch.account.information.ordinal);
    }
    
    public void set_search(Geary.SearchFolder search_folder) {
        if (search_branch != null && tree.has_branch(search_branch)) {
            // We already have a search folder.  If it's the same one, just
            // select it.  If it's a new search folder, remove the old one and
            // continue.
            if (search_folder == search_branch.get_search_folder()) {
                tree.place_cursor(search_branch.get_root(), false);
                return;
            } else {
                remove_search();
            }
        }
        
        search_branch = new SearchBranch(search_folder);
        tree.graft(search_branch, SEARCH_ORDINAL);
        tree.place_cursor(search_branch.get_root(), false);
    }
    
    public void remove_search() {
        if (search_branch != null) {
            tree.prune(search_branch);
            search_branch = null;
        }
    }
    
    public bool is_any_selected() {
        return tree.is_any_selected();
    }
}

