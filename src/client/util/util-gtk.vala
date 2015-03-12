/* Copyright 2012-2015 Yorba Foundation
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

void apply_style(Gtk.Widget widget, string style) {
    try {
        Gtk.CssProvider style_provider = new Gtk.CssProvider();
        style_provider.load_from_data(style, -1);
        
        Gtk.StyleContext style_context = widget.get_style_context();
        style_context.add_provider(style_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    } catch (Error e) {
        warning("Could not load style: %s", e.message);
    }
}

/**
 * This is not bound in Vala < 0.26.
 */
[CCode(cname = "g_binding_unbind")]
extern void unbind(Binding binding);

}
