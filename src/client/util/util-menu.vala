/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Use this MenuPositionFunc to position a popup menu relative to a widget
// with Gtk.Menu.popup().
//
// You *must* attach the button widget with Gtk.Menu.attach_to_widget() before
// this function can be used.
public void menu_popup_relative(Gtk.Menu menu, out int x, out int y, out bool push_in) {
    menu.realize();
    
    int rx, ry;
    menu.get_attach_widget().get_window().get_origin(out rx, out ry);
    
    Gtk.Allocation menu_button_allocation;
    menu.get_attach_widget().get_allocation(out menu_button_allocation);
    
    x = rx + menu_button_allocation.x;
    y = ry + menu_button_allocation.y + menu_button_allocation.height;
    
    push_in = false;
}

// This method must be called AFTER the button is added to the toolbar.
public void make_menu_dropdown_button(Gtk.ToggleToolButton toggle_tool_button, string label) {
    Gtk.ToggleButton? toggle_button = toggle_tool_button.get_child() as Gtk.ToggleButton;
    if (toggle_button == null) {
        debug("Problem making dropdown button: ToggleToolButton's child is not a ToggleButton");
        return;
    }
    
    Gtk.Widget? child = toggle_button.get_child();
    if (child != null)
        toggle_button.remove(child);
    
    Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    toggle_button.add(box);
    box.set_homogeneous(false);
    box.pack_start(new Gtk.Label(label));
    box.pack_start(new Gtk.Image.from_icon_name("menu-down", Gtk.IconSize.SMALL_TOOLBAR));
}

public void add_proxy_menu(Gtk.ToolItem tool_item, string label, Gtk.Menu proxy_menu) {
    Gtk.MenuItem proxy_menu_item = new Gtk.MenuItem.with_label(label);
    proxy_menu_item.submenu = proxy_menu;
    tool_item.create_menu_proxy.connect((sender) => {
        sender.set_proxy_menu_item("proxy", proxy_menu_item);
        return true;
    });
}
