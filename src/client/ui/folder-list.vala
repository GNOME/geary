/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderList : Sidebar.Tree {
    
    private class SpecialFolderBranch : Sidebar.RootOnlyBranch {
        public SpecialFolderBranch(Geary.SpecialFolder special, Geary.Folder folder) {
            base(new SpecialFolderEntry(special, folder));
        }
    }
    
    private class SpecialFolderEntry : Object, Sidebar.Entry, Sidebar.SelectableEntry {
        public Geary.SpecialFolder special { get; private set; }
        public Geary.Folder folder { get; private set; }
        
        public SpecialFolderEntry(Geary.SpecialFolder special, Geary.Folder folder) {
            this.special = special;
            this.folder = folder;
        }
        
        public string get_sidebar_name() {
            return special.name;
        }
        
        public string? get_sidebar_tooltip() {
            return null;
        }
        
        public Icon? get_sidebar_icon() {
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
                    
                default:
                    assert_not_reached();
            }
        }
        
        public string to_string() {
            return "SpecialFolderEntry: " + get_sidebar_name();
        }
    }
    
    private class FolderEntry : Object, Sidebar.Entry, Sidebar.SelectableEntry {
        public Geary.Folder folder { get; private set; }
        
        public FolderEntry(Geary.Folder folder) {
            this.folder = folder;
        }
        
        public string get_sidebar_name() {
            return folder.get_path().basename;
        }
        
        public string? get_sidebar_tooltip() {
            return null;
        }
        
        public Icon? get_sidebar_icon() {
            return IconFactory.instance.label_icon;
        }
        
        public string to_string() {
            return "FolderEntry: " + get_sidebar_name();
        }
    }
    
    public signal void folder_selected(Geary.Folder? folder);
    
    private Sidebar.Grouping user_folder_group;
    private Sidebar.Branch user_folder_branch;
    internal Gee.HashMap<Geary.FolderPath, Sidebar.Entry> entries = new Gee.HashMap<Geary.FolderPath,
        Sidebar.Entry>();
    
    public FolderList() {
        base(new Gtk.TargetEntry[0], Gdk.DragAction.ASK, drop_handler);
        entry_selected.connect(on_entry_selected);
        
        user_folder_group = new Sidebar.Grouping("", IconFactory.instance.label_folder_icon);
        user_folder_branch = new Sidebar.Branch(user_folder_group,
            Sidebar.Branch.Options.STARTUP_OPEN_GROUPING, user_folder_comparator);
        graft(user_folder_branch, int.MAX);
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
    
    public void add_folder(Geary.Folder folder) {
        if (folder.get_path().get_parent() == null) {
            // Top-level folder.
            user_folder_branch.graft(user_folder_group, new FolderEntry(folder));
        } else {
            Sidebar.Entry? entry = get_entry_for_folder_path(folder.get_path().get_parent());
            if (entry != null)
                user_folder_branch.graft(entry, new FolderEntry(folder));
            else
                debug("Could not add folder: %s", folder.to_string());
        }
    }
    
    public void add_special_folder(Geary.SpecialFolder special, Geary.Folder folder) {
        SpecialFolderBranch branch = new SpecialFolderBranch(special, folder);
        graft(branch, (int) special.folder_type);
        entries.set(folder.get_path(), branch.get_root());
    }
    
    public void select_path(Geary.FolderPath path) {
        Sidebar.Entry? entry = get_entry_for_folder_path(path);
        if (entry != null)
            place_cursor(entry, false);
    }
    
    private Sidebar.Entry? get_entry_for_folder_path(Geary.FolderPath path) {
        if (!entries.has_key(path))
            return null;
        
        return entries.get(path);
    }
}
