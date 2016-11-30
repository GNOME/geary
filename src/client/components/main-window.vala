/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/main-window.ui")]
public class MainWindow : Gtk.ApplicationWindow {
    private const int STATUS_BAR_HEIGHT = 18;

    /** Fired when the shift key is pressed or released. */
    public signal void on_shift_key(bool pressed);

    public Geary.Folder? current_folder { get; private set; default = null; }

    private Geary.AggregateProgressMonitor progress_monitor = new Geary.AggregateProgressMonitor();
    private Geary.ProgressMonitor? folder_progress = null;

    // Used to save/load the window state between sessions.
    public int window_width { get; set; }
    public int window_height { get; set; }
    public bool window_maximized { get; set; }

    // Widget descendants
    public FolderList.Tree folder_list { get; private set; default = new FolderList.Tree(); }
    public MainToolbar main_toolbar { get; private set; }
    public SearchBar search_bar { get; private set; default = new SearchBar(); }
    public ConversationListView conversation_list_view  { get; private set; default = new ConversationListView(); }
    public ConversationViewer conversation_viewer { get; private set; default = new ConversationViewer(); }
    public StatusBar status_bar { get; private set; default = new StatusBar(); }
    private MonitoredSpinner spinner = new MonitoredSpinner();
    [GtkChild]
    private Gtk.Box search_bar_box;
    [GtkChild]
    private Gtk.Paned folder_paned;
    [GtkChild]
    private Gtk.Paned conversations_paned;
    [GtkChild]
    private Gtk.Box folder_box;
    [GtkChild]
    private Gtk.ScrolledWindow folder_list_scrolled;
    [GtkChild]
    private Gtk.Box conversation_box;
    [GtkChild]
    private Gtk.ScrolledWindow conversation_list_scrolled;

    public MainWindow(GearyApplication application) {
        Object(application: application);

        load_config(application.config);
        restore_saved_window_state();

        add_accel_group(application.ui_manager.get_accel_group());

        application.controller.notify[GearyController.PROP_CURRENT_CONVERSATION]
            .connect(on_conversation_monitor_changed);
        application.controller.folder_selected.connect(on_folder_selected);
        Geary.Engine.instance.account_available.connect(on_account_available);
        Geary.Engine.instance.account_unavailable.connect(on_account_unavailable);

        set_styling();
        setup_layout(application.config);
        on_change_orientation();
    }

    private void load_config(Configuration config) {
        // This code both loads AND saves the pane positions with live updating. This is more
        // resilient against crashes because the value in dconf changes *immediately*, and
        // stays saved in the event of a crash.
        config.bind(Configuration.MESSAGES_PANE_POSITION_KEY, this.conversations_paned, "position");
        config.bind(Configuration.WINDOW_WIDTH_KEY, this, "window-width");
        config.bind(Configuration.WINDOW_HEIGHT_KEY, this, "window-height");
        config.bind(Configuration.WINDOW_MAXIMIZE_KEY, this, "window-maximized");
        // Update to layout
        if (config.folder_list_pane_position_horizontal == -1) {
            config.folder_list_pane_position_horizontal = config.folder_list_pane_position_old;
            config.messages_pane_position += config.folder_list_pane_position_old;
        }
        config.settings.changed[Configuration.FOLDER_LIST_PANE_HORIZONTAL_KEY]
            .connect(on_change_orientation);
    }

    private void restore_saved_window_state() {
        Gdk.Screen? screen = get_screen();
        if (screen != null &&
            this.window_width <= screen.get_width() &&
            this.window_height <= screen.get_height()) {
            set_default_size(this.window_width, this.window_height);
        }
        if (this.window_maximized) {
            maximize();
        }
        this.window_position = Gtk.WindowPosition.CENTER;
    }

    // Called on [un]maximize and possibly others. Save maximized state
    // for the next start.
    public override bool window_state_event(Gdk.EventWindowState event) {
        if ((event.new_window_state & Gdk.WindowState.WITHDRAWN) == 0) {
            bool maximized = (
                (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0
            );
            if (this.window_maximized != maximized) {
                this.window_maximized = maximized;
            }
        }
        return base.window_state_event(event);
    }

    // Called on window resize. Save window size for the next start.
    public override void size_allocate(Gtk.Allocation allocation) {
        base.size_allocate(allocation);

        Gdk.Screen? screen = get_screen();
        if (screen != null && !this.window_maximized) {
            // Get the size via ::get_size instead of the allocation
            // so that the window isn't ever-expanding.
            int width = 0;
            int height = 0;
            get_size(out width, out height);

            // Only store if the values have changed and are
            // reasonable-looking.
            if (this.window_width != width &&
                width > 0 && width <= screen.get_width())
                this.window_width = width;
            if (this.window_height != height &&
                height > 0 && height <= screen.get_height())
                this.window_height = height;
        }
    }

    private void set_styling() {
        Gtk.CssProvider provider = new Gtk.CssProvider();
        Gtk.StyleContext.add_provider_for_screen(Gdk.Display.get_default().get_default_screen(),
            provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        provider.parsing_error.connect((section, error) => {
            uint start = section.get_start_line();
            uint end = section.get_end_line();
            if (start == end)
                debug("Error parsing css on line %u: %s", start, error.message);
            else
                debug("Error parsing css on lines %u-%u: %s", start, end, error.message);
        });
        provider.load_from_resource(@"/org/gnome/Geary/geary.css");
    }

    private void setup_layout(Configuration config) {
        // Toolbar
        this.main_toolbar = new MainToolbar(config);
        this.main_toolbar.bind_property("search-open", this.search_bar, "search-mode-enabled",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        this.main_toolbar.bind_property("find-open", this.conversation_viewer.conversation_find_bar,
                "search-mode-enabled", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        if (config.desktop_environment == Configuration.DesktopEnvironment.UNITY) {
            BindingTransformFunc title_func = (binding, source, ref target) => {
                string folder = current_folder != null ? current_folder.get_display_name() + " " : "";
                string account = main_toolbar.account != null ? "(%s)".printf(main_toolbar.account) : "";

                target = "%s%s - %s".printf(folder, account, GearyApplication.NAME);

                return true;
            };
            bind_property("current-folder", this, "title", BindingFlags.SYNC_CREATE, title_func);
            main_toolbar.bind_property("account", this, "title", BindingFlags.SYNC_CREATE, title_func);
        } else {
            main_toolbar.show_close_button = true;
            set_titlebar(main_toolbar);
        }

        // Search bar
        this.search_bar_box.pack_start(this.search_bar, false, false, 0);
        // Folder list
        this.folder_list_scrolled.add(this.folder_list);
        // Conversation list
        this.conversation_list_scrolled.add(this.conversation_list_view);
        // Conversation viewer
        this.conversations_paned.pack2(this.conversation_viewer, true, true);

        // Status bar
        this.status_bar.set_size_request(-1, STATUS_BAR_HEIGHT);
        this.status_bar.set_border_width(2);
        this.spinner.set_size_request(STATUS_BAR_HEIGHT - 2, -1);
        this.spinner.set_progress_monitor(progress_monitor);
        this.status_bar.add(this.spinner);
    }

    // Returns true when there's a conversation list scrollbar visible, i.e. the list is tall
    // enough to need one.  Otherwise returns false.
    public bool conversation_list_has_scrollbar() {
        Gtk.Scrollbar? scrollbar = this.conversation_list_scrolled.get_vscrollbar() as Gtk.Scrollbar;
        return scrollbar != null && scrollbar.get_visible();
    }

    private void on_conversation_monitor_changed() {
        ConversationListStore? old_model = this.conversation_list_view.get_model();
        if (old_model != null) {
            this.progress_monitor.remove(old_model.preview_monitor);
            this.progress_monitor.remove(old_model.conversations.progress_monitor);
        }

        Geary.App.ConversationMonitor? conversations =
            GearyApplication.instance.controller.current_conversations;

        if (conversations != null) {
            ConversationListStore new_model =
                new ConversationListStore(conversations);
            this.progress_monitor.add(new_model.preview_monitor);
            this.progress_monitor.add(conversations.progress_monitor);
            this.conversation_list_view.set_model(new_model);
        }

        if (old_model != null) {
            // Must be destroyed, but only after it has been replaced.
            old_model.destroy();
        }
    }

    private void on_folder_selected(Geary.Folder? folder) {
        if (this.folder_progress != null) {
            this.progress_monitor.remove(this.folder_progress);
            this.folder_progress = null;
        }

        if (folder != null) {
            this.folder_progress = folder.opening_monitor;
            this.progress_monitor.add(this.folder_progress);
        }

        // disconnect from old folder
        if (this.current_folder != null)
            this.current_folder.properties.notify.disconnect(update_headerbar);

        // connect to new folder
        if (folder != null)
            folder.properties.notify.connect(update_headerbar);

        // swap it in
        this.current_folder = folder;

        update_headerbar();
    }

    private void on_account_available(Geary.AccountInformation account) {
        try {
            this.progress_monitor.add(Geary.Engine.instance.get_account_instance(account).opening_monitor);
            this.progress_monitor.add(Geary.Engine.instance.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }

    private void on_account_unavailable(Geary.AccountInformation account) {
        try {
            this.progress_monitor.remove(Geary.Engine.instance.get_account_instance(account).opening_monitor);
            this.progress_monitor.remove(Geary.Engine.instance.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }

    private void on_change_orientation() {
        bool horizontal = GearyApplication.instance.config.folder_list_pane_horizontal;
        bool initial = true;

        if (this.status_bar.parent != null) {
            this.status_bar.parent.remove(status_bar);
            initial = false;
        }

        GLib.Settings.unbind(this.folder_paned, "position");
        this.folder_paned.orientation = horizontal ? Gtk.Orientation.HORIZONTAL :
            Gtk.Orientation.VERTICAL;

        int folder_list_width =
            GearyApplication.instance.config.folder_list_pane_position_horizontal;
        if (horizontal) {
            if (!initial)
                this.conversations_paned.position += folder_list_width;
            this.folder_box.pack_start(status_bar, false, false);
        } else {
            if (!initial)
                this.conversations_paned.position -= folder_list_width;
            this.conversation_box.pack_start(status_bar, false, false);
        }

        GearyApplication.instance.config.bind(
            horizontal ? Configuration.FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY
            : Configuration.FOLDER_LIST_PANE_POSITION_VERTICAL_KEY,
            this.folder_paned, "position");
    }

    private void update_headerbar() {
        if (this.current_folder == null) {
            this.main_toolbar.account = null;
            this.main_toolbar.folder = null;

            return;
        }

        this.main_toolbar.account = this.current_folder.account.information.nickname;

        /// Current folder's name followed by its unread count, i.e. "Inbox (42)"
        // except for Drafts and Outbox, where we show total count
        int count;
        switch (this.current_folder.special_folder_type) {
            case Geary.SpecialFolderType.DRAFTS:
            case Geary.SpecialFolderType.OUTBOX:
                count = this.current_folder.properties.email_total;
            break;

            default:
                count = this.current_folder.properties.email_unread;
            break;
        }

        if (count > 0)
            this.main_toolbar.folder = _("%s (%d)").printf(this.current_folder.get_display_name(), count);
        else
            this.main_toolbar.folder = this.current_folder.get_display_name();
    }

    [GtkCallback]
    private bool on_key_press_event(Gdk.EventKey event) {
        if ((event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R)
            && (event.state & Gdk.ModifierType.SHIFT_MASK) == 0
            && !this.search_bar.search_entry_has_focus)
            on_shift_key(true);

        // Check whether the focused widget wants to handle it, if not let the accelerators kick in
        // via the default handling
        return propagate_key_event(event);
    }

    [GtkCallback]
    private bool on_key_release_event(Gdk.EventKey event) {
        // FIXME: it's possible the user will press two shift keys.  We want
        // the shift key to report as released when they release ALL of them.
        // There doesn't seem to be an easy way to do this in Gdk.
        if ((event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R)
            && !this.search_bar.search_entry_has_focus)
            on_shift_key(false);

        return propagate_key_event(event);
    }

    [GtkCallback]
    private bool on_focus_event() {
        on_shift_key(false);
        return false;
    }

    [GtkCallback]
    private bool on_delete_event() {
        if (Args.hidden_startup || GearyApplication.instance.config.startup_notifications)
            return hide_on_delete();

        GearyApplication.instance.exit();

        return true;
    }
}

