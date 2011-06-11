/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderListView : Gtk.TreeView {
    public signal void folder_selected(Geary.Folder? folder);
    
    public FolderListView(FolderListStore store) {
        set_model(store);
        
        Gtk.CellRendererText name_renderer = new Gtk.CellRendererText();
        Gtk.TreeViewColumn name_column = new Gtk.TreeViewColumn.with_attributes(
            FolderListStore.Column.NAME.to_string(), name_renderer, "text", FolderListStore.Column.NAME);
        append_column(name_column);
        
        get_selection().changed.connect(on_selection_changed);
    }
    
    private FolderListStore get_store() {
        return (FolderListStore) get_model();
    }
    
    private void on_selection_changed() {
        Gtk.TreeModel model;
        Gtk.TreePath? path = get_selection().get_selected_rows(out model).nth_data(0);
        if (path == null) {
            folder_selected(null);
            
            return;
        }
        
        Geary.Folder? folder = get_store().get_folder_at(path);
        if (folder != null)
            folder_selected(folder);
    }
}

