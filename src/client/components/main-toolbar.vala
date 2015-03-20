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
    public bool show_close_button_left { get; private set; default = true; }
    public bool show_close_button_right { get; private set; default = true; }
    public bool search_open { get; set; default = false; }
    public int left_pane_width { get; set; }
    
    private PillHeaderbar folder_header;
    private PillHeaderbar conversation_header;
    private Gtk.Button archive_button;
    private Gtk.Button trash_delete_button;
    private Binding guest_header_binding;
    
    public MainToolbar() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
        
        folder_header = new PillHeaderbar(GearyApplication.instance.actions);
        conversation_header = new PillHeaderbar(GearyApplication.instance.actions);
        folder_header.get_style_context().add_class("titlebar");
        folder_header.get_style_context().add_class("geary-titlebar-left");
        conversation_header.get_style_context().add_class("titlebar");
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
        
        if (!GearyApplication.instance.is_running_unity) {
            this.bind_property("account", folder_header, "title", BindingFlags.SYNC_CREATE);
            this.bind_property("folder", folder_header, "subtitle", BindingFlags.SYNC_CREATE);
        }
        this.bind_property("show-close-button-left", folder_header, "show-close-button",
            BindingFlags.SYNC_CREATE);
        this.bind_property("show-close-button-right", conversation_header, "show-close-button",
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
        
        // Assemble the empty menu
        GearyApplication.instance.load_ui_file("toolbar_empty_menu.ui");
        Gtk.Menu empty_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarEmptyMenu");
        empty_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        insert.clear();
        insert.add(folder_header.create_menu_button(null, empty_menu,
            GearyController.ACTION_EMPTY_MENU));
        Gtk.Box empty = folder_header.create_pill_buttons(insert, false);
        
        // Search
        insert.clear();
        Gtk.Button search_button = folder_header.create_toggle_button(
            "preferences-system-search-symbolic", GearyController.ACTION_TOGGLE_SEARCH);
        this.bind_property("search-open", search_button, "active",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        insert.add(search_button);
        Gtk.Box search = folder_header.create_pill_buttons(insert, false);
        
#if !GTK_3_12
        folder_header.add_end(empty);
        folder_header.add_end(search);
        folder_header.add_end(new Gtk.Separator(Gtk.Orientation.VERTICAL));
#else
        folder_header.add_end(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        folder_header.add_end(search);
        folder_header.add_end(empty);
#endif
        
        // Reply buttons
        insert.clear();
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-reply-sender-rtl-symbolic"
            : "mail-reply-sender-symbolic", GearyController.ACTION_REPLY_TO_MESSAGE));
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-reply-all-rtl-symbolic"
            : "mail-reply-all-symbolic", GearyController.ACTION_REPLY_ALL_MESSAGE));
        insert.add(conversation_header.create_toolbar_button(rtl ? "mail-forward-rtl-symbolic"
            : "mail-forward-symbolic", GearyController.ACTION_FORWARD_MESSAGE));
        conversation_header.add_start(conversation_header.create_pill_buttons(insert));
        
        // Mark, copy, move.
        insert.clear();
        insert.add(conversation_header.create_menu_button("marker-symbolic", mark_menu,
            GearyController.ACTION_MARK_AS_MENU));
        insert.add(conversation_header.create_menu_button(rtl ? "tag-rtl-symbolic" : "tag-symbolic",
            copy_folder_menu, GearyController.ACTION_COPY_MENU));
        insert.add(conversation_header.create_menu_button("folder-symbolic", move_folder_menu,
            GearyController.ACTION_MOVE_MENU));
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
#if GTK_3_12
        conversation_header.add_end(undo);
        conversation_header.add_end(archive_trash_delete);
#endif
        
        pack_start(folder_header, false, false);
        pack_start(conversation_header, true, true);
        
#if GTK_3_12
        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(set_window_buttons);
        realize.connect(set_window_buttons);
#else
        get_style_context().changed.connect(set_close_buttons_side);
        realize.connect(set_close_buttons_side);
#endif
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
        guest_header_binding = bind_property("show-close-button-right", header,
            "show-close-button", BindingFlags.SYNC_CREATE);
        pack_start(header, true, true);
#if GTK_3_12
        header.decoration_layout = conversation_header.decoration_layout;
#endif
    }
    
    public void remove_conversation_header(Gtk.HeaderBar header) {
        remove(header);
        header.get_style_context().remove_class("titlebar");
        header.get_style_context().remove_class("geary-titlebar-right");
        GtkUtil.unbind(guest_header_binding);
        header.show_close_button = false;
#if GTK_3_12
        header.decoration_layout = Gtk.Settings.get_default().gtk_decoration_layout;
#endif
        conversation_header.show();
    }
    
#if GTK_3_12
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
#else
    private void set_close_buttons_side() {
        bool at_end = folder_header.close_button_at_end();
        show_close_button_left = show_close_button && !at_end;
        show_close_button_right = show_close_button && at_end;
    }
#endif
}

