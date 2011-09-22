/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderListView : Gtk.TreeView {
    public signal void folder_selected(Geary.Folder? folder);
    
    public FolderListView(FolderListStore store) {
        set_model(store);
        
        set_headers_visible(false);
        
        Gtk.CellRendererText name_renderer = new Gtk.CellRendererText();
        Gtk.TreeViewColumn name_column = new Gtk.TreeViewColumn.with_attributes(
            FolderListStore.Column.NAME.to_string(), name_renderer, "text", FolderListStore.Column.NAME);
        append_column(name_column);
        
        get_selection().changed.connect(on_selection_changed);
    }
    
    private FolderListStore get_store() {
        return (FolderListStore) get_model();
    }
    
    public void select_path(Geary.FolderPath path) {
        Gtk.TreeIter? iter = get_store().find_path(path);
        if (iter == null)
            return;
        
        Gtk.TreePath tree_path = get_store().get_path(iter);
        
        get_selection().select_path(tree_path);
        set_cursor(tree_path, null, false);
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

