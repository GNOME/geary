/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016, 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/main-window.ui")]
public class MainWindow : Gtk.ApplicationWindow, Geary.BaseInterface {


    // Named actions.
    public const string ACTION_ARCHIVE_CONVERSATION = "archive-conv";
    public const string ACTION_CONVERSATION_DOWN = "down-conversation";
    public const string ACTION_CONVERSATION_LIST = "focus-conv-list";
    public const string ACTION_CONVERSATION_UP = "up-conversation";
    public const string ACTION_COPY_MENU = "show-copy-menu";
    public const string ACTION_DELETE_CONVERSATION = "delete-conv";
    public const string ACTION_EMPTY_SPAM = "empty-spam";
    public const string ACTION_EMPTY_TRASH = "empty-trash";
    public const string ACTION_FIND_IN_CONVERSATION = "conv-find";
    public const string ACTION_FORWARD_MESSAGE = "forward-message";
    public const string ACTION_MARK_AS_READ = "mark-message-read";
    public const string ACTION_MARK_AS_STARRED = "mark-message-starred";
    public const string ACTION_MARK_AS_UNREAD = "mark-message-unread";
    public const string ACTION_MARK_AS_UNSTARRED = "mark-message-unstarred";
    public const string ACTION_MOVE_MENU = "show-move-menu";
    public const string ACTION_REPLY_ALL_MESSAGE = "reply-all-message";
    public const string ACTION_REPLY_TO_MESSAGE = "reply-to-message";
    public const string ACTION_SEARCH = "search-conv";
    public const string ACTION_SHOW_MARK_MENU = "mark-message-menu";
    public const string ACTION_TOGGLE_FIND = "toggle-find";
    public const string ACTION_TOGGLE_SEARCH = "toggle-search";
    public const string ACTION_TOGGLE_SPAM = "toggle-message-spam";
    public const string ACTION_TRASH_CONVERSATION = "trash-conv";
    public const string ACTION_ZOOM = "zoom";

    private const int STATUS_BAR_HEIGHT = 18;
    private const int UPDATE_UI_INTERVAL = 60;
    private const int MIN_CONVERSATION_COUNT = 50;

    private const ActionEntry[] win_action_entries = {
        {GearyApplication.ACTION_CLOSE, on_close },
        {GearyApplication.ACTION_UNDO,  on_undo },
        {GearyApplication.ACTION_REDO,  on_redo },

        {ACTION_CONVERSATION_LIST,     on_conversation_list            },
        {ACTION_FIND_IN_CONVERSATION,  on_find_in_conversation_action  },
        {ACTION_SEARCH,                on_search_activated             },
        {ACTION_EMPTY_SPAM,            on_empty_spam                   },
        {ACTION_EMPTY_TRASH,           on_empty_trash                  },
        // Message actions
        {ACTION_REPLY_TO_MESSAGE,      on_reply_conversation },
        {ACTION_REPLY_ALL_MESSAGE,     on_reply_all_conversation },
        {ACTION_FORWARD_MESSAGE,       on_forward_conversation },
        {ACTION_ARCHIVE_CONVERSATION,  on_archive_conversation },
        {ACTION_TRASH_CONVERSATION,    on_trash_conversation   },
        {ACTION_DELETE_CONVERSATION,   on_delete_conversation  },
        {ACTION_COPY_MENU,             on_show_copy_menu       },
        {ACTION_MOVE_MENU,             on_show_move_menu       },
        {ACTION_CONVERSATION_UP,       on_conversation_up      },
        {ACTION_CONVERSATION_DOWN,     on_conversation_down    },
        // Message marking actions
        {ACTION_SHOW_MARK_MENU,     on_show_mark_menu           },
        {ACTION_MARK_AS_READ,       on_mark_as_read             },
        {ACTION_MARK_AS_UNREAD,     on_mark_as_unread           },
        {ACTION_MARK_AS_STARRED,    on_mark_as_starred          },
        {ACTION_MARK_AS_UNSTARRED,  on_mark_as_unstarred        },
        {ACTION_TOGGLE_SPAM,        on_mark_as_spam_toggle      },
        // Message viewer
        {ACTION_ZOOM,  on_zoom,  "s"  },
    };


    public static void add_window_accelerators(GearyApplication owner) {
        // Marking actions
        //
        // Unmark is the primary action
        owner.add_window_accelerators(
            ACTION_MARK_AS_READ, { "<Ctrl><Shift>U", "<Shift>I" }
        );
        owner.add_window_accelerators(
            ACTION_MARK_AS_UNREAD, { "<Ctrl>U", "<Shift>U" }
        );
        // Ephy uses Ctrl+D for bookmarking
        owner.add_window_accelerators(
            ACTION_MARK_AS_STARRED, { "<Ctrl>D", "S" }
        );
        owner.add_window_accelerators(
            ACTION_MARK_AS_UNSTARRED, { "<Ctrl><Shift>D", "D" }
        );
        owner.add_window_accelerators(
            ACTION_TOGGLE_SPAM, { "<Ctrl>J", "exclam" } // Exclamation mark (!)
        );

        // Replying & forwarding
        owner.add_window_accelerators(
            ACTION_REPLY_TO_MESSAGE, { "<Ctrl>R", "R" }
        );
        owner.add_window_accelerators(
            ACTION_REPLY_ALL_MESSAGE, { "<Ctrl><Shift>R", "<Shift>R" }
        );
        owner.add_window_accelerators(
            ACTION_FORWARD_MESSAGE, { "<Ctrl>L", "F" }
        );

        // Moving & labelling
        owner.add_window_accelerators(
            ACTION_COPY_MENU, { "<Ctrl>L", "L" }
        );
        owner.add_window_accelerators(
            ACTION_MOVE_MENU, { "<Ctrl>M", "M" }
        );
        owner.add_window_accelerators(
            ACTION_ARCHIVE_CONVERSATION, { "<Ctrl>K", "A", "Y" }
        );
        owner.add_window_accelerators(
            ACTION_TRASH_CONVERSATION, { "Delete", "BackSpace" }
        );
        owner.add_window_accelerators(
            ACTION_DELETE_CONVERSATION, { "<Shift>Delete", "<Shift>BackSpace" }
        );

        // Find & search
        owner.add_window_accelerators(
            ACTION_FIND_IN_CONVERSATION, { "<Ctrl>F", "slash" }
        );
        owner.add_window_accelerators(
            ACTION_SEARCH, { "<Ctrl>S" }
        );

        // Zoom
        owner.add_window_accelerators(
            ACTION_ZOOM+("('in')"), { "<Ctrl>equal", "<Ctrl>plus" }
        );
        owner.add_window_accelerators(
            ACTION_ZOOM+("('out')"), { "<Ctrl>minus" }
        );
        owner.add_window_accelerators(
            ACTION_ZOOM+("('normal')"), { "<Ctrl>0" }
        );

        // Navigation
        owner.add_window_accelerators(
            ACTION_CONVERSATION_LIST, { "<Ctrl>B" }
        );
        owner.add_window_accelerators(
            ACTION_CONVERSATION_UP, { "<Ctrl>bracketleft", "K" }
        );
        owner.add_window_accelerators(
            ACTION_CONVERSATION_DOWN, { "<Ctrl>bracketright", "J" }
        );
    }


    public new GearyApplication application {
        get { return (GearyApplication) base.get_application(); }
        set { base.set_application(value); }
    }

    /** Currently selected account, null if none selected */
    public Geary.Account? current_account {
        owned get {
            Geary.Account? account = null;
            if (this.current_folder != null) {
                account = this.current_folder.account;
            }
            return account;
        }
    }

    /** Currently selected folder, null if none selected */
    public Geary.Folder? current_folder { get; private set; default = null; }

    /** Conversations for the current folder, null if none selected */
    public Geary.App.ConversationMonitor? conversations {
        get; private set; default = null;
    }

    /** Determines if a composer is currently open in this window. */
    public bool has_composer {
        get {
            return (this.conversation_viewer.current_composer != null);
        }
    }

    /** Specifies if the Shift key is currently being held. */
    public bool is_shift_down { get; private set; default = false; }

    // Used to save/load the window state between sessions.
    public int window_width { get; set; }
    public int window_height { get; set; }
    public bool window_maximized { get; set; }

    // Widget descendants
    public FolderList.Tree folder_list { get; private set; default = new FolderList.Tree(); }
    public MainToolbar main_toolbar { get; private set; }
    public SearchBar search_bar { get; private set; default = new SearchBar(); }
    public ConversationListView conversation_list_view  { get; private set; }
    public ConversationViewer conversation_viewer { get; private set; }
    public StatusBar status_bar { get; private set; default = new StatusBar(); }
    private MonitoredSpinner spinner = new MonitoredSpinner();

    private Geary.AggregateProgressMonitor progress_monitor = new Geary.AggregateProgressMonitor();
    private Geary.TimeoutManager update_ui_timeout;
    private int64 update_ui_last = 0;

    private Application.CommandStack commands { get; protected set; }


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
    private Gtk.ScrolledWindow conversation_list_scrolled;
    [GtkChild]
    private Gtk.Overlay overlay;

    // This is a frame so users can use F6/Shift-F6 to get to it
    [GtkChild]
    private Gtk.Frame info_bar_frame;

    [GtkChild]
    private Gtk.Grid info_bar_container;

    [GtkChild]
    private Gtk.InfoBar offline_infobar;

    [GtkChild]
    private Gtk.InfoBar cert_problem_infobar;

    [GtkChild]
    private Gtk.InfoBar auth_problem_infobar;

    private MainWindowInfoBar? service_problem_infobar = null;

    /** Fired when the user requests an account status be retried. */
    public signal void retry_service_problem(Geary.ClientService.Status problem);

    /** Fired when the shift key is pressed or released. */
    public signal void on_shift_key(bool pressed);


    public MainWindow(GearyApplication application,
                      Application.CommandStack commands) {
        Object(
            application: application,
            show_menubar: false
        );
        base_ref();

        load_config(application.config);
        restore_saved_window_state();
        add_action_entries(win_action_entries, this);

        set_styling();
        setup_layout(application.config);
        on_change_orientation();

        this.commands = commands;
        this.commands.executed.connect(on_command_execute);
        this.commands.undone.connect(on_command_undo);
        this.commands.redone.connect(on_command_execute);
        update_command_actions();

        this.application.engine.account_available.connect(on_account_available);
        this.application.engine.account_unavailable.connect(on_account_unavailable);

        this.update_ui_timeout = new Geary.TimeoutManager.seconds(
            UPDATE_UI_INTERVAL, on_update_ui_timeout
        );
        this.update_ui_timeout.repetition = FOREVER;

        this.main_layout.show_all();
    }

    ~MainWindow() {
        this.update_ui_timeout.reset();
        base_unref();
    }

    /** Updates the window's account status info bars. */
    public void update_account_status(Geary.Account.Status status,
                                      bool has_auth_error,
                                      bool has_cert_error,
                                      Geary.Account? problem_source) {
        // Only ever show one at a time. Offline is primary since
        // nothing else can happen when offline. Service problems are
        // secondary since auth and cert problems can't be resolved
        // when the service isn't talking to the server. Cert problems
        // are tertiary since you can't auth if you can't connect.
        bool show_offline = false;
        bool show_service = false;
        bool show_cert = false;
        bool show_auth = false;

        if (!status.is_online()) {
            show_offline = true;
        } else if (status.has_service_problem()) {
            show_service = true;
        } else if (has_cert_error) {
            show_cert = true;
        } else if (has_auth_error) {
            show_auth = true;
        }

        if (show_service && this.service_problem_infobar == null) {
            Geary.ClientService? service = (
                problem_source.incoming.last_error != null
                ? problem_source.incoming
                : problem_source.outgoing
            );
            this.service_problem_infobar = new MainWindowInfoBar.for_problem(
                new Geary.ServiceProblemReport(
                    problem_source.information,
                    service.configuration,
                    service.last_error.thrown
                )
            );
            this.service_problem_infobar.retry.connect(on_service_problem_retry);

            show_infobar(this.service_problem_infobar);
        }

        this.offline_infobar.set_visible(show_offline);
        this.cert_problem_infobar.set_visible(show_cert);
        this.auth_problem_infobar.set_visible(show_auth);
        update_infobar_frame();
    }

    /** Selects the given account and folder. */
    public void show_folder(Geary.Folder folder) {
        this.folder_list.select_folder(folder);
    }

    /** Selects the given account, folder and email. */
    public void show_email(Geary.Folder folder, Geary.EmailIdentifier id) {
        // XXX this is broken in the case of the email's folder not
        // being currently selected and loaded, since changing folders
        // and loading the email in the conversation monitor won't
        // have completed until well after is it obtained
        // below. However, it should work in the only case where this
        // currently used, that is when a user clicks on a
        // notification for new mail in the current folder.
        show_folder(folder);
        Geary.App.Conversation? conversation =
            this.conversations.get_by_email_identifier(id);
        if (conversation != null) {
            this.conversation_list_view.select_conversation(conversation);
        }
    }

    /** Displays and focuses the search bar for the window. */
    public void show_search_bar(string? text = null) {
        this.search_bar.give_search_focus();
        if (text != null) {
            this.search_bar.set_search_text(text);
        }
    }

    /** Displays an infobar in the window. */
    public void show_infobar(MainWindowInfoBar info_bar) {
        this.info_bar_container.add(info_bar);
        this.info_bar_frame.show();
    }

    /** Displays a composer addressed to a specific email address. */
    public void open_composer_for_mailbox(Geary.RFC822.MailboxAddress to) {
        Application.Controller controller = this.application.controller;
        ComposerWidget composer = new ComposerWidget(
            this.application, this.current_folder.account, null, NEW_MESSAGE
        );
        composer.to = to.to_full_display();
        controller.add_composer(composer);
        show_composer(composer);
        composer.load.begin(null, null, null);
    }

    /** Displays a composer in the window if possible, else in a new window. */
    public void show_composer(ComposerWidget composer) {
        if (this.has_composer) {
            composer.state = ComposerWidget.ComposerState.DETACHED;
            new ComposerWindow(composer, this.application);
        } else {
            this.conversation_viewer.do_compose(composer);
            get_action(ACTION_FIND_IN_CONVERSATION).set_enabled(false);
        }
    }

    /**
     * Closes any open composers after prompting the user.
     *
     * Returns true if none were open or the user approved closing
     * them.
     */
    public bool close_composer() {
        bool closed = true;
        ComposerWidget? composer = this.conversation_viewer.current_composer;
        if (composer != null) {
            switch (composer.should_close()) {
            case DO_CLOSE:
                composer.close();
                break;

            case CANCEL_CLOSE:
                closed = false;
                break;
            }
        }
        return closed;
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
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Monitor? monitor = display.get_primary_monitor();
            if (monitor == null) {
                monitor = display.get_monitor_at_point(1, 1);
            }
            if (monitor != null &&
                this.window_width <= monitor.geometry.width &&
                this.window_height <= monitor.geometry.height) {
                set_default_size(this.window_width, this.window_height);
            }
        }
        this.window_position = Gtk.WindowPosition.CENTER;
        if (this.window_maximized) {
            maximize();
        }
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

        if (!this.window_maximized) {
            Gdk.Display? display = get_display();
            Gdk.Window? window = get_window();
            if (display != null && window != null) {
                Gdk.Monitor monitor = display.get_monitor_at_window(window);

                // Get the size via ::get_size instead of the
                // allocation so that the window isn't ever-expanding.
                int width = 0;
                int height = 0;
                get_size(out width, out height);

                // Only store if the values have changed and are
                // reasonable-looking.
                if (this.window_width != width &&
                    width > 0 && width <= monitor.geometry.width) {
                    this.window_width = width;
                }
                if (this.window_height != height &&
                    height > 0 && height <= monitor.geometry.height) {
                    this.window_height = height;
                }
            }
        }
    }

    public void add_notification(Components.InAppNotification notification) {
        this.overlay.add_overlay(notification);
        notification.show();
    }

    private void set_styling() {
        Gtk.CssProvider provider = new Gtk.CssProvider();
        Gtk.StyleContext.add_provider_for_screen(Gdk.Display.get_default().get_default_screen(),
            provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        if (_PROFILE != "") {
            Gtk.StyleContext ctx = this.get_style_context();
            ctx.add_class("devel");
        }

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
        this.conversation_list_view = new ConversationListView(this);
        this.conversation_list_view.load_more.connect(on_load_more);

        this.conversation_viewer = new ConversationViewer(
            this.application.config
        );
        this.conversation_viewer.conversation_added.connect(
            on_conversation_view_added
        );

        this.main_toolbar = new MainToolbar(config);
        this.main_toolbar.move_folder_menu.folder_selected.connect(on_move_conversation);
        this.main_toolbar.copy_folder_menu.folder_selected.connect(on_copy_conversation);
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
            bind_property("current-folder", this, "title", BindingFlags.SYNC_CREATE, (owned) title_func);
            main_toolbar.bind_property("account", this, "title", BindingFlags.SYNC_CREATE, (owned) title_func);
            main_layout.pack_start(main_toolbar, false, true, 0);
        } else {
            main_toolbar.show_close_button = true;
            set_titlebar(main_toolbar);
        }

        // Search bar
        this.search_bar_box.pack_start(this.search_bar, false, false, 0);

        // Folder list
        this.folder_list_scrolled.add(this.folder_list);
        this.folder_list.move_conversation.connect(on_move_conversation);
        this.folder_list.copy_conversation.connect(on_copy_conversation);

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

    /** {@inheritDoc} */
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

        bool handled = false;
        Gdk.ModifierType state = (
            event.state & Gtk.accelerator_get_default_mod_mask()
        );
        if (state > 0 && state != Gdk.ModifierType.SHIFT_MASK) {
            // Have a modifier held down (Ctrl, Alt, etc) that is used
            // as an accelerator so we don't need to worry about SKCs,
            // and the key press can be handled normally. Can't do
            // this with Shift though since that will stop chars being
            // typed in the composer that conflict with accels, like
            // `!`.
            handled = base.key_press_event(event);
        } else {
            // No modifier used as an accelerator is down, so kluge
            // input handling to make SKCs work per the above.
            handled = propagate_key_event(event);
            if (!handled) {
                handled = activate_key(event);
            }
            if (!handled) {
                handled = Gtk.bindings_activate_event(this, event);
            }
        }
        return handled;
    }

    /** {@inheritDoc} */
    public override bool key_release_event(Gdk.EventKey event) {
        check_shift_event(event);
        return base.key_release_event(event);
    }

    public void folder_selected(Geary.Folder? folder,
                                GLib.Cancellable? cancellable) {
        if (this.current_folder != null) {
            this.progress_monitor.remove(this.current_folder.opening_monitor);
            this.current_folder.properties.notify.disconnect(update_headerbar);
            close_conversation_monitor();
        }

        this.current_folder = folder;

        if (folder != null) {
            this.progress_monitor.add(folder.opening_monitor);
            folder.properties.notify.connect(update_headerbar);
            open_conversation_monitor.begin(cancellable);
        }

        update_headerbar();
    }

    private void update_command_actions() {
        get_action(GearyApplication.ACTION_UNDO).set_enabled(
            this.commands.can_undo
        );
        get_action(GearyApplication.ACTION_REDO).set_enabled(
            this.commands.can_redo
        );
    }

    private inline void handle_error(Geary.AccountInformation? account,
                                     GLib.Error error) {
        Geary.ProblemReport? report = (account != null)
            ? new Geary.AccountProblemReport(account, error)
            : new Geary.ProblemReport(error);
        this.application.controller.report_problem(report);
    }

    private void update_ui() {
        // Only update if we haven't done so within the last while
        int64 now = GLib.get_monotonic_time() / (1000 * 1000);
        if (this.update_ui_last + UPDATE_UI_INTERVAL < now) {
            this.update_ui_last = now;

            if (this.conversation_viewer.current_list != null) {
                this.conversation_viewer.current_list.update_display();
            }

            ConversationListStore? list_store =
                this.conversation_list_view.get_model() as ConversationListStore;
            if (list_store != null) {
                list_store.update_display();
            }
        }
    }

    private async void open_conversation_monitor(GLib.Cancellable cancellable) {
        this.conversations = new Geary.App.ConversationMonitor(
            this.current_folder,
            Geary.Folder.OpenFlags.NO_DELAY,
            // Include fields for the conversation viewer as well so
            // conversations can be displayed without having to go
            // back to the db
            ConversationListStore.REQUIRED_FIELDS |
            ConversationListBox.REQUIRED_FIELDS |
            ConversationEmail.REQUIRED_FOR_CONSTRUCT,
            MIN_CONVERSATION_COUNT
        );

        this.conversations.scan_completed.connect(on_scan_completed);
        this.conversations.scan_error.connect(on_scan_error);

        this.conversations.scan_completed.connect(
            on_conversation_count_changed
        );
        this.conversations.conversations_added.connect(
            on_conversation_count_changed
        );
        this.conversations.conversations_removed.connect(
            on_conversation_count_changed
        );

        ConversationListStore new_model = new ConversationListStore(
            this.conversations
        );
        this.progress_monitor.add(new_model.preview_monitor);
        this.progress_monitor.add(conversations.progress_monitor);
        this.conversation_list_view.set_model(new_model);

        // Work on a local copy since the main window's copy may
        // change if a folder is selected while closing.
        Geary.App.ConversationMonitor conversations = this.conversations;
        conversations.start_monitoring_async.begin(
            cancellable,
            (obj, res) => {
                try {
                    conversations.start_monitoring_async.end(res);
                } catch (Error err) {
                    Geary.AccountInformation account =
                        conversations.base_folder.account.information;
                    this.application.controller.report_problem(
                        new Geary.ServiceProblemReport(account, account.incoming, err)
                    );
                }
            }
        );
    }

    private void close_conversation_monitor() {
        ConversationListStore? old_model =
            this.conversation_list_view.get_model();
        if (old_model != null) {
            this.progress_monitor.remove(old_model.preview_monitor);
            this.progress_monitor.remove(old_model.conversations.progress_monitor);
        }

        this.conversations.scan_completed.disconnect(on_scan_completed);
        this.conversations.scan_error.disconnect(on_scan_error);

        this.conversations.scan_completed.disconnect(
            on_conversation_count_changed
        );
        this.conversations.conversations_added.disconnect(
            on_conversation_count_changed
        );
        this.conversations.conversations_removed.disconnect(
            on_conversation_count_changed
        );

        // Work on a local copy since the main window's copy may
        // change if a folder is selected while closing.
        Geary.App.ConversationMonitor conversations = this.conversations;
        conversations.stop_monitoring_async.begin(
            null,
            (obj, res) => {
                try {
                    conversations.stop_monitoring_async.end(res);
                } catch (Error err) {
                    warning(
                        "Error closing conversation monitor %s: %s",
                        this.conversations.base_folder.to_string(),
                        err.message
                    );
                }
            }
        );

        this.conversations = null;
    }

    private void create_composer_from_viewer(ComposerWidget.ComposeType compose_type) {
        ConversationEmail? email_view = null;
        ConversationListBox? list_view = this.conversation_viewer.current_list;
        if (list_view != null) {
            email_view = list_view.get_reply_target();
        }
        if (email_view != null) {
            email_view.get_selection_for_quoting.begin((obj, res) => {
                    string? quote = email_view.get_selection_for_quoting.end(res);
                    this.application.controller.compose_with_context_email(
                        compose_type, email_view.email, quote
                    );
                });
        }
    }

    private void load_more() {
        if (this.conversations != null) {
            this.conversations.min_window_count += MIN_CONVERSATION_COUNT;
        }
    }

    private void on_conversation_count_changed() {
        // Only update the UI if we don't currently have a composer,
        // so we don't clobber it
        if (!this.has_composer) {
            if (this.conversations.size == 0) {
                // Let the user know if there's no available conversations
                if (this.current_folder is Geary.SearchFolder) {
                    this.conversation_viewer.show_empty_search();
                } else {
                    this.conversation_viewer.show_empty_folder();
                }
                this.application.controller.enable_message_buttons(false);
            } else {
                // When not doing autoselect, we never get
                // conversations_selected firing from the convo list,
                // so we need to stop the loading spinner here.
                if (!this.application.config.autoselect &&
                    this.conversation_list_view.get_selection().count_selected_rows() == 0) {
                    this.conversation_viewer.show_none_selected();
                    this.application.controller.enable_message_buttons(false);
                }
            }
        }
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

    private void update_headerbar() {
        if (this.current_folder == null) {
            this.main_toolbar.account = null;
            this.main_toolbar.folder = null;

            return;
        }

        this.main_toolbar.account =
            this.current_folder.account.information.display_name;

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

    private void update_infobar_frame() {
        // Ensure the info bar frame is shown only when it has visible
        // children
        bool show_frame = false;
        this.info_bar_container.foreach((child) => {
                if (child.visible) {
                    show_frame = true;
                }
            });
        this.info_bar_frame.set_visible(show_frame);
    }

    private inline void check_shift_event(Gdk.EventKey event) {
        // FIXME: it's possible the user will press two shift keys.  We want
        // the shift key to report as released when they release ALL of them.
        // There doesn't seem to be an easy way to do this in Gdk.
        if (event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R) {
            Gtk.Widget? focus = get_focus();
            if (focus == null ||
                (!(focus is Gtk.Entry) && !(focus is ComposerWebView))) {
                this.is_shift_down = (event.type == Gdk.EventType.KEY_PRESS);
                this.main_toolbar.update_trash_button(
                    !this.is_shift_down &&
                    current_folder_supports_trash()
                );
                on_shift_key(this.is_shift_down);
            }
        }
    }

    private SimpleAction get_action(string name) {
        return (SimpleAction) lookup_action(name);
    }

    private bool current_folder_supports_trash() {
        Geary.Folder? current = this.current_folder;
        return (
            current != null &&
            current.special_folder_type != TRASH &&
            !current_folder.properties.is_local_only &&
            (current_folder as Geary.FolderSupport.Move) != null
        );
    }

    private void on_scan_completed(Geary.App.ConversationMonitor monitor) {
        // Done scanning.  Check if we have enough messages to fill
        // the conversation list; if not, trigger a load_more();
        if (is_visible() &&
            !conversation_list_has_scrollbar() &&
            monitor == this.conversations &&
            monitor.can_load_more) {
            debug("Not enough messages, loading more for folder %s",
                  this.current_folder.to_string());
            load_more();
        }
    }

    private void on_scan_error(Geary.App.ConversationMonitor monitor,
                               GLib.Error err) {
        Geary.AccountInformation account =
            monitor.base_folder.account.information;
        this.application.controller.report_problem(
            new Geary.ServiceProblemReport(account, account.incoming, err)
        );
    }

    private void on_load_more() {
        load_more();
    }

    [GtkCallback]
    private void on_map() {
        this.update_ui_timeout.start();
        update_ui();
    }

    [GtkCallback]
    private void on_unmap() {
        this.update_ui_timeout.reset();
    }

    [GtkCallback]
    private bool on_focus_event() {
        on_shift_key(false);
        return false;
    }

    [GtkCallback]
    private bool on_delete_event() {
        if (this.application.config.startup_notifications) {
            if (this.application.controller.close_composition_windows(true)) {
                hide();
            }
        } else {
            this.application.exit();
        }
        return Gdk.EVENT_STOP;
    }

    [GtkCallback]
    private void on_offline_infobar_response() {
        this.offline_infobar.hide();
        update_infobar_frame();
    }

    private void on_service_problem_retry() {
        this.service_problem_infobar = null;
        retry_service_problem(Geary.ClientService.Status.CONNECTION_FAILED);
    }

    [GtkCallback]
    private void on_cert_problem_retry() {
        this.cert_problem_infobar.hide();
        update_infobar_frame();
        retry_service_problem(Geary.ClientService.Status.TLS_VALIDATION_FAILED);
    }

    [GtkCallback]
    private void on_auth_problem_retry() {
        this.auth_problem_infobar.hide();
        update_infobar_frame();
        retry_service_problem(Geary.ClientService.Status.AUTHENTICATION_FAILED);
    }

    [GtkCallback]
    private void on_info_bar_container_remove() {
        update_infobar_frame();
    }

    private void on_update_ui_timeout() {
        update_ui();
    }

    private void on_command_execute(Application.Command command) {
        if (command.executed_label != null) {
            Components.InAppNotification ian =
                new Components.InAppNotification(command.executed_label);
            ian.set_button(_("Undo"), "win." + GearyApplication.ACTION_UNDO);
            add_notification(ian);
        }
        update_command_actions();
    }

    private void on_command_undo(Application.Command command) {
        if (command.undone_label != null) {
            Components.InAppNotification ian =
                new Components.InAppNotification(command.undone_label);
            ian.set_button(_("Redo"), "win." + GearyApplication.ACTION_REDO);
            add_notification(ian);
        }
        update_command_actions();
    }

    private void on_conversation_view_added(ConversationListBox list) {
        list.email_added.connect(on_conversation_viewer_email_added);
        list.mark_emails.connect(on_conversation_viewer_mark_emails);
    }

    private void on_conversation_viewer_email_added(ConversationEmail view) {
        view.load_error.connect(on_email_load_error);

        view.forward_message.connect(on_forward_message);
        view.reply_all_message.connect(on_reply_all_message);
        view.reply_to_message.connect(on_reply_to_message);
        view.edit_draft.connect(on_edit_draft);

        view.attachments_activated.connect(on_attachments_activated);
        view.save_attachments.connect(on_save_attachments);
        view.view_source.connect(on_view_source);

        Geary.App.Conversation conversation = this.conversation_viewer.current_list.conversation;
        bool in_current_folder = (
            conversation.is_in_base_folder(view.email.id) &&
            conversation.base_folder == current_folder
        );
        bool supports_trash = in_current_folder && current_folder_supports_trash();
        bool supports_delete = in_current_folder && current_folder is Geary.FolderSupport.Remove;
        view.trash_message.connect(on_trash_message);
        view.delete_message.connect(on_delete_message);
        view.set_folder_actions_enabled(supports_trash, supports_delete);
        this.on_shift_key.connect(view.shift_key_changed);

        foreach (ConversationMessage msg_view in view) {
            msg_view.link_activated.connect(on_link_activated);
            msg_view.save_image.connect((url, alt_text, buf) => {
                    on_save_image_extended(view, url, alt_text, buf);
                });
        }
    }

    // Window-level action callbacks

    private void on_undo() {
        this.application.controller.undo.begin();
    }

    private void on_redo() {
        this.application.controller.redo.begin();
    }

    private void on_close() {
        close();
    }

    private void on_conversation_list() {
        this.conversation_list_view.grab_focus();
    }

    private void on_find_in_conversation_action() {
        this.conversation_viewer.enable_find();
    }

    private void on_search_activated() {
        show_search_bar();
    }

    private void on_zoom(SimpleAction action, Variant? parameter) {
        ConversationListBox? view = this.conversation_viewer.current_list;
        if (view != null && parameter != null) {
            string zoom_action = parameter.get_string();
            if (zoom_action == "in")
                view.zoom_in();
            else if (zoom_action == "out")
                view.zoom_out();
            else
                view.zoom_reset();
        }
    }

    private void on_reply_conversation() {
        create_composer_from_viewer(REPLY);
    }

    private void on_reply_all_conversation() {
        create_composer_from_viewer(REPLY_ALL);
    }

    private void on_forward_conversation() {
        create_composer_from_viewer(FORWARD);
    }

    private void on_show_copy_menu() {
        this.main_toolbar.copy_message_button.clicked();
    }

    private void on_show_move_menu() {
        this.main_toolbar.move_message_button.clicked();
    }

    private void on_conversation_up() {
        this.conversation_list_view.scroll(Gtk.ScrollType.STEP_UP);
    }

    private void on_conversation_down() {
        this.conversation_list_view.scroll(Gtk.ScrollType.STEP_DOWN);
    }

    private void on_show_mark_menu() {
        bool unread_selected = false;
        bool read_selected = false;
        bool starred_selected = false;
        bool unstarred_selected = false;
        foreach (Geary.App.Conversation conversation in
                 this.conversation_list_view.get_selected_conversations()) {
            if (conversation.is_unread())
                unread_selected = true;

            // Only check the messages that "Mark as Unread" would mark, so we
            // don't add the menu option and have it not do anything.
            //
            // Sort by Date: field to correspond with ConversationViewer ordering
            Geary.Email? latest = conversation.get_latest_sent_email(
                Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
            if (latest != null && latest.email_flags != null
                && !latest.email_flags.contains(Geary.EmailFlags.UNREAD))
                read_selected = true;

            if (conversation.is_flagged()) {
                starred_selected = true;
            } else {
                unstarred_selected = true;
            }
        }
        get_action(ACTION_MARK_AS_READ).set_enabled(unread_selected);
        get_action(ACTION_MARK_AS_UNREAD).set_enabled(read_selected);
        get_action(ACTION_MARK_AS_STARRED).set_enabled(unstarred_selected);
        get_action(ACTION_MARK_AS_UNSTARRED).set_enabled(starred_selected);

        // If we're in Drafts/Outbox, we also shouldn't set a message as SPAM.
        bool in_spam_folder = current_folder.special_folder_type == Geary.SpecialFolderType.SPAM;
        get_action(ACTION_TOGGLE_SPAM).set_enabled(!in_spam_folder &&
            current_folder.special_folder_type != Geary.SpecialFolderType.DRAFTS &&
            current_folder.special_folder_type != Geary.SpecialFolderType.OUTBOX);
    }

    private void on_mark_as_read() {
    }

    private void on_mark_as_unread() {
    }

    private void on_mark_as_starred() {
    }

    private void on_mark_as_unstarred() {
    }

    private void on_mark_as_spam_toggle() {
    }

    private void on_move_conversation(Geary.Folder destination) {
    }

    private void on_copy_conversation(Geary.Folder destination) {
    }

    private void on_archive_conversation() {
    }

    private void on_trash_conversation() {
    }

    private void on_delete_conversation() {
    }

    private void on_empty_spam() {
    }

    private void on_empty_trash() {
    // Individual message view action callbacks

    private void on_conversation_viewer_mark_emails(Gee.Collection<Geary.EmailIdentifier> email,
                                                    Geary.EmailFlags? to_add,
                                                    Geary.EmailFlags? to_remove) {
    }

    private void on_email_load_error(ConversationEmail view, GLib.Error err) {
        handle_error(
            this.current_account != null ? this.current_account.information : null,
            err
        );
    }

    private void on_reply_to_message(ConversationEmail target_view) {
        target_view.get_selection_for_quoting.begin((obj, res) => {
                string? quote = target_view.get_selection_for_quoting.end(res);
                this.application.controller.compose_with_context_email(
                    REPLY, target_view.email, quote
                );
            });
    }

    private void on_reply_all_message(ConversationEmail target_view) {
        target_view.get_selection_for_quoting.begin((obj, res) => {
                string? quote = target_view.get_selection_for_quoting.end(res);
                this.application.controller.compose_with_context_email(
                    REPLY_ALL, target_view.email, quote
                );
            });
    }

    private void on_forward_message(ConversationEmail target_view) {
        target_view.get_selection_for_quoting.begin((obj, res) => {
                string? quote = target_view.get_selection_for_quoting.end(res);
                this.application.controller.compose_with_context_email(
                    FORWARD, target_view.email, quote
                );
            });
    }

    private void on_edit_draft(ConversationEmail target_view) {
        this.application.controller.compose_with_context_email(
            NEW_MESSAGE, target_view.email, null
        );
    }

    private void on_attachments_activated(Gee.Collection<Geary.Attachment> attachments) {
        if (this.application.config.ask_open_attachment) {
            QuestionDialog ask_to_open = new QuestionDialog.with_checkbox(
                this,
                _("Are you sure you want to open these attachments?"),
                _("Attachments may cause damage to your system if opened.  Only open files from trusted sources."),
                Stock._OPEN_BUTTON, Stock._CANCEL, _("Don’t _ask me again"), false);
            if (ask_to_open.run() != Gtk.ResponseType.OK) {
                return;
            }
            // only save checkbox state if OK was selected
            this.application.config.ask_open_attachment = !ask_to_open.is_checked;
        }

        foreach (Geary.Attachment attachment in attachments) {
            string uri = attachment.file.get_uri();
            try {
                this.application.show_uri(uri);
            } catch (Error err) {
                message("Unable to open attachment \"%s\": %s", uri, err.message);
            }
        }
    }

    private void on_save_attachments(Gee.Collection<Geary.Attachment> attachments) {
        if (this.current_account != null) {
            if (attachments.size == 1) {
                this.application.controller.save_attachment_to_file.begin(
                    this.current_account,
                    attachments.to_array()[0],
                    null
                );
            } else {
                this.application.controller.save_attachments_to_file.begin(
                    this.current_account,
                    attachments
                );
            }
        }
    }

    private void on_view_source(ConversationEmail email_view) {
        string source = (email_view.email.header.buffer.to_string() +
                         email_view.email.body.buffer.to_string());
        string temporary_filename;
        try {
            int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
                                                      out temporary_filename);
            FileUtils.set_contents(temporary_filename, source);
            FileUtils.close(temporary_handle);

            // ensure this file is only readable by the user ... this
            // needs to be done after the file is closed
            FileUtils.chmod(temporary_filename, (int) (Posix.S_IRUSR | Posix.S_IWUSR));

            string temporary_uri = Filename.to_uri(temporary_filename, null);
            this.application.show_uri(temporary_uri);
        } catch (Error error) {
            ErrorDialog dialog = new ErrorDialog(
                this,
                _("Failed to open default text editor."),
                error.message
            );
            dialog.run();
        }
    }

    private void on_save_image_extended(ConversationEmail view,
                                        string url,
                                        string? alt_text,
                                        Geary.Memory.Buffer resource_buf) {
        if (this.current_account != null) {
            this.application.controller.save_image_extended.begin(
                this.current_account, view, url, alt_text, resource_buf
            );
        }
    }

    private void on_trash_message(ConversationEmail target_view) {
    }

    private void on_delete_message(ConversationEmail target_view) {
    }

    private void on_link_activated(string uri) {
        try {
            if (uri.down().has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                this.application.controller.compose(uri);
            } else {
                this.application.show_uri(uri);
            }
        } catch (GLib.Error err) {
            handle_error(
                this.current_account != null ? this.current_account.information : null,
                err
            );
        }
    }

}
