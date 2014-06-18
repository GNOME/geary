/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FolderMenu : Gtk.Menu {
    private Gee.List<Geary.Folder> folder_list = new Gee.ArrayList<Geary.Folder>();

    public signal void folder_selected(Geary.Folder folder);

    public FolderMenu() {
    }
    
    public bool has_folder(Geary.Folder folder) {
        return folder_list.contains(folder);
    }
    
    public void add_folder(Geary.Folder folder) {
        // don't allow multiples and don't allow folders that can't be opened (that means they
        // support almost no operations and have no content)
        if (folder_list.contains(folder) || folder.properties.is_openable.is_impossible())
            return;
        
        // also don't allow local-only or virtual folders, which also have a limited set of
        // operations
        if (folder.properties.is_local_only || folder.properties.is_virtual)
            return;
        
        folder_list.add(folder);
        folder_list.sort(folder_sort);
        
        int index = folder_list.index_of(folder);
        insert(build_menu_item(folder), index);
        
        show_all();
    }
    
    public void enable_disable_folder(Geary.Folder folder, bool sensitive) {
        int index = folder_list.index_of(folder);
        if (index >= 0)
            get_children().nth_data(index).sensitive = sensitive;
    }
    
    public void remove_folder(Geary.Folder folder) {
        int index = folder_list.index_of(folder);
        folder_list.remove(folder);
        
        if (index >= 0)
            remove(get_children().nth_data(index));
        
        show_all();
    }
    
    public void clear() {
        folder_list.clear();
        this.foreach((w) => remove(w));
        show_all();
    }
    
    private Gtk.MenuItem build_menu_item(Geary.Folder folder) {
        Gtk.MenuItem menu_item = new Gtk.MenuItem.with_label(folder.path.to_string());
        menu_item.activate.connect(() => {
            folder_selected(folder);
        });
        
        return menu_item;
    }
    
    private static int folder_sort(Geary.Folder a, Geary.Folder b) {
        return a.path.compare_to(b.path);
    }
}

