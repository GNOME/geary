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
        public SpecialFolderBranch(Geary.SpecialFolder special, Geary.Folder folder) {
            base(new SpecialFolderEntry(special, folder));
        }
    }
    
    private class FolderEntry : Object, Sidebar.Entry, Sidebar.InternalDropTargetEntry,
        Sidebar.SelectableEntry {
        public Geary.Folder folder { get; private set; }
        
        public FolderEntry(Geary.Folder folder) {
            this.folder = folder;
        }
        
        public virtual string get_sidebar_name() {
            return folder.get_path().basename;
        }
        
        public string? get_sidebar_tooltip() {
            return null;
        }
        
        public virtual Icon? get_sidebar_icon() {
            return IconFactory.instance.label_icon;
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

    private class SpecialFolderEntry : FolderEntry {
        public Geary.SpecialFolder special { get; private set; }
        
        public SpecialFolderEntry(Geary.SpecialFolder special, Geary.Folder folder) {
            base (folder);
            this.special = special;
        }
        
        public override string get_sidebar_name() {
            return special.name;
        }
        
        public override Icon? get_sidebar_icon() {
            switch (special.folder_type) {
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
        
        public override string to_string() {
            return "SpecialFolderEntry: " + get_sidebar_name();
        }
    }
    
    public signal void folder_selected(Geary.Folder? folder);
    public signal void copy_conversation(Geary.Folder folder);
    public signal void move_conversation(Geary.Folder folder);
    
    private Sidebar.Grouping user_folder_group;
    private Sidebar.Branch user_folder_branch;
    internal Gee.HashMap<Geary.FolderPath, Sidebar.Entry> entries = new Gee.HashMap<
        Geary.FolderPath, Sidebar.Entry>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    
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
        if (selectable is SpecialFolderEntry) {
            folder_selected(((SpecialFolderEntry) selectable).folder);
        } else if (selectable is FolderEntry) {
            folder_selected(((FolderEntry) selectable).folder);
        }
    }

    public void set_user_folders_root_name(string name) {
        user_folder_group.rename(name);
    }
    
    private void reset_user_folder_group() {
        user_folder_group = new Sidebar.Grouping("", IconFactory.instance.label_folder_icon);
        user_folder_branch = new Sidebar.Branch(user_folder_group,
            Sidebar.Branch.Options.STARTUP_OPEN_GROUPING, user_folder_comparator);
    }
    
    public void add_folder(Geary.Folder folder) {
        FolderEntry folder_entry = new FolderEntry(folder);
        
        bool added = false;
        if (folder.get_path().get_parent() == null) {
            // Top-level folder.
            user_folder_branch.graft(user_folder_group, folder_entry);
            added = true;
        } else {
            Sidebar.Entry? entry = get_entry_for_folder_path(folder.get_path().get_parent());
            if (entry != null) {
                user_folder_branch.graft(entry, folder_entry);
                added = true;
            }
        }
        
        if (added)
            entries.set(folder.get_path(), folder_entry);
        else
            debug("Could not add folder to folder list: %s", folder.to_string());
    }
    
    public void add_special_folder(Geary.SpecialFolder special, Geary.Folder folder) {
        SpecialFolderBranch branch = new SpecialFolderBranch(special, folder);
        graft(branch, (int) special.folder_type);
        entries.set(folder.get_path(), branch.get_root());
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
