/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderList : Sidebar.Tree {

    public const Gtk.TargetEntry[] TARGET_ENTRY_LIST = {
        { "application/x-geary-mail", Gtk.TargetFlags.SAME_APP, 0 }
    };
    
    private class SpecialGrouping : Sidebar.Grouping {
        // Must be != 0 and unique among SpecialGroupings.  Bigger comes later
        // in the list.  If < 0, it comes before non-SpecialGroupings.
        public int position { get; private set; }
        
        public SpecialGrouping(int position, string name, Icon? open_icon,
            Icon? closed_icon = null, string? tooltip = null) {
            base(name, open_icon, closed_icon, tooltip);
            
            this.position = position;
        }
    }

    private class AccountBranch : Sidebar.Branch {
        public Geary.Account account { get; private set; }
        public SpecialGrouping uncommon_special_group { get; private set; }
        public SpecialGrouping user_folder_group { get; private set; }
        public Gee.HashMap<Geary.FolderPath, FolderEntry> folder_entries { get; private set; }
        
        public AccountBranch(Geary.Account account) {
            base(new Sidebar.Grouping(account.information.nickname, new ThemedIcon("emblem-mail")),
                Sidebar.Branch.Options.NONE, normal_folder_comparator, special_folder_comparator);
            
            this.account = account;
            uncommon_special_group = new SpecialGrouping(1, _("More"),
                new ThemedIcon("folder-open"), new ThemedIcon("folder"));
            user_folder_group = new SpecialGrouping(2, "",
                IconFactory.instance.get_custom_icon("tags", IconFactory.ICON_SIDEBAR));
            folder_entries = new Gee.HashMap<Geary.FolderPath, FolderEntry>();
            
            account.information.notify["nickname"].connect(on_nicknamed_changed);
            
            graft(get_root(), uncommon_special_group, special_folder_comparator);
            graft(get_root(), user_folder_group);
        }
        
        ~AccountBranch() {
            account.information.notify["nickname"].disconnect(on_nicknamed_changed);
        }
        
        private void on_nicknamed_changed() {
            ((Sidebar.Grouping) get_root()).rename(account.information.nickname);
        }
        
        private static int special_grouping_comparator(Sidebar.Entry a, Sidebar.Entry b) {
            SpecialGrouping? grouping_a = a as SpecialGrouping;
            SpecialGrouping? grouping_b = b as SpecialGrouping;
            
            assert(grouping_a != null || grouping_b != null);
            
            int position_a = (grouping_a != null ? grouping_a.position : 0);
            int position_b = (grouping_b != null ? grouping_b.position : 0);
            
            return position_a - position_b;
        }
        
        private static int special_folder_comparator(Sidebar.Entry a, Sidebar.Entry b) {
            if (a is Sidebar.Grouping || b is Sidebar.Grouping)
                return special_grouping_comparator(a, b);
            
            assert(a is FolderEntry);
            assert(b is FolderEntry);
            
            FolderEntry entry_a = (FolderEntry) a;
            FolderEntry entry_b = (FolderEntry) b;
            Geary.SpecialFolderType type_a = entry_a.folder.get_special_folder_type();
            Geary.SpecialFolderType type_b = entry_b.folder.get_special_folder_type();
            
            assert(type_a != Geary.SpecialFolderType.NONE);
            assert(type_b != Geary.SpecialFolderType.NONE);
            
            // Special folders are ordered by their enum value.
            return (int) type_a - (int) type_b;
        }
            
        private static int normal_folder_comparator(Sidebar.Entry a, Sidebar.Entry b) {
            // Non-special folders are compared based on name.
            return a.get_sidebar_name().collate(b.get_sidebar_name());
        }
        
        public FolderEntry? get_entry_for_path(Geary.FolderPath folder_path) {
            return folder_entries.get(folder_path);
        }
        
        public void add_folder(Geary.Folder folder) {
            FolderEntry folder_entry = new FolderEntry(folder);
            Geary.SpecialFolderType special_folder_type = folder.get_special_folder_type();
            if (special_folder_type != Geary.SpecialFolderType.NONE) {
                switch (special_folder_type) {
                    // These special folders go in the root of the account.
                    case Geary.SpecialFolderType.INBOX:
                    case Geary.SpecialFolderType.FLAGGED:
                    case Geary.SpecialFolderType.IMPORTANT:
                    case Geary.SpecialFolderType.ALL_MAIL:
                        graft(get_root(), folder_entry);
                    break;
                    
                    // Others go in the "More" grouping.
                    default:
                        graft(uncommon_special_group, folder_entry);
                    break;
                }
            } else if (folder.get_path().get_parent() == null) {
                // Top-level folders get put in our special user folders group.
                graft(user_folder_group, folder_entry);
            } else {
                Sidebar.Entry? entry = folder_entries.get(folder.get_path().get_parent());
                if (entry == null) {
                    debug("Could not add folder %s of type %s to folder list", folder.to_string(),
                        special_folder_type.to_string());
                    return;
                }
                graft(entry, folder_entry);
            }
            
            folder_entries.set(folder.get_path(), folder_entry);
        }
        
        public void remove_folder(Geary.Folder folder) {
            Sidebar.Entry? entry = folder_entries.get(folder.get_path());
            if(entry == null) {
                debug("Could not remove folder %s", folder.to_string());
                return;
            }
            
            prune(entry);
            folder_entries.unset(folder.get_path());
        }
    }
    
    private class FolderEntry : Object, Sidebar.Entry, Sidebar.InternalDropTargetEntry,
        Sidebar.SelectableEntry, Sidebar.EmphasizableEntry {
        public Geary.Folder folder { get; private set; }
        private bool has_unread;
        
        public FolderEntry(Geary.Folder folder) {
            this.folder = folder;
            has_unread = false;
        }
        
        public virtual string get_sidebar_name() {
            return folder.get_display_name();
        }
        
        public string? get_sidebar_tooltip() {
            return null;
        }
        
        public Icon? get_sidebar_icon() {
            switch (folder.get_special_folder_type()) {
                case Geary.SpecialFolderType.NONE:
                    return IconFactory.instance.get_custom_icon("tag", IconFactory.ICON_SIDEBAR);
                
                case Geary.SpecialFolderType.INBOX:
                    return new ThemedIcon("mail-inbox");
                
                case Geary.SpecialFolderType.DRAFTS:
                    return new ThemedIcon("accessories-text-editor");
                
                case Geary.SpecialFolderType.SENT:
                    return new ThemedIcon("mail-sent");
                
                case Geary.SpecialFolderType.FLAGGED:
                    return new ThemedIcon("starred");
                
                case Geary.SpecialFolderType.IMPORTANT:
                    return new ThemedIcon("task-due");
                
                case Geary.SpecialFolderType.ALL_MAIL:
                    return IconFactory.instance.get_custom_icon("mail-archive", IconFactory.ICON_SIDEBAR);
                
                case Geary.SpecialFolderType.SPAM:
                    return new ThemedIcon("mail-mark-junk");
                
                case Geary.SpecialFolderType.TRASH:
                    return new ThemedIcon("user-trash");
                
                case Geary.SpecialFolderType.OUTBOX:
                    return new ThemedIcon("mail-outbox");
                
                default:
                    assert_not_reached();
            }
        }
        
        public virtual string to_string() {
            return "FolderEntry: " + get_sidebar_name();
        }
        
        public bool is_emphasized() {
            return has_unread;
        }
        
        public void set_has_unread(bool has_unread) {
            if (this.has_unread == has_unread)
                return;
            
            this.has_unread = has_unread;
            is_emphasized_changed(has_unread);
        }

        public bool internal_drop_received(Gdk.DragContext context, Gtk.SelectionData data) {
            // Copy or move?
            Gdk.ModifierType mask;
            double[] axes = new double[2];
            context.get_device().get_state(context.get_dest_window(), axes, out mask);
            MainWindow main_window = GearyApplication.instance.get_main_window() as MainWindow;
            if ((mask & Gdk.ModifierType.CONTROL_MASK) != 0) {
                main_window.folder_list.copy_conversation(folder);
            } else {
                main_window.folder_list.move_conversation(folder);
            }

            return true;
        }
    }
    
    public signal void folder_selected(Geary.Folder? folder);
    public signal void copy_conversation(Geary.Folder folder);
    public signal void move_conversation(Geary.Folder folder);
    
    private Gee.HashMap<Geary.Account, AccountBranch> account_branches
        = new Gee.HashMap<Geary.Account, AccountBranch>();
    private int total_accounts = 0;
    private NewMessagesMonitor? monitor = null;
    
    public FolderList() {
        base(new Gtk.TargetEntry[0], Gdk.DragAction.ASK, drop_handler);
        entry_selected.connect(on_entry_selected);

        // Set self as a drag destination.
        Gtk.drag_dest_set(this, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            TARGET_ENTRY_LIST, Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
    }
    
    ~FolderList() {
        set_new_messages_monitor(null);
    }
    
    private void drop_handler(Gdk.DragContext context, Sidebar.Entry? entry,
        Gtk.SelectionData data, uint info, uint time) {
    }
    
    private FolderEntry? get_folder_entry(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        return (account_branch == null ? null :
            account_branch.get_entry_for_path(folder.get_path()));
    }
    
    private void on_entry_selected(Sidebar.SelectableEntry selectable) {
        if (selectable is FolderEntry) {
            folder_selected(((FolderEntry) selectable).folder);
        }
    }

    private void on_new_messages_changed(Geary.Folder folder, int count) {
        FolderEntry? entry = get_folder_entry(folder);
        if (entry != null)
            entry.set_has_unread(count > 0);
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
        if (!has_branch(account_branch))
            graft(account_branch, total_accounts++);
        
        account_branch.add_folder(folder);
    }

    public void remove_folder(Geary.Folder folder) {
        AccountBranch? account_branch = account_branches.get(folder.account);
        assert(account_branch != null);
        assert(has_branch(account_branch));
        
        // If this is the current folder, unselect it.
        Sidebar.Entry? entry = account_branch.folder_entries.get(folder.get_path());
        if (entry != null && is_selected(entry))
            folder_selected(null);
        
        account_branch.remove_folder(folder);
    }
    
    public void remove_account(Geary.Account account) {
        AccountBranch? account_branch = account_branches.get(account);
        if (account_branch != null) {
            // If a folder on this account is selected, unselect it.
            foreach (FolderEntry entry in account_branch.folder_entries.values) {
                if (is_selected(entry)) {
                    folder_selected(null);
                    break;
                }
            }
            
            if (has_branch(account_branch))
                prune(account_branch);
            account_branches.unset(account);
        }
    }
    
    public void select_folder(Geary.Folder folder) {
        FolderEntry? entry = get_folder_entry(folder);
        if (entry != null)
            place_cursor(entry, false);
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
}
