/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public enum Geary.SpecialFolderType {
    INBOX,
    DRAFTS,
    SENT,
    FLAGGED,
    ALL_MAIL,
    SPAM,
    TRASH
}

public class Geary.SpecialFolder : Object {
    public SpecialFolderType folder_type { get; private set; }
    public string name { get; private set; }
    public Geary.FolderPath path { get; private set; }
    public int ordering { get; private set; }
    
    public SpecialFolder(SpecialFolderType folder_type, string name, FolderPath path, int ordering) {
        this.folder_type = folder_type;
        this.name = name;
        this.path = path;
        this.ordering = ordering;
    }
}

public class Geary.SpecialFolderMap : Object {
    private Gee.HashMap<SpecialFolderType, SpecialFolder> map = new Gee.HashMap<SpecialFolderType,
        SpecialFolder>();
    
    public SpecialFolderMap() {
    }
    
    public void set_folder(SpecialFolder special_folder) {
        map.set(special_folder.folder_type, special_folder);
    }
    
    public SpecialFolder? get_folder(SpecialFolderType folder_type) {
        return map.get(folder_type);
    }
    
    public SpecialFolder? get_folder_by_path(FolderPath path) {
        foreach (SpecialFolder folder in map.values) {
            if (folder.path == path) {
                return folder;
            }
        }
        return null;
    }
    
    public Gee.Set<SpecialFolderType> get_supported_types() {
        return map.keys.read_only_view;
    }
    
    public Gee.Collection<SpecialFolder> get_all() {
        return map.values.read_only_view;
    }
}

