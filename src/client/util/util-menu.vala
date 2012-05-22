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

public void make_menu_dropdown_button(Gtk.ToggleToolButton toolbutton, string label) {
    Gtk.ToggleButton button = toolbutton.get_child() as Gtk.ToggleButton;
    button.remove(button.get_child());
    Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    box.set_homogeneous(false);
    button.add(box);
    box.pack_start(new Gtk.Label(label));
    box.pack_start(new Gtk.Image.from_icon_name("menu-down", Gtk.IconSize.SMALL_TOOLBAR));
}

