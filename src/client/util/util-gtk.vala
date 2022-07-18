/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Gtk {

    /** Delay before showing progress bar for background operations. */
    public const int SHOW_PROGRESS_TIMEOUT_MSEC = 1000;
    /** Minimum time for display of progress bar for background operations. */
    public const int HIDE_PROGRESS_TIMEOUT_MSEC = 1000;
    /** Frequency for pulse of progress bar for background operations. */
    public const int PROGRESS_PULSE_TIMEOUT_MSEC = 250;

    /**
     * Given an HTML-style color spec, parses the color and sets it to
     * the source RGB of the Cairo context. (Borrowed from Shotwell.)
     */
    public void set_source_color_from_string(Cairo.Context ctx, string spec) {
        Gdk.RGBA rgba = Gdk.RGBA();
        if (!rgba.parse(spec))
            error("Can't parse color %s", spec);
        ctx.set_source_rgb(rgba.red, rgba.green, rgba.blue);
    }

    /**
     * Returns whether the close button is at the end of the headerbar.
     */
    bool close_button_at_end() {
        string layout = global::Gtk.Settings.get_default().gtk_decoration_layout;
        bool at_end = false;
        // Based on logic of close_button_at_end in gtkheaderbar.c:
        // Close button appears at end iff "close" follows a colon in
        // the layout string.
        if (layout != null) {
            int colon_ind = layout.index_of(":");
            at_end = (colon_ind >= 0 && layout.index_of("close", colon_ind) >= 0);
        }
        return at_end;
    }

    /**
     * Allows iterating over a GMenu, without having to handle MenuItems
     * @param menu - The menu to iterate over
     * @param foreach_func - The function which will be called on the
     * attributes of menu's children
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
     * @param section - If the item represents a section, this will
     * return that section (or null otherwise)
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

    /**
     * Constructs a frozen GMenu from an existing model using a visitor.
     *
     * The visitor is applied to the given template model to each of
     * its items, or recursively for any section or submenu. If the
     * visitor returns false when passed an item, section or submenu
     * then it will be skipped, otherwise it will be added to a new
     * menu.
     *
     * The constructed menu will be returned frozen.
     *
     * @see MenuVisitor
     */
    public GLib.Menu construct_menu(GLib.MenuModel template,
                                    MenuVisitor visitor) {
        GLib.Menu model = new GLib.Menu();
        for (int i = 0; i < template.get_n_items(); i++) {
            GLib.MenuItem item = new GLib.MenuItem.from_model(template, i);
            string? action = null;
            GLib.Variant? action_value = item.get_attribute_value(
                GLib.Menu.ATTRIBUTE_ACTION, GLib.VariantType.STRING
            );
            if (action_value != null) {
                action = (string) action_value;
            }
            GLib.Menu? section = (GLib.Menu) item.get_link(
                GLib.Menu.LINK_SECTION
            );
            GLib.Menu? submenu = (GLib.Menu) item.get_link(
                GLib.Menu.LINK_SUBMENU
            );

            bool append = false;
            if (section != null) {
                if (visitor(template, section, action, item)) {
                    append = true;
                    section = construct_menu(section, visitor);
                    item.set_section(section);
                }
            } else if (submenu != null) {
                if (visitor(template, submenu, action, item)) {
                    append = true;
                    submenu = construct_menu(submenu, visitor);
                    item.set_submenu(submenu);
                }
            } else {
                append = visitor(template, null, action, item);
            }

            if (append) {
                model.append_item(item);
            }
        }
        model.freeze();
        return model;
    }

    /**
     * Visitor for {@link construct_menu}.
     *
     * Implementations should return true to accept the given child
     * menu or menu item, causing it to be included in the new model,
     * or false to reject it and cause it to be skipped.
     *
     * @param existing_menu - current menu or submenu being visited
     * @param existing_child_menu - if not null, a child menu that is
     * about to be descended into
     * @param existing_action - existing fully qualified action name
     * of the current item, if any
     * @param new_item - copy of the menu item being visited, which if
     * accepted will be added to the new model
     */
    public delegate bool MenuVisitor(GLib.MenuModel existing_menu,
                                     GLib.MenuModel? existing_child_menu,
                                     string? existing_action,
                                     GLib.MenuItem? new_item);

    /** Copies a GLib menu, setting targets for the given actions. */
    public GLib.Menu copy_menu_with_targets(GLib.Menu template,
                                            string group,
                                            Gee.Map<string,GLib.Variant> targets) {
        string group_prefix = group + ".";
        GLib.Menu copy = new GLib.Menu();
        for (int i = 0; i < template.get_n_items(); i++) {
            GLib.MenuItem item = new GLib.MenuItem.from_model(template, i);
            GLib.Menu? section = (GLib.Menu) item.get_link(
                GLib.Menu.LINK_SECTION
            );
            GLib.Menu? submenu = (GLib.Menu) item.get_link(
                GLib.Menu.LINK_SUBMENU
            );

            if (section != null) {
                item.set_section(
                    copy_menu_with_targets(section, group, targets)
                );
            } else if (submenu != null) {
                item.set_submenu(
                    copy_menu_with_targets(submenu, group, targets)
                );
            } else {
                string? action = (string) item.get_attribute_value(
                    GLib.Menu.ATTRIBUTE_ACTION, GLib.VariantType.STRING
                );
                if (action != null && action.has_prefix(group_prefix)) {
                    GLib.Variant? target = targets.get(
                        action.substring(group_prefix.length)
                    );
                    if (target != null) {
                        item.set_action_and_target_value(action, target);
                    }
                }
            }
            copy.append_item(item);
        }
        return copy;
    }

    /** Returns a truncated form of a URL if it is too long for display. */
    public string shorten_url(string url) {
        string new_url = url;
        if (url.length >= 90) {
            new_url = url.substring(0,40) + "…" + url.substring(-40);
        }
        return new_url;
    }

    public Gdk.RGBA rgba(double red, double green, double blue, double alpha) {
        return Gdk.RGBA() {
            red = red,
            green = green,
            blue = blue,
            alpha = alpha
        };
    }

    /* Connect this to Gtk.Widget.query_tooltip signal, will only show tooltip if label ellipsized */
    public bool query_tooltip_label(global::Gtk.Widget widget, int x, int y, bool keyboard, global::Gtk.Tooltip tooltip) {
        global::Gtk.Label label = widget as global::Gtk.Label;
        if (label.get_layout().is_ellipsized()) {
            tooltip.set_markup(label.label);
            return true;
        }
        return false;
    }
}
