/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
public class MainToolbar : PillToolbar {
    private const string ICON_CLEAR_NAME = "edit-clear-symbolic";
    private const string DEFAULT_SEARCH_TEXT = _("Search");
    
    public FolderMenu copy_folder_menu { get; private set; default = new FolderMenu(); }
    public FolderMenu move_folder_menu { get; private set; default = new FolderMenu(); }
    public string search_text { get { return search_entry.text; } }
    
    private Gtk.ToolItem search_container = new Gtk.ToolItem();
    private Gtk.Entry search_entry = new Gtk.Entry();
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
        orientation = Gtk.Orientation.HORIZONTAL;
        get_style_context().add_class(Gtk.STYLE_CLASS_MENUBAR); // Drag window via toolbar.
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();
        
        // Compose.
        insert.add(create_toolbar_button("text-editor-symbolic", GearyController.ACTION_NEW_MESSAGE));
        add(create_pill_buttons(insert, false));
        
        // Reply buttons
        insert.clear();
        insert.add(create_toolbar_button(rtl ? "reply-rtl-symbolic" : "reply-symbolic", GearyController.ACTION_REPLY_TO_MESSAGE));
        insert.add(create_toolbar_button(rtl ? "reply-all-rtl-symbolic" : "reply-all-symbolic", GearyController.ACTION_REPLY_ALL_MESSAGE));
        insert.add(create_toolbar_button(rtl ? "forward-rtl-symbolic" : "forward-symbolic", GearyController.ACTION_FORWARD_MESSAGE));
        add(create_pill_buttons(insert));
        
        // Mark, copy, move.
        insert.clear();
        insert.add(create_menu_button("marker-symbolic", mark_menu, GearyController.ACTION_MARK_AS_MENU));
        insert.add(create_menu_button(rtl ? "tag-rtl-symbolic" : "tag-symbolic", copy_folder_menu, GearyController.ACTION_COPY_MENU));
        insert.add(create_menu_button("folder-symbolic", move_folder_menu, GearyController.ACTION_MOVE_MENU));
        add(create_pill_buttons(insert));
        
        // Archive/delete button.
        // For this button, the controller sets the tooltip and icon depending on the context.
        insert.clear();
        insert.add(create_toolbar_button("", GearyController.ACTION_DELETE_MESSAGE, true));
        add(create_pill_buttons(insert));
        
        // Spacer.
        add(create_spacer());
        
        // Search bar.
        search_entry.width_chars = 32;
        search_entry.primary_icon_name = "edit-find-symbolic";
        search_entry.secondary_icon_name = "edit-clear-symbolic";
        search_entry.secondary_icon_activatable = true;
        search_entry.secondary_icon_sensitive = true;
        search_entry.tooltip_text = _("Search all mail in account for keywords (Ctrl+S)");
        search_entry.changed.connect(on_search_entry_changed);
        search_entry.icon_release.connect(on_search_entry_icon_release);
        search_entry.key_press_event.connect(on_search_key_press);
        on_search_entry_changed(); // set initial state
        search_entry.has_focus = true;
        search_container.add(search_entry);
        add(search_container);
        
        // Search upgrade progress bar.
        search_upgrade_progress_bar.margin_top = 3;
        search_upgrade_progress_bar.margin_bottom = 3;
        search_upgrade_progress_bar.show_text = true;
        
        // Set the progress bar's width to match the search entry's width.
        int minimum_width = 0;
        int natural_width = 0;
        search_entry.get_preferred_width(out minimum_width, out natural_width);
        search_upgrade_progress_bar.width_request = minimum_width;
        
        // Application button.
        insert.clear();
        insert.add(create_menu_button("emblem-system-symbolic", application_menu, GearyController.ACTION_GEAR_MENU));
        add(create_pill_buttons(insert));
        
        set_search_placeholder_text(DEFAULT_SEARCH_TEXT);
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
        search_entry.secondary_icon_name = search_entry.text != "" ? ICON_CLEAR_NAME : null;
    }
    
    private void on_search_entry_icon_release(Gtk.EntryIconPosition icon_pos, Gdk.Event event) {
        if (icon_pos == Gtk.EntryIconPosition.SECONDARY)
            search_entry.text = "";
    }
    
    private bool on_search_key_press(Gdk.EventKey event) {
        // Clear box if user hits escape.
        if (Gdk.keyval_name(event.keyval) == "Escape")
            search_entry.text = "";
        
        return false;
    }
    
    private void on_search_upgrade_start() {
        search_container.remove(search_container.get_child());
        search_container.add(search_upgrade_progress_bar);
        search_upgrade_progress_bar.show();
    }
    
    private void on_search_upgrade_finished() {
        search_container.remove(search_container.get_child());
        search_container.add(search_entry);
    }
    
    private void on_account_changed(Geary.Account? account) {
        on_search_upgrade_finished(); // Reset search box.
        
        if (search_upgrade_progress_monitor != null) {
            search_upgrade_progress_monitor.start.disconnect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.disconnect(on_search_upgrade_finished);
            search_upgrade_progress_monitor = null;
        }
        
        if (current_account != null)
            current_account.information.notify[Geary.AccountInformation.PROP_NICKNAME].disconnect(
                on_nickname_changed);
        
        if (account != null) {
            search_upgrade_progress_monitor = account.search_upgrade_monitor;
            search_upgrade_progress_bar.set_progress_monitor(search_upgrade_progress_monitor);
            
            search_upgrade_progress_monitor.start.connect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.connect(on_search_upgrade_finished);
            if (search_upgrade_progress_monitor.is_in_progress)
                on_search_upgrade_start(); // Remove search box, we're already in progress.
            
            account.information.notify[Geary.AccountInformation.PROP_NICKNAME].connect(
                on_nickname_changed);
        }
        
        current_account = account;
        
        search_upgrade_progress_bar.text = _("Indexing %s account").printf(account.information.nickname);
        on_nickname_changed(); // Set new account name.
    }
    
    private void on_nickname_changed() {
        set_search_placeholder_text(current_account == null ||
            GearyApplication.instance.controller.get_num_accounts() == 1 ? DEFAULT_SEARCH_TEXT :
            _("Search %s account").printf(current_account.information.nickname));
    }
}

