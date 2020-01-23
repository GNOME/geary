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
    public bool show_close_button { get; set; default = true; }
    // Search and find bar
    public bool search_open { get; set; default = false; }
    public bool find_open { get; set; default = false; }
    // Copy and Move popovers
    public FolderPopover copy_folder_menu { get; private set; default = new FolderPopover(); }
    public FolderPopover move_folder_menu { get; private set; default = new FolderPopover(); }
    // How many conversations are selected right now. Should automatically be updated.
    public int selected_conversations { get; set; }


    // Folder header elements
    [GtkChild]
    private Gtk.HeaderBar folder_header;
    [GtkChild]
    private Gtk.ToggleButton search_conversations_button;
    [GtkChild]
    private Gtk.MenuButton main_menu_button;

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

    [GtkChild]
    private Hdy.HeaderGroup header_group;

    private bool show_trash_button = true;

    // Load these at construction time
    private Gtk.Image trash_image = new Gtk.Image.from_icon_name("user-trash-symbolic", Gtk.IconSize.MENU);
    private Gtk.Image delete_image = new Gtk.Image.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);


    public MainToolbar(Application.Configuration config) {
        // Sync headerbar width with left pane
        config.bind(
            Application.Configuration.MESSAGES_PANE_POSITION_KEY,
            this,
            "left-pane-width",
            SettingsBindFlags.GET
        );
        this.bind_property("left-pane-width", this.folder_header, "width-request", BindingFlags.SYNC_CREATE);

        if (config.desktop_environment != UNITY) {
            this.bind_property("account", this.folder_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", this.folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        }

        // Assemble the main/mark menus
        Gtk.Builder builder = new Gtk.Builder.from_resource("/org/gnome/Geary/main-toolbar-menus.ui");
        MenuModel main_menu = (MenuModel) builder.get_object("main_menu");
        MenuModel mark_menu = (MenuModel) builder.get_object("mark_message_menu");

        // Setup folder header elements
        this.main_menu_button.popover = new Gtk.Popover.from_model(null, main_menu);
        this.bind_property("search-open", this.search_conversations_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        // Setup conversation header elements
        this.notify["selected-conversations"].connect(() => update_conversation_buttons());
        this.mark_message_button.popover = new Gtk.Popover.from_model(null, mark_menu);
        this.copy_message_button.popover = copy_folder_menu;
        this.move_message_button.popover = move_folder_menu;

        this.bind_property("find-open", this.find_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
    }

    public void set_conversation_header(Gtk.HeaderBar header) {
        conversation_header.hide();
        this.header_group.add_header_bar(header);
        pack_start(header, true, true);
    }

    public void remove_conversation_header(Gtk.HeaderBar header) {
        remove(header);
        this.header_group.remove_header_bar(header);
        conversation_header.show();
    }

    public void update_trash_button(bool show_trash) {
        this.show_trash_button = show_trash;
        update_conversation_buttons();
    }

    // Updates tooltip text depending on number of conversations selected.
    private void update_conversation_buttons() {
        this.mark_message_button.tooltip_text = ngettext(
            "Mark conversation",
            "Mark conversations",
            this.selected_conversations
        );
        this.copy_message_button.tooltip_text = ngettext(
            "Add label to conversation",
            "Add label to conversations",
            this.selected_conversations
        );
        this.move_message_button.tooltip_text = ngettext(
            "Move conversation",
            "Move conversations",
            this.selected_conversations
        );
        this.archive_button.tooltip_text = ngettext(
            "Archive conversation",
            "Archive conversations",
            this.selected_conversations
        );

        if (this.show_trash_button) {
            this.trash_delete_button.action_name = Action.Window.prefix(
                Application.MainWindow.ACTION_TRASH_CONVERSATION
            );
            this.trash_delete_button.image = trash_image;
            this.trash_delete_button.tooltip_text = ngettext(
                "Move conversation to Trash",
                "Move conversations to Trash",
                this.selected_conversations
            );
        } else {
            this.trash_delete_button.action_name = Action.Window.prefix(
                Application.MainWindow.ACTION_DELETE_CONVERSATION
            );
            this.trash_delete_button.image = delete_image;
            this.trash_delete_button.tooltip_text = ngettext(
                "Delete conversation",
                "Delete conversations",
                this.selected_conversations
            );
        }
    }
}
