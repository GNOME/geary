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
 * @see GearyAplication
 */
public class Application.Controller : Geary.BaseObject {


    // Properties
    public const string PROP_SELECTED_CONVERSATIONS ="selected-conversations";

    private const int SELECT_FOLDER_TIMEOUT_USEC = 100 * 1000;

    private const string PROP_ATTEMPT_OPEN_ACCOUNT = "attempt-open-account";

    private const uint MAX_AUTH_ATTEMPTS = 3;

    private static string untitled_file_name;


    static construct {
        // Translators: File name used in save chooser when saving
        // attachments that do not otherwise have a name.
        Controller.untitled_file_name = _("Untitled");
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
        public Application.ContactStore contacts { get; private set; }

        /** A cancellable tied to the life-cycle of the account. */
        public Cancellable cancellable {
            get; private set; default = new Cancellable();
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

    // Null if none selected
    private Geary.Folder? current_folder = null;

    // Null if no folder ever selected
    private Geary.Account? current_account = null;

    private Application.CommandStack commands { get; protected set; }

    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_search = new Cancellable();
    private Cancellable cancellable_open_account = new Cancellable();
    private Cancellable cancellable_context_dependent_buttons = new Cancellable();
    private Gee.Set<Geary.App.Conversation> selected_conversations = new Gee.HashSet<Geary.App.Conversation>();
    private Geary.App.Conversation? last_deleted_conversation = null;
    private Gee.LinkedList<ComposerWidget> composer_widgets = new Gee.LinkedList<ComposerWidget>();
    private uint select_folder_timeout_id = 0;
    private int64 next_folder_select_allowed_usec = 0;
    private Geary.Nonblocking.Mutex select_folder_mutex = new Geary.Nonblocking.Mutex();
    private Geary.Folder? previous_non_search_folder = null;
    private Gee.List<string?> pending_mailtos = new Gee.ArrayList<string>();

    // List of windows we're waiting to close before Geary closes.
    private Gee.List<ComposerWidget> waiting_to_close = new Gee.ArrayList<ComposerWidget>();


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
            ComposerWebView.load_resources();
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

        this.commands = new CommandStack();

        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow(this.application, this.commands);
        main_window.retry_service_problem.connect(on_retry_service_problem);
        main_window.notify["has-toplevel-focus"].connect(on_has_toplevel_focus);

        enable_message_buttons(false);

        engine.account_available.connect(on_account_available);

        // Connect to various UI signals.
        main_window.conversation_list_view.conversations_selected.connect(on_conversations_selected);
        main_window.conversation_list_view.conversation_activated.connect(on_conversation_activated);
        main_window.conversation_list_view.visible_conversations_changed.connect(on_visible_conversations_changed);
        main_window.folder_list.folder_selected.connect(on_folder_selected);
        main_window.search_bar.search_text_changed.connect((text) => { do_search(text); });
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

    /** Un-does the last executed application command, if any. */
    public async void undo() {
        this.commands.undo.begin(
            this.open_cancellable,
            (obj, res) => {
                try {
                    this.commands.undo.end(res);
                } catch (GLib.Error err) {
                    // XXX extract account info somehow
                    report_problem(new Geary.ProblemReport(err));
                }
            }
        );
    }

    /** Re-does the last undone application command, if any. */
    public async void redo() {
        this.commands.redo.begin(
            this.open_cancellable,
            (obj, res) => {
                try {
                    this.commands.redo.end(res);
                } catch (GLib.Error err) {
                    // XXX extract account info somehow
                    report_problem(new Geary.ProblemReport(err));
                }
            }
        );
    }

    /** Closes all accounts and windows, releasing held resources. */
    public async void close_async() {
        // Cancel internal processes early so they don't block
        // shutdown
        this.open_cancellable.cancel();

        this.application.engine.account_available.disconnect(on_account_available);

        // Release folder and conversations in the main window
        on_conversations_selected(new Gee.HashSet<Geary.App.Conversation>());
        on_folder_selected(null);

        // Disconnect from various UI signals.
        this.main_window.conversation_list_view.conversations_selected.disconnect(on_conversations_selected);
        this.main_window.conversation_list_view.conversation_activated.disconnect(on_conversation_activated);
        this.main_window.conversation_list_view.visible_conversations_changed.disconnect(on_visible_conversations_changed);
        this.main_window.folder_list.folder_selected.disconnect(on_folder_selected);

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

        // Close all inboxes. Launch these in parallel first so we're
        // not wasting time waiting for each one to close. The account
        // will wait around for them to actually close.
        foreach (AccountContext context in accounts) {
            Geary.Folder? inbox = context.inbox;
            if (inbox != null) {
                debug("Closing inbox: %s...", inbox.to_string());
                inbox.close_async.begin(null, (obj, ret) => {
                        try {
                            inbox.close_async.end(ret);
                        } catch (Error err) {
                            debug(
                                "Error closing Inbox %s at shutdown: %s",
                                inbox.to_string(), err.message
                            );
                        }
                    });
                context.inbox = null;
            }
        }

        // Close all Accounts. Again, this is done in parallel to
        // minimise time taken to close, but here use a barrier to
        // wait for all to actually finish closing.
        Geary.Nonblocking.CountingSemaphore close_barrier =
            new Geary.Nonblocking.CountingSemaphore(null);
        foreach (AccountContext context in accounts) {
            close_barrier.acquire();
            this.close_account.begin(
                context.account.information,
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

        this.current_folder = null;
        this.previous_non_search_folder = null;

        this.current_account = null;

        this.selected_conversations = new Gee.HashSet<Geary.App.Conversation>();
        this.last_deleted_conversation = null;

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
        if (current_account == null) {
            // Schedule the send for after we have an account open.
            pending_mailtos.add(mailto);
        } else {
            create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE, null, null, mailto);
        }
    }

    /**
     * Opens new composer with an existing message as context.
     */
    public void compose_with_context_email(ComposerWidget.ComposeType type,
                                           Geary.Email context,
                                           string? quote) {
        create_compose_widget(type, context, quote);
    }

    /** Adds a new composer to be kept track of. */
    public void add_composer(ComposerWidget widget) {
        debug(@"Added composer of type $(widget.compose_type); $(this.composer_widgets.size) composers total");
        widget.destroy.connect(this.on_composer_widget_destroy);
        this.composer_widgets.add(widget);
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

    private async void close_account(Geary.AccountInformation config) {
        AccountContext? context = this.accounts.get(config);
        if (context != null) {
            Geary.Account account = context.account;
            if (this.current_account == account) {
                this.current_account = null;

                previous_non_search_folder = null;
                main_window.search_bar.set_search_text(""); // Reset search.

                cancel_folder();
            }

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

            yield disconnect_account_async(context);
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

        account.email_sent.connect(on_sent);
        account.email_removed.connect(on_account_email_removed);
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.sending_monitor.start.connect(on_sending_started);
        account.sending_monitor.finish.connect(on_sending_finished);

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

    private async void disconnect_account_async(AccountContext context, Cancellable? cancellable = null) {
        debug("Disconnecting account: %s", context.account.information.id);

        Geary.Account account = context.account;

        // Guard against trying to disconnect the account twice
        this.accounts.unset(account.information);

        // Now the account is not in the accounts map, reset any
        // status notifications for it
        update_account_status();

        account.email_sent.disconnect(on_sent);
        account.email_removed.disconnect(on_account_email_removed);
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.sending_monitor.start.disconnect(on_sending_started);
        account.sending_monitor.finish.disconnect(on_sending_finished);

        main_window.folder_list.remove_account(account);

        context.cancellable.cancel();
        context.contacts.close();

        Geary.Folder? inbox = context.inbox;
        if (inbox != null) {
            try {
                yield inbox.close_async(cancellable);
            } catch (Error close_inbox_err) {
                debug("Unable to close monitored inbox: %s", close_inbox_err.message);
            }
            context.inbox = null;
        }

        try {
            yield account.close_async(cancellable);
        } catch (Error close_err) {
            debug("Unable to close account %s: %s", account.to_string(), close_err.message);
        }

        debug("Account closed: %s", account.to_string());
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

    // Update widgets and such to match capabilities of the current folder ... sensitivity is handled
    // by other utility methods
    private void update_ui() {
        this.main_window.main_toolbar.selected_conversations =
            this.selected_conversations.size;
        this.main_window.main_toolbar.update_trash_button(
            !this.main_window.is_shift_down &&
            current_folder_supports_trash()
        );
    }

    private void on_folder_selected(Geary.Folder? folder) {
        debug("Folder %s selected", folder != null ? folder.to_string() : "(null)");
        if (folder == null) {
            this.current_folder = null;
            main_window.conversation_list_view.set_model(null);
            main_window.main_toolbar.folder = null;
            this.main_window.folder_selected(null, null);
        } else if (folder != this.current_folder) {
            this.main_window.conversation_viewer.show_loading();
            get_window_action(MainWindow.ACTION_FIND_IN_CONVERSATION).set_enabled(false);
            enable_message_buttons(false);

            // To prevent the user from selecting folders too quickly,
            // we prevent additional selection changes to occur until
            // after a timeout has expired from the last one
            int64 now = get_monotonic_time();
            int64 diff = now - this.next_folder_select_allowed_usec;
            if (diff < SELECT_FOLDER_TIMEOUT_USEC) {
                // only start timeout if another timeout is not
                // running ... this means the user can click madly and
                // will see the last clicked-on folder 100ms after the
                // first one was clicked on
                if (this.select_folder_timeout_id == 0) {
                    this.select_folder_timeout_id = Timeout.add(
                        (uint) (diff / 1000),
                        () => {
                            this.select_folder_timeout_id = 0;
                            this.next_folder_select_allowed_usec = 0;
                            if (folder != this.current_folder) {
                                do_select_folder.begin(
                                    folder, on_select_folder_completed
                                );
                            }
                            return false;
                        });
                }
            } else {
                do_select_folder.begin(folder, on_select_folder_completed);
                this.next_folder_select_allowed_usec =
                    now + SELECT_FOLDER_TIMEOUT_USEC;
            }
        }
    }

    private async void do_select_folder(Geary.Folder folder) throws Error {
        debug("Switching to %s...", folder.to_string());

        closed_folder();

        // This function is not reentrant.  It should be, because it can be
        // called reentrant-ly if you select folders quickly enough.  This
        // mutex lock is a bandaid solution to make the function safe to
        // reenter.
        int mutex_token = yield select_folder_mutex.claim_async(cancellable_folder);

        // re-enable copy/move to the last selected folder
        if (current_folder != null) {
            main_window.main_toolbar.copy_folder_menu.enable_disable_folder(current_folder, true);
            main_window.main_toolbar.move_folder_menu.enable_disable_folder(current_folder, true);
        }

        this.current_folder = folder;

        if (this.current_account != folder.account) {
            this.current_account = folder.account;
            this.main_window.search_bar.set_account(this.current_account);

            // If we were waiting for an account to be selected before issuing mailtos, do that now.
            if (pending_mailtos.size > 0) {
                foreach(string? mailto in pending_mailtos)
                    compose(mailto);

                pending_mailtos.clear();
            }

            main_window.main_toolbar.copy_folder_menu.clear();
            main_window.main_toolbar.move_folder_menu.clear();
            foreach(Geary.Folder f in current_folder.account.list_folders()) {
                main_window.main_toolbar.copy_folder_menu.add_folder(f);
                main_window.main_toolbar.move_folder_menu.add_folder(f);
            }
        }

        if (!(current_folder is Geary.SearchFolder))
            previous_non_search_folder = current_folder;

        // disable copy/move to the new folder
        main_window.main_toolbar.copy_folder_menu.enable_disable_folder(current_folder, false);
        main_window.main_toolbar.move_folder_menu.enable_disable_folder(current_folder, false);

        update_ui();

        this.main_window.folder_selected(folder, this.cancellable_folder);

        clear_new_messages("do_select_folder", null);

        select_folder_mutex.release(ref mutex_token);

        debug("Switched to %s", folder.to_string());
    }

    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }

    private void on_conversations_selected(Gee.Set<Geary.App.Conversation> selected) {
        this.selected_conversations = selected;
        get_window_action(MainWindow.ACTION_FIND_IN_CONVERSATION).set_enabled(false);
        ConversationViewer viewer = this.main_window.conversation_viewer;
        if (this.current_folder != null && !this.main_window.has_composer) {
            switch(selected.size) {
            case 0:
                enable_message_buttons(false);
                viewer.show_none_selected();
                break;

            case 1:
                // Cancel existing avatar loads before loading new
                // convo since that will start loading more avatars
                Geary.App.Conversation convo = Geary.Collection.get_first(
                    selected
                );

                AccountContext? context = this.accounts.get(
                    convo.base_folder.account.information
                );

                // It's possible for a conversation with zero email to
                // be selected, when it has just evaporated after its
                // last email was removed but the conversation monitor
                // hasn't signalled its removal yet. In this case,
                // just don't load it since it will soon disappear.
                if (context != null && convo.get_count() > 0) {
                    viewer.load_conversation.begin(
                        convo,
                        context.emails,
                        context.contacts,
                        (obj, ret) => {
                            try {
                                viewer.load_conversation.end(ret);
                                enable_message_buttons(true);
                                get_window_action(
                                    MainWindow.ACTION_FIND_IN_CONVERSATION
                                ).set_enabled(true);
                            } catch (GLib.IOError.CANCELLED err) {
                                // All good
                            } catch (Error err) {
                                debug("Unable to load conversation: %s",
                                      err.message);
                            }
                        }
                    );
                }
                break;

            default:
                enable_multiple_message_buttons();
                viewer.show_multiple_selected();
                break;
            }
        }
    }

    private void on_conversation_activated(Geary.App.Conversation activated) {
        // Currently activating a conversation is only available for drafts folders.
        if (current_folder == null || current_folder.special_folder_type !=
            Geary.SpecialFolderType.DRAFTS)
            return;

        // TODO: Determine how to map between conversations and drafts correctly.
        Geary.Email draft = activated.get_latest_recv_email(
            Geary.App.Conversation.Location.IN_FOLDER
        );

        // Check all known composers since the draft may be open in a
        // detached composer
        bool already_open = false;
        foreach (ComposerWidget composer in this.composer_widgets) {
            if (composer.draft_id != null &&
                composer.draft_id.equal_to(draft.id)) {
                already_open = true;
                composer.present();
                composer.set_focus();
                break;
            }
        }

        if (!already_open) {
            create_compose_widget(
                ComposerWidget.ComposeType.NEW_MESSAGE, draft, null, null, true
            );
        }
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

                main_window.folder_list.add_folder(folder);
                if (folder.account == current_account) {
                    if (!main_window.main_toolbar.copy_folder_menu.has_folder(folder))
                        main_window.main_toolbar.copy_folder_menu.add_folder(folder);
                    if (!main_window.main_toolbar.move_folder_menu.has_folder(folder))
                        main_window.main_toolbar.move_folder_menu.add_folder(folder);
                }

                GLib.Cancellable cancellable = context.cancellable;

                switch (folder.special_folder_type) {
                case Geary.SpecialFolderType.INBOX:
                    // Special case handling of inboxes
                    if (context.inbox == null) {
                        context.inbox = folder;

                        // Select this inbox if there isn't an
                        // existing folder selected and it is the
                        // inbox for the first account
                        if (!main_window.folder_list.is_any_selected()) {
                            Geary.AccountInformation? first_account = null;
                            foreach (Geary.AccountInformation info in this.accounts.keys) {
                                if (first_account == null ||
                                    info.ordinal < first_account.ordinal) {
                                    first_account = info;
                                }
                            }
                            if (folder.account.information == first_account) {
                                // First we try to select the Inboxes branch inbox if
                                // it's there, falling back to the main folder list.
                                if (!main_window.folder_list.select_inbox(folder.account))
                                    main_window.folder_list.select_folder(folder);
                            }
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

                folder.special_folder_type_changed.connect(on_special_folder_type_changed);
            }
        }

        if (unavailable != null) {
            Gee.BidirIterator<Geary.Folder> unavailable_iterator =
                unavailable.bidir_iterator();
            bool has_prev = unavailable_iterator.last();
            while (has_prev) {
                Geary.Folder folder = unavailable_iterator.get();

                main_window.folder_list.remove_folder(folder);
                if (folder.account == current_account) {
                    if (main_window.main_toolbar.copy_folder_menu.has_folder(folder))
                        main_window.main_toolbar.copy_folder_menu.remove_folder(folder);
                    if (main_window.main_toolbar.move_folder_menu.has_folder(folder))
                        main_window.main_toolbar.move_folder_menu.remove_folder(folder);
                }

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

                folder.special_folder_type_changed.disconnect(on_special_folder_type_changed);

                has_prev = unavailable_iterator.previous();
            }
        }
    }

    private void cancel_folder() {
        Cancellable old_cancellable = cancellable_folder;
        cancellable_folder = new Cancellable();

        old_cancellable.cancel();
    }

    // Like cancel_folder() but doesn't cancel outstanding operations, allowing them to complete
    // in the background
    private void closed_folder() {
        cancellable_folder = new Cancellable();
    }

    private void cancel_search() {
        Cancellable old_cancellable = this.cancellable_search;
        this.cancellable_search = new Cancellable();

        old_cancellable.cancel();
    }

    private void cancel_context_dependent_buttons() {
        Cancellable old_cancellable = cancellable_context_dependent_buttons;
        cancellable_context_dependent_buttons = new Cancellable();

        old_cancellable.cancel();
    }

    // We need to include the second parameter, or valac doesn't recognize the function as matching
    // GearyApplication.exiting's signature.
    private bool on_application_exiting(GearyApplication sender, bool panicked) {
        if (close_composition_windows())
            return true;

        return sender.cancel_exit();
    }

    // this signal does not necessarily indicate that the application previously didn't have
    // focus and now it does
    private void on_has_toplevel_focus() {
        clear_new_messages("on_has_toplevel_focus", null);
    }

    // latest_sent_only uses Email's Date: field, which corresponds to
    // how they're sorted in the ConversationViewer, not whether they
    // are in the sent folder.
    private Gee.Collection<Geary.EmailIdentifier> get_conversation_email_ids(
        Gee.Collection<Geary.App.Conversation> conversations,
        bool latest_sent_only) {

        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.ArrayList<Geary.EmailIdentifier>();

        // Blacklist the Outbox unless that's currently selected since
        // we don't want any operations to apply to messages there
        // normally.
        Gee.Collection<Geary.FolderPath>? blacklist = null;
        if (this.current_folder != null &&
            this.current_folder.special_folder_type != Geary.SpecialFolderType.OUTBOX) {
            Geary.Folder? outbox = this.current_account.get_special_folder(
                Geary.SpecialFolderType.OUTBOX
            );

            blacklist = new Gee.ArrayList<Geary.FolderPath>();
            blacklist.add(outbox.path);
        }

        foreach(Geary.App.Conversation conversation in conversations) {
            if (latest_sent_only) {
                Geary.Email? latest = conversation.get_latest_sent_email(
                    Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER,
                    blacklist
                );
                if (latest != null) {
                    ids.add(latest.id);
                }
            } else {
                Geary.traverse<Geary.Email>(
                    conversation.get_emails(
                        Geary.App.Conversation.Ordering.NONE,
                        Geary.App.Conversation.Location.ANYWHERE,
                        blacklist
                    )
                ).map<Geary.EmailIdentifier>(e => e.id)
                .add_all_to(ids);
            }
        }

        return ids;
    }

    private Gee.Collection<Geary.EmailIdentifier>
        get_selected_email_ids(bool latest_sent_only) {
        return get_conversation_email_ids(
            this.selected_conversations, latest_sent_only
        );
    }

    private void on_visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible) {
        clear_new_messages("on_visible_conversations_changed", visible);
    }

    private bool should_notify_new_messages(Geary.Folder folder) {
        // A monitored folder must be selected to squelch notifications;
        // if conversation list is at top of display, don't display
        // and don't display if main window has top-level focus
        return folder != current_folder
            || main_window.conversation_list_view.vadjustment.value != 0.0
            || !main_window.has_toplevel_focus;
    }

    // Clears messages if conditions are true: anything in should_notify_new_messages() is
    // false and the supplied visible messages are visible in the conversation list view
    private void clear_new_messages(string caller, Gee.Set<Geary.App.Conversation>? supplied) {
        NotificationContext notifications = this.plugin_manager.notifications;
        if (current_folder != null && (
                !notifications.get_folders().contains(current_folder) ||
                should_notify_new_messages(current_folder))) {

            Gee.Set<Geary.App.Conversation> visible =
                supplied ?? main_window.conversation_list_view.get_visible_conversations();

            foreach (Geary.App.Conversation conversation in visible) {
                try {
                    if (notifications.are_any_new_messages(current_folder,
                                                           conversation.get_email_ids())) {
                        debug("Clearing new messages: %s", caller);
                        notifications.clear_new_messages(current_folder);
                        break;
                    }
                } catch (Geary.EngineError.NOT_FOUND err) {
                    // all good
                }
            }
        }
    }

    public async void save_attachment_to_file(Geary.Account account,
                                              Geary.Attachment attachment,
                                              string? alt_text) {
        AccountContext? context = this.accounts.get(account.information);
        GLib.Cancellable cancellable = (
            context != null ? context.cancellable : null
        );

        string alt_display_name = Geary.String.is_empty_or_whitespace(alt_text)
            ? Application.Controller.untitled_file_name : alt_text;
        string display_name = yield attachment.get_safe_file_name(
            alt_display_name
        );

        Geary.Memory.FileBuffer? content = null;
        try {
            content = new Geary.Memory.FileBuffer(attachment.file, true);
        } catch (GLib.Error err) {
            warning(
                "Error opening attachment file \"%s\": %s",
                attachment.file.get_uri(), err.message
            );
            report_problem(new Geary.ProblemReport(err));
        }

        yield this.prompt_save_buffer(display_name, content, cancellable);
    }

    public async void
        save_attachments_to_file(Geary.Account account,
                                 Gee.Collection<Geary.Attachment> attachments) {
        AccountContext? context = this.accounts.get(account.information);
        GLib.Cancellable cancellable = (
            context != null ? context.cancellable : null
        );

        Gtk.FileChooserNative dialog = new_save_chooser(Gtk.FileChooserAction.SELECT_FOLDER);

        bool accepted = (dialog.run() == Gtk.ResponseType.ACCEPT);
        string? filename = dialog.get_filename();
        dialog.destroy();
        if (!accepted || Geary.String.is_empty(filename))
            return;

        File dest_dir = File.new_for_path(filename);
        foreach (Geary.Attachment attachment in attachments) {
            Geary.Memory.FileBuffer? content = null;
            GLib.File? dest = null;
            try {
                content = new Geary.Memory.FileBuffer(attachment.file, true);
                dest = dest_dir.get_child_for_display_name(
                    yield attachment.get_safe_file_name(
                        Application.Controller.untitled_file_name
                    )
                );
            } catch (GLib.Error err) {
                warning(
                    "Error opening attachment files \"%s\": %s",
                    attachment.file.get_uri(), err.message
                );
                report_problem(new Geary.ProblemReport(err));
            }

            if (content != null &&
                dest != null &&
                yield check_overwrite(dest, cancellable)) {
                yield write_buffer_to_file(content, dest, cancellable);
            }
        }
    }

    public async void save_image_extended(Geary.Account account,
                                          ConversationEmail view,
                                          string url,
                                          string? alt_text,
                                          Geary.Memory.Buffer resource_buf) {
        AccountContext? context = this.accounts.get(account.information);
        GLib.Cancellable cancellable = (
            context != null ? context.cancellable : null
        );

        // This is going to be either an inline image, or a remote
        // image, so either treat it as an attachment to assume we'll
        // have a valid filename in the URL
        bool handled = false;
        if (url.has_prefix(ClientWebView.CID_URL_PREFIX)) {
            string cid = url.substring(ClientWebView.CID_URL_PREFIX.length);
            Geary.Attachment? attachment = null;
            try {
                attachment = view.email.get_attachment_by_content_id(cid);
            } catch (Error err) {
                debug("Could not get attachment \"%s\": %s", cid, err.message);
            }
            if (attachment != null) {
                yield this.save_attachment_to_file(
                    account, attachment, alt_text
                );
                handled = true;
            }
        }

        if (!handled) {
            GLib.File source = GLib.File.new_for_uri(url);
            // Querying the URL-based file for the display name
            // results in it being looked up, so just get the basename
            // from it directly. GIO seems to decode any %-encoded
            // chars anyway.
            string? display_name = source.get_basename();
            if (Geary.String.is_empty_or_whitespace(display_name)) {
                display_name = Controller.untitled_file_name;
            }

            yield this.prompt_save_buffer(
                display_name, resource_buf, cancellable
            );
        }
    }

    private async void prompt_save_buffer(string display_name,
                                          Geary.Memory.Buffer buffer,
                                          GLib.Cancellable? cancellable) {
        Gtk.FileChooserNative dialog = new_save_chooser(
            Gtk.FileChooserAction.SAVE
        );
        dialog.set_current_name(display_name);

        string? accepted_path = null;
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            accepted_path = dialog.get_filename();
        }
        dialog.destroy();

        if (!Geary.String.is_empty_or_whitespace(accepted_path)) {
            GLib.File dest_file = File.new_for_path(accepted_path);
            if (yield check_overwrite(dest_file, cancellable)) {
                yield write_buffer_to_file(buffer, dest_file, cancellable);
            }
        }
    }

    private async bool check_overwrite(GLib.File to_overwrite,
                                       GLib.Cancellable? cancellable) {
        bool overwrite = true;
        try {
            GLib.FileInfo file_info = yield to_overwrite.query_info_async(
                GLib.FileAttribute.STANDARD_DISPLAY_NAME,
                GLib.FileQueryInfoFlags.NONE,
                GLib.Priority.DEFAULT,
                cancellable
            );
            GLib.FileInfo parent_info = yield to_overwrite.get_parent()
                .query_info_async(
                    GLib.FileAttribute.STANDARD_DISPLAY_NAME,
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    cancellable
                );

            // Translators: Dialog primary label when prompting to
            // overwrite a file. The string substitution is the file'sx
            // name.
            string primary = _(
                "A file named “%s” already exists.  Do you want to replace it?"
            ).printf(file_info.get_display_name());

            // Translators: Dialog secondary label when prompting to
            // overwrite a file. The string substitution is the parent
            // folder's name.
            string secondary = _(
                "The file already exists in “%s”.  Replacing it will overwrite its contents."
            ).printf(parent_info.get_display_name());

            ConfirmationDialog dialog = new ConfirmationDialog(
                main_window, primary, secondary, _("_Replace"), "destructive-action"
            );
            overwrite = (dialog.run() == Gtk.ResponseType.OK);
        } catch (GLib.Error err) {
            // Oh well
        }
        return overwrite;
    }

    private async void write_buffer_to_file(Geary.Memory.Buffer buffer,
                                            File dest,
                                            GLib.Cancellable? cancellable) {
        try {
            FileOutputStream outs = dest.replace(
                null, false, FileCreateFlags.REPLACE_DESTINATION, cancellable
            );
            yield outs.splice_async(
                buffer.get_input_stream(),
                OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET,
                Priority.DEFAULT,
                cancellable
            );
        } catch (GLib.IOError.CANCELLED err) {
            try {
                yield dest.delete_async(GLib.Priority.HIGH, null);
            } catch (GLib.Error err) {
                // Oh well
            }
        } catch (GLib.Error err) {
            warning(
                "Error writing buffer \"%s\": %s",
                dest.get_uri(), err.message
            );
            report_problem(new Geary.ProblemReport(err));
        }
    }

    private inline Gtk.FileChooserNative new_save_chooser(Gtk.FileChooserAction action) {
        Gtk.FileChooserNative dialog = new Gtk.FileChooserNative(
            null,
            this.main_window,
            action,
            Stock._SAVE,
            Stock._CANCEL
        );
        dialog.set_local_only(false);
        return dialog;
    }

    internal bool close_composition_windows(bool main_window_only = false) {
        Gee.List<ComposerWidget> composers_to_destroy = new Gee.ArrayList<ComposerWidget>();
        bool quit_cancelled = false;

        // If there's composer windows open, give the user a chance to
        // save or cancel.
        foreach(ComposerWidget cw in composer_widgets) {
            if (!main_window_only ||
                cw.state != ComposerWidget.ComposerState.DETACHED) {
                // Check if we should close the window immediately, or
                // if we need to wait.
                ComposerWidget.CloseStatus status = cw.should_close();
                if (status == ComposerWidget.CloseStatus.PENDING_CLOSE) {
                    // Window is currently busy saving.
                    waiting_to_close.add(cw);
                } else if (status == ComposerWidget.CloseStatus.CANCEL_CLOSE) {
                    // User cancelled operation.
                    quit_cancelled = true;
                    break;
                } else if (status == ComposerWidget.CloseStatus.DO_CLOSE) {
                    // Hide any existing composer windows for the
                    // moment; actually deleting the windows will
                    // result in their removal from composer_windows,
                    // which could crash this loop.
                    composers_to_destroy.add(cw);
                    ((ComposerContainer) cw.parent).vanish();
                }
            }
        }

        // Safely destroy windows.
        foreach(ComposerWidget cw in composers_to_destroy)
            ((ComposerContainer) cw.parent).close_container();

        // If we cancelled the quit we can bail here.
        if (quit_cancelled) {
            waiting_to_close.clear();

            return false;
        }

        // If there's still windows saving, we can't exit just yet.  Hide the main window and wait.
        if (waiting_to_close.size > 0) {
            main_window.hide();

            return false;
        }

        // If we deleted all composer windows without the user cancelling, we can exit.
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
    private void create_compose_widget(ComposerWidget.ComposeType compose_type,
                                       Geary.Email? referred = null,
                                       string? quote = null,
                                       string? mailto = null,
                                       bool is_draft = false) {
        if (current_account == null)
            return;

        // There's a few situations where we can re-use an existing
        // composer, check for these first.

        if (compose_type == NEW_MESSAGE && !is_draft) {
            // We're creating a new message that isn't a draft, if
            // there's already a composer open, just use that
            ComposerWidget? existing =
                this.main_window.conversation_viewer.current_composer;
            if (existing != null &&
                existing.state == PANED &&
                existing.is_blank) {
                existing.present();
                existing.set_focus();
                return;
            }
        } else if (compose_type != NEW_MESSAGE) {
            // We're replying, see whether we already have a reply for
            // that message and if so, insert a quote into that.
            foreach (ComposerWidget existing in this.composer_widgets) {
                if (existing.state != DETACHED &&
                    ((referred != null && existing.referred_ids.contains(referred.id)) ||
                     quote != null)) {
                    existing.change_compose_type(compose_type, referred, quote);
                    return;
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

        ComposerWidget widget;
        if (mailto != null) {
            widget = new ComposerWidget.from_mailto(
                this.application, current_account, mailto
            );
        } else {
            widget = new ComposerWidget(
                this.application,
                current_account,
                is_draft ? referred.id : null,
                compose_type
            );
        }

        add_composer(widget);

        if (widget.state == INLINE || widget.state == INLINE_COMPACT) {
            this.main_window.conversation_viewer.do_compose_embedded(
                widget,
                referred
            );
        } else {
            this.main_window.show_composer(widget);
        }

        this.load_composer.begin(
            this.current_account,
            widget,
            referred,
            quote,
            this.cancellable_folder
        );
    }

    private async void load_composer(Geary.Account account,
                                     ComposerWidget widget,
                                     Geary.Email? referred = null,
                                     string? quote = null,
                                     GLib.Cancellable? cancellable) {
        Geary.Email? full = null;
        if (referred != null) {
            AccountContext? context = this.accounts.get(account.information);
            if (context != null) {
                try {
                    full = yield context.emails.fetch_email_async(
                        referred.id,
                        Geary.ComposedEmail.REQUIRED_REPLY_FIELDS |
                        ComposerWidget.REQUIRED_FIELDS,
                        NONE,
                        cancellable
                    );
                } catch (Error e) {
                    message("Could not load full message: %s", e.message);
                }
            }
        }
        try {
            yield widget.load(full, quote, cancellable);
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
        widget.set_focus();
    }

    private void on_composer_widget_destroy(Gtk.Widget sender) {
        composer_widgets.remove((ComposerWidget) sender);
        debug(@"Destroying composer of type $(((ComposerWidget) sender).compose_type); "
            + @"$(composer_widgets.size) composers remaining");

        if (waiting_to_close.remove((ComposerWidget) sender)) {
            // If we just removed the last window in the waiting to close list, it's time to exit!
            if (waiting_to_close.size == 0)
                this.application.exit();
        }
    }

    private bool current_folder_supports_trash() {
        return (current_folder != null && current_folder.special_folder_type != Geary.SpecialFolderType.TRASH
            && !current_folder.properties.is_local_only && current_account != null
            && (current_folder as Geary.FolderSupport.Move) != null);
    }

    private void on_sent(Geary.Account account, Geary.RFC822.Message sent) {
        // Translators: The label for an in-app notification. The
        // string substitution is a list of recipients of the email.
        string message = _(
            "Successfully sent mail to %s."
        ).printf(Util.Email.to_short_recipient_display(sent.to));
        Components.InAppNotification notification =
            new Components.InAppNotification(message);
        this.main_window.add_notification(notification);
        this.plugin_manager.notifications.email_sent(account, sent);
    }

    private SimpleAction get_window_action(string action_name) {
        return (SimpleAction) this.main_window.lookup_action(action_name);
    }

    // Disables all single-message buttons and enables all multi-message buttons.
    public void enable_multiple_message_buttons() {
        main_window.main_toolbar.selected_conversations = this.selected_conversations.size;

        // Single message only buttons.
        get_window_action(MainWindow.ACTION_REPLY_TO_MESSAGE).set_enabled(false);
        get_window_action(MainWindow.ACTION_REPLY_ALL_MESSAGE).set_enabled(false);
        get_window_action(MainWindow.ACTION_FORWARD_MESSAGE).set_enabled(false);

        // Mutliple message buttons.
        get_window_action(MainWindow.ACTION_MOVE_MENU).set_enabled(current_folder is Geary.FolderSupport.Move);
        get_window_action(MainWindow.ACTION_ARCHIVE_CONVERSATION).set_enabled(current_folder is Geary.FolderSupport.Archive);
        get_window_action(MainWindow.ACTION_TRASH_CONVERSATION).set_enabled(current_folder_supports_trash());
        get_window_action(MainWindow.ACTION_DELETE_CONVERSATION).set_enabled(current_folder is Geary.FolderSupport.Remove);

        cancel_context_dependent_buttons();
        enable_context_dependent_buttons_async.begin(true, cancellable_context_dependent_buttons);
    }

    // Enables or disables the message buttons on the toolbar.
    public void enable_message_buttons(bool sensitive) {
        main_window.main_toolbar.selected_conversations = this.selected_conversations.size;

        // No reply/forward in drafts folder.
        bool respond_sensitive = sensitive;
        if (current_folder != null && current_folder.special_folder_type == Geary.SpecialFolderType.DRAFTS)
            respond_sensitive = false;

        get_window_action(MainWindow.ACTION_REPLY_TO_MESSAGE).set_enabled(respond_sensitive);
        get_window_action(MainWindow.ACTION_REPLY_ALL_MESSAGE).set_enabled(respond_sensitive);
        get_window_action(MainWindow.ACTION_FORWARD_MESSAGE).set_enabled(respond_sensitive);
        get_window_action(MainWindow.ACTION_MOVE_MENU).set_enabled(sensitive && (current_folder is Geary.FolderSupport.Move));
        get_window_action(MainWindow.ACTION_ARCHIVE_CONVERSATION).set_enabled(sensitive && (current_folder is Geary.FolderSupport.Archive));
        get_window_action(MainWindow.ACTION_TRASH_CONVERSATION).set_enabled(sensitive && current_folder_supports_trash());
        get_window_action(MainWindow.ACTION_DELETE_CONVERSATION).set_enabled(sensitive && (current_folder is Geary.FolderSupport.Remove));

        cancel_context_dependent_buttons();
        enable_context_dependent_buttons_async.begin(sensitive, cancellable_context_dependent_buttons);
    }

    private async void enable_context_dependent_buttons_async(bool sensitive, Cancellable? cancellable) {
        Gee.MultiMap<Geary.EmailIdentifier, Type>? selected_operations = null;
        try {
            if (current_folder != null) {
                Geary.App.EmailStore? store = get_email_store_for_folder(current_folder);
                if (store != null) {
                    selected_operations = yield store
                        .get_supported_operations_async(get_selected_email_ids(false), cancellable);
                }
            }
        } catch (Error e) {
            debug("Error checking for what operations are supported in the selected conversations: %s",
                e.message);
        }

        // Exit here if the user has cancelled.
        if (cancellable != null && cancellable.is_cancelled())
            return;

        Gee.HashSet<Type> supported_operations = new Gee.HashSet<Type>();
        if (selected_operations != null)
            supported_operations.add_all(selected_operations.get_values());

        get_window_action(MainWindow.ACTION_SHOW_MARK_MENU).set_enabled(sensitive && (typeof(Geary.FolderSupport.Mark) in supported_operations));
        get_window_action(MainWindow.ACTION_COPY_MENU).set_enabled(sensitive && (supported_operations.contains(typeof(Geary.FolderSupport.Copy))));
    }

    // Returns a list of composer windows for an account, or null if none.
    public Gee.List<ComposerWidget>? get_composer_widgets_for_account(Geary.AccountInformation account) {
        Gee.LinkedList<ComposerWidget> ret = Geary.traverse<ComposerWidget>(composer_widgets)
            .filter(w => w.account.information == account)
            .to_linked_list();

        return ret.size >= 1 ? ret : null;
    }

    private void do_search(string search_text) {
        Geary.SearchFolder? search_folder = null;
        if (this.current_account != null) {
            search_folder = this.current_account.get_special_folder(
                Geary.SpecialFolderType.SEARCH
            ) as Geary.SearchFolder;
        }

        if (Geary.String.is_empty_or_whitespace(search_text)) {
            if (this.previous_non_search_folder != null &&
                this.current_folder is Geary.SearchFolder) {
                this.main_window.folder_list.select_folder(
                    this.previous_non_search_folder
                );
            }

            this.main_window.folder_list.remove_search();

            if (search_folder !=  null) {
                search_folder.clear();
            }
        } else if (search_folder != null) {
            cancel_search(); // Stop any search in progress

            search_folder.search(
                search_text,
                this.application.config.get_search_strategy(),
                this.cancellable_search
            );

            this.main_window.folder_list.set_search(search_folder);
        }
    }

    /**
     * Returns a read-only set of currently selected conversations.
     */
    public Gee.Set<Geary.App.Conversation> get_selected_conversations() {
        return selected_conversations.read_only_view;
    }

    private inline Geary.App.EmailStore? get_email_store_for_folder(Geary.Folder target) {
        AccountContext? context = this.accounts.get(target.account.information);
        return (context != null) ? context.emails : null;
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
