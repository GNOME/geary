/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
public class MainToolbar : PillHeaderbar {
    private const string ICON_CLEAR_NAME = "edit-clear-symbolic";
    private const string ICON_CLEAR_RTL_NAME = "edit-clear-rtl-symbolic";
    private const string DEFAULT_SEARCH_TEXT = _("Search");
    
    public FolderMenu copy_folder_menu { get; private set; default = new FolderMenu(); }
    public FolderMenu move_folder_menu { get; private set; default = new FolderMenu(); }
    public string search_text { get { return search_entry.text; } }
    public bool search_entry_has_focus { get { return search_entry.has_focus; } }
    
    private Gtk.Button archive_button;
    private Gtk.Button trash_buttons[2];
    private Gtk.SearchEntry search_entry = new Gtk.SearchEntry();
    private Geary.ProgressMonitor? search_upgrade_progress_monitor = null;
    private MonitoredProgressBar search_upgrade_progress_bar = new MonitoredProgressBar();
    private Geary.Account? current_account = null;
    
    public signal void search_text_changed(string search_text);
    
    public MainToolbar() {
        base(GearyApplication.instance.actions);
        GearyApplication.instance.controller.account_selected.connect(on_account_changed);
        
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
        insert.add(create_toolbar_button("text-editor-symbolic", GearyController.ACTION_NEW_MESSAGE));
        add_start(create_pill_buttons(insert, false));
        
        // Reply buttons
        insert.clear();
        insert.add(create_toolbar_button(rtl ? "mail-reply-sender-rtl-symbolic" : "mail-reply-sender-symbolic", GearyController.ACTION_REPLY_TO_MESSAGE));
        insert.add(create_toolbar_button(rtl ? "mail-reply-all-rtl-symbolic" : "mail-reply-all-symbolic", GearyController.ACTION_REPLY_ALL_MESSAGE));
        insert.add(create_toolbar_button(rtl ? "mail-forward-rtl-symbolic" : "mail-forward-symbolic", GearyController.ACTION_FORWARD_MESSAGE));
        add_start(create_pill_buttons(insert));
        
        // Mark, copy, move.
        insert.clear();
        insert.add(create_menu_button("marker-symbolic", mark_menu, GearyController.ACTION_MARK_AS_MENU));
        insert.add(create_menu_button(rtl ? "tag-rtl-symbolic" : "tag-symbolic", copy_folder_menu, GearyController.ACTION_COPY_MENU));
        insert.add(create_menu_button("folder-symbolic", move_folder_menu, GearyController.ACTION_MOVE_MENU));
        add_start(create_pill_buttons(insert));
        
        // The toolbar looks bad when you hide one of a pair of pill buttons.
        // Unfortunately, this means we have to have one pair for archive/trash
        // and one single button for just trash, for when the archive button is
        // hidden.
        insert.clear();
        insert.add(archive_button = create_toolbar_button(null, GearyController.ACTION_ARCHIVE_MESSAGE, true));
        insert.add(trash_buttons[0] = create_toolbar_button(null, GearyController.ACTION_TRASH_MESSAGE, true));
        Gtk.Box trash_archive = create_pill_buttons(insert);
        insert.clear();
        insert.add(trash_buttons[1] = create_toolbar_button(null, GearyController.ACTION_TRASH_MESSAGE, true));
        Gtk.Box trash = create_pill_buttons(insert, false);
        
        // Search bar.
        search_entry.width_chars = 28;
        search_entry.tooltip_text = _("Search all mail in account for keywords (Ctrl+S)");
        search_entry.changed.connect(on_search_entry_changed);
        search_entry.key_press_event.connect(on_search_key_press);
        on_search_entry_changed(); // set initial state
        search_entry.has_focus = true;
        
        // Search upgrade progress bar.
        search_upgrade_progress_bar.show_text = true;
        search_upgrade_progress_bar.visible = false;
        search_upgrade_progress_bar.no_show_all = true;
        
        // pack_end() ordering is reversed in GtkHeaderBar in 3.12 and above
#if !GTK_3_12
        add_end(trash_archive);
        add_end(trash);
        add_end(search_upgrade_progress_bar);
        add_end(search_entry);
#endif
        
        // Application button.  If we exported an app menu, we don't need this.
        if (!Gtk.Settings.get_default().gtk_shell_shows_app_menu) {
            insert.clear();
            insert.add(create_menu_button("emblem-system-symbolic", application_menu, GearyController.ACTION_GEAR_MENU));
            add_end(create_pill_buttons(insert));
        }
        
        // pack_end() ordering is reversed in GtkHeaderBar in 3.12 and above
#if GTK_3_12
        add_end(search_entry);
        add_end(search_upgrade_progress_bar);
        add_end(trash);
        add_end(trash_archive);
#endif
        
        set_search_placeholder_text(DEFAULT_SEARCH_TEXT);
    }
    
    private void show_archive_button(bool show) {
        if (show) {
            archive_button.show();
            trash_buttons[0].show();
            trash_buttons[1].hide();
        } else {
            archive_button.hide();
            trash_buttons[0].hide();
            trash_buttons[1].show();
        }
    }
    
    /// Updates the trash button as trash or delete, and shows or hides the archive button.
    public void update_trash_buttons(bool trash, bool archive) {
        string action_name = (trash ? GearyController.ACTION_TRASH_MESSAGE
            : GearyController.ACTION_DELETE_MESSAGE);
        foreach (Gtk.Button b in trash_buttons)
            setup_button(b, null, action_name, true);
        
        show_archive_button(archive);
    }
    
    public void set_search_text(string text) {
        search_entry.text = text;
    }
    
    public void give_search_focus() {
        search_entry.grab_focus();
    }
    
    public void set_search_placeholder_text(string placeholder) {
        search_entry.placeholder_text = placeholder;
    }
    
    private void on_search_entry_changed() {
        search_text_changed(search_entry.text);
        // Enable/disable clear button.
        search_entry.secondary_icon_name = search_entry.text != "" ?
            (get_direction() == Gtk.TextDirection.RTL ? ICON_CLEAR_RTL_NAME : ICON_CLEAR_NAME) : null;
    }
    
    private bool on_search_key_press(Gdk.EventKey event) {
        // Clear box if user hits escape.
        if (Gdk.keyval_name(event.keyval) == "Escape")
            search_entry.text = "";
        
        // Force search if user hits enter.
        if (Gdk.keyval_name(event.keyval) == "Return")
            on_search_entry_changed();
        
        return false;
    }
    
    private void on_search_upgrade_start() {
        // Set the progress bar's width to match the search entry's width.
        int minimum_width = 0;
        int natural_width = 0;
        search_entry.get_preferred_width(out minimum_width, out natural_width);
        search_upgrade_progress_bar.width_request = minimum_width;
        
        search_entry.hide();
        search_upgrade_progress_bar.show();
    }
    
    private void on_search_upgrade_finished() {
        search_entry.show();
        search_upgrade_progress_bar.hide();
    }
    
    private void on_account_changed(Geary.Account? account) {
        on_search_upgrade_finished(); // Reset search box.
        
        if (search_upgrade_progress_monitor != null) {
            search_upgrade_progress_monitor.start.disconnect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.disconnect(on_search_upgrade_finished);
            search_upgrade_progress_monitor = null;
        }
        
        if (current_account != null) {
            current_account.information.notify[Geary.AccountInformation.PROP_NICKNAME].disconnect(
                on_nickname_changed);
        }
        
        if (account != null) {
            search_upgrade_progress_monitor = account.search_upgrade_monitor;
            search_upgrade_progress_bar.set_progress_monitor(search_upgrade_progress_monitor);
            
            search_upgrade_progress_monitor.start.connect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.connect(on_search_upgrade_finished);
            if (search_upgrade_progress_monitor.is_in_progress)
                on_search_upgrade_start(); // Remove search box, we're already in progress.
            
            account.information.notify[Geary.AccountInformation.PROP_NICKNAME].connect(
                on_nickname_changed);
            
            search_upgrade_progress_bar.text = _("Indexing %s account").printf(account.information.nickname);
        }
        
        current_account = account;
        
        on_nickname_changed(); // Set new account name.
    }
    
    private void on_nickname_changed() {
        set_search_placeholder_text(current_account == null ||
            GearyApplication.instance.controller.get_num_accounts() == 1 ? DEFAULT_SEARCH_TEXT :
            _("Search %s account").printf(current_account.information.nickname));
    }
}

