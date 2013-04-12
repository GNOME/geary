/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A branch that holds all the folders for a particular account.
public class FolderList.AccountBranch : Sidebar.Branch {
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
        folder_entries = new Gee.HashMap<Geary.FolderPath, FolderEntry>(
            Geary.Hashable.hash_func, Geary.Equalable.equal_func);
        
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
        Sidebar.Entry? graft_point = null;
        FolderEntry folder_entry = new FolderEntry(folder);
        Geary.SpecialFolderType special_folder_type = folder.get_special_folder_type();
        if (special_folder_type != Geary.SpecialFolderType.NONE) {
            switch (special_folder_type) {
                // These special folders go in the root of the account.
                case Geary.SpecialFolderType.INBOX:
                case Geary.SpecialFolderType.FLAGGED:
                case Geary.SpecialFolderType.IMPORTANT:
                case Geary.SpecialFolderType.ALL_MAIL:
                    graft_point = get_root();
                break;
                
                // Others go in the "More" grouping.
                default:
                    graft_point = uncommon_special_group;
                break;
            }
        } else if (folder.get_path().get_parent() == null) {
            // Top-level folders get put in our special user folders group.
            graft_point = user_folder_group;
        } else {
            Sidebar.Entry? entry = folder_entries.get(folder.get_path().get_parent());
            if (entry != null)
                graft_point = entry;
        }
        
        // Due to how we enumerate folders on the server, it's unfortunately
        // possible now to have two folders that we'd put in the same place in
        // our tree.  In that case, we just ignore the second folder for now.
        // See #6616.
        if (graft_point != null) {
            Sidebar.Entry? twin = find_first_child(graft_point, (e) => {
                return e.get_sidebar_name() == folder_entry.get_sidebar_name();
            });
            if (twin != null)
                graft_point = null;
        }

        if (graft_point != null) {
            graft(graft_point, folder_entry);
            folder_entries.set(folder.get_path(), folder_entry);
        } else {
            debug("Could not add folder %s of type %s to folder list", folder.to_string(),
                special_folder_type.to_string());
        }
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
