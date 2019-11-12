/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Primary controller for an application instance.
 *
 * A single instance of this class is constructed by {@link
 * GearyAplication} when the primary application instance is started.
 */
public class Application.Controller : Geary.BaseObject {


    private const string PROP_ATTEMPT_OPEN_ACCOUNT = "attempt-open-account";
    private const uint MAX_AUTH_ATTEMPTS = 3;


    /** Determines if conversations can be trashed from the given folder. */
    public static bool does_folder_support_trash(Geary.Folder? target) {
        return (
            target != null &&
            target.special_folder_type != TRASH &&
            !target.properties.is_local_only &&
            (target as Geary.FolderSupport.Move) != null
        );
    }


    /**
     * Collects objects and state related to a single open account.
     */
    public class AccountContext : Geary.BaseObject {

        /** The account for this context. */
        public Geary.Account account { get; private set; }

        /** The account's Inbox folder */
        public Geary.Folder? inbox = null;

        /** The account's email store */
        public Geary.App.EmailStore emails { get; private set; }

        /** The account's contact store */
        public ContactStore contacts { get; private set; }

        /** The account's application command stack. */
        public CommandStack commands {
            get { return this.controller_stack; }
        }

        /** A cancellable tied to the life-cycle of the account. */
        public Cancellable cancellable {
            get; private set; default = new Cancellable();
        }

        /** The account's application command stack. */
        internal ControllerCommandStack controller_stack {
            get; protected set; default = new ControllerCommandStack();
        }

        /** Determines if the account has an authentication problem. */
        internal bool authentication_failed {
            get; private set; default = false;
        }

        /** Determines if the account is prompting for a pasword. */
        internal bool authentication_prompting {
            get; private set; default = false;
        }

        /** Determines if currently prompting for a password. */
        internal uint authentication_attempts {
            get; private set; default = 0;
        }

        /** Determines if any TLS certificate errors have been seen. */
        internal bool tls_validation_failed {
            get; private set; default = false;
        }

        /** Determines if currently prompting about TLS certificate errors. */
        internal bool tls_validation_prompting {
            get; private set; default = false;
        }


        public AccountContext(Geary.Account account,
                              Geary.App.EmailStore emails,
                              Application.ContactStore contacts) {
            this.account = account;
            this.emails = emails;
            this.contacts = contacts;
        }

        /** Returns the current effective status for the account. */
        public Geary.Account.Status get_effective_status() {
            Geary.Account.Status current = this.account.current_status;
            Geary.Account.Status effective = 0;
            if (current.is_online()) {
                effective |= ONLINE;
            }
            if (current.has_service_problem()) {
                // Only retain this flag if the problem isn't auth or
                // cert related, that is handled elsewhere.
                Geary.ClientService.Status incoming =
                    account.incoming.current_status;
                Geary.ClientService.Status outgoing =
                    account.outgoing.current_status;
                if (incoming != AUTHENTICATION_FAILED &&
                    incoming != TLS_VALIDATION_FAILED &&
                    outgoing != AUTHENTICATION_FAILED &&
                    outgoing != TLS_VALIDATION_FAILED) {
                    effective |= SERVICE_PROBLEM;
                }
            }
            return effective;
        }

    }


    /** Determines if the controller is open. */
    public bool is_open {
        get {
            return !this.open_cancellable.is_cancelled();
        }
    }

    /** The primary application instance that owns this controller. */
    public weak GearyApplication application { get; private set; } // circular ref

    /** Account management for the application. */
    public Accounts.Manager account_manager { get; private set; }

    /** Certificate management for the application. */
    public Application.CertificateManager certificate_manager {
        get; private set;
    }

    /** Avatar store for the application. */
    public Application.AvatarStore avatars {
        get; private set; default = new Application.AvatarStore();
    }

    /** Default main window */
    public MainWindow main_window { get; private set; }

    // Primary collection of the application's open accounts
    private Gee.Map<Geary.AccountInformation,AccountContext> accounts =
        new Gee.HashMap<Geary.AccountInformation,AccountContext>();

    // Cancelled if the controller is closed
    private GLib.Cancellable open_cancellable;

    private UpgradeDialog upgrade_dialog;
    private Folks.IndividualAggregator folks;

    private PluginManager plugin_manager;

    private Cancellable cancellable_open_account = new Cancellable();

    // Currently open composers
    private Gee.Collection<Composer.Widget> composer_widgets =
        new Gee.LinkedList<Composer.Widget>();

    // Composers that are in the process of closing
    private Gee.Collection<Composer.Widget> waiting_to_close =
        new Gee.LinkedList<Composer.Widget>();

    // Requested mailto composers not yet fullfulled
    private Gee.List<string?> pending_mailtos = new Gee.ArrayList<string>();


    /**
     * Constructs a new instance of the controller.
     */
    public async Controller(GearyApplication application,
                            GLib.Cancellable cancellable) {
        this.application = application;
        this.open_cancellable = cancellable;

        Geary.Engine engine = this.application.engine;

        // This initializes the IconFactory, important to do before
        // the actions are created (as they refer to some of Geary's
        // custom icons)
        IconFactory.instance.init();

        // Listen for attempts to close the application.
        this.application.exiting.connect(on_application_exiting);

        // Create DB upgrade dialog.
        this.upgrade_dialog = new UpgradeDialog();
        this.upgrade_dialog.notify[UpgradeDialog.PROP_VISIBLE_NAME].connect(
            display_main_window_if_ready
        );

        // Initialise WebKit and WebViews
        ClientWebView.init_web_context(
            this.application.config,
            this.application.get_web_extensions_dir(),
            this.application.get_user_cache_directory().get_child("web-resources")
        );
        try {
            ClientWebView.load_resources(
                this.application.get_user_config_directory()
            );
            Composer.WebView.load_resources();
            ConversationWebView.load_resources();
            Accounts.SignatureWebView.load_resources();
        } catch (Error err) {
            error("Error loading web resources: %s", err.message);
        }

        this.folks = Folks.IndividualAggregator.dup();
        if (!this.folks.is_prepared) {
            // Do this in the background since it can take a long time
            // on some systems and the GUI shouldn't be blocked by it
            this.folks.prepare.begin((obj, res) => {
                    try {
                        this.folks.prepare.end(res);
                    } catch (GLib.Error err) {
                        warning("Error preparing Folks: %s", err.message);
                    }
                });

        }

        this.plugin_manager = new PluginManager(application);
        this.plugin_manager.notifications = new NotificationContext(
            this.avatars,
            this.get_contact_store_for_account,
            this.should_notify_new_messages
        );
        this.plugin_manager.load();

        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow(this.application);
        main_window.retry_service_problem.connect(on_retry_service_problem);

        engine.account_available.connect(on_account_available);

        // Connect to various UI signals.
        this.main_window.folder_list.set_new_messages_monitor(
            this.plugin_manager.notifications
        );

        this.main_window.conversation_list_view.grab_focus();

        // Migrate configuration if necessary.
        try {
            Migrate.xdg_config_dir(this.application.get_user_data_directory(),
                this.application.get_user_config_directory());
        } catch (Error e) {
            error("Error migrating configuration directories: %s", e.message);
        }

        // Hook up cert, accounts and credentials machinery

        this.certificate_manager = yield new Application.CertificateManager(
            this.application.get_user_data_directory().get_child("pinned-certs"),
            cancellable
        );

        SecretMediator? libsecret = null;
        try {
            libsecret = yield new SecretMediator(cancellable);
        } catch (GLib.Error err) {
            error("Error opening libsecret: %s", err.message);
        }

        this.account_manager = new Accounts.Manager(
            libsecret,
            this.application.get_user_config_directory(),
            this.application.get_user_data_directory()
        );
        this.account_manager.account_added.connect(
            on_account_added
        );
        this.account_manager.account_status_changed.connect(
            on_account_status_changed
        );
        this.account_manager.account_removed.connect(
            on_account_removed
        );
        this.account_manager.report_problem.connect(
            on_report_problem
        );

        try {
            yield this.account_manager.connect_goa(cancellable);
        } catch (GLib.Error err) {
            warning("Error opening GOA: %s", err.message);
        }

        // Start the engine and load our accounts
        try {
            yield engine.open_async(
                this.application.get_resource_directory(), cancellable
            );
            yield this.account_manager.load_accounts(cancellable);
        } catch (Error e) {
            warning("Error opening Geary.Engine instance: %s", e.message);
        }

        // Expunge any deleted accounts in the background, so we're
        // not blocking the app continuing to open.
        this.expunge_accounts.begin();
    }

    /** Returns a context for an account, if any. */
    public AccountContext? get_context_for_account(Geary.AccountInformation account) {
        return this.accounts.get(account);
    }

    /** Closes all accounts and windows, releasing held resources. */
    public async void close_async() {
        // Cancel internal processes early so they don't block
        // shutdown
        this.open_cancellable.cancel();

        this.application.engine.account_available.disconnect(on_account_available);

        // Release folder and conversations in the main window
        yield this.main_window.select_folder(null, false);

        // hide window while shutting down, as this can take a few
        // seconds under certain conditions
        this.main_window.hide();

        // Release notification monitoring early so held resources can
        // be freed up
        this.plugin_manager.notifications.clear_folders();

        this.cancellable_open_account.cancel();

        // Create an array of known accounts so the loops below do not
        // explode if accounts are removed while iterating.
        AccountContext[] accounts = this.accounts.values.to_array();

        // Close all Accounts. Launch these in parallel to minimise
        // time taken to close, but here use a barrier to wait for all
        // to actually finish closing.
        Geary.Nonblocking.CountingSemaphore close_barrier =
            new Geary.Nonblocking.CountingSemaphore(null);
        foreach (AccountContext context in accounts) {
            close_barrier.acquire();
            this.close_account.begin(
                context.account.information,
                true,
                (obj, ret) => {
                    this.close_account.end(ret);
                    close_barrier.blind_notify();
                }
            );
        }
        try {
            yield close_barrier.wait_async();
        } catch (Error err) {
            debug("Error waiting at shutdown barrier: %s", err.message);
        }

        // Turn off the lights and lock the door behind you
        try {
            debug("Closing Engine...");
            yield Geary.Engine.instance.close_async(null);
            debug("Closed Engine");
        } catch (Error err) {
            message("Error closing Geary Engine instance: %s", err.message);
        }

        this.account_manager.account_added.disconnect(
            on_account_added
        );
        this.account_manager.account_status_changed.disconnect(
            on_account_status_changed
        );
        this.account_manager.account_removed.disconnect(
            on_account_removed
        );

        if (this.main_window != null) {
            this.application.remove_window(this.main_window);
            this.main_window.destroy();
        }

        this.pending_mailtos.clear();
        this.composer_widgets.clear();
        this.waiting_to_close.clear();

        this.avatars.close();

        debug("Closed Application.Controller");
    }

    /**
     * Opens or queues a new composer addressed to a specific email address.
     */
    public void compose(string? mailto = null) {
        Geary.Account? selected = this.main_window.selected_account;
        if (selected == null) {
            // Schedule the send for after we have an account open.
            this.pending_mailtos.add(mailto);
        } else {
            create_compose_widget(
                selected, NEW_MESSAGE, mailto, null, null, false
            );
        }
    }

    /**
     * Opens new composer with an existing message as context.
     */
    public void compose_with_context_email(Geary.Account account,
                                           Composer.Widget.ComposeType type,
                                           Geary.Email context,
                                           string? quote,
                                           bool is_draft) {
        create_compose_widget(account, type, null, context, quote, is_draft);
    }

    /** Adds a new composer to be kept track of. */
    public void add_composer(Composer.Widget widget) {
        debug(@"Added composer of type $(widget.compose_type); $(this.composer_widgets.size) composers total");
        widget.destroy.connect_after(this.on_composer_widget_destroy);
        this.composer_widgets.add(widget);
    }

    /** Returns a read-only collection of currently open composers .*/
    public Gee.Collection<Composer.Widget> get_composers() {
        return this.composer_widgets.read_only_view;
    }

    /** Opens any pending composers. */
    public void process_pending_composers() {
        foreach (string? mailto in this.pending_mailtos) {
            compose(mailto);
        }
        this.pending_mailtos.clear();
    }

    /** Displays a problem report when an error has been encountered. */
    public void report_problem(Geary.ProblemReport report) {
        debug("Problem reported: %s", report.to_string());

        if (report.error == null ||
            !(report.error.thrown is IOError.CANCELLED)) {
            MainWindowInfoBar info_bar = new MainWindowInfoBar.for_problem(report);
            info_bar.retry.connect(on_retry_problem);
            this.main_window.show_infobar(info_bar);
        }

        Geary.ServiceProblemReport? service_report =
            report as Geary.ServiceProblemReport;
        if (service_report != null && service_report.service.protocol == SMTP) {
            this.application.send_error_notification(
                /// Notification title.
                _("A problem occurred sending email for %s").printf(
                    service_report.account.display_name
                ),
                /// Notification body
                _("Email will not be sent until re-connected")
            );
        }
    }

    /** Returns the contact store for an account, if any. */
    public Application.ContactStore?
        get_contact_store_for_account(Geary.Account target) {
        AccountContext? context = this.accounts.get(target.information);
        return (context != null) ? context.contacts : null;
    }

    /**
     * Updates flags for a collection of conversations.
     *
     * If `prefer_adding` is true, this will add the flag if not set
     * on all conversations or else will remove it. If false, this
     * will remove the flag if not set on all conversations or else
     * add it.
     */
    public async void mark_conversations(Geary.Folder location,
                                         Gee.Collection<Geary.App.Conversation> conversations,
                                         Geary.NamedFlag flag,
                                         bool prefer_adding)
        throws GLib.Error {
        Geary.Iterable<Geary.App.Conversation> selecting =
            Geary.traverse(conversations);
        Geary.EmailFlags flags = new Geary.EmailFlags();

        if (flag.equal_to(Geary.EmailFlags.UNREAD)) {
            selecting = selecting.filter(c => prefer_adding ^ c.is_unread());
            flags.add(Geary.EmailFlags.UNREAD);
        } else if (flag.equal_to(Geary.EmailFlags.FLAGGED)) {
            selecting = selecting.filter(c => prefer_adding ^ c.is_flagged());
            flags.add(Geary.EmailFlags.FLAGGED);
        } else {
            throw new Geary.EngineError.UNSUPPORTED(
                "Marking as %s is not supported", flag.to_string()
            );
        }

        Gee.Collection<Geary.EmailIdentifier>? messages = null;
        Gee.Collection<Geary.App.Conversation> selected =
            selecting.to_linked_list();

        bool do_add = prefer_adding ^ selected.is_empty;
        if (selected.is_empty) {
            selected = conversations;
        }

        if (do_add) {
            // Only apply to the latest in-folder message in
            // conversations that don't already have the flag, since
            // we don't want to flag every message in the conversation
            messages = Geary.traverse(selected).map<Geary.EmailIdentifier>(
                c => c.get_latest_recv_email(IN_FOLDER_OUT_OF_FOLDER).id
            ).to_linked_list();
        } else {
            // Remove the flag from those that have it
            messages = new Gee.LinkedList<Geary.EmailIdentifier>();
            foreach (Geary.App.Conversation convo in selected) {
                foreach (Geary.Email email in
                         convo.get_emails(RECV_DATE_DESCENDING)) {
                    if (email.email_flags != null &&
                        email.email_flags.contains(flag)) {
                        messages.add(email.id);
                    }
                }
            }
        }

        yield mark_messages(
            location,
            conversations,
            messages,
            do_add ? flags : null,
            do_add ? null : flags
        );
    }

    /**
     * Updates flags for a collection of email.
     *
     * This should only be used when working with specific messages
     * (for example, marking a specific message in a conversation)
     * rather than when working with whole conversations. In that
     * case, use {@link mark_conversations}.
     */
    public async void mark_messages(Geary.Folder location,
                                    Gee.Collection<Geary.App.Conversation> conversations,
                                    Gee.Collection<Geary.EmailIdentifier> messages,
                                    Geary.EmailFlags? to_add,
                                    Geary.EmailFlags? to_remove)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(location.account.information);
        if (context != null) {
            yield context.commands.execute(
                new MarkEmailCommand(
                    location,
                    conversations,
                    messages,
                    context.emails,
                    to_add,
                    to_remove,
                    /// Translators: Label for in-app notification
                    ngettext(
                        "Conversation marked",
                        "Conversations marked",
                        conversations.size
                    ),
                    /// Translators: Label for in-app notification
                    ngettext(
                        "Conversation un-marked",
                        "Conversations un-marked",
                        conversations.size
                    )
                ),
                context.cancellable
            );
        }
    }

    public async void move_conversations(Geary.FolderSupport.Move source,
                                         Geary.Folder destination,
                                         Gee.Collection<Geary.App.Conversation> conversations)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(source.account.information);
        if (context != null) {
            yield context.commands.execute(
                new MoveEmailCommand(
                    source,
                    destination,
                    conversations,
                    to_in_folder_email_ids(conversations),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Conversation moved to %s",
                        "Conversations moved to %s",
                        conversations.size
                    ).printf(destination.get_display_name()),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the source folder.
                    ngettext(
                        "Conversation restored to %s",
                        "Conversations restored to %s",
                        conversations.size
                    ).printf(source.get_display_name())
                ),
                context.cancellable
            );
        }
    }

    public async void move_conversations_special(Geary.Folder source,
                                                 Geary.SpecialFolderType destination,
                                                 Gee.Collection<Geary.App.Conversation> conversations)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(source.account.information);
        if (context != null) {
            Command? command = null;
            Gee.Collection<Geary.EmailIdentifier> messages =
                to_in_folder_email_ids(conversations);
            /// Translators: Label for in-app notification. String
            /// substitution is the name of the destination folder.
            string undone_tooltip = ngettext(
                "Conversation restored to %s",
                "Conversations restored to %s",
                messages.size
            ).printf(source.get_display_name());

            if (destination == ARCHIVE) {
                Geary.FolderSupport.Archive? archive_source = (
                    source as Geary.FolderSupport.Archive
                );
                if (archive_source == null) {
                    throw new Geary.EngineError.UNSUPPORTED(
                        "Folder does not support archiving: %s",
                        source.to_string()
                    );
                }
                command = new ArchiveEmailCommand(
                    archive_source,
                    conversations,
                    messages,
                    /// Translators: Label for in-app notification.
                    ngettext(
                        "Conversation archived",
                        "Conversations archived",
                        messages.size
                    ),
                    undone_tooltip
                );
            } else {
                Geary.FolderSupport.Move? move_source = (
                    source as Geary.FolderSupport.Move
                );
                if (move_source == null) {
                    throw new Geary.EngineError.UNSUPPORTED(
                        "Folder does not support moving: %s",
                        source.to_string()
                    );
                }
                Geary.Folder? dest = source.account.get_special_folder(
                    destination
                );
                if (dest == null) {
                    throw new Geary.EngineError.NOT_FOUND(
                        "No folder found for: %s", destination.to_string()
                    );
                }
                command = new MoveEmailCommand(
                    move_source,
                    dest,
                    conversations,
                    messages,
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Conversation moved to %s",
                        "Conversations moved to %s",
                        messages.size
                    ).printf(destination.get_display_name()),
                    undone_tooltip
                );
            }

            yield context.commands.execute(command, context.cancellable);
        }
    }

    public async void move_messages_special(Geary.Folder source,
                                            Geary.SpecialFolderType destination,
                                            Gee.Collection<Geary.App.Conversation> conversations,
                                            Gee.Collection<Geary.EmailIdentifier> messages)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(source.account.information);
        if (context != null) {
            Command? command = null;
            /// Translators: Label for in-app notification. String
            /// substitution is the name of the destination folder.
            string undone_tooltip = ngettext(
                "Message restored to %s",
                "Messages restored to %s",
                messages.size
            ).printf(source.get_display_name());

            if (destination == ARCHIVE) {
                Geary.FolderSupport.Archive? archive_source = (
                    source as Geary.FolderSupport.Archive
                );
                if (archive_source == null) {
                    throw new Geary.EngineError.UNSUPPORTED(
                        "Folder does not support archiving: %s",
                        source.to_string()
                    );
                }
                command = new ArchiveEmailCommand(
                    archive_source,
                    conversations,
                    messages,
                    /// Translators: Label for in-app notification.
                    ngettext(
                        "Message archived",
                        "Messages archived",
                        messages.size
                    ),
                    undone_tooltip
                );
            } else {
                Geary.FolderSupport.Move? move_source = (
                    source as Geary.FolderSupport.Move
                );
                if (move_source == null) {
                    throw new Geary.EngineError.UNSUPPORTED(
                        "Folder does not support moving: %s",
                        source.to_string()
                    );
                }

                Geary.Folder? dest = source.account.get_special_folder(
                    destination
                );
                if (dest == null) {
                    throw new Geary.EngineError.NOT_FOUND(
                        "No folder found for: %s", destination.to_string()
                    );
                }

                command = new MoveEmailCommand(
                    move_source,
                    dest,
                    conversations,
                    messages,
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Message moved to %s",
                        "Messages moved to %s",
                        messages.size
                    ).printf(destination.get_display_name()),
                    undone_tooltip
                );
            }

            yield context.commands.execute(command, context.cancellable);
        }
    }

    public async void copy_conversations(Geary.FolderSupport.Copy source,
                                         Geary.Folder destination,
                                         Gee.Collection<Geary.App.Conversation> conversations)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(source.account.information);
        if (context != null) {
            yield context.commands.execute(
                new CopyEmailCommand(
                    source,
                    destination,
                    conversations,
                    to_in_folder_email_ids(conversations),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Conversation labelled as %s",
                        "Conversations labelled as %s",
                        conversations.size
                    ).printf(destination.get_display_name()),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Conversation un-labelled as %s",
                        "Conversations un-labelled as %s",
                        conversations.size
                    ).printf(destination.get_display_name())
                ),
                context.cancellable
            );
        }
    }

    public async void delete_conversations(Geary.FolderSupport.Remove target,
                                           Gee.Collection<Geary.App.Conversation> conversations)
        throws GLib.Error {
        yield delete_messages(
            target, conversations, to_in_folder_email_ids(conversations)
        );
    }

    public async void delete_messages(Geary.FolderSupport.Remove target,
                                      Gee.Collection<Geary.App.Conversation> conversations,
                                      Gee.Collection<Geary.EmailIdentifier> messages)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(target.account.information);
        if (context != null) {
            Command command = new DeleteEmailCommand(
                target, conversations, messages
            );
            command.executed.connect(
                () => context.controller_stack.email_removed(target, messages)
            );
            yield context.commands.execute(command, context.cancellable);
        }
    }

    public async void empty_folder_special(Geary.Account source,
                                           Geary.SpecialFolderType type)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(source.information);
        if (context != null) {
            Geary.FolderSupport.Empty? emptyable = (
                source.get_special_folder(type)
                as Geary.FolderSupport.Empty
            );
            if (emptyable == null) {
                throw new Geary.EngineError.UNSUPPORTED(
                    "Special folder type not supported %s", type.to_string()
                );
            }

            Command command = new EmptyFolderCommand(emptyable);
            command.executed.connect(
                // Not quite accurate, but close enough
                () => context.controller_stack.folders_removed(
                    Geary.Collection.single(emptyable)
                )
            );
            yield context.commands.execute(command, context.cancellable);
        }
    }

    /** Expunges removed accounts while the controller remains open. */
    internal async void expunge_accounts() {
        try {
            yield this.account_manager.expunge_accounts(this.open_cancellable);
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    private void open_account(Geary.Account account) {
        account.information.authentication_failure.connect(
            on_authentication_failure
        );
        account.information.untrusted_host.connect(on_untrusted_host);
        account.notify["current-status"].connect(
            on_account_status_notify
        );
        account.report_problem.connect(on_report_problem);
        connect_account_async.begin(account, cancellable_open_account);
    }

    private async void close_account(Geary.AccountInformation config,
                                     bool is_shutdown) {
        AccountContext? context = this.accounts.get(config);
        if (context != null) {
            debug("Closing account: %s", context.account.information.id);
            Geary.Account account = context.account;

            // Guard against trying to close the account twice
            this.accounts.unset(account.information);

            // Stop updating status and showing errors when closing
            // the account - the user doesn't care any more
            account.report_problem.disconnect(on_report_problem);
            account.information.authentication_failure.disconnect(
                on_authentication_failure
            );
            account.information.untrusted_host.disconnect(on_untrusted_host);
            account.notify["current-status"].disconnect(
                on_account_status_notify
            );

            account.email_removed.disconnect(on_account_email_removed);
            account.folders_available_unavailable.disconnect(on_folders_available_unavailable);

            Geary.Smtp.ClientService? smtp = (
                account.outgoing as Geary.Smtp.ClientService
            );
            if (smtp != null) {
                smtp.email_sent.disconnect(on_sent);
                smtp.sending_monitor.start.disconnect(on_sending_started);
                smtp.sending_monitor.finish.disconnect(on_sending_finished);
            }

            // Now the account is not in the accounts map, reset any
            // status notifications for it
            update_account_status();

            // If we're not shutting down, select the inbox of the
            // first account so that we show something other than
            // empty conversation list/viewer.
            Geary.Folder? to_select = null;
            if (!is_shutdown) {
                Geary.AccountInformation? first_account = get_first_account();
                if (first_account != null) {
                    AccountContext? first_context = this.accounts[first_account];
                    if (first_context != null) {
                        to_select = first_context.inbox;
                    }
                }
            }

            yield this.main_window.remove_account(account, to_select);

            context.cancellable.cancel();
            context.contacts.close();

            // Explicitly close the inbox since we explicitly open it
            Geary.Folder? inbox = context.inbox;
            if (inbox != null) {
                try {
                    yield inbox.close_async(null);
                } catch (Error close_inbox_err) {
                    debug("Unable to close monitored inbox: %s", close_inbox_err.message);
                }
                context.inbox = null;
            }

            try {
                yield account.close_async(null);
            } catch (Error close_err) {
                debug("Unable to close account %s: %s", account.to_string(), close_err.message);
            }

            debug("Account closed: %s", account.to_string());
        }
    }

    private void update_account_status() {
        // Start off assuming all accounts are online and error free
        // (i.e. no status issues to indicate) and proceed until
        // proven incorrect.
        Geary.Account.Status effective_status = ONLINE;
        bool has_auth_error = false;
        bool has_cert_error = false;
        Geary.Account? service_problem_source = null;
        foreach (AccountContext context in this.accounts.values) {
            Geary.Account.Status status = context.get_effective_status();
            if (!status.is_online()) {
                effective_status &= ~Geary.Account.Status.ONLINE;
            }
            if (status.has_service_problem()) {
                effective_status |= SERVICE_PROBLEM;
                if (service_problem_source == null) {
                    service_problem_source = context.account;
                }
            }
            has_auth_error |= context.authentication_failed;
            has_cert_error |= context.tls_validation_failed;
        }

        foreach (Gtk.Window window in this.application.get_windows()) {
            MainWindow? main = window as MainWindow;
            if (main != null) {
                main.update_account_status(
                    effective_status,
                    has_auth_error,
                    has_cert_error,
                    service_problem_source
                );
            }
        }
    }

    private bool is_currently_prompting() {
        return this.accounts.values.fold<bool>(
            (ctx, seed) => (
                ctx.authentication_prompting |
                ctx.tls_validation_prompting |
                seed
            ),
            false
        );
    }

    private async void prompt_for_password(AccountContext context,
                                           Geary.ServiceInformation service) {
        Geary.AccountInformation account = context.account.information;
        bool is_incoming = (service == account.incoming);
        Geary.Credentials credentials = is_incoming
            ? account.incoming.credentials
            : account.get_outgoing_credentials();

        bool handled = true;
        if (context.authentication_attempts > MAX_AUTH_ATTEMPTS ||
            credentials == null) {
            // We have run out of authentication attempts or have
            // been asked for creds but don't even have a login. So
            // just bail out immediately and flag the account as
            // needing attention.
            handled = false;
        } else if (this.account_manager.is_goa_account(account)) {
            context.authentication_prompting = true;
            try {
                yield account.load_incoming_credentials(context.cancellable);
                yield account.load_outgoing_credentials(context.cancellable);
            } catch (GLib.Error err) {
                // Bail out right away, but probably should be opening
                // the GOA control panel.
                handled = false;
                report_problem(new Geary.AccountProblemReport(account, err));
            }
            context.authentication_prompting = false;
        } else {
            context.authentication_prompting = true;
            PasswordDialog password_dialog = new PasswordDialog(
                this.application.get_active_window(),
                account,
                service,
                credentials
            );
            if (password_dialog.run()) {
                // The update the credentials for the service that the
                // credentials actually came from
                Geary.ServiceInformation creds_service =
                    (credentials == account.incoming.credentials)
                    ? account.incoming
                    : account.outgoing;
                creds_service.credentials = credentials.copy_with_token(
                    password_dialog.password
                );

                // Update the remember password pref if changed
                bool remember = password_dialog.remember_password;
                if (creds_service.remember_password != remember) {
                    creds_service.remember_password = remember;
                    account.changed();
                }

                SecretMediator libsecret = (SecretMediator) account.mediator;
                try {
                    // Update the secret using the service where the
                    // credentials originated, since the service forms
                    // part of the key's identity
                    if (creds_service.remember_password) {
                        yield libsecret.update_token(
                            account, creds_service, context.cancellable
                        );
                    } else {
                        yield libsecret.clear_token(
                            account, creds_service, context.cancellable
                        );
                    }
                } catch (GLib.IOError.CANCELLED err) {
                    // all good
                } catch (GLib.Error err) {
                    report_problem(
                        new Geary.ServiceProblemReport(account, service, err)
                    );
                }

                context.authentication_attempts++;
            } else {
                // User cancelled, bail out unconditionally
                handled = false;
            }
            context.authentication_prompting = false;
        }

        if (handled) {
            try {
                yield this.application.engine.update_account_service(
                    account, service, context.cancellable
                );
            } catch (GLib.Error err) {
                report_problem(
                    new Geary.ServiceProblemReport(account, service, err)
                );
            }
        } else {
            context.authentication_attempts = 0;
            context.authentication_failed = true;
            update_account_status();
        }
    }

    private async void prompt_untrusted_host(AccountContext context,
                                             Geary.ServiceInformation service,
                                             Geary.Endpoint endpoint,
                                             GLib.TlsConnection cx) {
        if (this.application.config.revoke_certs) {
            // XXX
        }

        context.tls_validation_prompting = true;
        try {
            yield this.certificate_manager.prompt_pin_certificate(
                this.main_window,
                context.account.information,
                service,
                endpoint,
                false,
                context.cancellable
            );
            context.tls_validation_failed = false;
        } catch (Application.CertificateManagerError.UNTRUSTED err) {
            // Don't report an error here, the user simply declined.
            context.tls_validation_failed = true;
        } catch (Application.CertificateManagerError err) {
            // Assume validation is now good, but report the error
            // since the cert may not have been saved
            context.tls_validation_failed = false;
            report_problem(
                new Geary.ServiceProblemReport(
                    context.account.information,
                    service,
                    err
                )
            );
        }

        context.tls_validation_prompting = false;
        update_account_status();
    }

    private void on_account_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        if (folder.special_folder_type == Geary.SpecialFolderType.OUTBOX) {
            main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SEND_FAILURE);
            main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SAVE_SENT_MAIL_FAILED);
        }
    }

    private void on_sending_started() {
        main_window.status_bar.activate_message(StatusBar.Message.OUTBOX_SENDING);
    }

    private void on_sending_finished() {
        main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SENDING);
    }

    private async void connect_account_async(Geary.Account account, Cancellable? cancellable = null) {
        AccountContext context = new AccountContext(
            account,
            new Geary.App.EmailStore(account),
            new Application.ContactStore(account, this.folks)
        );

        // XXX Need to set this early since
        // on_folders_available_unavailable expects it to be there
        this.accounts.set(account.information, context);

        account.email_removed.connect(on_account_email_removed);
        account.folders_available_unavailable.connect(on_folders_available_unavailable);

        Geary.Smtp.ClientService? smtp = (
            account.outgoing as Geary.Smtp.ClientService
        );
        if (smtp != null) {
            smtp.email_sent.connect(on_sent);
            smtp.sending_monitor.start.connect(on_sending_started);
            smtp.sending_monitor.finish.connect(on_sending_finished);
        }

        bool retry = false;
        do {
            try {
                account.set_data(PROP_ATTEMPT_OPEN_ACCOUNT, true);
                yield account.open_async(cancellable);
                retry = false;
            } catch (Error open_err) {
                debug("Unable to open account %s: %s", account.to_string(), open_err.message);

                if (open_err is Geary.EngineError.CORRUPT) {
                    retry = yield account_database_error_async(account);
                }

                if (!retry) {
                    report_problem(
                        new Geary.AccountProblemReport(
                            account.information,
                            open_err
                        )
                    );

                    this.account_manager.disable_account(account.information);
                    this.accounts.unset(account.information);
                }
            }
        } while (retry);

        main_window.folder_list.set_user_folders_root_name(account, _("Labels"));
        display_main_window_if_ready();
        update_account_status();
    }

    // Returns true if the caller should try opening the account again
    private async bool account_database_error_async(Geary.Account account) {
        bool retry = true;

        // give the user two options: reset the Account local store, or exit Geary.  A third
        // could be done to leave the Account in an unopened state, but we don't currently
        // have provisions for that.
        QuestionDialog dialog = new QuestionDialog(main_window,
            _("Unable to open the database for %s").printf(account.information.id),
            _("There was an error opening the local mail database for this account. This is possibly due to corruption of the database file in this directory:\n\n%s\n\nGeary can rebuild the database and re-synchronize with the server or exit.\n\nRebuilding the database will destroy all local email and its attachments. <b>The mail on the your server will not be affected.</b>")
                .printf(account.information.data_dir.get_path()),
            _("_Rebuild"), _("E_xit"));
        dialog.use_secondary_markup(true);
        switch (dialog.run()) {
            case Gtk.ResponseType.OK:
                // don't use Cancellable because we don't want to interrupt this process
                try {
                    yield account.rebuild_async();
                } catch (Error err) {
                    ErrorDialog errdialog = new ErrorDialog(main_window,
                        _("Unable to rebuild database for “%s”").printf(account.information.id),
                        _("Error during rebuild:\n\n%s").printf(err.message));
                    errdialog.run();

                    retry = false;
                }
            break;

            default:
                retry = false;
            break;
        }

        return retry;
    }

    /**
     * Returns true if we've attempted to open all accounts at this point.
     */
    private bool did_attempt_open_all_accounts() {
        try {
            foreach (Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
                Geary.Account a = Geary.Engine.instance.get_account_instance(info);
                if (a.get_data<bool?>(PROP_ATTEMPT_OPEN_ACCOUNT) == null)
                    return false;
            }
        } catch(Error e) {
            error("Could not open accounts: %s", e.message);
        }

        return true;
    }

    /**
     * Displays the main window if we're ready.  Otherwise does nothing.
     */
    private void display_main_window_if_ready() {
        if (did_attempt_open_all_accounts() &&
            !upgrade_dialog.visible &&
            !cancellable_open_account.is_cancelled() &&
            !this.application.is_background_service)
            main_window.show();
    }

    /**
     * Returns the number of accounts that exist in Geary.  Note that not all accounts may be
     * open.  Zero is returned on an error.
     */
    public int get_num_accounts() {
        try {
            return Geary.Engine.instance.get_accounts().size;
        } catch (Error e) {
            debug("Error getting number of accounts: %s", e.message);
        }

        return 0; // on error
    }

    private bool is_inbox_descendant(Geary.Folder target) {
        bool is_descendent = false;

        Geary.Account account = target.account;
        Geary.Folder? inbox = account.get_special_folder(Geary.SpecialFolderType.INBOX);

        if (inbox != null) {
            is_descendent = inbox.path.is_descendant(target.path);
        }
        return is_descendent;
    }

    private void on_special_folder_type_changed(Geary.Folder folder,
                                                Geary.SpecialFolderType old_type,
                                                Geary.SpecialFolderType new_type) {
        Geary.AccountInformation info = folder.account.information;

        // Update the main window
        this.main_window.folder_list.remove_folder(folder);
        this.main_window.folder_list.add_folder(folder);
        // Since removing the folder will also remove its children
        // from the folder list, we need to check for any and re-add
        // them. See issue #11.
        try {
            foreach (Geary.Folder child in
                     folder.account.list_matching_folders(folder.path)) {
                main_window.folder_list.add_folder(child);
            }
        } catch (Error err) {
            // Oh well
        }

        // Update notifications
        this.plugin_manager.notifications.remove_folder(folder);
        if (folder.special_folder_type == Geary.SpecialFolderType.INBOX ||
            (folder.special_folder_type == Geary.SpecialFolderType.NONE &&
             is_inbox_descendant(folder))) {
            this.plugin_manager.notifications.add_folder(
                folder, this.accounts.get(info).cancellable
            );
        }
    }

    private void on_folders_available_unavailable(
        Geary.Account account,
        Gee.BidirSortedSet<Geary.Folder>? available,
        Gee.BidirSortedSet<Geary.Folder>? unavailable) {
        AccountContext context = this.accounts.get(account.information);

        if (available != null && available.size > 0) {
            foreach (Geary.Folder folder in available) {
                if (!should_add_folder(available, folder)) {
                    continue;
                }
                folder.special_folder_type_changed.connect(on_special_folder_type_changed);
                this.main_window.add_folder(folder);

                GLib.Cancellable cancellable = context.cancellable;
                switch (folder.special_folder_type) {
                case Geary.SpecialFolderType.INBOX:
                    // Special case handling of inboxes
                    if (context.inbox == null) {
                        context.inbox = folder;

                        // Select this inbox if there isn't an
                        // existing folder selected and it is the
                        // inbox for the first account
                        if (!this.main_window.folder_list.is_any_selected() &&
                            folder.account.information == get_first_account()) {
                            // First we try to select the Inboxes branch inbox if
                            // it's there, falling back to the main folder list.
                            if (!main_window.folder_list.select_inbox(folder.account))
                                main_window.folder_list.select_folder(folder);
                        }
                    }

                    folder.open_async.begin(Geary.Folder.OpenFlags.NO_DELAY, cancellable);

                    // Always notify for new messages in the Inbox
                    this.plugin_manager.notifications.add_folder(
                        folder, cancellable
                    );
                    break;

                case Geary.SpecialFolderType.NONE:
                    // Only notify for new messages in non-special
                    // descendants of the Inbox
                    if (is_inbox_descendant(folder)) {
                        this.plugin_manager.notifications.add_folder(
                            folder, cancellable
                        );
                    }
                    break;
                }
            }
        }

        if (unavailable != null) {
            Gee.BidirIterator<Geary.Folder> unavailable_iterator =
                unavailable.bidir_iterator();
            bool has_prev = unavailable_iterator.last();
            while (has_prev) {
                Geary.Folder folder = unavailable_iterator.get();
                folder.special_folder_type_changed.disconnect(on_special_folder_type_changed);
                this.main_window.remove_folder(folder);

                switch (folder.special_folder_type) {
                case Geary.SpecialFolderType.INBOX:
                    context.inbox = null;
                    this.plugin_manager.notifications.remove_folder(folder);
                    break;

                case Geary.SpecialFolderType.NONE:
                    // Only notify for new messages in non-special
                    // descendants of the Inbox
                    if (is_inbox_descendant(folder)) {
                        this.plugin_manager.notifications.remove_folder(folder);
                    }
                    break;
                }

                has_prev = unavailable_iterator.previous();
            }

            // Notify the command stack that folders have gone away
            context.controller_stack.folders_removed(unavailable);
        }
    }

    // We need to include the second parameter, or valac doesn't recognize the function as matching
    // GearyApplication.exiting's signature.
    private bool on_application_exiting(GearyApplication sender, bool panicked) {
        if (close_composition_windows())
            return true;

        return sender.cancel_exit();
    }

    private bool should_notify_new_messages(Geary.Folder folder) {
        // A monitored folder must be selected to squelch notifications;
        // if conversation list is at top of display, don't display
        // and don't display if main window has top-level focus
        return (
            folder != this.main_window.selected_folder ||
            this.main_window.conversation_list_view.vadjustment.value != 0.0 ||
            !this.main_window.has_toplevel_focus
        );
    }

    // Clears messages if conditions are true: anything in should_notify_new_messages() is
    // false and the supplied visible messages are visible in the conversation list view
    public void clear_new_messages(string caller,
                                   Gee.Set<Geary.App.Conversation>? supplied) {
        Geary.Folder? selected = this.main_window.selected_folder;
        NotificationContext notifications = this.plugin_manager.notifications;
        if (selected != null && (
                !notifications.get_folders().contains(selected) ||
                should_notify_new_messages(selected))) {

            Gee.Set<Geary.App.Conversation> visible =
                supplied ?? main_window.conversation_list_view.get_visible_conversations();

            foreach (Geary.App.Conversation conversation in visible) {
                try {
                    if (notifications.are_any_new_messages(selected,
                                                           conversation.get_email_ids())) {
                        debug("Clearing new messages: %s", caller);
                        notifications.clear_new_messages(selected);
                        break;
                    }
                } catch (Geary.EngineError.NOT_FOUND err) {
                    // all good
                }
            }
        }
    }

    /** Displays a composer on the last active main window. */
    internal void show_composer(Composer.Widget composer,
                                Gee.Collection<Geary.EmailIdentifier>? refers_to) {
        this.main_window.show_composer(composer, refers_to);
        composer.set_focus();
    }

    internal bool close_composition_windows() {
        // Take a copy of the collection of composers since closing
        // any will cause the underlying collection to change.
        var composers = new Gee.LinkedList<Composer.Widget>();
        composers.add_all(this.composer_widgets);
        bool quit_cancelled = false;

        foreach (var composer in composers) {
            if (composer.current_mode == NONE) {
                // Composer currently isn't being presented at all
                // (it's probably in the undo stack), so just close it
                this.waiting_to_close.add(composer);
                composer.close.begin();
            } else {
                switch (composer.confirm_close()) {
                case Composer.Widget.CloseStatus.PENDING:
                    this.waiting_to_close.add(composer);
                    break;

                case Composer.Widget.CloseStatus.CANCELLED:
                    quit_cancelled = true;
                    break;
                }
            }
        }

        // If we cancelled the quit we can bail here.
        if (quit_cancelled) {
            this.waiting_to_close.clear();
            return false;
        }

        // If there's still windows saving, we can't exit just yet.
        if (this.waiting_to_close.size > 0) {
            this.main_window.set_sensitive(false);
            return false;
        }

        // If we deleted all composer windows without the user
        // cancelling, we can exit.
        return true;
    }

    /**
     * Creates a composer widget.
     *
     * Depending on the arguments, this can be inline in the
     * conversation or as a new window.
     *
     * @param compose_type - Whether it's a new message, a reply, a
     * forwarded mail, ...
     * @param referred - The mail of which we should copy the from/to/...
     * addresses
     * @param quote - The quote after the mail body
     * @param mailto - A "mailto:"-link
     * @param is_draft - Whether we're starting from a draft (true) or
     * a new mail (false)
     */
    private void create_compose_widget(Geary.Account account,
                                       Composer.Widget.ComposeType compose_type,
                                       string? mailto,
                                       Geary.Email? referred,
                                       string? quote,
                                       bool is_draft) {
        // There's a few situations where we can re-use an existing
        // composer, check for these first.
        if (compose_type == NEW_MESSAGE && !is_draft) {
            // We're creating a new message that isn't a draft, if
            // there's already a composer open, just use that
            Composer.Widget? existing =
                this.main_window.conversation_viewer.current_composer;
            if (existing != null &&
                existing.current_mode == PANED &&
                existing.is_blank) {
                existing.present();
                return;
            }
        } else if (compose_type != NEW_MESSAGE && referred != null) {
            // A reply/forward was requested, see whether there is
            // already an inline message that is either a
            // reply/forward for that message, or there is a quote
            // to insert into it.
            foreach (Composer.Widget existing in this.composer_widgets) {
                if ((existing.current_mode == INLINE ||
                     existing.current_mode == INLINE_COMPACT) &&
                    (referred.id in existing.get_referred_ids() ||
                     quote != null)) {
                    try {
                        existing.append_to_email(referred, quote, compose_type);
                        existing.present();
                        return;
                    } catch (Geary.EngineError error) {
                        report_problem(new Geary.ProblemReport(error));
                    }
                }
            }

            // Can't re-use an existing composer, so need to create a
            // new one. Replies must open inline in the main window,
            // so we need to ensure there are no composers open there
            // first.
            if (!this.main_window.close_composer()) {
                return;
            }
        }

        Composer.Widget widget;
        if (mailto != null) {
            widget = new Composer.Widget.from_mailto(
                this.application, account, mailto
            );
        } else {
            widget = new Composer.Widget(
                this.application, account, compose_type
            );
        }

        add_composer(widget);
        show_composer(
            widget,
            referred != null ? Geary.Collection.single(referred.id) : null
        );

        this.load_composer.begin(
            account,
            widget,
            referred,
            is_draft,
            quote
        );
    }

    private async void load_composer(Geary.Account account,
                                     Composer.Widget widget,
                                     Geary.Email? referred = null,
                                     bool is_draft,
                                     string? quote = null) {
        Geary.Email? full = null;
        GLib.Cancellable? cancellable = null;
        if (referred != null) {
            AccountContext? context = this.accounts.get(account.information);
            if (context != null) {
                cancellable = context.cancellable;
                try {
                    full = yield context.emails.fetch_email_async(
                        referred.id,
                        Geary.ComposedEmail.REQUIRED_REPLY_FIELDS |
                        Composer.Widget.REQUIRED_FIELDS,
                        NONE,
                        cancellable
                    );
                } catch (Error e) {
                    message("Could not load full message: %s", e.message);
                }
            }
        }
        try {
            yield widget.load(full, is_draft, quote, cancellable);
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    private void on_composer_widget_destroy(Gtk.Widget sender) {
        composer_widgets.remove((Composer.Widget) sender);
        debug(@"Destroying composer of type $(((Composer.Widget) sender).compose_type); "
            + @"$(composer_widgets.size) composers remaining");

        if (waiting_to_close.remove((Composer.Widget) sender)) {
            // If we just removed the last window in the waiting to close list, it's time to exit!
            if (waiting_to_close.size == 0)
                this.application.exit();
        }
    }

        // Translators: The label for an in-app notification. The
        // string substitution is a list of recipients of the email.
    private void on_sent(Geary.Smtp.ClientService service,
                         Geary.RFC822.Message sent) {
        string message = _(
            "Successfully sent mail to %s."
        ).printf(Util.Email.to_short_recipient_display(sent));
        Components.InAppNotification notification =
            new Components.InAppNotification(message);
        this.main_window.add_notification(notification);

        AccountContext? context = this.accounts.get(service.account);
        if (context != null) {
            this.plugin_manager.notifications.email_sent(context.account, sent);
        }
    }

    // Returns a list of composer windows for an account, or null if none.
    public Gee.List<Composer.Widget>? get_composer_widgets_for_account(Geary.AccountInformation account) {
        Gee.LinkedList<Composer.Widget> ret = Geary.traverse<Composer.Widget>(composer_widgets)
            .filter(w => w.account.information == account)
            .to_linked_list();

        return ret.size >= 1 ? ret : null;
    }

    private Geary.AccountInformation? get_first_account() {
        return this.accounts.keys.iterator().fold<Geary.AccountInformation?>(
            (next, prev) => {
                return prev == null || next.ordinal < prev.ordinal ? next : prev;
            },
            null
        );
    }

    private bool should_add_folder(Gee.Collection<Geary.Folder>? all,
                                   Geary.Folder folder) {
        // if folder is openable, add it
        if (folder.properties.is_openable != Geary.Trillian.FALSE)
            return true;
        else if (folder.properties.has_children == Geary.Trillian.FALSE)
            return false;

        // if folder contains children, we must ensure that there is at least one of the same type
        Geary.SpecialFolderType type = folder.special_folder_type;
        foreach (Geary.Folder other in all) {
            if (other.special_folder_type == type && other.path.parent == folder.path)
                return true;
        }

        return false;
    }

    private Gee.Collection<Geary.EmailIdentifier>
        to_in_folder_email_ids(Gee.Collection<Geary.App.Conversation> conversations) {
        Gee.Collection<Geary.EmailIdentifier> messages =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        foreach (Geary.App.Conversation conversation in conversations) {
            foreach (Geary.Email email in
                     conversation.get_emails(RECV_DATE_ASCENDING, IN_FOLDER)) {
                messages.add(email.id);
            }
        }
        return messages;
    }

    private void on_account_available(Geary.AccountInformation info) {
        Geary.Account? account = null;
        try {
            account = Geary.Engine.instance.get_account_instance(info);
        } catch (Error e) {
            error("Error creating account instance: %s", e.message);
        }

        if (account != null) {
            upgrade_dialog.add_account(account, cancellable_open_account);
            open_account(account);
        }
    }

    private void on_account_added(Geary.AccountInformation added,
                                  Accounts.Manager.Status status) {
        if (status == Accounts.Manager.Status.ENABLED) {
            try {
                this.application.engine.add_account(added);
            } catch (GLib.Error err) {
                report_problem(new Geary.AccountProblemReport(added, err));
            }
        }
    }

    private void on_account_status_changed(Geary.AccountInformation changed,
                                           Accounts.Manager.Status status) {
        switch (status) {
        case Accounts.Manager.Status.ENABLED:
            if (!this.application.engine.has_account(changed.id)) {
                try {
                    this.application.engine.add_account(changed);
                } catch (GLib.Error err) {
                    report_problem(new Geary.AccountProblemReport(changed, err));
                }
            }
            break;

        case Accounts.Manager.Status.UNAVAILABLE:
        case Accounts.Manager.Status.DISABLED:
            if (this.application.engine.has_account(changed.id)) {
                this.close_account.begin(
                    changed,
                    false,
                    (obj, res) => {
                        this.close_account.end(res);
                        try {
                            this.application.engine.remove_account(changed);
                        } catch (GLib.Error err) {
                            report_problem(
                                new Geary.AccountProblemReport(changed, err)
                            );
                        }
                    }
                );
            }
            break;
        }
    }

    private void on_account_removed(Geary.AccountInformation removed) {
        debug("%s: Closing account for removal", removed.id);
        this.close_account.begin(
            removed,
            false,
            (obj, res) => {
                this.close_account.end(res);
                debug("%s: Account closed", removed.id);
                try {
                    this.application.engine.remove_account(removed);
                    debug("%s: Account removed from engine", removed.id);
                } catch (GLib.Error err) {
                    report_problem(
                        new Geary.AccountProblemReport(removed, err)
                    );
                }
            }
        );
    }

    private void on_report_problem(Geary.ProblemReport problem) {
        report_problem(problem);
    }

    private void on_retry_problem(MainWindowInfoBar info_bar) {
        Geary.ServiceProblemReport? service_report =
            info_bar.report as Geary.ServiceProblemReport;
        if (service_report != null) {
            AccountContext? context = this.accounts.get(service_report.account);
            if (context != null && context.account.is_open()) {
                switch (service_report.service.protocol) {
                case Geary.Protocol.IMAP:
                    context.account.incoming.restart.begin(context.cancellable);
                    break;

                case Geary.Protocol.SMTP:
                    context.account.outgoing.restart.begin(context.cancellable);
                    break;
                }
            }
        }
    }

    private void on_account_status_notify() {
        update_account_status();
    }

    private void on_authentication_failure(Geary.AccountInformation account,
                                           Geary.ServiceInformation service) {
        AccountContext? context = this.accounts.get(account);
        if (context != null && !is_currently_prompting()) {
            this.prompt_for_password.begin(context, service);
        }
    }

    private void on_untrusted_host(Geary.AccountInformation account,
                                   Geary.ServiceInformation service,
                                   Geary.Endpoint endpoint,
                                   TlsConnection cx) {
        AccountContext? context = this.accounts.get(account);
        if (context != null && !is_currently_prompting()) {
            this.prompt_untrusted_host.begin(context, service, endpoint, cx);
        }
    }

    private void on_retry_service_problem(Geary.ClientService.Status type) {
        bool has_restarted = false;
        foreach (AccountContext context in this.accounts.values) {
            Geary.Account account = context.account;
            if (account.current_status.has_service_problem() &&
                (account.incoming.current_status == type ||
                 account.outgoing.current_status == type)) {

                Geary.ClientService service =
                    (account.incoming.current_status == type)
                        ? account.incoming
                        : account.outgoing;

                bool do_restart = true;
                switch (type) {
                case AUTHENTICATION_FAILED:
                    if (has_restarted) {
                        // Only restart at most one at a time, so we
                        // don't attempt to re-auth multiple bad
                        // accounts at once.
                        do_restart = false;
                    } else {
                        // Reset so the infobar does not show up again
                        context.authentication_failed = false;
                    }
                    break;

                case TLS_VALIDATION_FAILED:
                    if (has_restarted) {
                        // Only restart at most one at a time, so we
                        // don't attempt to re-pin multiple bad
                        // accounts at once.
                        do_restart = false;
                    } else {
                        // Reset so the infobar does not show up again
                        context.tls_validation_failed = false;
                    }
                    break;
                }

                if (do_restart) {
                    has_restarted = true;
                    service.restart.begin(context.cancellable);
                }
            }
        }
    }

}


/** Base class for all application controller commands. */
internal class Application.ControllerCommandStack : CommandStack {


    private EmailCommand? last_executed = null;


    /** {@inheritDoc} */
    public override async void execute(Command target,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Guard against things like Delete being held down by only
        // executing a command if it is different to the last one.
        if (this.last_executed == null || !this.last_executed.equal_to(target)) {
            this.last_executed = target as EmailCommand;
            yield base.execute(target, cancellable);
        }
    }

    /** {@inheritDoc} */
    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.last_executed = null;
        yield base.undo(cancellable);
    }

    /** {@inheritDoc} */
    public override async void redo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.last_executed = null;
        yield base.redo(cancellable);
    }

    /**
     * Notifies the stack that one or more folders were removed.
     *
     * This will cause any commands involving the given folder to be
     * removed from the stack. It should only be called as a response
     * to un-recoverable changes, e.g. when the server notifies that a
     * folder has been removed.
     */
    internal void folders_removed(Gee.Collection<Geary.Folder> removed) {
        Gee.Iterator<Command> commands = this.undo_stack.iterator();
        while (commands.next()) {
            EmailCommand? email = commands.get() as EmailCommand;
            if (email != null) {
                if (email.folders_removed(removed) == REMOVE) {
                    commands.remove();
                }
            }
        }
    }

    /**
     * Notifies the stack that email was removed from a folder.
     *
     * This will cause any commands involving the given email
     * identifiers to be removed from commands where they are present,
     * potentially also causing the command to be removed from the
     * stack. It should only be called as a response to un-recoverable
     * changes, e.g. when the server notifies that an email has been
     * removed as a result of some other client removing it, or the
     * message being deleted completely.
     */
    internal void email_removed(Geary.Folder location,
                                Gee.Collection<Geary.EmailIdentifier> targets) {
        Gee.Iterator<Command> commands = this.undo_stack.iterator();
        while (commands.next()) {
            EmailCommand? email = commands.get() as EmailCommand;
            if (email != null) {
                if (email.email_removed(location, targets) == REMOVE) {
                    commands.remove();
                }
            }
        }
    }

}


/** Base class for email-related commands. */
public abstract class Application.EmailCommand : Command {


    /** Specifies a command's response to external mail state changes. */
    public enum StateChangePolicy {
        /** The change can be ignored */
        IGNORE,

        /** The command is no longer valid and should be removed */
        REMOVE;
    }


    /**
     * Returns the folder where the command was initially executed.
     *
     * This is used by the main window to return to the folder where
     * the command was first carried out.
     */
    public Geary.Folder location {
        get; protected set;
    }

    /**
     * Returns the conversations which the command was initially applied to.
     *
     * This is used by the main window to return to the conversation where
     * the command was first carried out.
     */
    public Gee.Collection<Geary.App.Conversation> conversations {
        get; private set;
    }

    /**
     * Returns the email which the command was initially applied to.
     *
     * This is used by the main window to return to the conversation where
     * the command was first carried out.
     */
    public Gee.Collection<Geary.EmailIdentifier> email {
        get; private set;
    }

    private Gee.Collection<Geary.App.Conversation> mutable_conversations;
    private Gee.Collection<Geary.EmailIdentifier> mutable_email;


    protected EmailCommand(Geary.Folder location,
                           Gee.Collection<Geary.App.Conversation> conversations,
                           Gee.Collection<Geary.EmailIdentifier> email) {
        this.location = location;
        this.conversations = conversations.read_only_view;
        this.email = email.read_only_view;

        this.mutable_conversations = conversations;
        this.mutable_email = email;
    }


    public override bool equal_to(Command other) {
        if (this == other) {
            return true;
        }

        if (this.get_type() != other.get_type()) {
            return false;
        }

        EmailCommand? other_email = other as EmailCommand;
        if (other_email == null) {
            return false;
        }

        return (
            this.location == other_email.location &&
            this.conversations.size == other_email.conversations.size &&
            this.email.size == other_email.email.size &&
            this.conversations.contains_all(other_email.conversations) &&
            this.email.contains_all(other_email.email)
        );
    }

    /**
     * Determines the command's response when a folder is removed.
     *
     * This is called when some external means (such as another
     * command, or another email client altogether) has caused a
     * folder to be removed.
     *
     * The returned policy will determine if the command is unaffected
     * by the change and hence can remain on the stack, or is no
     * longer valid and hence must be removed.
     */
    internal virtual StateChangePolicy folders_removed(
        Gee.Collection<Geary.Folder> removed
    ) {
        return (
            this.location in removed
            ? StateChangePolicy.REMOVE
            : StateChangePolicy.IGNORE
        );
    }

    /**
     * Determines the command's response when email is removed.
     *
     * This is called when some external means (such as another
     * command, or another email client altogether) has caused a
     * email in a folder to be removed.
     *
     * The returned policy will determine if the command is unaffected
     * by the change and hence can remain on the stack, or is no
     * longer valid and hence must be removed.
     */
    internal virtual StateChangePolicy email_removed(
        Geary.Folder location,
        Gee.Collection<Geary.EmailIdentifier> targets
    ) {
        StateChangePolicy ret = IGNORE;
        if (this.location == location) {
            // Any removed email should have already been removed from
            // their conversations by the time we here, so just remove
            // any conversations that don't have any messages left.
            Gee.Iterator<Geary.App.Conversation> conversations =
                this.mutable_conversations.iterator();
            while (conversations.next()) {
                var conversation = conversations.get();
                if (!conversation.has_any_non_deleted_email()) {
                    conversations.remove();
                }
            }

            // Update message set to remove all removed messages
            this.mutable_email.remove_all(targets);

            // If we have no more conversations or messages, then the
            // command won't be able to do anything and should be
            // removed.
            if (this.mutable_conversations.is_empty ||
                this.mutable_email.is_empty) {
                ret = REMOVE;
            }
        }
        return ret;
    }

}


/**
 * Mixin for trivial application commands.
 *
 * Trivial commands should not cause a notification to be shown when
 * initially executed.
 */
public interface Application.TrivialCommand : Command {

}


private class Application.MarkEmailCommand : TrivialCommand, EmailCommand {


    private Geary.App.EmailStore store;
    private Geary.EmailFlags? to_add;
    private Geary.EmailFlags? to_remove;


    public MarkEmailCommand(Geary.Folder location,
                            Gee.Collection<Geary.App.Conversation> conversations,
                            Gee.Collection<Geary.EmailIdentifier> messages,
                            Geary.App.EmailStore store,
                            Geary.EmailFlags? to_add,
                            Geary.EmailFlags? to_remove,
                            string? executed_label = null,
                            string? undone_label = null) {
        base(location, conversations, messages);
        this.store = store;
        this.to_add = to_add;
        this.to_remove = to_remove;

        this.executed_label = executed_label;
        this.undone_label = undone_label;
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.store.mark_email_async(
            this.email, this.to_add, this.to_remove, cancellable
        );
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.store.mark_email_async(
            this.email, this.to_remove, this.to_add, cancellable
        );
    }

    public override bool equal_to(Command other) {
        if (!base.equal_to(other)) {
            return false;
        }

        MarkEmailCommand other_mark = (MarkEmailCommand) other;
        return (
            ((this.to_add == other_mark.to_add) ||
             (this.to_add != null &&
              other_mark.to_add != null &&
              this.to_add.equal_to(other_mark.to_add))) &&
            ((this.to_remove == other_mark.to_remove) ||
             (this.to_remove != null &&
              other_mark.to_remove != null &&
              this.to_remove.equal_to(other_mark.to_remove)))
        );
    }

}


private abstract class Application.RevokableCommand : EmailCommand {


    public override bool can_undo {
        get { return this.revokable != null && this.revokable.valid; }
    }

    private Geary.Revokable? revokable = null;


    protected RevokableCommand(Geary.Folder location,
                               Gee.Collection<Geary.App.Conversation> conversations,
                               Gee.Collection<Geary.EmailIdentifier> email) {
        base(location, conversations, email);
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        set_revokable(yield execute_impl(cancellable));
        if (this.revokable != null && this.revokable.valid) {
            yield this.revokable.commit_async(cancellable);
        }
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.revokable == null) {
            throw new Geary.EngineError.UNSUPPORTED(
                "Cannot undo command, no revokable available"
            );
        }

        yield this.revokable.revoke_async(cancellable);
        set_revokable(null);
    }

    protected abstract async Geary.Revokable
        execute_impl(GLib.Cancellable cancellable)
        throws GLib.Error;

    private void set_revokable(Geary.Revokable? updated) {
        if (this.revokable != null) {
            this.revokable.committed.disconnect(on_revokable_committed);
        }

        this.revokable = updated;

        if (this.revokable != null) {
            this.revokable.committed.connect(on_revokable_committed);
        }
    }

    private void on_revokable_committed(Geary.Revokable? updated) {
        set_revokable(updated);
    }

}


private class Application.MoveEmailCommand : RevokableCommand {


    private Geary.FolderSupport.Move source;
    private Geary.Folder destination;


    public MoveEmailCommand(Geary.FolderSupport.Move source,
                            Geary.Folder destination,
                            Gee.Collection<Geary.App.Conversation> conversations,
                            Gee.Collection<Geary.EmailIdentifier> messages,
                            string? executed_label = null,
                            string? undone_label = null) {
        base(source, conversations, messages);

        this.source = source;
        this.destination = destination;

        this.executed_label = executed_label;
        this.undone_label = undone_label;
    }

    internal override EmailCommand.StateChangePolicy folders_removed(
        Gee.Collection<Geary.Folder> removed
    ) {
        return (
            this.destination in removed
            ? EmailCommand.StateChangePolicy.REMOVE
            : base.folders_removed(removed)
        );
    }

    internal override EmailCommand.StateChangePolicy email_removed(
        Geary.Folder location,
        Gee.Collection<Geary.EmailIdentifier> targets
    ) {
        // With the current revokable mechanism we can't determine if
        // specific messages removed from the destination are
        // affected, so if the dest is the location, just assume they
        // are for now.
        return (
            location == this.destination
            ? EmailCommand.StateChangePolicy.REMOVE
            : base.email_removed(location, targets)
        );
    }

    protected override async Geary.Revokable
        execute_impl(GLib.Cancellable cancellable)
        throws GLib.Error {
        bool open = false;
        try {
            yield this.source.open_async(
                Geary.Folder.OpenFlags.NO_DELAY, cancellable
            );
            open = true;
            return yield this.source.move_email_async(
                this.email,
                this.destination.path,
                cancellable
            );
        } finally {
            if (open) {
                try {
                    yield this.source.close_async(null);
                } catch (GLib.Error err) {
                    // ignored
                }
            }
        }
    }

}


private class Application.ArchiveEmailCommand : RevokableCommand {


    /** {@inheritDoc} */
    public Geary.Folder command_location {
        get; protected set;
    }

    /** {@inheritDoc} */
    public Gee.Collection<Geary.EmailIdentifier> command_conversations {
        get; protected set;
    }

    /** {@inheritDoc} */
    public Gee.Collection<Geary.EmailIdentifier> command_email {
        get; protected set;
    }

    private Geary.FolderSupport.Archive source;


    public ArchiveEmailCommand(Geary.FolderSupport.Archive source,
                               Gee.Collection<Geary.App.Conversation> conversations,
                               Gee.Collection<Geary.EmailIdentifier> messages,
                               string? executed_label = null,
                               string? undone_label = null) {
        base(source, conversations, messages);
        this.source = source;
        this.executed_label = executed_label;
        this.undone_label = undone_label;
    }

    internal override EmailCommand.StateChangePolicy folders_removed(
        Gee.Collection<Geary.Folder> removed
    ) {
        EmailCommand.StateChangePolicy ret = base.folders_removed(removed);
        if (ret == IGNORE) {
            // With the current revokable mechanism we can't determine
            // if specific messages removed from the destination are
            // affected, so if the dest is the location, just assume
            // they are for now.
            foreach (var folder in removed) {
                if (folder.special_folder_type == ARCHIVE) {
                    ret = REMOVE;
                    break;
                }
            }
        }
        return ret;
    }

    internal override EmailCommand.StateChangePolicy email_removed(
        Geary.Folder location,
        Gee.Collection<Geary.EmailIdentifier> targets
    ) {
        // With the current revokable mechanism we can't determine if
        // specific messages removed from the destination are
        // affected, so if the dest is the location, just assume they
        // are for now.
        return (
            location.special_folder_type == ARCHIVE
            ? EmailCommand.StateChangePolicy.REMOVE
            : base.email_removed(location, targets)
        );
    }

    protected override async Geary.Revokable
        execute_impl(GLib.Cancellable cancellable)
        throws GLib.Error {
        bool open = false;
        try {
            yield this.source.open_async(
                Geary.Folder.OpenFlags.NO_DELAY, cancellable
            );
            open = true;
            return yield this.source.archive_email_async(
                this.email, cancellable
            );
        } finally {
            if (open) {
                try {
                    yield this.source.close_async(null);
                } catch (GLib.Error err) {
                    // ignored
                }
            }
        }
    }

}


private class Application.CopyEmailCommand : EmailCommand {


    public override bool can_undo {
        // Engine doesn't yet support it :(
        get { return false; }
    }

    private Geary.FolderSupport.Copy source;
    private Geary.Folder destination;


    public CopyEmailCommand(Geary.FolderSupport.Copy source,
                            Geary.Folder destination,
                            Gee.Collection<Geary.App.Conversation> conversations,
                            Gee.Collection<Geary.EmailIdentifier> messages,
                            string? executed_label = null,
                            string? undone_label = null) {
        base(source, conversations, messages);
        this.source = source;
        this.destination = destination;

        this.executed_label = executed_label;
        this.undone_label = undone_label;
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool open = false;
        try {
            yield this.source.open_async(
                Geary.Folder.OpenFlags.NO_DELAY, cancellable
            );
            open = true;
            yield this.source.copy_email_async(
                this.email, this.destination.path, cancellable
            );
        } finally {
            if (open) {
                try {
                    yield this.source.close_async(null);
                } catch (GLib.Error err) {
                    // ignored
                }
            }
        }
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED(
            "Cannot undo copy, not yet supported"
        );
    }

    internal override EmailCommand.StateChangePolicy folders_removed(
        Gee.Collection<Geary.Folder> removed
    ) {
        return (
            this.destination in removed
            ? EmailCommand.StateChangePolicy.REMOVE
            : base.folders_removed(removed)
        );
    }

    internal override EmailCommand.StateChangePolicy email_removed(
        Geary.Folder location,
        Gee.Collection<Geary.EmailIdentifier> targets
    ) {
        // With the current revokable mechanism we can't determine if
        // specific messages removed from the destination are
        // affected, so if the dest is the location, just assume they
        // are for now.
        return (
            location == this.destination
            ? EmailCommand.StateChangePolicy.REMOVE
            : base.email_removed(location, targets)
        );
    }

}


private class Application.DeleteEmailCommand : EmailCommand {


    public override bool can_undo {
        get { return false; }
    }

    private Geary.FolderSupport.Remove target;


    public DeleteEmailCommand(Geary.FolderSupport.Remove target,
                              Gee.Collection<Geary.App.Conversation> conversations,
                              Gee.Collection<Geary.EmailIdentifier> email) {
        base(target, conversations, email);
        this.target = target;
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool open = false;
        try {
            yield this.target.open_async(
                Geary.Folder.OpenFlags.NO_DELAY, cancellable
            );
            open = true;
            yield this.target.remove_email_async(this.email, cancellable);
        } finally {
            if (open) {
                try {
                    yield this.target.close_async(null);
                } catch (GLib.Error err) {
                    // ignored
                }
            }
        }
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED(
            "Cannot undo emptying a folder: %s",
            this.target.path.to_string()
        );
    }

}


private class Application.EmptyFolderCommand : Command {


    public override bool can_undo {
        get { return false; }
    }

    private Geary.FolderSupport.Empty target;


    public EmptyFolderCommand(Geary.FolderSupport.Empty target) {
        this.target = target;
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool open = false;
        try {
            yield this.target.open_async(
                Geary.Folder.OpenFlags.NO_DELAY, cancellable
            );
            open = true;
            yield this.target.empty_folder_async(cancellable);
        } finally {
            if (open) {
                try {
                    yield this.target.close_async(null);
                } catch (GLib.Error err) {
                    // ignored
                }
            }
        }
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED(
            "Cannot undo emptying a folder: %s",
            this.target.path.to_string()
        );
    }

    /** Determines if this command is equal to another. */
    public override bool equal_to(Command other) {
        EmptyFolderCommand? other_type = other as EmptyFolderCommand;
        return (other_type != null && this.target == other_type.target);
    }

}
