/*
 * Copyright © 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * The toolbar for the main window.
 *
 * @see Application.MainWindow
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-main-toolbar.ui")]
public class Components.MainToolbar : Hdy.Leaflet {

    // How wide the left pane should be. Auto-synced with our settings
    public int left_pane_width { get; set; }

    // Used to form the title of the folder header
    public string account { get; set; }
    public string folder { get; set; }

    // Close button settings
    public bool show_close_button { get; set; default = true; }

    // Search bar
    public bool search_open { get; set; default = false; }

    private ConversationActionBar conversation_viewer_action_bar;

    [GtkChild] private unowned Hdy.Leaflet conversations_leaflet;

    // Folder header elements
    [GtkChild] private unowned Hdy.HeaderBar folder_header;
    [GtkChild] private unowned Gtk.MenuButton main_menu_button;

    [GtkChild] private unowned Gtk.Separator folder_separator;

    // Conversations header elements
    [GtkChild] private unowned Hdy.HeaderBar conversations_header;
    [GtkChild] private unowned Gtk.ToggleButton search_conversations_button;

    [GtkChild] private unowned Gtk.Separator conversations_separator;

    // Conversation header elements
    [GtkChild] private unowned ConversationHeaderBar conversation_header;

    [GtkChild] private unowned Hdy.HeaderGroup header_group;

    Gtk.SizeGroup conversation_group;

    public MainToolbar(Application.Configuration config,
                       ConversationActionBar action_bar) {
        if (config.desktop_environment != UNITY) {
            this.bind_property("account", this.conversations_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", this.conversations_header, "subtitle", BindingFlags.SYNC_CREATE);
        }
        this.conversation_viewer_action_bar = action_bar;
        this.conversation_header.action_bar = action_bar;

        // Assemble the main/mark menus
        Gtk.Builder builder = new Gtk.Builder.from_resource("/org/gnome/Geary/components-main-toolbar-menus.ui");
        MenuModel main_menu = (MenuModel) builder.get_object("main_menu");

        // Setup folder header elements
        this.main_menu_button.popover = new Gtk.Popover.from_model(null, main_menu);
        this.bind_property("search-open", this.search_conversations_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
    }

    public void set_conversation_header(Hdy.HeaderBar header) {
        remove(conversation_header);
        this.header_group.add_header_bar(header);
        header.hexpand = true;
        conversation_group.remove_widget(conversation_header);
        conversation_group.add_widget(header);
        add(header);
        child_set(header, "name", "conversation", null);
    }

    public void remove_conversation_header(Hdy.HeaderBar header) {
        remove(header);
        this.header_group.remove_header_bar(header);
        conversation_group.remove_widget(header);
        conversation_group.add_widget(conversation_header);
        add(conversation_header);
        child_set(conversation_header, "name", "conversation", null);
    }

    public void add_to_size_groups(Gtk.SizeGroup folder_group,
                                   Gtk.SizeGroup folder_separator_group,
                                   Gtk.SizeGroup conversations_group,
                                   Gtk.SizeGroup conversations_separator_group,
                                   Gtk.SizeGroup conversation_group) {
        folder_group.add_widget(folder_header);
        folder_separator_group.add_widget(folder_separator);
        conversations_group.add_widget(conversations_header);
        conversations_separator_group.add_widget(conversations_separator);
        conversation_group.add_widget(conversation_header);
        this.conversation_group = conversation_group;
    }

    public void add_to_swipe_groups(Hdy.SwipeGroup conversations_group,
                                    Hdy.SwipeGroup conversation_group) {
        conversations_group.add_swipeable(this.conversations_leaflet);
        conversation_group.add_swipeable(this);
    }

    public void add_conversation_actions(ConversationActions actions) {
        conversation_header.add_conversation_actions(actions);
    }

    public void show_main_menu() {
        this.main_menu_button.clicked();
    }

}
