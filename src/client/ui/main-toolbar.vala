/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the main toolbar.
public class MainToolbar : Gtk.Box {
    private const string ICON_CLEAR_NAME = "edit-clear-symbolic";
    private const string DEFAULT_SEARCH_TEXT = _("Search");
    
    private Gtk.Toolbar toolbar;
    public FolderMenu copy_folder_menu { get; private set; }
    public FolderMenu move_folder_menu { get; private set; }
    public string search_text { get { return search_entry.text; } }
    
    private GtkUtil.ToggleToolbarDropdown mark_menu_dropdown;
    private GtkUtil.ToggleToolbarDropdown app_menu_dropdown;
    private Gtk.ToolItem search_container;
    private Gtk.Entry search_entry;
    private Geary.ProgressMonitor? search_upgrade_progress_monitor = null;
    private MonitoredProgressBar search_upgrade_progress_bar = new MonitoredProgressBar();
    
    public signal void search_text_changed(string search_text);
    
    public MainToolbar() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        
        GearyApplication.instance.controller.account_selected.connect(on_account_changed);
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("toolbar.glade");
        toolbar = builder.get_object("toolbar") as Gtk.Toolbar;

        // Setup each of the normal toolbar buttons.
        set_toolbutton_action(builder, GearyController.ACTION_NEW_MESSAGE);
        set_toolbutton_action(builder, GearyController.ACTION_REPLY_TO_MESSAGE);
        set_toolbutton_action(builder, GearyController.ACTION_REPLY_ALL_MESSAGE);
        set_toolbutton_action(builder, GearyController.ACTION_FORWARD_MESSAGE);
        set_toolbutton_action(builder, GearyController.ACTION_DELETE_MESSAGE);

        // Setup the folder menus (move/copy).
        
        Gtk.ToggleToolButton copy_toggle_button = set_toolbutton_action(builder,
            GearyController.ACTION_COPY_MENU) as Gtk.ToggleToolButton;
        copy_folder_menu = new FolderMenu(
            IconFactory.instance.get_custom_icon("tag-new", IconFactory.ICON_TOOLBAR),
            Gtk.IconSize.LARGE_TOOLBAR, null, null);
        copy_folder_menu.attach(copy_toggle_button);
        
        Gtk.ToggleToolButton move_toggle_button = set_toolbutton_action(builder,
            GearyController.ACTION_MOVE_MENU) as Gtk.ToggleToolButton;
        move_folder_menu = new FolderMenu(
            IconFactory.instance.get_custom_icon("mail-move", IconFactory.ICON_TOOLBAR),
            Gtk.IconSize.LARGE_TOOLBAR, null, null);
        move_folder_menu.attach(move_toggle_button);
        
        // Assemble mark menu button.
        GearyApplication.instance.load_ui_file("toolbar_mark_menu.ui");
        Gtk.Menu mark_menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMarkMenu")
            as Gtk.Menu;
        Gtk.Menu mark_proxy_menu = (Gtk.Menu) GearyApplication.instance.ui_manager
            .get_widget("/ui/ToolbarMarkMenuProxy");
        Gtk.ToggleToolButton mark_menu_button = set_toolbutton_action(builder,
            GearyController.ACTION_MARK_AS_MENU) as Gtk.ToggleToolButton;
        mark_menu_dropdown = new GtkUtil.ToggleToolbarDropdown(
            IconFactory.instance.get_custom_icon("edit-mark", IconFactory.ICON_TOOLBAR),
            Gtk.IconSize.LARGE_TOOLBAR, mark_menu, mark_proxy_menu);
        mark_menu_dropdown.attach(mark_menu_button);
        
        // Search bar.
        search_container = (Gtk.ToolItem) builder.get_object("search_container");
        search_entry = (Gtk.Entry) builder.get_object("search_entry");
        search_entry.changed.connect(on_search_entry_changed);
        search_entry.icon_release.connect(on_search_entry_icon_release);
        search_entry.key_press_event.connect(on_search_key_press);
        on_search_entry_changed(); // set initial state
        search_entry.has_focus = true;
        
        // Setup the application menu.
        GearyApplication.instance.load_ui_file("toolbar_menu.ui");
        Gtk.Menu application_menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMenu")
            as Gtk.Menu;
        Gtk.Menu application_proxy_menu = GearyApplication.instance.ui_manager.get_widget("/ui/ToolbarMenuProxy")
            as Gtk.Menu;
        Gtk.ToggleToolButton app_menu_button = set_toolbutton_action(builder, GearyController.ACTION_GEAR_MENU)
            as Gtk.ToggleToolButton;
        app_menu_dropdown = new GtkUtil.ToggleToolbarDropdown(
            IconFactory.instance.get_theme_icon("application-menu"), Gtk.IconSize.LARGE_TOOLBAR,
            application_menu, application_proxy_menu);
        app_menu_dropdown.show_arrow = false;
        app_menu_dropdown.attach(app_menu_button);
        
        toolbar.get_style_context().add_class("primary-toolbar");
        
        search_upgrade_progress_bar.show_text = true;
        search_upgrade_progress_bar.margin_top = search_upgrade_progress_bar.margin_bottom = 3;
        
        add(toolbar);
        set_search_placeholder_text(DEFAULT_SEARCH_TEXT);
    }
    
    private Gtk.ToolButton set_toolbutton_action(Gtk.Builder builder, string action) {
        Gtk.ToolButton button = builder.get_object(action) as Gtk.ToolButton;
        
        // Must manually set use_action_appearance to false until Glade re-adds this feature.
        // See this ticket: https://bugzilla.gnome.org/show_bug.cgi?id=694407#c11
        button.use_action_appearance = false;
        button.set_related_action(GearyApplication.instance.actions.get_action(action));
        return button;
    }
    
    public void set_search_text(string text) {
        search_entry.text = text;
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
        
        if (account != null) {
            search_upgrade_progress_monitor = account.search_upgrade_monitor;
            search_upgrade_progress_bar.set_progress_monitor(search_upgrade_progress_monitor);
            
            search_upgrade_progress_monitor.start.connect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.connect(on_search_upgrade_finished);
            if (search_upgrade_progress_monitor.is_in_progress)
                on_search_upgrade_start(); // Remove search box, we're already in progress.
        }
        
        search_upgrade_progress_bar.text = _("Indexing %s account").printf(account.information.nickname);
        
        set_search_placeholder_text(account == null || GearyApplication.instance.controller.get_num_accounts() == 1 ?
             DEFAULT_SEARCH_TEXT : _("Search %s account").printf(account.information.nickname));
    }
}

