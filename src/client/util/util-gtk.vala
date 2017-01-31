/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace GtkUtil {

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

public void add_proxy_menu(Gtk.ToolItem tool_item, string label, Gtk.Menu proxy_menu) {
    Gtk.MenuItem proxy_menu_item = new Gtk.MenuItem.with_label(label);
    proxy_menu_item.submenu = proxy_menu;
    tool_item.create_menu_proxy.connect((sender) => {
        sender.set_proxy_menu_item("proxy", proxy_menu_item);
        return true;
    });
}

public void add_accelerator(Gtk.UIManager ui_manager, Gtk.ActionGroup action_group,
    string accelerator, string action) {
    // Parse the accelerator.
    uint key = 0;
    Gdk.ModifierType modifiers = 0;
    Gtk.accelerator_parse(accelerator, out key, out modifiers);
    if (key == 0) {
        debug("Failed to parse accelerator '%s'", accelerator);
        return;
    }
    
    // Connect the accelerator to the action.
    ui_manager.get_accel_group().connect(key, modifiers, Gtk.AccelFlags.VISIBLE,
        (group, obj, key, modifiers) => {
            action_group.get_action(action).activate();
            return true;
        });
}

public void show_menuitem_accel_labels(Gtk.Widget widget) {
    Gtk.MenuItem? item = widget as Gtk.MenuItem;
    if (item == null) {
        return;
    }
    
    string? path = item.get_accel_path();
    if (path == null) {
        return;
    }
    Gtk.AccelKey? key = null;
    Gtk.AccelMap.lookup_entry(path, out key);
    if (key == null) {
        return;
    }
    item.foreach(
        (widget) => { add_accel_to_label(widget, key); }
    );
}

private void add_accel_to_label(Gtk.Widget widget, Gtk.AccelKey key) {
    Gtk.AccelLabel? label = widget as Gtk.AccelLabel;
    if (label == null) {
        return;
    }

    // We should check for (key.accel_flags & Gtk.AccelFlags.VISIBLE) before
    // running the following code. However, there appears to be some
    // funny business going on because key.accel_flags always turns up as 0,
    // even though we explicitly set it to Gtk.AccelFlags.VISIBLE before.
    label.set_accel(key.accel_key, key.accel_mods);
    label.refetch();
}

/**
 * Removes all items from a menu.
 */
public void clear_menu(Gtk.Menu menu) {
    GLib.List<weak Gtk.Widget> children = menu.get_children();
    foreach (weak Gtk.Widget child in children)
        menu.remove(child);
}

/**
 * Given an HTML-style color spec, parses the color and sets it to the source RGB of the Cairo context.
 * (Borrowed from Shotwell.)
 */
void set_source_color_from_string(Cairo.Context ctx, string spec) {
    Gdk.RGBA rgba = Gdk.RGBA();
    if (!rgba.parse(spec))
        error("Can't parse color %s", spec);
    ctx.set_source_rgb(rgba.red, rgba.green, rgba.blue);
}

/**
 * Set xalign property on Gtk.Label in a compatible way.
 *
 * GtkMisc is being deprecated in GTK+ 3 and the "xalign" property has been moved to GtkLabel.  This
 * causes compatibility problems with newer versions of Vala generating code that won't link with
 * older versions of GTK+.  This is a convenience method until Geary requires GTK+ 3.16 as its
 * minimum GTK+ version.
 */
public void set_label_xalign(Gtk.Label label, float xalign) {
    label.set("xalign", xalign);
}

/**
 * Returns whether the close button is at the end of the headerbar.
 */
bool close_button_at_end() {
    string layout = Gtk.Settings.get_default().gtk_decoration_layout;
    bool at_end = false;
    // Based on logic of close_button_at_end in gtkheaderbar.c: Close button appears
    // at end iff "close" follows a colon in the layout string.
    if (layout != null) {
        int colon_ind = layout.index_of(":");
        at_end = (colon_ind >= 0 && layout.index_of("close", colon_ind) >= 0);
    }
    return at_end;
}

/**
 * Allows iterating over a GMenu, without having to handle MenuItems
 * @param menu - The menu to iterate over
 * @param foreach_func - The function which will be called on the attributes of menu's children
 */
void menu_foreach(Menu menu, MenuForeachFunc foreach_func) {
    for (int i = 0; i < menu.get_n_items(); i++) {
        // Get the attributes we're interested in
        Variant? label = menu.get_item_attribute_value(i, Menu.ATTRIBUTE_LABEL, VariantType.STRING);
        Variant? action_name = menu.get_item_attribute_value(i, Menu.ATTRIBUTE_ACTION, VariantType.STRING);
        Variant? action_target = menu.get_item_attribute_value(i, Menu.ATTRIBUTE_TARGET, VariantType.STRING);

        // Check if the child is a section
        Menu? section = (Menu) menu.get_item_link(i, Menu.LINK_SECTION);

        // Callback
        foreach_func((label != null) ? label.get_string() : null,
                     (action_name != null) ? action_name.get_string() : null,
                     action_target,
                     section);
    }
}

/*
 * Used for menu_foreach()
 * @param id - The id if one was set
 * @param label - The label if one was set
 * @param action_name - The action name, if set
 * @param action_target - The action target, if set
 * @param section - If the item represents a section, this will return that section (or null otherwise)
 */
delegate void MenuForeachFunc(string? label, string? action_name, Variant? target, Menu? section);

}
