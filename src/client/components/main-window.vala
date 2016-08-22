/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class MainWindow : Gtk.ApplicationWindow {
    private const int MESSAGE_LIST_WIDTH = 250;
    private const int FOLDER_LIST_WIDTH = 100;
    private const int STATUS_BAR_HEIGHT = 18;
    
    /// Fired when the shift key is pressed or released.
    public signal void on_shift_key(bool pressed);
    
    public FolderList.Tree folder_list { get; private set; default = new FolderList.Tree(); }
    public MainToolbar main_toolbar { get; private set; }
    public SearchBar search_bar { get; private set; default = new SearchBar(); }
    public ConversationListView conversation_list_view  { get; private set; default = new ConversationListView(); }
    public ConversationViewer conversation_viewer { get; private set; default = new ConversationViewer(); }
    public StatusBar status_bar { get; private set; default = new StatusBar(); }
    public Geary.Folder? current_folder { get; private set; default = null; }
    
    public int window_width { get; set; }
    public int window_height { get; set; }
    public bool window_maximized { get; set; }

    private Gtk.Paned folder_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    private Gtk.Paned conversations_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    
    private Gtk.ScrolledWindow conversation_list_scrolled;
    private MonitoredSpinner spinner = new MonitoredSpinner();
    private Gtk.Box folder_box;
    private Gtk.Box conversation_box;
    private Geary.AggregateProgressMonitor progress_monitor = new Geary.AggregateProgressMonitor();
    private Geary.ProgressMonitor? folder_progress = null;
    
    public MainWindow(GearyApplication application) {
        Object(application: application);
        set_show_menubar(false);
        
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK
            | Gdk.EventMask.FOCUS_CHANGE_MASK);
        
        // This code both loads AND saves the pane positions with live
        // updating. This is more resilient against crashes because
        // the value in dconf changes *immediately*, and stays saved
        // in the event of a crash.
        Configuration config = GearyApplication.instance.config;
        config.bind(Configuration.MESSAGES_PANE_POSITION_KEY, conversations_paned, "position");
        config.bind(Configuration.WINDOW_WIDTH_KEY, this, "window-width");
        config.bind(Configuration.WINDOW_HEIGHT_KEY, this, "window-height");
        config.bind(Configuration.WINDOW_MAXIMIZE_KEY, this, "window-maximized");
        // Update to layout
        if (config.folder_list_pane_position_horizontal == -1) {
            config.folder_list_pane_position_horizontal = config.folder_list_pane_position_old;
            config.messages_pane_position += config.folder_list_pane_position_old;
        }

        // Restore saved window state
        Gdk.Screen? screen = get_screen();
        if (screen != null &&
            this.window_width <= screen.get_width() &&
            this.window_height <= screen.get_height()) {
            set_default_size(this.window_width, this.window_height);
        }
        if (this.window_maximized) {
            maximize();
        }
        set_position(Gtk.WindowPosition.CENTER);

        add_accel_group(GearyApplication.instance.ui_manager.get_accel_group());
        
        spinner.set_progress_monitor(progress_monitor);

        delete_event.connect(on_delete_event);
        key_press_event.connect(on_key_press_event);
        key_release_event.connect(on_key_release_event);
        focus_in_event.connect(on_focus_event);
        GearyApplication.instance.config.settings.changed[
            Configuration.FOLDER_LIST_PANE_HORIZONTAL_KEY].connect(on_change_orientation);
        GearyApplication.instance.controller.notify[GearyController.PROP_CURRENT_CONVERSATION].
            connect(on_conversation_monitor_changed);
        GearyApplication.instance.controller.folder_selected.connect(on_folder_selected);
        Geary.Engine.instance.account_available.connect(on_account_available);
        Geary.Engine.instance.account_unavailable.connect(on_account_unavailable);

        // Toolbar.
        main_toolbar = new MainToolbar();
        main_toolbar.bind_property("search-open", search_bar, "search-mode-enabled",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        main_toolbar.bind_property("find-open", conversation_viewer.conversation_find_bar, "search-mode-enabled",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        main_toolbar.show_close_button = true;
        set_titlebar(main_toolbar);

        set_styling();
        create_layout();
        on_change_orientation();
    }

    private bool on_delete_event() {
        if (Args.hidden_startup || GearyApplication.instance.config.startup_notifications)
            return hide_on_delete();
        
        GearyApplication.instance.exit();
        
        return true;
    }

    // Fired on [un]maximize and possibly others. Save maximized state
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

    // Fired on window resize. Save window size for the next start.
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
    
    private void create_layout() {
        Gtk.Box main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        
        // folder list
        Gtk.ScrolledWindow folder_list_scrolled = new Gtk.ScrolledWindow(null, null);
        folder_list_scrolled.set_size_request(FOLDER_LIST_WIDTH, -1);
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add(folder_list);
        Gtk.Frame folder_frame = new Gtk.Frame(null);
        folder_frame.shadow_type = Gtk.ShadowType.IN;
        folder_frame.get_style_context ().add_class("geary-folder-frame");
        folder_frame.add(folder_list_scrolled);
        folder_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        folder_box.pack_start(folder_frame, true, true);

        // message list
        conversation_list_scrolled = new Gtk.ScrolledWindow(null, null);
        conversation_list_scrolled.set_size_request(MESSAGE_LIST_WIDTH, -1);
        conversation_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        conversation_list_scrolled.add(conversation_list_view);
        Gtk.Frame conversation_frame = new Gtk.Frame(null);
        conversation_frame.shadow_type = Gtk.ShadowType.IN;
        conversation_frame.get_style_context ().add_class("geary-conversation-frame");
        conversation_frame.add(conversation_list_scrolled);
        conversation_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        conversation_box.pack_start(conversation_frame, true, true);
        
        // Three-pane display.
        status_bar.set_size_request(-1, STATUS_BAR_HEIGHT);
        status_bar.set_border_width(2);
        spinner.set_size_request(STATUS_BAR_HEIGHT - 2, -1);
        status_bar.add(spinner);
        
        folder_paned.get_style_context().add_class("geary-sidebar-pane-separator");

        // Folder list to the left of everything.
        folder_paned.pack1(folder_box, false, false);
        folder_paned.pack2(conversation_box, true, false);
        
        Gtk.Box search_bar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        search_bar_box.pack_start(search_bar, false, false, 0);
        search_bar_box.pack_start(folder_paned);
        search_bar_box.get_style_context().add_class(Gtk.STYLE_CLASS_SIDEBAR);
        
        // Message list left of message viewer.
        conversations_paned.pack1(search_bar_box, false, false);
        conversations_paned.pack2(conversation_viewer, true, true);
        main_layout.pack_end(conversations_paned, true, true, 0);
        
        add(main_layout);
    }
    
    // Returns true when there's a conversation list scrollbar visible, i.e. the list is tall
    // enough to need one.  Otherwise returns false.
    public bool conversation_list_has_scrollbar() {
        Gtk.Scrollbar? scrollbar = conversation_list_scrolled.get_vscrollbar() as Gtk.Scrollbar;
        return scrollbar != null && scrollbar.get_visible();
    }
    
    private bool on_key_press_event(Gdk.EventKey event) {
        if ((event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R)
            && (event.state & Gdk.ModifierType.SHIFT_MASK) == 0 && !search_bar.search_entry_has_focus)
            on_shift_key(true);
        
        // Check whether the focused widget wants to handle it, if not let the accelerators kick in
        // via the default handling
        return propagate_key_event(event);
    }
    
    private bool on_key_release_event(Gdk.EventKey event) {
        // FIXME: it's possible the user will press two shift keys.  We want
        // the shift key to report as released when they release ALL of them.
        // There doesn't seem to be an easy way to do this in Gdk.
        if ((event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R)
            && !search_bar.search_entry_has_focus)
            on_shift_key(false);
        
        return propagate_key_event(event);
    }
    
    private bool on_focus_event() {
        on_shift_key(false);
        return false;
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
        if (folder_progress != null) {
            progress_monitor.remove(folder_progress);
            folder_progress = null;
        }
        
        if (folder != null) {
            folder_progress = folder.opening_monitor;
            progress_monitor.add(folder_progress);
        }
        
        // disconnect from old folder
        if (current_folder != null)
            current_folder.properties.notify.disconnect(update_headerbar);
        
        // connect to new folder
        if (folder != null)
            folder.properties.notify.connect(update_headerbar);
        
        // swap it in
        current_folder = folder;
        
        update_headerbar();
    }
    
    private void on_account_available(Geary.AccountInformation account) {
        try {
            progress_monitor.add(Geary.Engine.instance.get_account_instance(account).opening_monitor);
            progress_monitor.add(Geary.Engine.instance.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }
    
    private void on_account_unavailable(Geary.AccountInformation account) {
        try {
            progress_monitor.remove(Geary.Engine.instance.get_account_instance(account).opening_monitor);
            progress_monitor.remove(Geary.Engine.instance.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }
    
    private void on_change_orientation() {
        bool horizontal = GearyApplication.instance.config.folder_list_pane_horizontal;
        bool initial = true;
        
        if (status_bar.parent != null) {
            status_bar.parent.remove(status_bar);
            initial = false;
        }
        
        GLib.Settings.unbind(folder_paned, "position");
        folder_paned.orientation = horizontal ? Gtk.Orientation.HORIZONTAL :
            Gtk.Orientation.VERTICAL;
        
        int folder_list_width =
            GearyApplication.instance.config.folder_list_pane_position_horizontal;
        if (horizontal) {
            if (!initial)
                conversations_paned.position += folder_list_width;
            folder_box.pack_start(status_bar, false, false);
        } else {
            if (!initial)
                conversations_paned.position -= folder_list_width;
            conversation_box.pack_start(status_bar, false, false);
        }
        
        GearyApplication.instance.config.bind(
            horizontal ? Configuration.FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY
            : Configuration.FOLDER_LIST_PANE_POSITION_VERTICAL_KEY,
            folder_paned, "position");
    }
    
    private void update_headerbar() {
        if (current_folder == null) {
            main_toolbar.account = null;
            main_toolbar.folder = null;
            
            return;
        }
        
        main_toolbar.account = current_folder.account.information.nickname;
        
        /// Current folder's name followed by its unread count, i.e. "Inbox (42)"
        // except for Drafts and Outbox, where we show total count
        int count;
        switch (current_folder.special_folder_type) {
            case Geary.SpecialFolderType.DRAFTS:
            case Geary.SpecialFolderType.OUTBOX:
                count = current_folder.properties.email_total;
            break;
            
            default:
                count = current_folder.properties.email_unread;
            break;
        }
        
        if (count > 0)
            main_toolbar.folder = _("%s (%d)").printf(current_folder.get_display_name(), count);
        else
            main_toolbar.folder = current_folder.get_display_name();
    }
}

