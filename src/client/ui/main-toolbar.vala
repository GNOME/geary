/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Draws the main toolbar.
public class MainToolbar : Gtk.Box {
    private Gtk.Toolbar toolbar;
    private Gtk.Menu menu;
    private Gtk.Menu mark_menu;
    private Gtk.ToggleToolButton menu_button;
    private Gtk.ToggleToolButton mark_menu_button;
    
    public MainToolbar() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        
        GearyApplication.instance.load_ui_file("toolbar_mark_menu.ui");
        mark_menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMarkMenu") as Gtk.Menu;
        
        GearyApplication.instance.load_ui_file("toolbar_menu.ui");
        menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMenu") as Gtk.Menu;
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("toolbar.glade");
        toolbar = builder.get_object("toolbar") as Gtk.Toolbar;
        
        Gtk.ToolButton new_message = builder.get_object(GearyController.ACTION_NEW_MESSAGE)
            as Gtk.ToolButton;
        new_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_NEW_MESSAGE));
        
        Gtk.ToolButton reply_to_message = builder.get_object(GearyController.ACTION_REPLY_TO_MESSAGE)
            as Gtk.ToolButton;
        reply_to_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_REPLY_TO_MESSAGE));
        
        Gtk.ToolButton reply_all_message = builder.get_object(GearyController.ACTION_REPLY_ALL_MESSAGE)
            as Gtk.ToolButton;
        reply_all_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_REPLY_ALL_MESSAGE));
        
        Gtk.ToolButton forward_message = builder.get_object(GearyController.ACTION_FORWARD_MESSAGE)
            as Gtk.ToolButton;
        forward_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_FORWARD_MESSAGE));
        
        Gtk.ToolButton archive_message = builder.get_object(GearyController.ACTION_DELETE_MESSAGE)
            as Gtk.ToolButton;
        archive_message.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_DELETE_MESSAGE));

        mark_menu_button = builder.get_object(GearyController.ACTION_MARK_AS_MENU) as Gtk.ToggleToolButton;
        mark_menu_button.set_related_action(GearyApplication.instance.actions.get_action(
            GearyController.ACTION_MARK_AS_MENU));
        mark_menu.attach_to_widget(mark_menu_button, null);
        mark_menu.deactivate.connect(on_deactivate_mark_menu);
        mark_menu_button.clicked.connect(on_show_mark_menu);

        Gtk.ToggleButton button = mark_menu_button.get_child() as Gtk.ToggleButton;
        button.remove(button.get_child());
        Gtk.Box box = new Gtk.HBox(false, 0);
        button.add(box);
        box.pack_start(new Gtk.Label(_("Mark")));
        box.pack_start(new Gtk.Image.from_icon_name("menu-down", Gtk.IconSize.LARGE_TOOLBAR));

        menu_button = builder.get_object("menu_button") as Gtk.ToggleToolButton;
        menu.attach_to_widget(menu_button, null);
        menu.deactivate.connect(on_deactivate_menu);
        menu_button.clicked.connect(on_show_menu);
        
        toolbar.get_style_context().add_class("primary-toolbar");
        
        add(toolbar);
    }
    
    private void on_show_menu() {
        // Prevent loop
        if (!menu_button.active)
            return;
        
        menu.popup(null, null, menu_popup_relative, 0, 0);
        menu.select_first(true);
    }

    private void on_deactivate_menu() {
        menu_button.active = false;
    }
    
    private void on_show_mark_menu() {
        // Prevent loop
        if (!mark_menu_button.active)
            return;
        
        mark_menu.popup(null, null, menu_popup_relative, 0, 0);
        mark_menu.select_first(true);
    }

    private void on_deactivate_mark_menu() {
        mark_menu_button.active = false;
    }
}
