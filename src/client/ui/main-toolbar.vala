/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Draws the main toolbar.
public class MainToolbar : Gtk.VBox {
    private Gtk.Toolbar toolbar;
    private Gtk.Menu menu;
    private Gtk.ToolButton menu_button;
    
    public MainToolbar() {
        GearyApplication.instance.load_ui_file("toolbar_menu.ui");
        menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMenu") as Gtk.Menu;
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("toolbar.glade");
        toolbar = builder.get_object("toolbar") as Gtk.Toolbar;
        
        Gtk.ToolButton new_message = builder.get_object(GearyController.ACTION_NEW_MESSAGE)
            as Gtk.ToolButton;
        new_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_NEW_MESSAGE));
        
        Gtk.ToolButton archive_message = builder.get_object(GearyController.ACTION_DELETE_MESSAGE)
            as Gtk.ToolButton;
        archive_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_DELETE_MESSAGE));
        
        menu_button = builder.get_object("menu_button") as Gtk.ToolButton;
        menu_button.clicked.connect(on_show_menu);
        
        toolbar.get_style_context().add_class("primary-toolbar");
        
        add(toolbar);
    }
    
    private void on_show_menu() {
        menu.popup(null, null, popup_pos, 0, 0);
    }
    
    private void popup_pos(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        menu.realize();
        
        int rx, ry;
        get_window().get_root_origin(out rx, out ry);
        
        Gtk.Allocation menu_button_allocation;
        menu_button.get_allocation(out menu_button_allocation);
        
        Gtk.Allocation toolbar_allocation;
        get_allocation(out toolbar_allocation);
        
        x = rx + menu_button_allocation.x;
        y = ry + menu_button_allocation.height + toolbar_allocation.height;
        
        push_in = false;
    }
}
