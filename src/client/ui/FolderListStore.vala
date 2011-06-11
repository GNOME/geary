/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderListStore : Gtk.TreeStore {
    public enum Column {
        NAME,
        FOLDER_OBJECT,
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                NAME,
                FOLDER_OBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (string),
                typeof (Geary.Folder)
            };
        }
        
        public string to_string() {
            switch (this) {
                case NAME:
                    return _("Name");
                
                case FOLDER_OBJECT:
                    return "(hidden)";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public FolderListStore() {
        set_column_types(Column.get_types());
    }
    
    public void add_folder(Geary.Folder folder) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter,
            Column.NAME, folder.name,
            Column.FOLDER_OBJECT, folder
        );
    }
    
    public void add_folders(Gee.Collection<Geary.Folder> folders) {
        foreach (Geary.Folder folder in folders)
            add_folder(folder);
    }
    
    public Geary.Folder? get_folder_at(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.Folder folder;
        get(iter, Column.FOLDER_OBJECT, out folder);
        
        return folder;
    }
}

