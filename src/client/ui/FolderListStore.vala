/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderListStore : Gtk.TreeStore {
    public enum Column {
        NAME,
        N_COLUMNS;
        
        public static Column[] all() {
            return { NAME };
        }
        
        public static Type[] get_types() {
            return {
                typeof (string)
            };
        }
        
        public string to_string() {
            switch (this) {
                case NAME:
                    return _("Name");
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public FolderListStore() {
        set_column_types(Column.get_types());
    }
    
    public void add_folder(string folder) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter, Column.NAME, folder);
    }
    
    public string? get_folder_at(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        string folder;
        get(iter, 0, out folder);
        
        return folder;
    }
}

