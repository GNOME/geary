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
    // Close button settings
    public bool show_close_button { get; set; default = false; }
    public bool show_close_button_left { get; private set; default = true; }
    public bool show_close_button_right { get; private set; default = true; }
    // Search and find bar
    public bool search_open { get; set; default = false; }
    public bool find_open { get; set; default = false; }
    // Copy and Move popovers
    public FolderPopover copy_folder_menu { get; private set; default = new FolderPopover(); }
    public FolderPopover move_folder_menu { get; private set; default = new FolderPopover(); }
    // How many conversations are selected right now. Should automatically be updated.
    public int selected_conversations { get; set; }
    // Whether to show the trash or the delete button
    public bool show_trash_button { get; set; default = true; }
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

    // Conversation header elements
    [GtkChild]
    private Gtk.HeaderBar conversation_header;
    [GtkChild]
    private Gtk.MenuButton mark_message_button;
    [GtkChild]
    public Gtk.MenuButton copy_message_button;
    [GtkChild]
    public Gtk.MenuButton move_message_button;
    [GtkChild]
    private Gtk.Button archive_button;
    [GtkChild]
    private Gtk.Button trash_delete_button;
    [GtkChild]
    private Gtk.ToggleButton find_button;

    // Other
    [GtkChild]
    private Gtk.Button undo_button;

    // Load these at construction time
    private Gtk.Image trash_image = new Gtk.Image.from_icon_name("user-trash-symbolic", Gtk.IconSize.MENU);
    private Gtk.Image delete_image = new Gtk.Image.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);

    // Tooltips
    private const string DELETE_CONVERSATION_TOOLTIP_SINGLE = _("Delete conversation (Shift+Delete)");
    private const string DELETE_CONVERSATION_TOOLTIP_MULTIPLE = _("Delete conversations (Shift+Delete)");
    private const string TRASH_CONVERSATION_TOOLTIP_SINGLE = _("Move conversation to Trash (Delete, Backspace)");
    private const string TRASH_CONVERSATION_TOOLTIP_MULTIPLE = _("Move conversations to Trash (Delete, Backspace)");
    private const string ARCHIVE_CONVERSATION_TOOLTIP_SINGLE = _("Archive conversation (A)");
    private const string ARCHIVE_CONVERSATION_TOOLTIP_MULTIPLE = _("Archive conversations (A)");
    private const string MARK_MESSAGE_MENU_TOOLTIP_SINGLE = _("Mark conversation");
    private const string MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE = _("Mark conversations");
    private const string LABEL_MESSAGE_TOOLTIP_SINGLE = _("Add label to conversation");
    private const string LABEL_MESSAGE_TOOLTIP_MULTIPLE = _("Add label to conversations");
    private const string MOVE_MESSAGE_TOOLTIP_SINGLE = _("Move conversation");
    private const string MOVE_MESSAGE_TOOLTIP_MULTIPLE = _("Move conversations");

    public MainToolbar(Configuration config) {
        // Instead of putting a separator between the two headerbars, as other applications do,
        // we put a separator at the right end of the left headerbar.  This greatly improves
        // the appearance under the Ambiance theme (see bug #746171).  To get this separator to
        // line up with the handle of the pane, we need to extend the width of the left-hand
        // headerbar a bit.  Six pixels is right both for Adwaita and Ambiance.
        config.bind(Configuration.MESSAGES_PANE_POSITION_KEY, this, "left-pane-width",
            SettingsBindFlags.GET);
        this.bind_property("left-pane-width", this.folder_header, "width-request",
            BindingFlags.SYNC_CREATE, (binding, source_value, ref target_value) => {
                target_value = left_pane_width + 6;
                return true;
            });

        if (config.desktop_environment != Configuration.DesktopEnvironment.UNITY) {
            this.bind_property("account", this.folder_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", this.folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        }
        this.bind_property("show-close-button-left", this.folder_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-right", this.conversation_header, "show-close-button",
            BindingFlags.SYNC_CREATE);

        // Assemble the empty/mark menus
        Gtk.Builder builder = new Gtk.Builder.from_resource("/org/gnome/Geary/main-toolbar-menus.ui");
        MenuModel empty_menu = (MenuModel) builder.get_object("empty_menu");
        MenuModel mark_menu = (MenuModel) builder.get_object("mark_message_menu");

        // Setup folder header elements
        this.empty_menu_button.popover = new Gtk.Popover.from_model(null, empty_menu);
        this.bind_property("search-open", this.search_conversations_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        // Setup conversation header elements
        this.notify["selected-conversations"].connect(() => update_conversation_buttons());
        this.notify["show-trash-button"].connect(() => update_conversation_buttons());
        this.mark_message_button.popover = new Gtk.Popover.from_model(null, mark_menu);
        this.copy_message_button.popover = copy_folder_menu;
        this.move_message_button.popover = move_folder_menu;

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

    // Updates tooltip text depending on number of conversations selected.
    private void update_conversation_buttons() {
        this.mark_message_button.tooltip_text = ngettext(MARK_MESSAGE_MENU_TOOLTIP_SINGLE,
                                                         MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE,
                                                         this.selected_conversations);
        this.copy_message_button.tooltip_text = ngettext(LABEL_MESSAGE_TOOLTIP_SINGLE,
                                                         LABEL_MESSAGE_TOOLTIP_MULTIPLE,
                                                         this.selected_conversations);
        this.move_message_button.tooltip_text = ngettext(MOVE_MESSAGE_TOOLTIP_SINGLE,
                                                         MOVE_MESSAGE_TOOLTIP_MULTIPLE,
                                                         this.selected_conversations);
        this.archive_button.tooltip_text = ngettext(ARCHIVE_CONVERSATION_TOOLTIP_SINGLE,
                                                    ARCHIVE_CONVERSATION_TOOLTIP_MULTIPLE,
                                                    this.selected_conversations);

        if (this.show_trash_button) {
            this.trash_delete_button.action_name = "win."+GearyController.ACTION_TRASH_CONVERSATION;
            this.trash_delete_button.image = trash_image;
            this.trash_delete_button.tooltip_text = ngettext(TRASH_CONVERSATION_TOOLTIP_SINGLE,
                                                             TRASH_CONVERSATION_TOOLTIP_MULTIPLE,
                                                             this.selected_conversations);
        } else {
            this.trash_delete_button.action_name = "win."+GearyController.ACTION_DELETE_CONVERSATION;
            this.trash_delete_button.image = delete_image;
            this.trash_delete_button.tooltip_text = ngettext(DELETE_CONVERSATION_TOOLTIP_SINGLE,
                                                             DELETE_CONVERSATION_TOOLTIP_MULTIPLE,
                                                             this.selected_conversations);
        }
    }
}
