/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
[GtkTemplate (ui = "/org/gnome/Geary/main-toolbar.ui")]
public class MainToolbar : Gtk.Box {

    // How wide the left pane should be. Auto-synced with our settings
    public int left_pane_width { get; set; }

    // Used to form the title of the folder header
    public string account { get; set; }
    public string folder { get; set; }
    public string subject { get; set; }

    // Close button settings
    public bool show_close_button { get; set; default = false; }
    public bool show_close_button_left { get; private set; default = true; }
    public bool show_close_button_right { get; private set; default = true; }

    // Search and find bar
    public bool search_open { get; set; default = false; }
    public bool find_open { get; set; default = false; }

    // The tooltip of the Undo-button
    public string undo_tooltip {
        owned get { return this.undo_button.tooltip_text; }
        set { this.undo_button.tooltip_text = value; }
    }

    // Folder header elements
    [GtkChild]
    private Gtk.HeaderBar folder_header;
    [GtkChild]
    private Gtk.MenuButton empty_menu_button;
    [GtkChild]
    private Gtk.ToggleButton search_conversations_button;
    private Binding guest_header_binding;

    // Selection header elements
    [GtkChild]
    private Gtk.HeaderBar selection_header;

    [GtkChild]
    private Gtk.Label selection_label;

    // Conversation header elements
    [GtkChild]
    private Gtk.HeaderBar conversation_header;
    [GtkChild]
    private Gtk.ToggleButton find_button;

    // Other
    [GtkChild]
    private Gtk.Button undo_button;

    public MainToolbar(Configuration config) {
        config.bind(Configuration.MESSAGES_PANE_POSITION_KEY, this, "left-pane-width",
            SettingsBindFlags.GET);
        this.bind_property("left-pane-width", this.folder_header, "width-request",
            BindingFlags.SYNC_CREATE, (binding, source_value, ref target_value) => {
                target_value = left_pane_width;
                return true;
            });
        this.bind_property("left-pane-width", this.selection_header, "width-request",
            BindingFlags.SYNC_CREATE, (binding, source_value, ref target_value) => {
                target_value = left_pane_width;
                return true;
            });

        if (config.desktop_environment != Configuration.DesktopEnvironment.UNITY) {
            this.bind_property("account", this.folder_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", this.folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        }
        this.bind_property("subject", this.conversation_header, "title", BindingFlags.SYNC_CREATE);
        this.bind_property("subject", this.conversation_header, "tooltip-text", BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-left", this.folder_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-right", this.conversation_header, "show-close-button",
            BindingFlags.SYNC_CREATE);

        // Assemble the empty menu
        Gtk.Builder builder = new Gtk.Builder.from_resource("/org/gnome/Geary/main-toolbar-menus.ui");
        MenuModel empty_menu = (MenuModel) builder.get_object("empty_menu");

        // Setup folder header elements
        this.empty_menu_button.popover = new Gtk.Popover.from_model(null, empty_menu);
        this.bind_property("search-open", this.search_conversations_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        this.bind_property("find-open", this.find_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(set_window_buttons);
        this.realize.connect(set_window_buttons);
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

    internal void set_selection_mode_enabled(bool enabled) {
        if (enabled) {
            update_selection_count(0);
        }
        this.folder_header.set_visible(!enabled);
        this.selection_header.set_visible(enabled);
    }

    internal void update_selection_count(int count) {
        string text = "";
        if (count == 0) {
            text = _("Click to select conversations");
        } else {
            text = ngettext(
                "%d conversation selected",
                "%d conversations selected",
                count
            ).printf(count);

        }
        this.selection_label.set_text(text);
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

}
