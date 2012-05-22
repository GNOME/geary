/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class FolderMenu {
    private Gtk.Menu? menu = null;
    private Gtk.ToggleToolButton button;
    private Gee.List<Geary.Folder> folder_list = new Gee.ArrayList<Geary.Folder>();

    public signal void folder_selected(Geary.Folder folder);

    public FolderMenu(Gtk.ToggleToolButton button) {
        this.button = button;
    }

    public void add_folder(Geary.Folder folder) {
        folder_list.add(folder);
        folder_list.sort((CompareFunc) folder_sort);
        menu = null;
    }

    public void remove_folder(Geary.Folder folder) {
        int index = folder_list.index_of(folder);
        if (index >= 0) {
            folder_list.remove_at(index);
        }
    }

    public void show() {
        // Prevent activation loops.
        if (!button.active) {
            return;
        }

        // If the menu is currently null, build it.
        if (menu == null) {
            build_menu();
        }

        // Show the menu.
        menu.popup(null, null, menu_popup_relative, 0, 0);
        menu.select_first(true);
    }

    private void build_menu() {
        // TODO Add fancy filter option.
        // TODO Make the menu items checkboxes instead of buttons.
        // TODO Merge the move/copy menus and just have a move/copy buttons at bottom of this menu.
        menu = new Gtk.Menu();
        foreach (Geary.Folder folder in folder_list) {
            Gtk.MenuItem menu_item = new Gtk.MenuItem.with_label(folder.get_path().to_string());
            menu_item.activate.connect(() => {
                on_menu_item_activated(folder);
            });
            menu.append(menu_item);
        }

        // Finish setting up the menu.
        menu.attach_to_widget(button, null);
        menu.deactivate.connect(on_menu_deactivate);
        menu.show_all();
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

