/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderMenu : GtkUtil.ToggleToolbarDropdown {
    private Gee.List<Geary.Folder> folder_list = new Gee.ArrayList<Geary.Folder>();

    public signal void folder_selected(Geary.Folder folder);

    public FolderMenu(Icon icon, Gtk.IconSize icon_size, Gtk.Menu? supplied_menu,
        Gtk.Menu? supplied_proxy_menu) {
        base (icon, icon_size, supplied_menu, supplied_proxy_menu);
        
        // TODO Add fancy filter option.
        // TODO Make the menu items checkboxes instead of buttons.
        // TODO Merge the move/copy menus and just have a move/copy buttons at bottom of this menu.
    }
    
    public bool has_folder(Geary.Folder folder) {
        return folder_list.contains(folder);
    }
    
    public void add_folder(Geary.Folder folder) {
        folder_list.add(folder);
        folder_list.sort((CompareFunc) folder_sort);
        
        int index = folder_list.index_of(folder);
        menu.insert(build_menu_item(folder), index);
        proxy_menu.insert(build_menu_item(folder), index);
        
        menu.show_all();
        proxy_menu.show_all();
    }

    public void remove_folder(Geary.Folder folder) {
        int index = folder_list.index_of(folder);
        folder_list.remove(folder);
        
        if (index >= 0) {
            menu.remove(menu.get_children().nth_data(index));
            proxy_menu.remove(proxy_menu.get_children().nth_data(index));
        }
        
        menu.show_all();
        proxy_menu.show_all();
    }
    
    public void clear() {
        folder_list.clear();
        menu.foreach((w) => menu.remove(w));
        proxy_menu.foreach((w) => proxy_menu.remove(w));
        menu.show_all();
        proxy_menu.show_all();
    }
    
    private Gtk.MenuItem build_menu_item(Geary.Folder folder) {
        Gtk.MenuItem menu_item = new Gtk.MenuItem.with_label(folder.get_path().to_string());
        menu_item.activate.connect(() => {
            folder_selected(folder);
        });
        
        return menu_item;
    }
    
    private static int folder_sort(Geary.Folder a, Geary.Folder b) {
        return a.get_path().compare(b.get_path());
    }
}

