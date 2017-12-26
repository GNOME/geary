/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016-2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/main-window.ui")]
public class MainWindow : Gtk.ApplicationWindow {


    public const string ACTION_SELECTION_MODE_DISABLE = "selection-mode-disable";
    public const string ACTION_SELECTION_MODE_ENABLE = "selection-mode-enable";


    private const int STATUS_BAR_HEIGHT = 18;

    private const ActionEntry[] action_entries = {
        {ACTION_SELECTION_MODE_DISABLE, on_selection_mode_disabled },
        {ACTION_SELECTION_MODE_ENABLE, on_selection_mode_enabled }
    };


    public new GearyApplication application {
        get { return (GearyApplication) base.get_application(); }
        set { base.set_application(value); }
    }

    // Used to save/load the window state between sessions.
    public int window_width { get; set; }
    public int window_height { get; set; }
    public bool window_maximized { get; set; }

    // Widget descendants
    public FolderList.Tree folder_list { get; private set; default = new FolderList.Tree(); }
    public MainToolbar main_toolbar { get; private set; }
    public SearchBar search_bar { get; private set; default = new SearchBar(); }
    public ConversationList conversation_list  { get; private set; }
    public ConversationViewer conversation_viewer { get; private set; default = new ConversationViewer(); }
    public StatusBar status_bar { get; private set; default = new StatusBar(); }

    public Geary.Folder? current_folder { get; private set; default = null; }

    private ConversationActionBar conversation_list_actions =
        new ConversationActionBar();
    private Geary.AggregateProgressMonitor progress_monitor =
        new Geary.AggregateProgressMonitor();
    private Geary.ProgressMonitor? folder_progress = null;

    private MonitoredSpinner spinner = new MonitoredSpinner();

    [GtkChild]
    private Gtk.Box main_layout;
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
    private Gtk.Grid conversation_list_grid;
    [GtkChild]
    private Gtk.ScrolledWindow conversation_list_scrolled;

    // This is a frame so users can use F6/Shift-F6 to get to it
    [GtkChild]
    private Gtk.Frame info_bar_frame;

    [GtkChild]
    private Gtk.Grid info_bar_container;

    /** Fired when the shift key is pressed or released. */
    public signal void on_shift_key(bool pressed);


    public MainWindow(GearyApplication application) {
        Object(application: application);

        this.conversation_list = new ConversationList(application.config);
        this.conversation_list.conversation_selection_changed.connect(on_conversation_selection_changed);
        this.conversation_list.conversation_activated.connect(on_conversation_activated);
        this.conversation_list.item_marked.connect(on_conversation_item_marked);
        this.conversation_list.marked_conversations_evaporated.connect(on_selection_mode_disabled);
        this.conversation_list.selection_mode_enabled.connect(on_selection_mode_enabled);
        this.conversation_list.visible_conversations_changed.connect(on_visible_conversations_changed);
        this.conversation_list.load_more.connect(on_load_more);

        this.conversation_list_grid.add(this.conversation_list_actions);

        load_config(application.config);
        restore_saved_window_state();

        application.controller.notify[GearyController.PROP_CURRENT_CONVERSATION]
            .connect(on_conversation_monitor_changed);
        application.controller.folder_selected.connect(on_folder_selected);
        this.application.engine.account_available.connect(on_account_available);
        this.application.engine.account_unavailable.connect(on_account_unavailable);

        set_styling();
        setup_layout(application.config);
        setup_actions();
        on_change_orientation();
    }

    public void show_infobar(MainWindowInfoBar info_bar) {
        this.info_bar_container.add(info_bar);
        this.info_bar_frame.show();
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
        try {
            File file = File.new_for_uri(@"resource:///org/gnome/Geary/geary.css");
            provider.load_from_file(file);
        } catch (Error e) {
            error("Could not load CSS: %s", e.message);
        }
    }

    private void setup_layout(Configuration config) {
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
            main_layout.pack_start(main_toolbar, false, true, 0);
        } else {
            main_toolbar.show_close_button = true;
            set_titlebar(main_toolbar);
        }

        // Search bar
        this.search_bar_box.pack_start(this.search_bar, false, false, 0);
        // Folder list
        this.folder_list_scrolled.add(this.folder_list);
        // Conversation list
        this.conversation_list_scrolled.add(this.conversation_list);
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

    public override bool key_press_event(Gdk.EventKey event) {
        check_shift_event(event);

        /* Ensure that single-key command (SKC) shortcuts don't
         * interfere with text input.
         *
         * The default GtkWindow::key_press_event implementation calls
         * gtk_window_activate_key -- which would activate the SKC,
         * before calling gtk_window_propagate_key_event -- which
         * would send the event to any focused text entry control, so
         * we need to override that. A quick hack is to just call
         * gtk_window_propagate_key_event here, then chain up. But
         * that means two calls to that method for every key press,
         * which in the worst case means all widgets in the focus
         * chain would be consulted to handle the press twice, which
         * sucks.
         *
         * Worse however, is that due to WK2 Bug 136430[0], WebView
         * instances duplicate any key events they don't handle. For
         * the editor, that means simple key presses like 'a' will
         * only result in a single event, since the web view adds the
         * letter to the document. But if not handled, e.g. when the
         * user presses Shift, Ctrl, or similar, then it also produces
         * a second event. Combined with the
         * gtk_window_propagate_key_event above, this leads to a
         * cambrian explosion of key events - an exponential number
         * are generated, which is bad. This problem also applies to
         * ConversationWebView instances, since none of them handle
         * events.
         *
         * The work around here is completely override the default
         * implementation to reverse it. So if something related to
         * key handling breaks in the future, this might be a good
         * place to start looking. Better alternatives welcome.
         *
         * [0] - <https://bugs.webkit.org/show_bug.cgi?id=136430>
         */

        bool handled = propagate_key_event(event);
        if (!handled) {
            handled = activate_key(event);
        }
        if (!handled) {
            handled = Gtk.bindings_activate_event(this, event);
        }
        return handled;
    }

    private void setup_actions() {
        add_action_entries(action_entries, this);
        add_window_accelerators(ACTION_SELECTION_MODE_DISABLE, { "Escape", });
    }

    private void add_window_accelerators(string action, string[] accelerators) {
        this.application.set_accels_for_action("win." + action, accelerators);
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

    private inline void check_shift_event(Gdk.EventKey event) {
        // FIXME: it's possible the user will press two shift keys.  We want
        // the shift key to report as released when they release ALL of them.
        // There doesn't seem to be an easy way to do this in Gdk.
        if (event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R) {
            Gtk.Widget? focus = get_focus();
            if (focus == null ||
                (!(focus is Gtk.Entry) && !(focus is ComposerWebView))) {
                on_shift_key(event.type == Gdk.EventType.KEY_PRESS);
            }
        }
    }

    private inline SimpleAction get_action(string name) {
        return (SimpleAction) lookup_action(name);
    }

    private void show_conversation(Geary.App.Conversation? target) {
        Geary.App.Conversation? current = null;
        ConversationListBox? listbox = this.conversation_viewer.current_list;
        if (listbox != null) {
            current = listbox.conversation;
        }
        SimpleAction find_action = get_action(
            GearyController.ACTION_FIND_IN_CONVERSATION
        );
        if (target != null) {
            if (target != current &&
                !this.conversation_viewer.is_composer_visible) {
                this.conversation_viewer.load_conversation.begin(
                    target,
                    this.application.config,
                    this.application.controller.avatar_session,
                    (obj, ret) => {
                        try {
                            this.conversation_viewer.load_conversation.end(ret);
                            this.application.controller.enable_message_buttons(true);
                            find_action.set_enabled(true);
                        } catch (Error err) {
                            debug("Unable to load conversation: %s",
                                  err.message);
                        }
                    }
                );
            }
        } else {
            find_action.set_enabled(false);
            this.application.controller.enable_message_buttons(false);
            this.conversation_viewer.show_none_selected();
        }
    }

    private void set_selection_mode_enabled(bool enabled) {
        get_action(ACTION_SELECTION_MODE_DISABLE).set_enabled(enabled);
        get_action(ACTION_SELECTION_MODE_ENABLE).set_enabled(!enabled);
        this.main_toolbar.set_selection_mode_enabled(enabled);
        this.conversation_list.set_selection_mode_enabled(enabled);
        this.conversation_viewer.show_none_selected();
    }

    private void on_conversation_monitor_changed() {
        this.conversation_list.freeze_selection();
        ConversationListModel? old_model = this.conversation_list.model;
        if (old_model != null) {
            this.progress_monitor.remove(old_model.monitor.progress_monitor);
            this.progress_monitor.remove(old_model.previews.progress);

            Geary.App.ConversationMonitor? old_monitor = old_model.monitor;
            old_monitor.scan_error.disconnect(on_scan_error);
            old_monitor.seed_completed.disconnect(on_seed_completed);
            old_monitor.seed_completed.disconnect(on_conversation_count_changed);
            old_monitor.seed_completed.disconnect(on_initial_conversation_load);
            old_monitor.scan_completed.disconnect(on_conversation_count_changed);
            old_monitor.conversations_added.disconnect(on_conversation_count_changed);
            old_monitor.conversations_removed.disconnect(on_conversation_count_changed);
        }

        Geary.App.ConversationMonitor? new_monitor =
            this.application.controller.current_conversations;
        if (new_monitor != null) {
            this.conversation_list.bind_model(new_monitor);
            ConversationListModel new_model = this.conversation_list.model;

            this.progress_monitor.add(new_model.monitor.progress_monitor);
            this.progress_monitor.add(new_model.previews.progress);

            new_monitor.scan_error.connect(on_scan_error);
            new_monitor.seed_completed.connect(on_seed_completed);
            new_monitor.seed_completed.connect(on_conversation_count_changed);
            new_monitor.seed_completed.connect(on_initial_conversation_load);
            new_monitor.scan_completed.connect(on_conversation_count_changed);
            new_monitor.conversations_added.connect(on_conversation_count_changed);
            new_monitor.conversations_removed.connect(on_conversation_count_changed);
        }
        this.conversation_list.thaw_selection();
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
        if (folder != null) {
            folder.properties.notify.connect(update_headerbar);
            this.conversation_list_actions.set_account(folder.account);
            this.conversation_list_actions.update_location(this.current_folder);
        }

        // swap it in
        this.current_folder = folder;

        update_headerbar();
        set_selection_mode_enabled(false);
    }

    private void on_account_available(Geary.AccountInformation account) {
        try {
            this.progress_monitor.add(this.application.engine.get_account_instance(account).opening_monitor);
            this.progress_monitor.add(this.application.engine.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }

    private void on_account_unavailable(Geary.AccountInformation account) {
        try {
            this.progress_monitor.remove(this.application.engine.get_account_instance(account).opening_monitor);
            this.progress_monitor.remove(this.application.engine.get_account_instance(account).sending_monitor);
        } catch (Error e) {
            debug("Could not access account progress monitors: %s", e.message);
        }
    }

    private void on_change_orientation() {
        bool horizontal = this.application.config.folder_list_pane_horizontal;
        bool initial = true;

        if (this.status_bar.parent != null) {
            this.status_bar.parent.remove(status_bar);
            initial = false;
        }

        GLib.Settings.unbind(this.folder_paned, "position");
        this.folder_paned.orientation = horizontal ? Gtk.Orientation.HORIZONTAL :
            Gtk.Orientation.VERTICAL;

        int folder_list_width =
            this.application.config.folder_list_pane_position_horizontal;
        if (horizontal) {
            if (!initial)
                this.conversations_paned.position += folder_list_width;
            this.folder_box.pack_start(status_bar, false, false);
        } else {
            if (!initial)
                this.conversations_paned.position -= folder_list_width;
            this.conversation_box.pack_start(status_bar, false, false);
        }

        this.application.config.bind(
            horizontal ? Configuration.FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY
            : Configuration.FOLDER_LIST_PANE_POSITION_VERTICAL_KEY,
            this.folder_paned, "position");
    }

    private void on_conversation_selection_changed(Geary.App.Conversation? selection) {
        show_conversation(selection);
    }

    private void on_conversation_activated(Geary.App.Conversation activated) {
        // Currently activating a conversation is only available for drafts folders.
        if (this.current_folder != null &&
            this.current_folder.special_folder_type == Geary.SpecialFolderType.DRAFTS) {
            // TODO: Determine how to map between conversations and drafts correctly.
            Geary.Email draft = activated.get_latest_recv_email(
                Geary.App.Conversation.Location.IN_FOLDER
                );
            this.application.controller.create_compose_widget(
                ComposerWidget.ComposeType.NEW_MESSAGE, draft, null, null, true
            );
        }
    }

    private void on_conversation_item_marked(ConversationListItem item, bool marked) {
        if (marked) {
            show_conversation(item.conversation);
        } else {
            this.conversation_viewer.show_none_selected();
        }
        this.main_toolbar.update_selection_count(
            this.conversation_list.get_marked_items().size
        );
    }

    private void on_initial_conversation_load() {
        // When not doing autoselect, we never get
        // conversations_selected firing from the convo list, so we
        // need to clear the convo viewer here
        if (!this.application.config.autoselect) {
            this.conversation_viewer.show_none_selected();
            this.application.controller.enable_message_buttons(false);
        }

        this.conversation_list.model.monitor.seed_completed.disconnect(on_initial_conversation_load);
    }

    private void on_load_more() {
        debug("on_load_more");
        this.application.controller.current_conversations.min_window_count += GearyController.CONVERSATION_PAGE_SIZE;
    }

    private void on_scan_error(Error err) {
        debug("Scan error: %s", err.message);
    }

    private void on_seed_completed() {
        // Done scanning.  Check if we have enough messages to fill the conversation list; if not,
        // trigger a load_more();
        if (!conversation_list_has_scrollbar()) {
            debug("Not enough messages, loading more for folder %s", current_folder.to_string());
            on_load_more();
        }
    }

    private void on_conversation_count_changed() {
        if (this.conversation_list.model.monitor != null) {
            int count = this.conversation_list.model.monitor.get_conversation_count();
            if (count == 0) {
                // Let the user know if there's no available conversations
                if (this.current_folder is Geary.SearchFolder) {
                    this.conversation_viewer.show_empty_search();
                } else {
                    this.conversation_viewer.show_empty_folder();
                }
                this.application.controller.enable_message_buttons(false);
            }
        }
    }

    [GtkCallback]
    private bool on_delete_event() {
        if (this.application.is_background_service) {
            if (this.application.controller.close_composition_windows(true)) {
                hide();
            }
        } else {
            this.application.exit();
        }
        return Gdk.EVENT_STOP;
    }

    [GtkCallback]
    private bool on_focus_event() {
        on_shift_key(false);
        return false;
    }

    [GtkCallback]
    private bool on_key_release_event(Gdk.EventKey event) {
        check_shift_event(event);
        return Gdk.EVENT_PROPAGATE;
    }

    [GtkCallback]
    private void on_info_bar_container_remove() {
        // Ensure the info bar frame is hidden when the last info bar
        // is removed from the container.
        if (this.info_bar_container.get_children().length() == 0) {
            this.info_bar_frame.hide();
        }
    }

    private void on_selection_mode_enabled() {
        set_selection_mode_enabled(true);
    }

    private void on_selection_mode_disabled() {
        set_selection_mode_enabled(false);
    }

    private void on_visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible) {
        this.application.controller.clear_new_messages("on_visible_conversations_changed", visible);
    }

}
