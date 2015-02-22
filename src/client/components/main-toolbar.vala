/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
public class MainToolbar : Gtk.Box {
    public FolderMenu copy_folder_menu { get; private set; default = new FolderMenu(); }
    public FolderMenu move_folder_menu { get; private set; default = new FolderMenu(); }
    public string account { get; set; }
    public string folder { get; set; }
    public bool show_close_button { get; set; default = false; }
    public bool search_open { get; set; default = false; }
    
    private PillHeaderbar folder_header;
    private PillHeaderbar conversation_header;
    private Gtk.Button archive_button;
    private Gtk.Button trash_delete_button;
    
    public MainToolbar() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        
        folder_header = new PillHeaderbar(GearyApplication.instance.actions);
        conversation_header = new PillHeaderbar(GearyApplication.instance.actions);
        folder_header.get_style_context().add_class("titlebar");
        folder_header.get_style_context().add_class("geary-titlebar-left");
        conversation_header.get_style_context().add_class("titlebar");
        conversation_header.get_style_context().add_class("geary-titlebar-right");
        GearyApplication.instance.config.bind(Configuration.MESSAGES_PANE_POSITION_KEY,
            folder_header, "width-request", SettingsBindFlags.GET);
        
        this.bind_property("account", conversation_header, "title", BindingFlags.SYNC_CREATE);
        this.bind_property("folder", conversation_header, "subtitle", BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button", conversation_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        
        bool rtl = get_direction() == Gtk.TextDirection.RTL;
        
        // Assemble mark menu.
        GearyApplication.instance.load_ui_file("toolbar_mark_menu.ui");
        Gtk.Menu mark_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMarkMenu");
        mark_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        
        // Setup the application menu.
        GearyApplication.instance.load_ui_file("toolbar_menu.ui");
        Gtk.Menu application_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMenu");
        application_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        
        // Toolbar setup.
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();
        
        // Compose.
        insert.add(folder_header.create_toolbar_button("text-editor-symbolic",
            GearyController.ACTION_NEW_MESSAGE));
        folder_header.add_start(folder_header.create_pill_buttons(insert, false));
        
        // Search
        insert.clear();
        Gtk.Button search = folder_header.create_toggle_button(
            "preferences-system-search-symbolic", GearyController.ACTION_TOGGLE_SEARCH);
        this.bind_property("search-open", search, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        insert.add(search);
        folder_header.add_end(folder_header.create_pill_buttons(insert, false));
        
        // Reply buttons
        insert.clear();
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-reply-sender-rtl-symbolic"
            : "mail-reply-sender-symbolic", GearyController.ACTION_REPLY_TO_MESSAGE));
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-reply-all-rtl-symbolic"
            : "mail-reply-all-symbolic", GearyController.ACTION_REPLY_ALL_MESSAGE));
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-forward-rtl-symbolic"
            : "mail-forward-symbolic", GearyController.ACTION_FORWARD_MESSAGE));
        conversation_header.add_start(conversation_header.create_pill_buttons(insert));
        
        // Assemble the empty menu
        GearyApplication.instance.load_ui_file("toolbar_empty_menu.ui");
        Gtk.Menu empty_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarEmptyMenu");
        empty_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        
        // Mark, copy, move.
        insert.clear();
        insert.add(conversation_header.create_menu_button("marker-symbolic", mark_menu,
            GearyController.ACTION_MARK_AS_MENU));
        insert.add(conversation_header.create_menu_button(rtl ? "tag-rtl-symbolic" : "tag-symbolic",
            copy_folder_menu, GearyController.ACTION_COPY_MENU));
        insert.add(conversation_header.create_menu_button("folder-symbolic", move_folder_menu,
            GearyController.ACTION_MOVE_MENU));
        insert.add(conversation_header.create_menu_button(null, empty_menu,
            GearyController.ACTION_EMPTY_MENU));
        conversation_header.add_start(conversation_header.create_pill_buttons(insert));
        
        insert.clear();
        insert.add(archive_button = conversation_header.create_toolbar_button(null, GearyController.ACTION_ARCHIVE_MESSAGE, true));
        insert.add(trash_delete_button = conversation_header.create_toolbar_button(null, GearyController.ACTION_TRASH_MESSAGE, false));
        Gtk.Box archive_trash_delete = conversation_header.create_pill_buttons(insert);
        
        insert.clear();
        insert.add(conversation_header.create_toolbar_button(null, GearyController.ACTION_UNDO,
            false));
        Gtk.Box undo = conversation_header.create_pill_buttons(insert);
        
        // pack_end() ordering is reversed in GtkHeaderBar in 3.12 and above
#if !GTK_3_12
        conversation_header.add_end(archive_trash_delete);
        conversation_header.add_end(undo);
#endif
        
        // Application button.  If we exported an app menu, we don't need this.
        if (!Gtk.Settings.get_default().gtk_shell_shows_app_menu) {
            insert.clear();
            insert.add(conversation_header.create_menu_button("emblem-system-symbolic",
                application_menu, GearyController.ACTION_GEAR_MENU));
            conversation_header.add_end(conversation_header.create_pill_buttons(insert));
        }
        
        // pack_end() ordering is reversed in GtkHeaderBar in 3.12 and above
#if GTK_3_12
        conversation_header.add_end(undo);
        conversation_header.add_end(archive_trash_delete);
#endif
        
        pack_start(folder_header, false, false);
        pack_start(new Gtk.Separator(Gtk.Orientation.VERTICAL), false, false);
        pack_start(conversation_header, true, true);
    }
    
    /// Updates the trash button as trash or delete, and shows or hides the archive button.
    public void update_trash_archive_buttons(bool trash, bool archive) {
        string action_name = (trash ? GearyController.ACTION_TRASH_MESSAGE
            : GearyController.ACTION_DELETE_MESSAGE);
        conversation_header.setup_button(trash_delete_button, null, action_name, false);
        
        archive_button.visible = archive;
    }
    
    public void set_conversation_header(Gtk.HeaderBar header) {
        conversation_header.hide();
        header.get_style_context().add_class("titlebar");
        header.get_style_context().add_class("geary-titlebar-right");
        header.show_close_button = show_close_button;
        pack_start(header, true, true);
    }
    
    public void remove_conversation_header(Gtk.HeaderBar header) {
        remove(header);
        header.get_style_context().remove_class("titlebar");
        header.get_style_context().remove_class("geary-titlebar-right");
        header.show_close_button = false;
        conversation_header.show();
    }
}

