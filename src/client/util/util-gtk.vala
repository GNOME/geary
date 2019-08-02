/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Gtk {

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

    /** Determines if a widget's window has client-side WM decorations. */
    public inline bool has_client_side_decorations(global::Gtk.Widget widget) {
        bool has_csd = true;
        global::Gtk.Window? window = widget.get_toplevel() as global::Gtk.Window;
        if (window != null) {
            has_csd = window.get_style_context().has_class(Gtk.STYLE_CLASS_CSD);
        }
        return has_csd;
    }

    /**
     * Returns whether the close button is at the end of the headerbar.
     */
    bool close_button_at_end() {
        string layout = global::Gtk.Settings.get_default().gtk_decoration_layout;
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

    /**
     * Returns the CSS border box height for a widget.
     *
     * This adjusts the GTK widget's allocated height to exclude extra
     * space added by the CSS margin property, if any.
     */
    public inline int get_border_box_height(global::Gtk.Widget widget) {
        global::Gtk.StyleContext style = widget.get_style_context();
        global::Gtk.StateFlags flags = style.get_state();
        global::Gtk.Border margin = style.get_margin(flags);

        return widget.get_allocated_height() - margin.top - margin.bottom;
    }

}
