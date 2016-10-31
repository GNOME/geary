/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
public class MainToolbar : Gtk.Box {
    private Gtk.ActionGroup action_group;
    public FolderPopover copy_folder_menu { get; private set; default = new FolderPopover(); }
    public FolderPopover move_folder_menu { get; private set; default = new FolderPopover(); }
    public string account { get; set; }
    public string folder { get; set; }
    public bool show_close_button { get; set; default = false; }
    public bool show_close_button_left { get; private set; default = true; }
    public bool show_close_button_right { get; private set; default = true; }
    public bool search_open { get; set; default = false; }
    public bool find_open { get; set; default = false; }
    public int left_pane_width { get; set; }

    private Gtk.HeaderBar folder_header;
    private Gtk.HeaderBar conversation_header;
    private Gtk.Button archive_button;
    private Gtk.Button trash_delete_button;
    private Binding guest_header_binding;

    public MainToolbar() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        this.action_group = GearyApplication.instance.actions;

        folder_header = new Gtk.HeaderBar();
        conversation_header = new Gtk.HeaderBar();
        folder_header.get_style_context().add_class("geary-titlebar");
        folder_header.get_style_context().add_class("geary-titlebar-left");
        conversation_header.get_style_context().add_class("geary-titlebar");
        conversation_header.get_style_context().add_class("geary-titlebar-right");

        // Instead of putting a separator between the two headerbars, as other applications do,
        // we put a separator at the right end of the left headerbar.  This greatly improves
        // the appearance under the Ambiance theme (see bug #746171).  To get this separator to
        // line up with the handle of the pane, we need to extend the width of the left-hand
        // headerbar a bit.  Six pixels is right both for Adwaita and Ambiance.
        GearyApplication.instance.config.bind(Configuration.MESSAGES_PANE_POSITION_KEY,
            this, "left-pane-width", SettingsBindFlags.GET);
        this.bind_property("left-pane-width", folder_header, "width-request",
            BindingFlags.SYNC_CREATE, (binding, source_value, ref target_value) => {
                target_value = left_pane_width + 6;
                return true;
            });

        this.bind_property("account", folder_header, "title", BindingFlags.SYNC_CREATE);
        this.bind_property("folder", folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-left", folder_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-right", conversation_header, "show-close-button",
            BindingFlags.SYNC_CREATE);

        // Assemble mark menu.
        GearyApplication.instance.load_ui_resource("toolbar_mark_menu.ui");
        Gtk.Menu mark_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMarkMenu");
        mark_menu.foreach(GtkUtil.show_menuitem_accel_labels);

        // Toolbar setup.
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();

        // Compose.
        insert.add(create_toolbar_button("text-editor-symbolic",
            GearyController.ACTION_NEW_MESSAGE));
        add_start(folder_header, create_pill_buttons(insert, false));

        // Assemble the empty menu
        GearyApplication.instance.load_ui_resource("toolbar_empty_menu.ui");
        Gtk.Menu empty_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarEmptyMenu");
        empty_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        insert.clear();
        insert.add(create_menu_button(null, empty_menu, GearyController.ACTION_EMPTY_MENU));
        Gtk.Box empty = create_pill_buttons(insert, false);

        // Search
        insert.clear();
        Gtk.Button search_button = create_toggle_button("preferences-system-search-symbolic",
            GearyController.ACTION_TOGGLE_SEARCH);
        this.bind_property("search-open", search_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        insert.add(search_button);
        Gtk.Box search = create_pill_buttons(insert, false);

        add_end(folder_header, new Gtk.Separator(Gtk.Orientation.VERTICAL));
        add_end(folder_header, search);
        add_end(folder_header, empty);

        // Reply buttons
        insert.clear();
        insert.add(create_toolbar_button("mail-reply-sender-symbolic",
            GearyController.ACTION_REPLY_TO_MESSAGE));
        insert.add(create_toolbar_button("mail-reply-all-symbolic",
            GearyController.ACTION_REPLY_ALL_MESSAGE));
        insert.add(create_toolbar_button("mail-forward-symbolic",
            GearyController.ACTION_FORWARD_MESSAGE));
        add_start(conversation_header, create_pill_buttons(insert));

        // Mark, copy, move.
        insert.clear();
        insert.add(create_menu_button("marker-symbolic", mark_menu,
            GearyController.ACTION_MARK_AS_MENU));
        insert.add(create_popover_button("tag-symbolic", copy_folder_menu,
            GearyController.ACTION_COPY_MENU));
        insert.add(create_popover_button("folder-symbolic", move_folder_menu,
            GearyController.ACTION_MOVE_MENU));
        add_start(conversation_header, create_pill_buttons(insert));

        // Archive, undo, find
        insert.clear();
        insert.add(archive_button = create_toolbar_button(null, GearyController.ACTION_ARCHIVE_MESSAGE, true));
        insert.add(trash_delete_button = create_toolbar_button(null, GearyController.ACTION_TRASH_MESSAGE, false));
        Gtk.Box archive_trash_delete = create_pill_buttons(insert);

        insert.clear();
        insert.add(create_toolbar_button(null, GearyController.ACTION_UNDO,
            false));
        Gtk.Box undo = create_pill_buttons(insert);

        Gtk.Button find_button = create_toggle_button(
            "preferences-system-search-symbolic", GearyController.ACTION_TOGGLE_FIND);
        this.bind_property("find-open", find_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        insert.clear();
        insert.add(find_button);
        Gtk.Box find = create_pill_buttons(insert);

        add_end(conversation_header, find);
        add_end(conversation_header, undo);
        add_end(conversation_header, archive_trash_delete);

        pack_start(folder_header, false, false);
        pack_start(conversation_header, true, true);

        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(set_window_buttons);
        realize.connect(set_window_buttons);
    }

    public void update_trash_button(bool is_trash) {
        string action_name = (is_trash ? GearyController.ACTION_TRASH_MESSAGE
            : GearyController.ACTION_DELETE_MESSAGE);
        setup_button(trash_delete_button, null, action_name, false);
    }

    public void set_conversation_header(Gtk.HeaderBar header) {
        conversation_header.hide();
        header.get_style_context().add_class("geary-titlebar");
        header.get_style_context().add_class("geary-titlebar-right");
        guest_header_binding = bind_property("show-close-button-right", header,
            "show-close-button", BindingFlags.SYNC_CREATE);
        pack_start(header, true, true);
        header.decoration_layout = conversation_header.decoration_layout;
    }

    public void remove_conversation_header(Gtk.HeaderBar header) {
        remove(header);
        header.get_style_context().remove_class("geary-titlebar");
        header.get_style_context().remove_class("geary-titlebar-right");
        guest_header_binding.unbind();
        header.show_close_button = false;
        header.decoration_layout = Gtk.Settings.get_default().gtk_decoration_layout;
        conversation_header.show();
    }

    private void set_window_buttons() {
        string[] buttons = Gtk.Settings.get_default().gtk_decoration_layout.split(":");
        if (buttons.length != 2) {
            warning("gtk_decoration_layout in unexpected format");
            return;
        }
        show_close_button_left = show_close_button;
        show_close_button_right = show_close_button;
        folder_header.decoration_layout = buttons[0] + ":";
        conversation_header.decoration_layout = ":" + buttons[1];
    }

    // PILLBAR METHODS
    public virtual void add_start(Gtk.HeaderBar header_bar, Gtk.Widget widget) {
        header_bar.pack_start(widget);
    }

    public virtual void add_end(Gtk.HeaderBar header_bar, Gtk.Widget widget) {
        header_bar.pack_end(widget);
    }

    public virtual void setup_button(Gtk.Button b, string? icon_name, string action_name,
        bool show_label = false) {
        Gtk.Action related_action = action_group.get_action(action_name);
        b.focus_on_click = false;
        b.tooltip_text = related_action.tooltip;
        related_action.notify["tooltip"].connect(() => { b.tooltip_text = related_action.tooltip; });
        b.related_action = related_action;

        // Load icon by name with this fallback order: specified icon name, the action's icon name,
        // the action's stock ID ... although stock IDs are being deprecated, that's how we specify
        // the icon in the GtkActionEntry (also being deprecated) and GTK+ 3.14 doesn't support that
        // any longer
        string? icon_to_load = icon_name ?? b.related_action.icon_name;
        if (icon_to_load == null)
            icon_to_load = b.related_action.stock_id;

        // set pixel size to force GTK+ to load our images from our installed directory, not the theme
        // directory
        if (icon_to_load != null) {
            Gtk.Image image = new Gtk.Image.from_icon_name(icon_to_load, Gtk.IconSize.MENU);
            image.set_pixel_size(16);
            b.image = image;
        }

        b.always_show_image = true;

        if (!show_label)
            b.label = null;
    }

    /**
     * Given an icon and action, creates a button that triggers the action.
     */
    public virtual Gtk.Button create_toolbar_button(string? icon_name, string action_name, bool show_label = false) {
        Gtk.Button b = new Gtk.Button();
        setup_button(b, icon_name, action_name, show_label);

        return b;
    }

    /**
     * Given an icon and action, creates a toggle button that triggers the action.
     */
    public virtual Gtk.Button create_toggle_button(string? icon_name, string action_name) {
        Gtk.ToggleButton b = new Gtk.ToggleButton();
        setup_button(b, icon_name, action_name);

        return b;
    }

    /**
     * Given an icon, menu, and action, creates a button that triggers the menu and the action.
     */
    public virtual Gtk.MenuButton create_menu_button(string? icon_name, Gtk.Menu? menu, string action_name) {
        Gtk.MenuButton b = new Gtk.MenuButton();
        setup_button(b, icon_name, action_name);
        b.popup = menu;

        if (b.related_action != null) {
            b.related_action.activate.connect(() => {
                    b.clicked();
                });
            // Null out the action since by connecting it to clicked
            // above, invoking would cause an infinite loop otherwise.
            b.related_action = null;
        }

        return b;
    }

    /**
     * Given an icon, popover, and action, creates a button that triggers the popover and the action.
     */
    public virtual Gtk.MenuButton create_popover_button(string? icon_name, Gtk.Popover? popover, string action_name) {
        Gtk.MenuButton b = new Gtk.MenuButton();
        setup_button(b, icon_name, action_name);
        b.set_popover(popover);
        b.clicked.connect(() => popover.show_all());

        if (b.related_action != null) {
            b.related_action.activate.connect(() => {
                    b.clicked();
                });
            // Null out the action since by connecting it to clicked
            // above, invoking would cause an infinite loop otherwise.
            b.related_action = null;
        }

        return b;
    }

    /**
     * Given a list of buttons, creates a "pill-style" tool item that can be appended to this
     * toolbar.  Optionally adds spacers "before" and "after" the buttons (those terms depending
     * on Gtk.TextDirection)
     */
    public virtual Gtk.Box create_pill_buttons(Gee.Collection<Gtk.Button> buttons,
        bool before_spacer = true, bool after_spacer = false) {
        Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        box.valign = Gtk.Align.CENTER;
        box.halign = Gtk.Align.CENTER;

        if (buttons.size > 1) {
            box.get_style_context().add_class(Gtk.STYLE_CLASS_RAISED);
            box.get_style_context().add_class(Gtk.STYLE_CLASS_LINKED);
        }

        foreach(Gtk.Button button in buttons)
            box.add(button);

        return box;
    }
}
