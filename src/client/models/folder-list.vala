/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderList : Sidebar.Tree {

    public const Gtk.TargetEntry[] TARGET_ENTRY_LIST = {
        { "application/x-geary-mail", Gtk.TargetFlags.SAME_APP, 0 }
    };

    private class SpecialFolderBranch : Sidebar.RootOnlyBranch {
        public SpecialFolderBranch(Geary.Folder folder) {
            base(new FolderEntry(folder));
            
            assert(folder.get_special_folder_type() != Geary.SpecialFolderType.NONE);
        }
    }
    
    private class FolderEntry : Object, Sidebar.Entry, Sidebar.InternalDropTargetEntry,
        Sidebar.SelectableEntry {
        public Geary.Folder folder { get; private set; }
        
        public FolderEntry(Geary.Folder folder) {
            this.folder = folder;
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
                
                case Geary.SpecialFolderType.ALL_MAIL:
                    return new ThemedIcon("archive");
                
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
    
    private Sidebar.Grouping user_folder_group;
    private Sidebar.Branch user_folder_branch;
    internal Gee.HashMap<Geary.FolderPath, Sidebar.Entry> entries = new Gee.HashMap<
        Geary.FolderPath, Sidebar.Entry>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    internal Gee.HashMap<Geary.FolderPath, Sidebar.Branch> branches = new Gee.HashMap<
        Geary.FolderPath, Sidebar.Branch>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    
    public FolderList() {
        base(new Gtk.TargetEntry[0], Gdk.DragAction.ASK, drop_handler);
        entry_selected.connect(on_entry_selected);

        reset_user_folder_group();
        graft(user_folder_branch, int.MAX);

        // Set self as a drag destination.
        Gtk.drag_dest_set(this, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            TARGET_ENTRY_LIST, Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
    }

    private static int user_folder_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        int result = a.get_sidebar_name().collate(b.get_sidebar_name());
        
        return (result != 0) ? result : strcmp(a.get_sidebar_name(), b.get_sidebar_name());
    }
    
    private void drop_handler(Gdk.DragContext context, Sidebar.Entry? entry,
        Gtk.SelectionData data, uint info, uint time) {
    }
    
    private void on_entry_selected(Sidebar.SelectableEntry selectable) {
        if (selectable is FolderEntry) {
            folder_selected(((FolderEntry) selectable).folder);
        }
    }

    public void set_user_folders_root_name(string name) {
        user_folder_group.rename(name);
    }
    
    private void reset_user_folder_group() {
        user_folder_group = new Sidebar.Grouping("",
            IconFactory.instance.get_custom_icon("tags", IconFactory.ICON_SIDEBAR));
        user_folder_branch = new Sidebar.Branch(user_folder_group,
            Sidebar.Branch.Options.STARTUP_OPEN_GROUPING, user_folder_comparator);
    }
    
    public void add_folder(Geary.Folder folder) {
        bool added = false;

        Geary.SpecialFolderType special_folder_type = folder.get_special_folder_type();
        if (special_folder_type != Geary.SpecialFolderType.NONE) {
            SpecialFolderBranch branch = new SpecialFolderBranch(folder);
            graft(branch, (int) special_folder_type);
            entries.set(folder.get_path(), branch.get_root());
            branches.set(folder.get_path(), branch);
            added = true;
        } else if (folder.get_path().get_parent() == null) {
            // Top-level folder.
            FolderEntry folder_entry = new FolderEntry(folder);
            user_folder_branch.graft(user_folder_group, folder_entry);
            entries.set(folder.get_path(), folder_entry);
            branches.set(folder.get_path(), user_folder_branch);
            added = true;
        } else {
            FolderEntry folder_entry = new FolderEntry(folder);
            Sidebar.Entry? entry = get_entry_for_folder_path(folder.get_path().get_parent());
            if (entry != null) {
                user_folder_branch.graft(entry, folder_entry);
                entries.set(folder.get_path(), folder_entry);
                branches.set(folder.get_path(), user_folder_branch);
                added = true;
            }
        }
        
        if (!added) {
            debug("Could not add folder %s of type %s to folder list", folder.to_string(),
                special_folder_type.to_string());
        }
    }

    public void remove_folder(Geary.Folder folder) {
        Sidebar.Entry? entry = get_entry_for_folder_path(folder.get_path());
        Sidebar.Branch? branch = get_branch_for_folder_path(folder.get_path());
        if(entry != null && branch != null) {
            if (branch is SpecialFolderBranch) {
                this.prune(branch);
            } else {
                branch.prune(entry);
            }
        } else {
            debug(@"Could not remove folder $(folder.get_path())");
        }
    }
    
    public void remove_all_branches() {
        prune_all();
        entries.clear();
        reset_user_folder_group();
    }
    
    public void select_path(Geary.FolderPath path) {
        Sidebar.Entry? entry = get_entry_for_folder_path(path);
        if (entry != null)
            place_cursor(entry, false);
    }
    
    private Sidebar.Entry? get_entry_for_folder_path(Geary.FolderPath path) {
        return entries.get(path);
    }

    private Sidebar.Branch? get_branch_for_folder_path(Geary.FolderPath path) {
        return branches.get(path);
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
