/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2016, 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/application-main-window.ui")]
public class Application.MainWindow :
    Gtk.ApplicationWindow, Geary.BaseInterface {


    // Named actions.
    public const string ACTION_ARCHIVE_CONVERSATION = "archive-conversation";
    public const string ACTION_CONVERSATION_DOWN = "down-conversation";
    public const string ACTION_CONVERSATION_UP = "up-conversation";
    public const string ACTION_DELETE_CONVERSATION = "delete-conversation";
    public const string ACTION_FIND_IN_CONVERSATION = "find-in-conversation";
    public const string ACTION_FORWARD_CONVERSATION = "forward-conversation";
    public const string ACTION_MARK_AS_READ = "mark-conversation-read";
    public const string ACTION_MARK_AS_STARRED = "mark-conversation-starred";
    public const string ACTION_MARK_AS_UNREAD = "mark-conversation-unread";
    public const string ACTION_MARK_AS_UNSTARRED = "mark-conversation-unstarred";
    public const string ACTION_REPLY_ALL_CONVERSATION = "reply-all-conversation";
    public const string ACTION_REPLY_CONVERSATION = "reply-conversation";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SHOW_COPY_MENU = "show-copy-menu";
    public const string ACTION_SHOW_MARK_MENU = "show-mark-menu";
    public const string ACTION_SHOW_MOVE_MENU = "show-move-menu";
    public const string ACTION_TOGGLE_JUNK = "toggle-conversation-junk";
    public const string ACTION_TRASH_CONVERSATION = "trash-conversation";
    public const string ACTION_ZOOM = "zoom";

    private const ActionEntry[] EDIT_ACTIONS = {
        { Action.Edit.UNDO, on_undo },
        { Action.Edit.REDO, on_redo },
    };

    private const ActionEntry[] WINDOW_ACTIONS = {
        { Action.Window.CLOSE, on_close },

        { ACTION_FIND_IN_CONVERSATION, on_find_in_conversation_action },
        { ACTION_SEARCH, on_search_activated },
        // Message actions
        { ACTION_REPLY_CONVERSATION, on_reply_conversation },
        { ACTION_REPLY_ALL_CONVERSATION, on_reply_all_conversation },
        { ACTION_FORWARD_CONVERSATION, on_forward_conversation },
        { ACTION_ARCHIVE_CONVERSATION, on_archive_conversation },
        { ACTION_TRASH_CONVERSATION, on_trash_conversation },
        { ACTION_DELETE_CONVERSATION, on_delete_conversation },
        { ACTION_SHOW_COPY_MENU, on_show_copy_menu },
        { ACTION_SHOW_MOVE_MENU, on_show_move_menu },
        { ACTION_CONVERSATION_UP, on_conversation_up },
        { ACTION_CONVERSATION_DOWN, on_conversation_down },
        // Message marking actions
        { ACTION_SHOW_MARK_MENU, on_show_mark_menu },
        { ACTION_MARK_AS_READ, on_mark_as_read },
        { ACTION_MARK_AS_UNREAD, on_mark_as_unread },
        { ACTION_MARK_AS_STARRED, on_mark_as_starred },
        { ACTION_MARK_AS_UNSTARRED, on_mark_as_unstarred },
        { ACTION_TOGGLE_JUNK, on_mark_as_junk_toggle },
        // Message viewer
        { ACTION_ZOOM, on_zoom, "s" },
    };

    private const int STATUS_BAR_HEIGHT = 18;
    private const int UPDATE_UI_INTERVAL = 60;
    private const int MIN_CONVERSATION_COUNT = 50;


    static construct {
        // Set up default keybindings
        unowned Gtk.BindingSet bindings = Gtk.BindingSet.by_class(
            (ObjectClass) typeof(MainWindow).class_ref()
        );

        //
        // Replying & forwarding
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.R, CONTROL_MASK,
            "reply-conversation-sender", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.R, CONTROL_MASK | SHIFT_MASK,
            "reply-conversation-all", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.L, CONTROL_MASK,
            "forward-conversation", 0
        );

        // Marking actions
        //
        // Unread is the primary action, so it doesn't get the <Shift>
        // modifier
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.U, CONTROL_MASK,
            "mark-conversations-read", 1, typeof(bool), true
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.U, CONTROL_MASK | SHIFT_MASK,
            "mark-conversations-read", 1, typeof(bool), false
        );
        // Ephy uses Ctrl+D for bookmarking
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.D, CONTROL_MASK,
            "mark-conversations-starred", 1, typeof(bool), true
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.D, CONTROL_MASK | SHIFT_MASK,
            "mark-conversations-starred", 1, typeof(bool), false
        );

        //
        // Moving & labelling
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.B, CONTROL_MASK,
            "show-copy-menu", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.M, CONTROL_MASK,
            "show-move-menu", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.K, CONTROL_MASK,
            "archive-conversations", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.J, CONTROL_MASK,
            "junk-conversations", 0
        );
        // Many ways to trash
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.BackSpace, 0,
            "trash-conversations", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.Delete, 0,
            "trash-conversations", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.KP_Delete, 0,
            "trash-conversations", 0
        );
        // Many ways to delete
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.BackSpace, SHIFT_MASK,
            "delete-conversations", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.Delete, SHIFT_MASK,
            "delete-conversations", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.KP_Delete, SHIFT_MASK,
            "delete-conversations", 0
        );

        //
        // Find & search
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.F, CONTROL_MASK,
            "find", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.S, CONTROL_MASK,
            "search", 0
        );

        //
        // Navigation
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.Left, MOD1_MASK,
            "navigate", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.PAGE_LEFT
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.Right, MOD1_MASK,
            "navigate", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.PAGE_RIGHT
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.comma, CONTROL_MASK,
            "navigate", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.STEP_UP
        );
        Gtk.BindingEntry.add_signal(
            bindings,
            Gdk.Key.period, CONTROL_MASK,
            "navigate", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.STEP_DOWN
        );
    }


    public static void add_accelerators(Client owner) {
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
    }


    private enum ConversationCount { NONE, SINGLE, MULTIPLE; }


    /** Returns the window's associated client application instance. */
    public new Client application {
        get { return (Client) base.get_application(); }
        set { base.set_application(value); }
    }

    /** Currently selected account, null if none selected */
    public Geary.Account? selected_account { get; private set; default = null; }

    /** Currently selected folder, null if none selected */
    public Geary.Folder? selected_folder { get; private set; default = null; }

    /** Conversations for the current folder, null if none selected */
    public Geary.App.ConversationMonitor? conversations {
        get; private set; default = null;
    }

    /** The attachment manager for this window. */
    public AttachmentManager attachments { get; private set; }

    /** Determines if conversations in the selected folder can be trashed. */
    public bool selected_folder_supports_trash {
        get {
            return Controller.does_folder_support_trash(this.selected_folder);
        }
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
    public SearchBar search_bar { get; private set; }
    public ConversationListView conversation_list_view  { get; private set; }
    public ConversationViewer conversation_viewer { get; private set; }

    public Components.InfoBarStack conversation_list_info_bars {
        get; private set; default = new Components.InfoBarStack(PRIORITY_QUEUE);
    }

    public StatusBar status_bar { get; private set; default = new StatusBar(); }

    private Controller controller;

    private MonitoredSpinner spinner = new MonitoredSpinner();

    private Gee.Set<AccountContext> accounts = new Gee.HashSet<AccountContext>();

    private GLib.SimpleActionGroup edit_actions = new GLib.SimpleActionGroup();

    // Determines if the conversation viewer should auto-mark messages
    // on next load
    private bool previous_selection_was_interactive = false;

    // Caches the last non-search folder so it can be re-selected on
    // the search folder closing
    private Geary.Folder? previous_non_search_folder = null;

    private Geary.AggregateProgressMonitor progress_monitor = new Geary.AggregateProgressMonitor();

    private GLib.Cancellable action_update_cancellable = new GLib.Cancellable();
    private GLib.Cancellable folder_open = new GLib.Cancellable();
    private GLib.Cancellable search_open = new GLib.Cancellable();

    private Geary.TimeoutManager update_ui_timeout;
    private int64 update_ui_last = 0;


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
    private Gtk.Box conversation_list_box;
    [GtkChild]
    private Gtk.ScrolledWindow conversation_list_scrolled;
    [GtkChild]
    private Gtk.Overlay overlay;

    private Components.InfoBarStack info_bars =
        new Components.InfoBarStack(SINGLE);

    private Components.InfoBar offline_infobar;

    private Components.InfoBar cert_problem_infobar;

    private Components.InfoBar auth_problem_infobar;

    private Components.ProblemReportInfoBar? service_problem_infobar = null;

    /** Fired when the user requests an account status be retried. */
    public signal void retry_service_problem(Geary.ClientService.Status problem);


    /** Keybinding signal for replying to sender for the current conversation. */
    [Signal (action=true)]
    public virtual signal void reply_conversation_sender() {
        activate_action(get_window_action(ACTION_REPLY_CONVERSATION));
    }

    /** Keybinding signal for replying to all for the current conversation. */
    [Signal (action=true)]
    public virtual signal void reply_conversation_all() {
        activate_action(get_window_action(ACTION_REPLY_ALL_CONVERSATION));
    }

    /** Keybinding signal for forwarding the current conversation. */
    [Signal (action=true)]
    public virtual signal void forward_conversation() {
        activate_action(get_window_action(ACTION_FORWARD_CONVERSATION));
    }

    /** Keybinding signal for marking the current selection read. */
    [Signal (action=true)]
    public virtual signal void mark_conversations_read(bool prefer_read) {
        activate_action(
            prefer_read
            ? get_window_action(ACTION_MARK_AS_READ)
            : get_window_action(ACTION_MARK_AS_UNREAD)
        );
    }

    /** Keybinding signal for marking the current selection starred. */
    [Signal (action=true)]
    public virtual signal void mark_conversations_starred(bool prefer_starred) {
        activate_action(
            prefer_starred
            ? get_window_action(ACTION_MARK_AS_STARRED)
            : get_window_action(ACTION_MARK_AS_UNSTARRED)
        );
    }

    /** Keybinding signal for showing the copy/label menu. */
    [Signal (action=true)]
    public virtual signal void show_copy_menu() {
        activate_action(get_window_action(ACTION_SHOW_COPY_MENU));
    }

    /** Keybinding signal for showing the move menu. */
    [Signal (action=true)]
    public virtual signal void show_move_menu() {
        activate_action(get_window_action(ACTION_SHOW_MOVE_MENU));
    }

    /** Keybinding signal for archiving the current selection. */
    [Signal (action=true)]
    public virtual signal void archive_conversations() {
        activate_action(get_window_action(ACTION_ARCHIVE_CONVERSATION));
    }

    /** Keybinding signal for junking the current selection. */
    [Signal (action=true)]
    public virtual signal void junk_conversations() {
        activate_action(get_window_action(ACTION_TOGGLE_JUNK));
    }

    /** Keybinding signal for trashing the current selection. */
    [Signal (action=true)]
    public virtual signal void trash_conversations() {
        // XXX the Shift+BackSpace combo above doesn't seem to work
        // for delete, so double-check here.
        activate_action(
            !this.is_shift_down
            ? get_window_action(ACTION_TRASH_CONVERSATION)
            : get_window_action(ACTION_DELETE_CONVERSATION)
        );
    }

    /** Keybinding signal for deleting the current selection. */
    [Signal (action=true)]
    public virtual signal void delete_conversations() {
        activate_action(get_window_action(ACTION_DELETE_CONVERSATION));
    }

    /** Keybinding signal for activating conversation search. */
    [Signal (action=true)]
    public virtual signal void search() {
        activate_action(get_window_action(ACTION_SEARCH));
    }

    /** Keybinding signal for activating in-conversation find. */
    [Signal (action=true)]
    public virtual signal void find() {
        activate_action(get_window_action(ACTION_FIND_IN_CONVERSATION));
    }

    /** Keybinding signal for shifting the keyboard focus. */
    [Signal (action=true)]
    public virtual signal void navigate(Gtk.ScrollType type) {
        switch (type) {
        case Gtk.ScrollType.PAGE_LEFT:
            if (get_direction() != RTL) {
                focus_previous_pane();
            } else {
                focus_next_pane();
            }
            break;
        case Gtk.ScrollType.PAGE_RIGHT:
            if (get_direction() != RTL) {
                focus_next_pane();
            } else {
                focus_previous_pane();
            }
            break;
        case Gtk.ScrollType.STEP_UP:
            activate_action(get_window_action(ACTION_CONVERSATION_UP));
            break;
        case Gtk.ScrollType.STEP_DOWN:
            activate_action(get_window_action(ACTION_CONVERSATION_DOWN));
            break;
        default:
            this.get_window().beep();
            break;
        }
    }


    internal MainWindow(Client application) {
        Object(
            application: application,
            show_menubar: false
        );
        base_ref();

        // Keep a ref on the current controller so that even if the
        // application has been shut down, any async tasks that are
        // running (and presumably being cancelled) can still complete
        // without a warning.
        this.controller = application.controller;

        load_config(application.config);
        restore_saved_window_state();

        if (_PROFILE != "") {
            this.get_style_context().add_class("devel");
        }

        this.info_bars.shadow_type = IN;
        this.conversation_list_info_bars.shadow_type = IN;

        // Edit actions
        this.edit_actions.add_action_entries(EDIT_ACTIONS, this);
        insert_action_group(Action.Edit.GROUP_NAME, this.edit_actions);

        // Window actions
        add_action_entries(MainWindow.WINDOW_ACTIONS, this);

        this.focus_in_event.connect((w, e) => {
            application.controller.window_focus_in();
            return false;
        });
        this.focus_out_event.connect((w, e) => {
            application.controller.window_focus_out();
            return false;
        });

        setup_layout(application.config);
        on_change_orientation();

        update_command_actions();
        update_conversation_actions(NONE);

        this.attachments = new AttachmentManager(this);

        this.update_ui_timeout = new Geary.TimeoutManager.seconds(
            UPDATE_UI_INTERVAL, on_update_ui_timeout
        );
        this.update_ui_timeout.repetition = FOREVER;

        // Add future and existing accounts to the main window
        this.controller.account_available.connect(
            on_account_available
        );
        this.controller.account_unavailable.connect(
            on_account_unavailable
        );
        foreach (AccountContext context in
                 this.controller.get_account_contexts()) {
            add_account(context);
        }

        this.offline_infobar = new Components.InfoBar(
            // Translators: An info bar status label
            _("Working offline"),
            // Translators: An info bar description label
            _("You will not be able to send or receive email until re-connected.")
        );
        this.offline_infobar.show_close_button = true;
        this.offline_infobar.response.connect(on_offline_infobar_response);

        this.auth_problem_infobar = new Components.InfoBar(
            // Translators: An info bar status label
            _("Login problem"),
            // Translators: An info bar description label
            _("An account has reported an incorrect login or password.")
        );
        // Translators: An info bar button label
        var auth_retry = new Gtk.Button.with_label(_("Login"));
        auth_retry.show();
        // Translators: An info bar button tool-tip
        auth_retry.tooltip_text = _(
            "Retry login, you will be prompted for your password"
        );
        auth_retry.clicked.connect(on_auth_problem_retry);
        this.auth_problem_infobar.get_action_area().add(auth_retry);

        this.cert_problem_infobar = new Components.InfoBar(
            // Translators: An info bar status label
            _("Security problem"),
            // Translators: An info bar description label
            _("An account has reported an untrusted server.")
        );
        // Translators: An info bar button label
        var cert_retry = new Gtk.Button.with_label(_("Check"));
        cert_retry.show();
        // Translators: An info bar button tool-tip
        cert_retry.tooltip_text = _(
            "Check the security details for the connection"
        );
        cert_retry.clicked.connect(on_cert_problem_retry);
        this.cert_problem_infobar.get_action_area().add(cert_retry);

        this.conversation_list_view.grab_focus();
    }

    ~MainWindow() {
        base_unref();
    }

    /** {@inheritDoc} */
    public override void destroy() {
        if (this.application != null) {
            this.controller.account_available.disconnect(
                on_account_available
            );
            this.controller.account_unavailable.disconnect(
                on_account_unavailable
            );
        }
        this.update_ui_timeout.reset();
        base.destroy();
    }

    /** Updates the window's title and headerbar titles. */
    public void update_title() {
        AccountContext? account = get_selected_account_context();
        FolderContext? folder = (
            account != null && this.selected_folder != null
            ? account.get_folder(this.selected_folder)
            : null
        );
        string title = _("Geary");
        string? account_name = null;
        string? folder_name = null;
        if (account != null && folder != null) {
            account_name = account.account.information.display_name;
            folder_name = folder.display_name;
            /// Translators: Main window title, first string
            /// substitution being the currently selected folder name,
            /// the second being the selected account name.
            title = _("%s — %s").printf(folder_name, account_name);
        }
        this.title = title;
        this.main_toolbar.account = account_name ?? "";
        this.main_toolbar.folder = folder_name?? "";
    }

    /** Updates the window's account status info bars. */
    public void update_account_status(Geary.Account.Status status,
                                      bool has_auth_error,
                                      bool has_cert_error,
                                      Geary.Account? problem_source) {
        // Only ever show one info bar at a time. Offline is primary
        // since nothing else can happen when offline. Service
        // problems are secondary since auth and cert problems can't
        // be resolved when the service isn't talking to the
        // server. Cert problems are tertiary since you can't auth if
        // you can't connect.
        if (!status.is_online()) {
            this.info_bars.add(this.offline_infobar);
        } else if (status.has_service_problem()) {
            Geary.ClientService? service = (
                problem_source.incoming.last_error != null
                ? problem_source.incoming
                : problem_source.outgoing
            );
            this.service_problem_infobar = new Components.ProblemReportInfoBar(
                new Geary.ServiceProblemReport(
                    problem_source.information,
                    service.configuration,
                    service.last_error.thrown
                )
            );
            this.service_problem_infobar.retry.connect(on_service_problem_retry);
            this.info_bars.add(this.service_problem_infobar);
        } else if (has_cert_error) {
            this.info_bars.add(this.cert_problem_infobar);
        } else if (has_auth_error) {
            this.info_bars.add(this.auth_problem_infobar);
        } else {
            this.info_bars.remove_all();
        }
    }

    /**
     * Selects and open the given folder.
     *
     * If is_interactive is true, the selection is treated as being
     * caused directly by human request (e.g. clicking on a folder in
     * the folder list), as opposed to some side effect.
     */
    public async void select_folder(Geary.Folder? to_select,
                                    bool is_interactive,
                                    bool inhibit_autoselect = false) {
        if (this.selected_folder != to_select) {
            // Cancel any existing folder loading
            this.folder_open.cancel();
            var cancellable = this.folder_open = new GLib.Cancellable();

            // Dispose of all existing objects for the currently
            // selected model.

            if (this.selected_folder != null) {
                this.main_toolbar.copy_folder_menu.enable_disable_folder(
                    this.selected_folder, true
                );
                this.main_toolbar.move_folder_menu.enable_disable_folder(
                    this.selected_folder, true
                );

                this.progress_monitor.remove(this.selected_folder.opening_monitor);
                this.selected_folder.properties.notify.disconnect(update_headerbar);
                this.selected_folder = null;
            }
            if (this.conversations != null) {
                this.progress_monitor.remove(this.conversations.progress_monitor);
                close_conversation_monitor(this.conversations);
                this.conversations = null;
            }
            var conversations_model = this.conversation_list_view.get_model();
            if (conversations_model != null) {
                this.progress_monitor.remove(conversations_model.preview_monitor);
                this.conversation_list_view.set_model(null);
            }

            this.conversation_list_info_bars.remove_all();

            // With everything disposed of, update existing window
            // state

            select_account(to_select != null ? to_select.account : null);
            this.selected_folder = to_select;

            // Ensure that the folder is selected in the UI if
            // this was called by something other than the
            // selection changed callback. That will check to
            // ensure that we're not setting it again.
            if (to_select != null) {
                // Prefer the inboxes branch if it is a thing, but
                // only for non-interactive calls
                if (is_interactive ||
                    (to_select.used_as != INBOX ||
                     !this.folder_list.select_inbox(to_select.account))) {
                    this.folder_list.select_folder(to_select);
                }
            } else {
                this.folder_list.deselect_folder();
            }

            update_conversation_actions(NONE);
            update_title();
            this.main_toolbar.update_trash_button(
                !this.is_shift_down && this.selected_folder_supports_trash
            );
            this.conversation_viewer.show_loading();
            this.previous_selection_was_interactive = is_interactive;

            debug("Folder selected: %s",
                  (to_select != null) ? to_select.to_string() : "(null)");

            // Finally, hook up the new folder if any and start
            // loading conversations.

            if (to_select != null) {
                this.progress_monitor.add(to_select.opening_monitor);
                to_select.properties.notify.connect(update_headerbar);

                this.conversations = new Geary.App.ConversationMonitor(
                    to_select,
                    // Include fields for the conversation viewer as well so
                    // conversations can be displayed without having to go
                    // back to the db
                    ConversationListStore.REQUIRED_FIELDS |
                    ConversationListBox.REQUIRED_FIELDS |
                    ConversationEmail.REQUIRED_FOR_CONSTRUCT,
                    MIN_CONVERSATION_COUNT
                );
                this.progress_monitor.add(this.conversations.progress_monitor);

                conversations_model = new ConversationListStore(
                    this.conversations, this.application.config

                );
                this.progress_monitor.add(conversations_model.preview_monitor);
                if (inhibit_autoselect) {
                    this.conversation_list_view.inhibit_next_autoselect();
                }
                this.conversation_list_view.set_model(conversations_model);

                // disable copy/move to the new folder
                this.main_toolbar.copy_folder_menu.enable_disable_folder(
                    to_select, false
                );
                this.main_toolbar.move_folder_menu.enable_disable_folder(
                    to_select, false
                );

                yield open_conversation_monitor(this.conversations, cancellable);
                yield this.controller.process_pending_composers();
            }
        }

        update_headerbar();
    }

    /** Selects the given account, folder and conversations. */
    public async void show_conversations(Geary.Folder location,
                                         Gee.Collection<Geary.App.Conversation> to_show,
                                         bool is_interactive) {
        bool inhibit_autoselect = (location != this.selected_folder);
        yield select_folder(location, is_interactive, inhibit_autoselect);
        // The folder may have changed again by the type the async
        // call returns, so only continue if still current
        if (this.selected_folder == location) {
            // Since conversation ids don't persist between
            // conversation monitor instances, need to load
            // conversations based on their messages.
            var latest_email = new Gee.HashSet<Geary.EmailIdentifier>();
            foreach (var stale in to_show) {
                Geary.Email? first = stale.get_latest_recv_email(IN_FOLDER);
                if (first != null) {
                    latest_email.add(first.id);
                }
            }
            var loaded = yield load_conversations_for_email(
                location, latest_email
            );
            if (!loaded.is_empty) {
                yield select_conversations(
                    loaded,
                    Gee.Collection.empty<Geary.EmailIdentifier>(),
                    is_interactive
                );
            }
        }
    }

    /** Selects the given account, folder and email. */
    public async void show_email(Geary.Folder location,
                                 Gee.Collection<Geary.EmailIdentifier> to_show,
                                 bool is_interactive) {
        bool inhibit_autoselect = (location != this.selected_folder);
        yield select_folder(location, is_interactive, inhibit_autoselect);
        // The folder may have changed again by the type the async
        // call returns, so only continue if still current
        if (this.selected_folder == location) {
            var loaded = yield load_conversations_for_email(location, to_show);

            if (loaded.size == 1) {
                // A single conversation was loaded, so ensure we
                // scroll to the email in the conversation.
                Geary.App.Conversation? target = Geary.Collection.first(loaded);
                ConversationListBox? current_list =
                    this.conversation_viewer.current_list;
                if (current_list != null &&
                    current_list.conversation == target) {
                    // The target conversation is already loaded, just
                    // scroll to the messages.
                    //
                    // XXX this is actually racy, since the view may
                    // still be in the middle of loading the messages
                    // obtained from the conversation monitor when
                    // this call is made.
                    current_list.scroll_to_messages(to_show);
                } else {
                    // The target conversation is not loaded, select
                    // it and scroll to the messages.
                    yield select_conversations(loaded, to_show, is_interactive);
                }
            } else if (!loaded.is_empty) {
                // Multiple conversations found, just select those
                yield select_conversations(
                    loaded,
                    Gee.Collection.empty<Geary.EmailIdentifier>(),
                    is_interactive
                );
            } else {
            }
        }
    }

    /** Displays and focuses the search bar for the window. */
    public void show_search_bar(string? text = null) {
        this.search_bar.grab_focus();
        if (text != null) {
            this.search_bar.entry.text = text;
        }
    }

    /** Displays an infobar in the window. */
    public void show_info_bar(Gtk.InfoBar info_bar) {
        if (!this.info_bars.has_current) {
            this.info_bars.add(info_bar);
        }
    }

    /**
     * Displays a composer in the window if possible, else in a new window.
     */
    internal void show_composer(Composer.Widget composer) {
        if (this.has_composer) {
            composer.detach(this.application);
        } else {
            // See if the currently displayed conversation contains
            // any of the composer's referred emails (preferring the
            // latest), and if so add it inline, otherwise add it full
            // paned.
            Geary.Email? latest_referred = null;
            if (this.conversation_viewer.current_list != null) {
                Gee.Collection<Geary.EmailIdentifier>? referrants =
                    composer.get_referred_ids();
                Geary.App.Conversation selected =
                    this.conversation_viewer.current_list.conversation;
                latest_referred = selected.get_emails(
                    RECV_DATE_DESCENDING
                ).first_match(
                    (email) => email.id in referrants
                );
            }

            if (latest_referred != null) {
                this.conversation_viewer.do_compose_embedded(
                    composer, latest_referred
                );
            } else {
                this.conversation_viewer.do_compose(composer);
            }
        }
    }

    /**
     * Closes any open composers, after prompting the user if requested.
     *
     * Returns true if none were open or the user approved closing
     * them.
     */
    internal bool close_composer(bool should_prompt, bool is_shutdown = false) {
        bool closed = true;
        Composer.Widget? composer = this.conversation_viewer.current_composer;
        if (composer != null &&
            composer.conditional_close(should_prompt, is_shutdown) == CANCELLED) {
            closed = false;
        }
        return closed;
    }

    internal async void start_search(string query_text, bool is_interactive) {
        var context = get_selected_account_context();
        if (context != null) {
            // Stop any search in progress
            this.search_open.cancel();
            var cancellable = this.search_open = new GLib.Cancellable();

            if (this.previous_non_search_folder == null &&
                this.selected_folder != null &&
                this.selected_folder.used_as != SEARCH) {
                this.previous_non_search_folder = this.selected_folder;
            }

            var strategy = this.application.config.get_search_strategy();
            try {
                var query = yield context.account.new_search_query(
                    query_text,
                    strategy,
                    cancellable
                );
                this.folder_list.set_search(
                    this.application.engine, context.search
                );
                yield context.search.search(query, cancellable);
            } catch (GLib.Error error) {
                handle_error(context.account.information, error);
            }
        }
    }

    internal void stop_search(bool is_interactive) {
        // Stop any search in progress
        this.search_open.cancel();
        this.search_open = new GLib.Cancellable();

        if (this.selected_folder == null ||
            this.selected_folder.used_as == SEARCH) {
            var to_select = this.previous_non_search_folder;
            if (to_select == null) {
                var account = get_selected_account_context();
                if (account != null) {
                    to_select = account.inbox;
                }

            }
            if (to_select != null) {
                this.select_folder.begin(
                    this.previous_non_search_folder, is_interactive
                );
            } else {
                select_first_inbox(is_interactive);
            }
        }
        this.folder_list.remove_search();

        foreach (var context in this.controller.get_account_contexts()) {
            context.search.clear();
        }
    }

    internal bool select_first_inbox(bool is_interactive) {
        bool success = false;
        Geary.Folder? inbox = get_first_inbox();
        if (inbox != null) {
            this.select_folder.begin(inbox, is_interactive);
            success = true;
        }
        return success;
    }

    private void add_account(AccountContext to_add) {
        if (!this.accounts.contains(to_add)) {
            this.folder_list.set_user_folders_root_name(
                to_add.account, _("Labels")
            );

            this.progress_monitor.add(to_add.account.background_progress);
            Geary.Smtp.ClientService? smtp = (
                to_add.account.outgoing as Geary.Smtp.ClientService
            );
            if (smtp != null) {
                this.progress_monitor.add(smtp.sending_monitor);
            }

            to_add.folders_available.connect(on_folders_available);
            to_add.folders_unavailable.connect(on_folders_unavailable);
            to_add.commands.executed.connect(on_command_execute);
            to_add.commands.undone.connect(on_command_undo);
            to_add.commands.redone.connect(on_command_redo);

            add_folders(to_add.get_folders());
            this.accounts.add(to_add);
        }
    }

    /**
     * Removes the given account from the main window.
     *
     * If `to_select` is not null, the given folder will be selected,
     * otherwise no folder will be.
     */
    private async void remove_account(AccountContext to_remove,
                                      Geary.Folder? to_select) {
        if (this.accounts.contains(to_remove)) {
            // Explicitly unset the selected folder if it belongs to the
            // account so we block until it's gone. This also clears the
            // previous search folder, so it won't try to re-load that
            // that when the account is gone.
            if (this.selected_folder != null &&
                this.selected_folder.account == to_remove.account) {
                bool is_account_search_active = (
                    this.selected_folder.used_as == SEARCH
                );

                yield select_folder(to_select, false);

                if (is_account_search_active) {
                    this.search_bar.entry.text = "";
                    this.search_bar.search_mode_enabled = false;
                }
            }

            to_remove.commands.executed.disconnect(on_command_execute);
            to_remove.commands.undone.disconnect(on_command_undo);
            to_remove.commands.redone.disconnect(on_command_redo);
            to_remove.folders_available.disconnect(on_folders_available);
            to_remove.folders_available.disconnect(on_folders_unavailable);

            this.progress_monitor.remove(to_remove.account.background_progress);
            Geary.Smtp.ClientService? smtp = (
                to_remove.account.outgoing as Geary.Smtp.ClientService
            );
            if (smtp != null) {
                this.progress_monitor.remove(smtp.sending_monitor);
            }

            // Finally, remove the account and its folders
            remove_folders(to_remove.get_folders(), false);
            this.folder_list.remove_account(to_remove.account);
            this.accounts.remove(to_remove);
        }
    }

    /** Adds a folder to the window. */
    private void add_folders(Gee.Collection<FolderContext> to_add) {
        foreach (var context in to_add) {
            this.folder_list.add_folder(context);
            if (context.folder.account == this.selected_account) {
                this.main_toolbar.copy_folder_menu.add_folder(context.folder);
                this.main_toolbar.move_folder_menu.add_folder(context.folder);
            }
            context.folder.use_changed.connect(on_use_changed);
        }
    }

    /** Removes a folder from the window. */
    private void remove_folders(Gee.Collection<FolderContext> to_remove,
                                bool update_selecton) {
        foreach (var context in to_remove) {
            Geary.Folder folder = context.folder;
            if (this.selected_folder == folder) {
                var account = get_selected_account_context();
                if (account != null) {
                    this.select_folder.begin(account.inbox, true);
                }
            }

            folder.use_changed.disconnect(on_use_changed);
            if (folder.account == this.selected_account) {
                this.main_toolbar.copy_folder_menu.remove_folder(folder);
                this.main_toolbar.move_folder_menu.remove_folder(folder);
            }
            this.folder_list.remove_folder(context);
        }
    }

    private AccountContext? get_selected_account_context() {
        AccountContext? context = null;
        if (this.selected_account != null) {
            context = this.controller.get_context_for_account(
                this.selected_account.information
            );
        }
        return context;
    }

    private Geary.Folder? get_first_inbox() {
        Geary.Folder? inbox = null;
        try {
            Geary.Account? first = Geary.Collection.first<Geary.Account>(
                this.application.engine.get_accounts()
            );
            if (first != null) {
                inbox = first.get_special_folder(INBOX);
            }
        } catch (GLib.Error error) {
            debug("Error getting inbox for first account");
        }
        return inbox;
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
        config.settings.changed[
            Configuration.FOLDER_LIST_PANE_HORIZONTAL_KEY
        ].connect(on_change_orientation);
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

    private void setup_layout(Configuration config) {
        this.notify["has-toplevel-focus"].connect(on_has_toplevel_focus);

        // Search bar
        this.search_bar = new SearchBar(this.application.engine);
        this.search_bar.search_text_changed.connect(on_search);
        this.search_bar_box.pack_start(this.search_bar, false, false, 0);

        // Folder list
        this.folder_list.folder_selected.connect(on_folder_selected);
        this.folder_list.move_conversation.connect(on_move_conversation);
        this.folder_list.copy_conversation.connect(on_copy_conversation);
        this.folder_list_scrolled.add(this.folder_list);

        // Conversation list
        this.conversation_list_box.pack_start(
            this.conversation_list_info_bars, false, false, 0
        );
        this.conversation_list_view = new ConversationListView(
            this.application.config
        );
        this.conversation_list_view.load_more.connect(on_load_more);
        this.conversation_list_view.mark_conversations.connect(on_mark_conversations);
        this.conversation_list_view.conversations_selected.connect(on_conversations_selected);
        this.conversation_list_view.conversation_activated.connect(on_conversation_activated);
        this.conversation_list_view.visible_conversations_changed.connect(on_visible_conversations_changed);
        this.conversation_list_scrolled.add(conversation_list_view);

        // Conversation viewer
        this.conversation_viewer = new ConversationViewer(
            this.application.config
        );
        this.conversation_viewer.conversation_added.connect(
            on_conversation_view_added
        );

        this.conversations_paned.pack2(this.conversation_viewer, true, false);

        // Main toolbar
        this.main_toolbar = new MainToolbar(config);
        this.main_toolbar.move_folder_menu.folder_selected.connect(on_move_conversation);
        this.main_toolbar.copy_folder_menu.folder_selected.connect(on_copy_conversation);
        this.main_toolbar.bind_property("search-open", this.search_bar, "search-mode-enabled",
            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        this.main_toolbar.bind_property("find-open", this.conversation_viewer.conversation_find_bar,
                "search-mode-enabled", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        if (config.desktop_environment == UNITY) {
            this.main_toolbar.show_close_button = false;
            this.main_layout.pack_start(main_toolbar, false, true, 0);
        } else {
            var titlebar = new Hdy.TitleBar();
            titlebar.show();
            titlebar.add(this.main_toolbar);
            set_titlebar(titlebar);
        }

        this.main_layout.pack_start(this.info_bars, false, true, 0);

        // Status bar
        this.status_bar.set_size_request(-1, STATUS_BAR_HEIGHT);
        this.status_bar.set_border_width(2);
        this.spinner.set_size_request(STATUS_BAR_HEIGHT - 2, -1);
        this.spinner.set_progress_monitor(progress_monitor);
        this.status_bar.add(this.spinner);
        this.status_bar.show_all();
    }

    /** {@inheritDoc} */
    public override bool key_press_event(Gdk.EventKey event) {
        check_shift_event(event);
        return base.key_press_event(event);
    }

    /** {@inheritDoc} */
    public override bool key_release_event(Gdk.EventKey event) {
        check_shift_event(event);
        return base.key_release_event(event);
    }

    internal bool prompt_empty_folder(Geary.Folder.SpecialUse type) {
        var folder_name = Util.I18n.to_folder_type_display_name(type);
        ConfirmationDialog dialog = new ConfirmationDialog(
            this,
            _("Empty all email from your %s folder?").printf(folder_name),
            _("This removes the email from Geary and your email server.") +
            "  <b>" + _("This cannot be undone.") + "</b>",
            _("Empty %s").printf(folder_name),
            "destructive-action"
        );
        dialog.use_secondary_markup(true);
        dialog.set_focus_response(Gtk.ResponseType.CANCEL);
        return (dialog.run() == Gtk.ResponseType.OK);
    }

    /** Un-does the last executed application command, if any. */
    private async void undo() {
        AccountContext? selected = get_selected_account_context();
        if (selected != null) {
            selected.commands.undo.begin(
                selected.cancellable,
                (obj, res) => {
                    try {
                        selected.commands.undo.end(res);
                    } catch (GLib.Error err) {
                        handle_error(selected.account.information, err);
                    }
                }
            );
        }
    }

    /** Re-does the last undone application command, if any. */
    private async void redo() {
        AccountContext? selected = get_selected_account_context();
        if (selected != null) {
            selected.commands.redo.begin(
                selected.cancellable,
                (obj, res) => {
                    try {
                        selected.commands.redo.end(res);
                    } catch (GLib.Error err) {
                        handle_error(selected.account.information, err);
                    }
                }
            );
        }
    }

    private void update_command_actions() {
        AccountContext? selected = get_selected_account_context();
        get_edit_action(Action.Edit.UNDO).set_enabled(
            selected != null && selected.commands.can_undo
        );
        get_edit_action(Action.Edit.REDO).set_enabled(
            selected != null && selected.commands.can_redo
        );
    }

    private bool prompt_delete_conversations(int count) {
        ConfirmationDialog dialog = new ConfirmationDialog(
            this,
            /// Translators: Primary text for a confirmation dialog
            ngettext(
                "Do you want to permanently delete this conversation?",
                "Do you want to permanently delete these conversations?",
                count
            ),
            null,
            _("Delete"), "destructive-action"
        );
        return (dialog.run() == Gtk.ResponseType.OK);
    }

    private bool prompt_delete_messages(int count) {
        ConfirmationDialog dialog = new ConfirmationDialog(
            this,
            /// Translators: Primary text for a confirmation dialog
            ngettext(
                "Do you want to permanently delete this message?",
                "Do you want to permanently delete these messages?",
                count
            ),
            null,
            _("Delete"), "destructive-action"
        );
        return (dialog.run() == Gtk.ResponseType.OK);
    }

    private async Gee.Collection<Geary.App.Conversation>
        load_conversations_for_email(
            Geary.Folder location,
            Gee.Collection<Geary.EmailIdentifier> to_load) {
        bool was_loaded = false;
        // Can't assume the conversation monitor is valid, so check
        // it first.
        if (this.conversations != null &&
            this.conversations.base_folder == location) {
            try {
                yield this.conversations.load_email(to_load, this.folder_open);
                was_loaded = true;
            } catch (GLib.Error err) {
                debug("Error loading conversations to show them: %s",
                      err.message);
            }
        }

        // Conversation monitor may have changed since resuming from
        // the last async statement, so check it's still valid again.
        var loaded = new Gee.HashSet<Geary.App.Conversation>();
        if (was_loaded &&
            this.conversations != null &&
            this.conversations.base_folder == location) {
            foreach (var id in to_load) {
                Geary.App.Conversation? conversation =
                    this.conversations.get_by_email_identifier(id);
                if (conversation != null) {
                    loaded.add(conversation);
                }
            }
        }
        return loaded;
    }

    private inline void handle_error(Geary.AccountInformation? account,
                                     GLib.Error error) {
        Geary.ProblemReport? report = (account != null)
            ? new Geary.AccountProblemReport(account, error)
            : new Geary.ProblemReport(error);
        this.controller.report_problem(report);
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

    private void select_account(Geary.Account? account) {
        if (this.selected_account != account) {
            if (this.selected_account != null) {
                this.main_toolbar.copy_folder_menu.clear();
                this.main_toolbar.move_folder_menu.clear();
            }

            this.selected_account = account;
            this.search_bar.set_account(account);

            if (account != null) {
                foreach (Geary.Folder folder in account.list_folders()) {
                    this.main_toolbar.copy_folder_menu.add_folder(folder);
                    this.main_toolbar.move_folder_menu.add_folder(folder);
                }
            }

            update_command_actions();
        }
    }

    private async void select_conversations(Gee.Collection<Geary.App.Conversation> to_select,
                                            Gee.Collection<Geary.EmailIdentifier> scroll_to,
                                            bool is_interactive) {
        bool start_mark_timer = (
            this.previous_selection_was_interactive && is_interactive
        );
        this.previous_selection_was_interactive = is_interactive;

        // Ensure that the conversations are selected in the UI if
        // this was called by something other than the selection
        // changed callback. That will check to ensure that we're not
        // setting it again.
        this.conversation_list_view.select_conversations(to_select);

        this.main_toolbar.selected_conversations = to_select.size;
        if (this.selected_folder != null && !this.has_composer) {
            switch(to_select.size) {
            case 0:
                update_conversation_actions(NONE);
                this.conversation_viewer.show_none_selected();
                break;

            case 1:
                update_conversation_actions(SINGLE);
                Geary.App.Conversation? convo = Geary.Collection.first(to_select);

                // It's possible for a conversation with zero email to
                // be selected, when it has just evaporated after its
                // last email was removed but the conversation monitor
                // hasn't signalled its removal yet. In this case,
                // just don't load it since it will soon disappear.
                AccountContext? context = get_selected_account_context();
                if (context != null && convo.get_count() > 0) {
                    try {
                        yield this.conversation_viewer.load_conversation(
                            convo,
                            scroll_to,
                            context.emails,
                            context.contacts,
                            start_mark_timer
                        );
                    } catch (Geary.EngineError.NOT_FOUND err) {
                        // The first interesting email from the
                        // conversation wasn't found. If the
                        // conversation has completely evaporated by
                        // now then fine, otherwise throw the
                        // error. This happens e.g. in the drafts
                        // folder, there is a race between the
                        // composer being discarded and the draft
                        // itself disappearing
                        if (convo.get_count() == 0) {
                            debug("Ignoring not found error: %s", err.message);
                        } else {
                            handle_error(
                                convo.base_folder.account.information, err
                            );
                        }
                    } catch (GLib.IOError.CANCELLED err) {
                        // All good
                    } catch (GLib.Error err) {
                        handle_error(convo.base_folder.account.information, err);
                    }
                }
                break;

            default:
                update_conversation_actions(MULTIPLE);
                this.conversation_viewer.show_multiple_selected();
                break;
            }
        }
    }

    private async void open_conversation_monitor(Geary.App.ConversationMonitor to_open,
                                                 GLib.Cancellable cancellable) {
        to_open.scan_completed.connect(on_scan_completed);
        to_open.scan_error.connect(on_scan_error);

        to_open.scan_completed.connect(on_conversation_count_changed);
        to_open.conversations_added.connect(on_conversation_count_changed);
        to_open.conversations_removed.connect(on_conversation_count_changed);

        to_open.start_monitoring.begin(
            NO_DELAY,
            cancellable,
            (obj, res) => {
                try {
                    to_open.start_monitoring.end(res);
                } catch (GLib.Error err) {
                    handle_error(to_open.base_folder.account.information, err);
                }
            }
        );
    }

    private void close_conversation_monitor(Geary.App.ConversationMonitor to_close) {
        to_close.scan_completed.disconnect(on_scan_completed);
        to_close.scan_error.disconnect(on_scan_error);

        to_close.scan_completed.disconnect(on_conversation_count_changed);
        to_close.conversations_added.disconnect(on_conversation_count_changed);
        to_close.conversations_removed.disconnect(on_conversation_count_changed);

        to_close.stop_monitoring.begin(
            null,
            (obj, res) => {
                try {
                    to_close.stop_monitoring.end(res);
                } catch (GLib.Error err) {
                    warning(
                        "Error closing conversation monitor %s: %s",
                        to_close.base_folder.to_string(),
                        err.message
                    );
                }
            }
        );
    }

    private async void create_composer(Geary.Account send_context,
                                       Composer.Widget.ContextType type,
                                       Geary.Email context,
                                       string? quote) {
        var composer = yield this.controller.compose_with_context(
            this.controller.get_context_for_account(send_context.information),
            type,
            context,
            quote ?? ""
        );
        this.controller.present_composer(composer);
    }

    private async void create_composer_from_viewer(Composer.Widget.ContextType type) {
        Geary.Account? account = this.selected_account;
        ConversationEmail? email_view = null;
        ConversationListBox? list_view = this.conversation_viewer.current_list;
        if (list_view != null) {
            email_view = list_view.get_reply_target();
        }
        if (account != null && email_view != null) {
            string? quote = yield email_view.get_selection_for_quoting();
            yield create_composer(account, type, email_view.email, quote);
        }
    }

    private void load_more() {
        if (this.conversations != null) {
            this.conversations.min_window_count += MIN_CONVERSATION_COUNT;
        }
    }

    private void on_conversations_selected(Gee.Set<Geary.App.Conversation> selected) {
        this.select_conversations.begin(selected, Gee.Collection.empty(), true);
    }

    private void on_conversation_count_changed() {
        // Only update the UI if we don't currently have a composer,
        // so we don't clobber it
        if (!this.has_composer) {
            if (this.conversations.size == 0) {
                // Let the user know if there's no available conversations
                if (this.selected_folder.used_as == SEARCH) {
                    this.conversation_viewer.show_empty_search();
                } else {
                    this.conversation_viewer.show_empty_folder();
                }
                update_conversation_actions(NONE);
            } else {
                // When not doing autoselect, we never get
                // conversations_selected firing from the convo list,
                // so we need to stop the loading spinner here.
                if (!this.application.config.autoselect &&
                    this.conversation_list_view.get_selection().count_selected_rows() == 0) {
                    this.conversation_viewer.show_none_selected();
                    update_conversation_actions(NONE);
                }
            }
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
            this.conversation_list_box.pack_start(status_bar, false, false);
        }

        this.application.config.bind(
            horizontal
            ? Configuration.FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY
            : Configuration.FOLDER_LIST_PANE_POSITION_VERTICAL_KEY,
            this.folder_paned, "position");
    }

    private void update_headerbar() {
        update_title();
        if (this.selected_folder != null) {
            // Current folder's name followed by its unread count,
            // i.e. "Inbox (42)" except for Drafts and Outbox, where
            // we show total count
            int count;
            switch (this.selected_folder.used_as) {
            case DRAFTS:
            case OUTBOX:
                count = this.selected_folder.properties.email_total;
                break;

            default:
                count = this.selected_folder.properties.email_unread;
                break;
            }

            if (count > 0) {
                this.main_toolbar.folder = _("%s (%d)").printf(
                    this.main_toolbar.folder, count
                );
            }
        }
    }

    private void update_conversation_actions(ConversationCount count) {
        bool sensitive = (count != NONE);
        bool multiple = (count == MULTIPLE);

        get_window_action(ACTION_FIND_IN_CONVERSATION).set_enabled(
            sensitive && !multiple
        );

        bool reply_sensitive = (
            sensitive &&
            !multiple &&
            this.selected_folder != null &&
            this.selected_folder.used_as != DRAFTS
        );
        get_window_action(ACTION_REPLY_CONVERSATION).set_enabled(reply_sensitive);
        get_window_action(ACTION_REPLY_ALL_CONVERSATION).set_enabled(reply_sensitive);
        get_window_action(ACTION_FORWARD_CONVERSATION).set_enabled(reply_sensitive);

        bool move_enabled = (
            sensitive && (selected_folder is Geary.FolderSupport.Move)
        );
        this.main_toolbar.move_message_button.set_sensitive(move_enabled);
        get_window_action(ACTION_SHOW_MOVE_MENU).set_enabled(move_enabled);

        bool copy_enabled = (
            sensitive && (selected_folder is Geary.FolderSupport.Copy)
        );
        this.main_toolbar.copy_message_button.set_sensitive(copy_enabled);
        get_window_action(ACTION_SHOW_COPY_MENU).set_enabled(move_enabled);

        get_window_action(ACTION_ARCHIVE_CONVERSATION).set_enabled(
            sensitive && (selected_folder is Geary.FolderSupport.Archive)
        );
        get_window_action(ACTION_TRASH_CONVERSATION).set_enabled(
            sensitive && this.selected_folder_supports_trash
        );
        get_window_action(ACTION_DELETE_CONVERSATION).set_enabled(
            sensitive && (selected_folder is Geary.FolderSupport.Remove)
        );

        this.update_context_dependent_actions.begin(sensitive);
    }

    private async void update_context_dependent_actions(bool sensitive) {
        // Cancel any existing update that is running
        this.action_update_cancellable.cancel();
        GLib.Cancellable cancellable = new Cancellable();
        this.action_update_cancellable = cancellable;

        Gee.MultiMap<Geary.EmailIdentifier, Type>? selected_operations = null;
        if (this.selected_folder != null) {
            AccountContext? context =
                this.controller.get_context_for_account(
                    this.selected_folder.account.information
                );
            if (context != null) {
                Gee.Collection<Geary.EmailIdentifier> ids =
                    new Gee.LinkedList<Geary.EmailIdentifier>();
                foreach (Geary.App.Conversation convo in
                         this.conversation_list_view.get_selected()) {
                    ids.add_all(convo.get_email_ids());
                }
                try {
                    selected_operations = yield context.emails.get_supported_operations_async(
                        ids, cancellable
                    );
                } catch (GLib.Error e) {
                    debug("Error checking for what operations are supported in the selected conversations: %s",
                          e.message);
                }
            }
        }

        if (!cancellable.is_cancelled()) {
            Gee.HashSet<Type> supported_operations = new Gee.HashSet<Type>();
            if (selected_operations != null) {
                supported_operations.add_all(selected_operations.get_values());
            }

            get_window_action(ACTION_SHOW_MARK_MENU).set_enabled(
                sensitive &&
                (typeof(Geary.FolderSupport.Mark) in supported_operations)
            );
            get_window_action(ACTION_SHOW_COPY_MENU).set_enabled(
                sensitive &&
                (supported_operations.contains(typeof(Geary.FolderSupport.Copy)))
            );
            get_window_action(ACTION_SHOW_MOVE_MENU).set_enabled(
                sensitive &&
                (supported_operations.contains(typeof(Geary.FolderSupport.Move)))
            );
        }
    }

    private void set_shift_key_down(bool down) {
        this.is_shift_down = down;
        this.main_toolbar.update_trash_button(
            !down && this.selected_folder_supports_trash
        );
    }

    private inline void check_shift_event(Gdk.EventKey event) {
        // FIXME: it's possible the user will press two shift keys.  We want
        // the shift key to report as released when they release ALL of them.
        // There doesn't seem to be an easy way to do this in Gdk.
        if (event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R) {
            Gtk.Widget? focus = get_focus();
            if (focus == null ||
                (!(focus is Gtk.Entry) && !(focus is Composer.WebView))) {
                set_shift_key_down(event.type == Gdk.EventType.KEY_PRESS);
            }
        }
    }

    private void focus_next_pane() {
        var focus = get_focus();
        if (focus != null) {
            if (focus == this.folder_list ||
                focus.is_ancestor(this.folder_list)) {
                focus = this.conversation_list_view;
            } else if (focus == this.conversation_list_view ||
                       focus.is_ancestor(this.conversation_list_view)) {
                focus = this.conversation_viewer.visible_child;
            } else if (focus == this.conversation_viewer ||
                       focus.is_ancestor(this.conversation_viewer)) {
                focus = this.folder_list;
            }
        }

        if (focus != null) {
            focus.focus(TAB_FORWARD);
        } else {
            get_window().beep();
        }
    }

    private void focus_previous_pane() {
        var focus = get_focus();
        if (focus != null) {
            if (focus == this.folder_list ||
                focus.is_ancestor(this.folder_list)) {
                focus = this.conversation_viewer.visible_child;
            } else if (focus == this.conversation_list_view ||
                       focus.is_ancestor(this.conversation_list_view)) {
                focus = this.folder_list;
            } else if (focus == this.conversation_viewer ||
                       focus.is_ancestor(this.conversation_viewer)) {
                focus = this.conversation_list_view;
            }
        }

        if (focus != null) {
            focus.focus(TAB_FORWARD);
        } else {
            get_window().beep();
        }

    }

    private SimpleAction get_window_action(string name) {
        return (SimpleAction) lookup_action(name);
    }

    private SimpleAction get_edit_action(string name) {
        return (SimpleAction) this.edit_actions.lookup_action(name);
    }

    private void activate_action(GLib.Action? action) {
        if (action != null && action.get_enabled()) {
            action.activate(null);
        } else {
            get_window().beep();
        }
    }

    private void on_scan_completed(Geary.App.ConversationMonitor monitor) {
        // Done scanning.  Check if we have enough messages to fill
        // the conversation list; if not, trigger a load_more();
        Gtk.Scrollbar? scrollbar = (
            this.conversation_list_scrolled.get_vscrollbar() as Gtk.Scrollbar
        );
        if (is_visible() &&
            (scrollbar == null || !scrollbar.get_visible()) &&
            monitor == this.conversations &&
            monitor.can_load_more) {
            debug("Not enough messages, loading more for folder %s",
                  this.selected_folder.to_string());
            load_more();
        }
    }

    private void on_scan_error(Geary.App.ConversationMonitor monitor,
                               GLib.Error err) {
        Geary.AccountInformation account =
            monitor.base_folder.account.information;
        this.controller.report_problem(
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
        this.set_shift_key_down(false);
        return false;
    }

    [GtkCallback]
    private bool on_delete_event() {
        if (close_composer(true, false)) {
            this.sensitive = false;
            this.select_folder.begin(
                null,
                false,
                true,
                (obj, res) => {
                    this.select_folder.end(res);
                    destroy();
                }
            );
        }
        return Gdk.EVENT_STOP;
    }

    private void on_offline_infobar_response() {
        this.info_bars.remove(this.offline_infobar);
    }

    private void on_service_problem_retry() {
        this.info_bars.remove(this.service_problem_infobar);
        this.service_problem_infobar = null;
        retry_service_problem(Geary.ClientService.Status.CONNECTION_FAILED);
    }

    private void on_cert_problem_retry() {
        this.info_bars.remove(this.cert_problem_infobar);
        retry_service_problem(Geary.ClientService.Status.TLS_VALIDATION_FAILED);
    }

    private void on_auth_problem_retry() {
        this.info_bars.remove(this.auth_problem_infobar);
        retry_service_problem(Geary.ClientService.Status.AUTHENTICATION_FAILED);
    }

    private void on_update_ui_timeout() {
        update_ui();
    }

    private void on_account_available(AccountContext account) {
        add_account(account);
    }

    private void on_account_unavailable(AccountContext account,
                                        bool is_shutdown) {
        // If we're not shutting down, select the inbox of the first
        // account so that we show something other than empty
        // conversation list/viewer.
        Geary.Folder? to_select = null;
        if (!is_shutdown) {
            to_select = get_first_inbox();
        }
        this.remove_account.begin(account, to_select);
    }

    private void on_folders_available(Gee.Collection<FolderContext> available) {
        add_folders(available);
    }

    private void on_folders_unavailable(Gee.Collection<FolderContext> unavailable) {
        remove_folders(unavailable, true);
    }

    private void on_use_changed(Geary.Folder folder,
                                Geary.Folder.SpecialUse old_type,
                                Geary.Folder.SpecialUse new_type) {
        // Update the main window
        AccountContext? context = this.controller.get_context_for_account(
            folder.account.information
        );
        if (context != null) {
            FolderContext? folder_context = context.get_folder(folder);
            if (folder_context != null) {
                this.folder_list.remove_folder(folder_context);
                this.folder_list.add_folder(folder_context);

                // Since removing the folder will also remove its children
                // from the folder list, we need to check for any and re-add
                // them. See issue #11.
                try {
                    foreach (Geary.Folder child in
                             folder.account.list_matching_folders(folder.path)) {
                        FolderContext? child_context = context.get_folder(child);
                        if (child_context != null) {
                            this.folder_list.add_folder(child_context);
                        }
                    }
                } catch (Error err) {
                    // Oh well
                }
            }
        }
    }

    private void on_command_execute(Command command) {
        if (!(command is TrivialCommand)) {
            // Only show an execute notification for non-trivial
            // commands
            on_command_redo(command);
        } else {
            // Still have to update the undo/redo actions for trivial
            // commands
            update_command_actions();
        }
    }

    private void on_command_undo(Command command) {
        update_command_actions();
        EmailCommand? email = command as EmailCommand;
        if (email != null) {
            if (email.conversations.size > 1) {
                this.show_conversations.begin(
                    email.location, email.conversations, false
                );
            } else {
                this.show_email.begin(
                    email.location, email.email, false
                );
            }
        }
        if (command.undone_label != null) {
            Components.InAppNotification ian =
                new Components.InAppNotification(command.undone_label);
            ian.set_button(_("Redo"), Action.Edit.prefix(Action.Edit.REDO));
            add_notification(ian);
        }
    }

    private void on_command_redo(Command command) {
        update_command_actions();
        if (command.executed_label != null) {
            uint notification_time =
                Components.InAppNotification.DEFAULT_DURATION;
            if (command.executed_notification_brief) {
                notification_time =
                    application.config.brief_notification_duration;
            }
            Components.InAppNotification ian = new Components.InAppNotification(
                command.executed_label, notification_time
            );
            ian.set_button(_("Undo"), Action.Edit.prefix(Action.Edit.UNDO));
            add_notification(ian);
        }
    }

    private void on_conversation_view_added(ConversationListBox list) {
        list.email_loaded.connect(on_email_loaded);
        list.mark_email.connect(on_email_mark);
        list.reply_to_all_email.connect(on_email_reply_to_all);
        list.reply_to_sender_email.connect(on_email_reply_to_sender);
        list.forward_email.connect(on_email_forward);
        list.trash_email.connect(on_email_trash);
        list.delete_email.connect(on_email_delete);
    }

    // Window-level action callbacks

    private void on_undo() {
        this.undo.begin();
    }

    private void on_redo() {
        this.redo.begin();
    }

    private void on_close() {
        close();
    }

    // this signal does not necessarily indicate that the application
    // previously didn't have focus and now it does
    private void on_has_toplevel_focus() {
        if (this.selected_folder != null) {
            this.controller.clear_new_messages(
                this.selected_folder,
                this.conversation_list_view.get_visible_conversations()
            );
        }
    }

    private void on_folder_selected(Geary.Folder? folder) {
        this.select_folder.begin(folder, true);
    }

    private void on_search(string text) {
        if (Geary.String.is_empty_or_whitespace(text)) {
            stop_search(true);
        } else {
            this.start_search.begin(text, true);
        }
    }

    private void on_visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible) {
        if (this.selected_folder != null) {
            this.controller.clear_new_messages(this.selected_folder, visible);
        }
    }

    private void on_conversation_activated(Geary.App.Conversation activated) {
        if (this.selected_folder != null) {
            if (this.selected_folder.used_as != DRAFTS) {
                this.application.new_window.begin(
                    this.selected_folder,
                    this.conversation_list_view.copy_selected()
                );
            } else {
                // TODO: Determine how to map between conversations
                // and drafts correctly.
                Geary.Email draft = activated.get_latest_recv_email(IN_FOLDER);
                this.create_composer.begin(
                    this.selected_folder.account,
                    EDIT,
                    draft,
                    null
                );
            }
        }
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
        this.create_composer_from_viewer.begin(REPLY_SENDER);
    }

    private void on_reply_all_conversation() {
        this.create_composer_from_viewer.begin(REPLY_ALL);
    }

    private void on_forward_conversation() {
        this.create_composer_from_viewer.begin(FORWARD);
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
                 this.conversation_list_view.get_selected()) {
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
        get_window_action(ACTION_MARK_AS_READ).set_enabled(unread_selected);
        get_window_action(ACTION_MARK_AS_UNREAD).set_enabled(read_selected);
        get_window_action(ACTION_MARK_AS_STARRED).set_enabled(unstarred_selected);
        get_window_action(ACTION_MARK_AS_UNSTARRED).set_enabled(starred_selected);

        // If we're in Drafts/Outbox, we also shouldn't set a message as junk
        bool in_junk_folder = (selected_folder.used_as == JUNK);
        get_window_action(ACTION_TOGGLE_JUNK).set_enabled(
            !in_junk_folder &&
            selected_folder.used_as != DRAFTS &&
            selected_folder.used_as != OUTBOX
        );
    }

    private void on_mark_conversations(Gee.Collection<Geary.App.Conversation> conversations,
                                       Geary.NamedFlag flag) {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            this.controller.mark_conversations.begin(
                location,
                conversations,
                flag,
                true,
                (obj, res) => {
                    try {
                        this.controller.mark_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_mark_as_read() {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            this.controller.mark_conversations.begin(
                location,
                this.conversation_list_view.copy_selected(),
                Geary.EmailFlags.UNREAD,
                false,
                (obj, res) => {
                    try {
                        this.controller.mark_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_mark_as_unread() {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            this.controller.mark_conversations.begin(
                location,
                this.conversation_list_view.copy_selected(),
                Geary.EmailFlags.UNREAD,
                true,
                (obj, res) => {
                    try {
                        this.controller.mark_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_mark_as_starred() {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            this.controller.mark_conversations.begin(
                location,
                this.conversation_list_view.copy_selected(),
                Geary.EmailFlags.FLAGGED,
                true,
                (obj, res) => {
                    try {
                        this.controller.mark_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_mark_as_unstarred() {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            this.controller.mark_conversations.begin(
                location,
                this.conversation_list_view.copy_selected(),
                Geary.EmailFlags.FLAGGED,
                false,
                (obj, res) => {
                    try {
                        this.controller.mark_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_mark_as_junk_toggle() {
        Geary.Folder? source = this.selected_folder;
        if (source != null) {
            Geary.Folder.SpecialUse destination =
                (source.used_as != JUNK)
                ? Geary.Folder.SpecialUse.JUNK
                : Geary.Folder.SpecialUse.INBOX;
            this.controller.move_conversations_special.begin(
                source,
                destination,
                this.conversation_list_view.copy_selected(),
                (obj, res) => {
                    try {
                        this.controller.move_conversations_special.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );
        }
    }

    private void on_move_conversation(Geary.Folder destination) {
        Geary.FolderSupport.Move source =
            this.selected_folder as Geary.FolderSupport.Move;
        if (source != null) {
            this.controller.move_conversations.begin(
                source,
                destination,
                this.conversation_list_view.copy_selected(),
                (obj, res) => {
                    try {
                        this.controller.move_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );

        }
    }

    private void on_copy_conversation(Geary.Folder destination) {
        Geary.FolderSupport.Copy source =
            this.selected_folder as Geary.FolderSupport.Copy;
        if (source != null) {
            this.controller.copy_conversations.begin(
                source,
                destination,
                this.conversation_list_view.copy_selected(),
                (obj, res) => {
                    try {
                        this.controller.copy_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );

        }
    }

    private void on_archive_conversation() {
        Geary.Folder source = this.selected_folder;
        if (source != null) {
            this.controller.move_conversations_special.begin(
                source,
                ARCHIVE,
                this.conversation_list_view.copy_selected(),
                (obj, res) => {
                    try {
                        this.controller.move_conversations_special.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );
        }
    }

    private void on_trash_conversation() {
        Geary.Folder source = this.selected_folder;
        if (source != null) {
            this.controller.move_conversations_special.begin(
                source,
                TRASH,
                this.conversation_list_view.copy_selected(),
                (obj, res) => {
                    try {
                        this.controller.move_conversations_special.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );
        }
    }

    private void on_delete_conversation() {
        Geary.FolderSupport.Remove target =
            this.selected_folder as Geary.FolderSupport.Remove;
        Gee.Collection<Geary.App.Conversation> conversations =
            this.conversation_list_view.copy_selected();
        if (target != null && this.prompt_delete_conversations(conversations.size)) {
            this.controller.delete_conversations.begin(
                target,
                conversations,
                (obj, res) => {
                    try {
                        this.controller.delete_conversations.end(res);
                    } catch (GLib.Error err) {
                        handle_error(target.account.information, err);
                    }
                }
            );
        }
    }

    private void on_email_loaded(ConversationListBox view,
                                 Geary.Email loaded) {
        this.controller.email_loaded(
            view.conversation.base_folder.account.information,
            loaded
        );
    }

    private void on_email_mark(ConversationListBox view,
                               Gee.Collection<Geary.EmailIdentifier> messages,
                               Geary.NamedFlag? to_add,
                               Geary.NamedFlag? to_remove) {
        Geary.Folder? location = this.selected_folder;
        if (location != null) {
            Geary.EmailFlags add_flags = null;
            if (to_add != null) {
                add_flags = new Geary.EmailFlags();
                add_flags.add(to_add);
            }
            Geary.EmailFlags remove_flags = null;
            if (to_remove != null) {
                remove_flags = new Geary.EmailFlags();
                remove_flags.add(to_remove);
            }
            this.controller.mark_messages.begin(
                location,
                Geary.Collection.single(view.conversation),
                messages,
                add_flags,
                remove_flags,
                (obj, res) => {
                    try {
                        this.controller.mark_messages.end(res);
                    } catch (GLib.Error err) {
                        handle_error(location.account.information, err);
                    }
                }
            );
        }
    }

    private void on_email_reply_to_sender(Geary.Email target, string? quote) {
        if (this.selected_account != null) {
            this.create_composer.begin(
                this.selected_account, REPLY_SENDER, target, quote
            );
        }
    }

    private void on_email_reply_to_all(Geary.Email target, string? quote) {
        if (this.selected_account != null) {
            this.create_composer.begin(
                this.selected_account, REPLY_ALL, target, quote
            );
        }
    }

    private void on_email_forward(Geary.Email target, string? quote) {
        if (this.selected_account != null) {
            this.create_composer.begin(
                this.selected_account, FORWARD, target, quote
            );
        }
    }

    private void on_email_trash(ConversationListBox view, Geary.Email target) {
        Geary.Folder? source = this.selected_folder;
        if (source != null) {
            this.controller.move_messages_special.begin(
                source,
                TRASH,
                Geary.Collection.single(view.conversation),
                Geary.Collection.single(target.id),
                (obj, res) => {
                    try {
                        this.controller.move_messages_special.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );
        }
    }

    private void on_email_delete(ConversationListBox view, Geary.Email target) {
        Geary.FolderSupport.Remove? source =
            this.selected_folder as Geary.FolderSupport.Remove;
        if (source != null && prompt_delete_messages(1)) {
            this.controller.delete_messages.begin(
                source,
                Geary.Collection.single(view.conversation),
                Geary.Collection.single(target.id),
                (obj, res) => {
                    try {
                        this.controller.delete_messages.end(res);
                    } catch (GLib.Error err) {
                        handle_error(source.account.information, err);
                    }
                }
            );
        }
    }

}
