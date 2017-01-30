/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
[GtkTemplate (ui = "/org/gnome/Geary/main-toolbar.ui")]
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

    // Folder header elements
    [GtkChild]
    private Gtk.HeaderBar folder_header;
    [GtkChild]
    private Gtk.Button compose_new_message_button;
    [GtkChild]
    private Gtk.MenuButton empty_menu_button;
    [GtkChild]
    private Gtk.ToggleButton search_conversations_button;
    private Binding guest_header_binding;

    // Conversation header elements
    [GtkChild]
    private Gtk.HeaderBar conversation_header;
    [GtkChild]
    private Gtk.Button reply_sender_button;
    [GtkChild]
    private Gtk.Button reply_all_button;
    [GtkChild]
    private Gtk.Button forward_button;
    [GtkChild]
    private Gtk.MenuButton mark_message_button;
    [GtkChild]
    private Gtk.MenuButton copy_message_button;
    [GtkChild]
    private Gtk.MenuButton move_message_button;
    [GtkChild]
    private Gtk.Button archive_button;
    [GtkChild]
    private Gtk.Button trash_delete_button;
    [GtkChild]
    private Gtk.Button undo_button;
    [GtkChild]
    private Gtk.ToggleButton find_button;

    public MainToolbar(Configuration config) {
        this.action_group = GearyApplication.instance.actions;

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

        if (config.desktop_environment != Configuration.DesktopEnvironment.UNITY) {
            this.bind_property("account", folder_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        }
        this.bind_property("show-close-button-left", folder_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-right", conversation_header, "show-close-button",
            BindingFlags.SYNC_CREATE);

        // Assemble the empty/mark menus
        GearyApplication.instance.load_ui_resource("toolbar_empty_menu.ui");
        Gtk.Menu empty_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarEmptyMenu");
        GearyApplication.instance.load_ui_resource("toolbar_mark_menu.ui");
        Gtk.Menu mark_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMarkMenu");

        // Setup folder header elements
        setup_button(compose_new_message_button, GearyController.ACTION_NEW_MESSAGE);
        empty_menu_button.popup = empty_menu;

        setup_button(search_conversations_button, GearyController.ACTION_TOGGLE_SEARCH);
        this.bind_property("search-open", search_conversations_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        // Setup conversation header elements
        setup_button(reply_sender_button, GearyController.ACTION_REPLY_TO_MESSAGE);
        setup_button(reply_all_button, GearyController.ACTION_REPLY_ALL_MESSAGE);
        setup_button(forward_button, GearyController.ACTION_FORWARD_MESSAGE);

        setup_menu_button(mark_message_button, mark_menu, GearyController.ACTION_MARK_AS_MENU);
        setup_popover_button(copy_message_button, copy_folder_menu, GearyController.ACTION_COPY_MENU);
        setup_popover_button(move_message_button, move_folder_menu, GearyController.ACTION_MOVE_MENU);

        setup_button(archive_button, GearyController.ACTION_ARCHIVE_CONVERSATION, true);
        setup_button(trash_delete_button, GearyController.ACTION_TRASH_CONVERSATION);
        setup_button(undo_button, GearyController.ACTION_UNDO);

        setup_button(find_button, GearyController.ACTION_TOGGLE_FIND);
        this.bind_property("find-open", find_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(set_window_buttons);
        realize.connect(set_window_buttons);
    }

    public void update_trash_button(bool is_trash) {
        string action_name = (is_trash ? GearyController.ACTION_TRASH_CONVERSATION
            : GearyController.ACTION_DELETE_CONVERSATION);
        setup_button(trash_delete_button, action_name, false);
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

    private void setup_button(Gtk.Button b, string action_name, bool show_label = false) {
        Gtk.Action related_action = action_group.get_action(action_name);
        b.focus_on_click = false;
        b.use_underline = true;
        b.tooltip_text = related_action.tooltip;
        related_action.notify["tooltip"].connect(() => { b.tooltip_text = related_action.tooltip; });
        b.related_action = related_action;

        // Load icon by name with this fallback order: specified icon name, the action's icon name,
        // the action's stock ID ... although stock IDs are being deprecated, that's how we specify
        // the icon in the GtkActionEntry (also being deprecated) and GTK+ 3.14 doesn't support that
        // any longer
        string? icon_to_load = b.related_action.icon_name;
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

        if (show_label)
            b.label = related_action.label;
        else
            b.label = null;
    }

    /**
     * Given an icon, menu, and action, creates a button that triggers the menu and the action.
     */
    private void setup_menu_button(Gtk.MenuButton b, Gtk.Menu menu, string action_name) {
        setup_button(b, action_name);
        menu.foreach(GtkUtil.show_menuitem_accel_labels);
        b.popup = menu;

        if (b.related_action != null) {
            b.related_action.activate.connect(() => {
                    b.clicked();
                });
            // Null out the action since by connecting it to clicked
            // above, invoking would cause an infinite loop otherwise.
            b.related_action = null;
        }
    }

    /**
     * Given an icon, popover, and action, creates a button that triggers the popover and the action.
     */
    private void setup_popover_button(Gtk.MenuButton b, Gtk.Popover popover, string action_name) {
        setup_button(b, action_name);
        b.popover = popover;
        b.clicked.connect(() => popover.show_all());

        if (b.related_action != null) {
            b.related_action.activate.connect(() => {
                    b.clicked();
                });
            // Null out the action since by connecting it to clicked
            // above, invoking would cause an infinite loop otherwise.
            b.related_action = null;
        }
    }
}
