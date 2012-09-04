/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderMenu {
    private Gtk.Menu? menu = null;
    private Gtk.Menu proxy_menu;
    private Gtk.ToggleToolButton button;
    private Gee.List<Geary.Folder> folder_list = new Gee.ArrayList<Geary.Folder>();

    public signal void folder_selected(Geary.Folder folder);

    public FolderMenu(Gtk.ToggleToolButton button, string? icon_name, string? label) {
        this.button = button;
        
        // TODO Add fancy filter option.
        // TODO Make the menu items checkboxes instead of buttons.
        // TODO Merge the move/copy menus and just have a move/copy buttons at bottom of this menu.
        
        menu = new Gtk.Menu();
        attach_menu(button, menu);
        menu.deactivate.connect(on_menu_deactivate);
        menu.show_all();
        
        proxy_menu = new Gtk.Menu();
        add_proxy_menu(button, label, proxy_menu);
        
        // only use label for proxy, not the toolbar
        make_menu_dropdown_button(button, icon_name, null);
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
    
    public void show() {
        if (!button.active)
            return;
        
        menu.popup(null, null, menu_popup_relative, 0, 0);
        menu.select_first(true);
    }

    private Gtk.MenuItem build_menu_item(Geary.Folder folder) {
        Gtk.MenuItem menu_item = new Gtk.MenuItem.with_label(folder.get_path().to_string());
        menu_item.activate.connect(() => {
            on_menu_item_activated(folder);
        });
        
        return menu_item;
    }
    
    private void attach_menu(Gtk.ToggleToolButton button, Gtk.Menu menu) {
        menu.attach_to_widget(button, null);
        menu.deactivate.connect(() => button.active = false);
        button.clicked.connect(show);
    }

    private void on_menu_deactivate() {
        button.active = false;
    }

    private void on_menu_item_activated(Geary.Folder folder) {
        folder_selected(folder);
    }

    private static int folder_sort(Geary.Folder a, Geary.Folder b) {
        return a.get_path().to_string().casefold().collate(b.get_path().to_string().casefold());
    }
}

