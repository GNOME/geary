/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2016-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Primary controller for an application instance.
 *
 * A single instance of this class is constructed by {@link Client}
 * when the primary application instance is started.
 */
internal class Application.Controller :
    Geary.BaseObject, AccountInterface, Composer.ApplicationInterface {


    private const uint MAX_AUTH_ATTEMPTS = 3;

    private const uint CLEANUP_CHECK_AFTER_IDLE_BACKGROUND_MINUTES = 5;

    /** Determines if conversations can be trashed from the given folder. */
    public static bool does_folder_support_trash(Geary.Folder? target) {
        return (
            target != null &&
            target.used_as != TRASH &&
            !target.properties.is_local_only &&
            (target as Geary.FolderSupport.Move) != null
        );
    }

    /** Determines if folders should be added to main windows. */
    private static bool should_add_folder(Gee.Collection<Geary.Folder>? all,
                                          Geary.Folder folder) {
        // if folder is openable, add it
        if (folder.properties.is_openable != Geary.Trillian.FALSE)
            return true;
        else if (folder.properties.has_children == Geary.Trillian.FALSE)
            return false;

        // if folder contains children, we must ensure that there is
        // at least one of the same type
        Geary.Folder.SpecialUse type = folder.used_as;
        foreach (Geary.Folder other in all) {
            if (other.used_as == type && other.path.parent == folder.path)
                return true;
        }

        return false;
    }


    /** Determines if the controller is open. */
    public bool is_open {
        get {
            return !this.controller_open.is_cancelled();
        }
    }

    /** The primary application instance that owns this controller. */
    public weak Client application { get; private set; } // circular ref

    /** Account management for the application. */
    public Accounts.Manager account_manager { get; private set; }

    /** Plugin manager for the application. */
    public PluginManager plugins { get; private set; }

    /** Certificate management for the application. */
    public Application.CertificateManager certificate_manager {
        get; private set;
    }

    // Primary collection of the application's open accounts
    private Gee.Map<Geary.AccountInformation,AccountContext> accounts =
        new Gee.HashMap<Geary.AccountInformation,AccountContext>();
    private bool is_loading_accounts = true;

    // Cancelled if the controller is closed
    private GLib.Cancellable controller_open;

    private DatabaseManager database_manager;
    private Folks.IndividualAggregator folks;

    // List composers that have not yet been closed
    private Gee.Collection<Composer.Widget> composer_widgets =
        new Gee.LinkedList<Composer.Widget>();

    // Requested mailto composers not yet fullfulled
    private Gee.List<string?> pending_mailtos = new Gee.ArrayList<string>();

    // Timeout to do work in idle after all windows have been sent to the background
    private Geary.TimeoutManager all_windows_backgrounded_timeout;

    private GLib.Cancellable? storage_cleanup_cancellable;


    /**
     * Emitted when a composer is registered.
     *
     * This will be emitted after a composer is constructed, but
     * before it is shown.
     */
    public signal void composer_registered(Composer.Widget widget);

    /**
     * Emitted when a composer is deregistered.
     *
     * This will be emitted when a composer has been closed and is
     * about to be destroyed.
     */
    public signal void composer_deregistered(Composer.Widget widget);

    /**
     * Constructs a new instance of the controller.
     */
    public async Controller(Client application,
                            GLib.Cancellable cancellable)
        throws GLib.Error {
        this.application = application;
        this.controller_open = cancellable;

        GLib.File config_dir = application.get_home_config_directory();
        GLib.File data_dir = application.get_home_data_directory();

        // This initializes the IconFactory, important to do before
        // the actions are created (as they refer to some of Geary's
        // custom icons)
        IconFactory.init(application.get_resource_directory());

        // Create DB upgrade dialog.
        this.database_manager = new DatabaseManager(application);

        // Initialise WebKit and WebViews
        Components.WebView.init_web_context(
            this.application.config,
            this.application.get_web_extensions_dir(),
            this.application.get_home_cache_directory().get_child(
                "web-resources"
            )
        );
        Components.WebView.load_resources(config_dir);
        Composer.WebView.load_resources();
        ConversationWebView.load_resources();
        Accounts.SignatureWebView.load_resources();

        this.all_windows_backgrounded_timeout =
            new Geary.TimeoutManager.seconds(CLEANUP_CHECK_AFTER_IDLE_BACKGROUND_MINUTES * 60, on_unfocused_idle);

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

        this.plugins = new PluginManager(
            this.application,
            this,
            this.application.config,
            this.application.get_app_plugins_dir()
        );

        // Create standard config directory
        try {
            config_dir.make_directory_with_parents();
        } catch (GLib.IOError.EXISTS err) {
            // fine
        }

        // Migrate configuration if necessary.
        Util.Migrate.xdg_config_dir(config_dir, data_dir);
        Util.Migrate.release_config(
            application.get_config_search_path(), config_dir
        );

        // Hook up cert, accounts and credentials machinery

        this.certificate_manager = yield new Application.CertificateManager(
            data_dir.get_child("pinned-certs"),
            cancellable
        );
        // Commit e8061379 mistakenly used config_dir for cert manager
        // above, so remove it if found. This can be pulled out post
        // v40.
        try {
            yield Geary.Files.recursive_delete_async(
                config_dir.get_child("pinned-certs")
            );
        } catch (GLib.IOError.NOT_FOUND err) {
            // exactly as planned
        }

        SecretMediator? libsecret = yield new SecretMediator(
            this.application, cancellable
        );

        application.engine.account_available.connect(on_account_available);

        this.account_manager = new Accounts.Manager(
            libsecret,
            config_dir,
            data_dir
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

        yield this.account_manager.connect_goa(cancellable);

        // Load accounts
        yield this.account_manager.load_accounts(cancellable);
        this.is_loading_accounts = false;

        // Expunge any deleted accounts in the background, so we're
        // not blocking the app continuing to open.
        this.expunge_accounts.begin();
    }

    /** Closes all windows and accounts, releasing held resources. */
    public async void close() {
        // Stop listening for account changes up front so we don't
        // attempt to add new accounts while shutting down.
        this.account_manager.account_added.disconnect(
            on_account_added
        );
        this.account_manager.account_status_changed.disconnect(
            on_account_status_changed
        );
        this.account_manager.account_removed.disconnect(
            on_account_removed
        );
        this.application.engine.account_available.disconnect(
            on_account_available
        );

        foreach (MainWindow window in this.application.get_main_windows()) {
            window.sensitive = false;
        }

        // Close any open composers up-front before anything else is
        // shut down so any pending operations have a chance to
        // complete.
        var composer_barrier = new Geary.Nonblocking.CountingSemaphore(null);
        // Take a copy of the collection of composers since
        // closing any will cause the underlying collection to change.
        var composers = new Gee.LinkedList<Composer.Widget>();
        composers.add_all(this.composer_widgets);
        foreach (var composer in composers) {
            if (composer.current_mode != CLOSED) {
                composer_barrier.acquire();
                composer.close.begin(
                    (obj, res) => {
                        composer.close.end(res);
                        composer_barrier.blind_notify();
                    }
                );
            }
        }

        try {
            yield composer_barrier.wait_async();
        } catch (GLib.Error err) {
            warning("Error waiting at composer barrier: %s", err.message);
        }

        // Now that all composers are closed, we can shut down the
        // rest of the client and engine. Cancel internal processes
        // first so they don't block shutdown.
        this.controller_open.cancel();

        // Release folder and conversations in main windows before
        // closing them so we know they are released before closing
        // the accounts
        var window_barrier = new Geary.Nonblocking.CountingSemaphore(null);
        foreach (MainWindow window in this.application.get_main_windows()) {
            window_barrier.acquire();
            window.select_folder.begin(
                null,
                false,
                true,
                (obj, res) => {
                    window.select_folder.end(res);
                    window.close();
                    window_barrier.blind_notify();
                }
            );
        }
        try {
            yield window_barrier.wait_async();
        } catch (GLib.Error err) {
            warning("Error waiting at window barrier: %s", err.message);
        }

        // Release general resources now there's no more UI
        try {
            this.plugins.close();
        } catch (GLib.Error err) {
            warning("Error closing plugin manager: %s", err.message);
        }
        this.pending_mailtos.clear();
        this.composer_widgets.clear();

        // Create a copy of known accounts so the loop below does not
        // explode if accounts are removed while iterating.
        var closing_accounts = new Gee.LinkedList<AccountContext>();
        closing_accounts.add_all(this.accounts.values);
        var account_barrier = new Geary.Nonblocking.CountingSemaphore(null);
        foreach (AccountContext context in closing_accounts) {
            account_barrier.acquire();
            this.close_account.begin(
                context.account.information,
                true,
                (obj, ret) => {
                    this.close_account.end(ret);
                    account_barrier.blind_notify();
                }
            );
        }
        try {
            yield account_barrier.wait_async();
        } catch (GLib.Error err) {
            warning("Error waiting at account barrier: %s", err.message);
        }

        info("Closed Application.Controller");
    }

    /**
     * Opens a composer for writing a new, blank message.
     */
    public async Composer.Widget compose_blank(AccountContext send_context,
                                               Geary.RFC822.MailboxAddress? to = null) {
        MainWindow main = this.application.get_active_main_window();
        Composer.Widget composer = main.conversation_viewer.current_composer;
        if (composer == null ||
            composer.current_mode != PANED ||
            !composer.is_blank ||
            composer.sender_context != send_context) {
            composer = new Composer.Widget(
                this,
                this.application.config,
                send_context,
                null
            );
            register_composer(composer);
        }
        try {
            yield composer.load_empty_body(to);
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
        return composer;
    }

    /**
     * Opens new composer with an existing message as context.
     *
     * If the given type is {@link Composer.Widget.ContextType.EDIT},
     * the context is loaded to be edited (e.g. for drafts, templates,
     * sending again. Otherwise the context is treated as the email to
     * be replied to, etc.
     *
     * Returns null if there is an existing composer open and the
     * prompt to close it was declined.
     */
    public async Composer.Widget? compose_with_context(AccountContext send_context,
                                                       Composer.Widget.ContextType type,
                                                       Geary.Email context,
                                                       string? quote) {
        MainWindow main = this.application.get_active_main_window();
        Composer.Widget? composer = null;
        if (type == EDIT) {
            // Check all known composers since the context may be open
            // an existing composer already.
            foreach (var existing in this.composer_widgets) {
                if (existing.current_mode != NONE &&
                    existing.current_mode != CLOSED &&
                    composer.sender_context == send_context &&
                    existing.saved_id != null &&
                    existing.saved_id.equal_to(context.id)) {
                    composer = existing;
                    break;
                }
            }
        } else {
            // See whether there is already an inline message in the
            // current window that is either a reply/forward for that
            // message, or there is a quote to insert into it.
            foreach (var existing in this.composer_widgets) {
                if (existing.get_toplevel() == main &&
                    (existing.current_mode == INLINE ||
                     existing.current_mode == INLINE_COMPACT) &&
                    existing.sender_context == send_context &&
                    (context.id in existing.get_referred_ids() ||
                     quote != null)) {
                    try {
                        existing.append_to_email(context, quote, type);
                        composer = existing;
                        break;
                    } catch (Geary.EngineError error) {
                        report_problem(new Geary.ProblemReport(error));
                    }
                }
            }

            // Can't re-use an existing composer, so need to create a
            // new one. Replies must open inline in the main window,
            // so we need to ensure there are no composers open there
            // first.
            if (composer == null && !main.close_composer(true)) {
                // Prompt to close the existing composer was declined,
                // so bail out
                return null;
            }
        }

        if (composer == null) {
            composer = new Composer.Widget(
                this,
                this.application.config,
                send_context,
                null
            );
            register_composer(composer);

            try {
                yield composer.load_context(type, context, quote);
            } catch (GLib.Error err) {
                report_problem(new Geary.ProblemReport(err));
            }
        }
        return composer;
    }

    /**
     * Opens a composer with the given `mailto:` URL.
     */
    public async void compose_mailto(string mailto) {
        MainWindow? window = this.application.last_active_main_window;
        if (window != null && window.selected_account != null) {
            var context = this.accounts.get(window.selected_account.information);
            if (context != null) {
                var composer = new Composer.Widget(
                    this,
                    this.application.config,
                    context
                );
                register_composer(composer);
                present_composer(composer);

                try {
                    yield composer.load_mailto(mailto);
                } catch (GLib.Error err) {
                    report_problem(new Geary.ProblemReport(err));
                }
            }
        } else {
            // Schedule the send for after we have an account open.
            this.pending_mailtos.add(mailto);
        }
    }

    /** Displays a problem report when an error has been encountered. */
    public void report_problem(Geary.ProblemReport report) {
        debug("Problem reported: %s", report.to_string());

        if (report.error == null ||
            !(report.error.thrown is IOError.CANCELLED)) {
            var info_bar = new Components.ProblemReportInfoBar(report);
            info_bar.retry.connect(on_retry_problem);
            this.application.get_active_main_window().show_info_bar(info_bar);
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
                    ).printf(Util.I18n.to_folder_display_name(destination)),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the source folder.
                    ngettext(
                        "Conversation restored to %s",
                        "Conversations restored to %s",
                        conversations.size
                    ).printf(Util.I18n.to_folder_display_name(source))
                ),
                context.cancellable
            );
        }
    }

    public async void move_conversations_special(Geary.Folder source,
                                                 Geary.Folder.SpecialUse destination,
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
            ).printf(Util.I18n.to_folder_display_name(source));

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
                    ).printf(Util.I18n.to_folder_display_name(dest)),
                    undone_tooltip
                );
            }

            yield context.commands.execute(command, context.cancellable);
        }
    }

    public async void move_messages_special(Geary.Folder source,
                                            Geary.Folder.SpecialUse destination,
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
            ).printf(Util.I18n.to_folder_display_name(source));

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
                    ).printf(Util.I18n.to_folder_display_name(dest)),
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
                    ).printf(Util.I18n.to_folder_display_name(destination)),
                    /// Translators: Label for in-app
                    /// notification. String substitution is the name
                    /// of the destination folder.
                    ngettext(
                        "Conversation un-labelled as %s",
                        "Conversations un-labelled as %s",
                        conversations.size
                    ).printf(Util.I18n.to_folder_display_name(destination))
                ),
                context.cancellable
            );
        }
    }

    public async void delete_conversations(Geary.FolderSupport.Remove target,
                                           Gee.Collection<Geary.App.Conversation> conversations)
        throws GLib.Error {
        var messages = target.properties.is_virtual
            ? to_all_email_ids(conversations)
            : to_in_folder_email_ids(conversations);
        yield delete_messages(target, conversations, messages);
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

    public async void empty_folder(Geary.Folder target)
        throws GLib.Error {
        AccountContext? context = this.accounts.get(target.account.information);
        if (context != null) {
            Geary.FolderSupport.Empty? emptyable = (
                target as Geary.FolderSupport.Empty
            );
            if (emptyable == null) {
                throw new Geary.EngineError.UNSUPPORTED(
                    "Emptying folder not supported %s", target.path.to_string()
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

    /** Returns a context for an account, if any. */
    internal AccountContext? get_context_for_account(Geary.AccountInformation account) {
        return this.accounts.get(account);
    }

    /** Returns a read-only collection of contexts each active account. */
    internal Gee.Collection<AccountContext> get_account_contexts() {
        return this.accounts.values.read_only_view;
    }

    internal void register_window(MainWindow window) {
        window.retry_service_problem.connect(on_retry_service_problem);
    }

    internal void unregister_window(MainWindow window) {
        window.retry_service_problem.disconnect(on_retry_service_problem);
    }

    /** Opens any pending composers. */
    internal async void process_pending_composers() {
        foreach (string? mailto in this.pending_mailtos) {
            yield compose_mailto(mailto);
        }
        this.pending_mailtos.clear();
    }

    /** Queues the email in a composer for delivery. */
    internal async void send_composed_email(Composer.Widget composer) {
        AccountContext context = composer.sender_context;
        try {
            yield context.commands.execute(
                new SendComposerCommand(this.application, context, composer),
                context.cancellable
            );
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    /** Saves the email in a composer as a draft on the server. */
    internal async void save_composed_email(Composer.Widget composer) {
        // XXX this doesn't actually do what it says on the tin, since
        // the composer's draft manager is already saving drafts on
        // the server. Until we get that saving local-only, this will
        // only be around for pushing the composer onto the undo stack
        AccountContext context = composer.sender_context;
        try {
            yield context.commands.execute(
                new SaveComposerCommand(this, composer),
                context.cancellable
            );
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    /** Queues a composer to be discarded. */
    internal async void discard_composed_email(Composer.Widget composer) {
        AccountContext context = composer.sender_context;
        try {
            yield context.commands.execute(
                new DiscardComposerCommand(this, composer),
                context.cancellable
            );
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    /** Expunges removed accounts while the controller remains open. */
    internal async void expunge_accounts() {
        try {
            yield this.account_manager.expunge_accounts(this.controller_open);
        } catch (GLib.Error err) {
            report_problem(new Geary.ProblemReport(err));
        }
    }

    private void add_account(Geary.AccountInformation added) {
        try {
            this.application.engine.add_account(added);
        } catch (Geary.EngineError.ALREADY_EXISTS err) {
            // all good
        } catch (GLib.Error err) {
            report_problem(new Geary.AccountProblemReport(added, err));
        }
    }

    private async void open_account(Geary.Account account) {
        AccountContext context = new AccountContext(
            account,
            new Geary.App.SearchFolder(account, account.local_folder_root),
            new Geary.App.EmailStore(account),
            new Application.ContactStore(account, this.folks)
        );
        this.accounts.set(account.information, context);

        this.database_manager.add_account(account, this.controller_open);

        account.information.authentication_failure.connect(
            on_authentication_failure
        );
        account.information.untrusted_host.connect(on_untrusted_host);
        account.notify["current-status"].connect(
            on_account_status_notify
        );
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.report_problem.connect(on_report_problem);

        Geary.Smtp.ClientService? smtp = (
            account.outgoing as Geary.Smtp.ClientService
        );
        if (smtp != null) {
            smtp.email_sent.connect(on_sent);
        }

        // Notify before opening so that listeners have a chance to
        // hook into it before signals start getting fired by folders
        // becoming available, etc.
        account_available(context, this.is_loading_accounts);

        bool retry = false;
        do {
            try {
                yield account.open_async(this.controller_open);
                retry = false;
            } catch (GLib.Error open_err) {
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

        update_account_status();
    }

    private async void remove_account(Geary.AccountInformation removed) {
        yield close_account(removed, false);
        try {
            this.application.engine.remove_account(removed);
        } catch (Geary.EngineError.NOT_FOUND err) {
            // all good
        } catch (GLib.Error err) {
            report_problem(
                new Geary.AccountProblemReport(removed, err)
            );
        }
    }

    private async void close_account(Geary.AccountInformation config,
                                     bool is_shutdown) {
        AccountContext? context = this.accounts.get(config);
        if (context != null) {
            debug("Closing account: %s", context.account.information.id);
            Geary.Account account = context.account;

            account_unavailable(context, is_shutdown);

            // Guard against trying to close the account twice
            this.accounts.unset(account.information);

            this.database_manager.remove_account(account);

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

            account.folders_available_unavailable.disconnect(on_folders_available_unavailable);

            Geary.Smtp.ClientService? smtp = (
                account.outgoing as Geary.Smtp.ClientService
            );
            if (smtp != null) {
                smtp.email_sent.disconnect(on_sent);
            }

            // Now the account is not in the accounts map, reset any
            // status notifications for it
            update_account_status();

            // Stop any background processes
            context.search.clear_query();
            context.contacts.close();
            context.cancellable.cancel();

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

        foreach (MainWindow window in this.application.get_main_windows()) {
            window.update_account_status(
                effective_status,
                has_auth_error,
                has_cert_error,
                service_problem_source
            );
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
                this.application.get_active_main_window(),
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

    // Returns true if the caller should try opening the account again
    private async bool account_database_error_async(Geary.Account account) {
        bool retry = true;

        // give the user two options: reset the Account local store, or exit Geary.  A third
        // could be done to leave the Account in an unopened state, but we don't currently
        // have provisions for that.
        QuestionDialog dialog = new QuestionDialog(
            this.application.get_active_main_window(),
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
                    ErrorDialog errdialog = new ErrorDialog(
                        this.application.get_active_main_window(),
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

    private void on_folders_available_unavailable(
        Geary.Account account,
        Gee.BidirSortedSet<Geary.Folder>? available,
        Gee.BidirSortedSet<Geary.Folder>? unavailable) {
        var account_context = this.accounts.get(account.information);

        if (available != null && available.size > 0) {
            var added_contexts = new Gee.LinkedList<FolderContext>();
            foreach (var folder in available) {
                if (Controller.should_add_folder(available, folder)) {
                    if (folder.used_as == INBOX) {
                        if (account_context.inbox == null) {
                            account_context.inbox = folder;
                        }
                        folder.open_async.begin(
                            NO_DELAY, account_context.cancellable
                        );
                    }

                    var folder_context = new FolderContext(folder);
                    added_contexts.add(folder_context);
                }
            }
            if (!added_contexts.is_empty) {
                account_context.add_folders(added_contexts);
            }
        }

        if (unavailable != null) {
            Gee.BidirIterator<Geary.Folder> unavailable_iterator =
                unavailable.bidir_iterator();
            bool has_prev = unavailable_iterator.last();
            var removed_contexts = new Gee.LinkedList<FolderContext>();
            while (has_prev) {
                Geary.Folder folder = unavailable_iterator.get();

                if (folder.used_as == INBOX) {
                    account_context.inbox = null;
                }

                var folder_context = account_context.get_folder(folder);
                if (folder_context != null) {
                    removed_contexts.add(folder_context);
                }

                has_prev = unavailable_iterator.previous();
            }
            if (!removed_contexts.is_empty) {
                account_context.remove_folders(removed_contexts);
            }

            // Notify the command stack that folders have gone away
            account_context.controller_stack.folders_removed(unavailable);
        }
    }

    /** Clears new message counts in notification plugin contexts. */
    internal void clear_new_messages(Geary.Folder source,
                                     Gee.Set<Geary.App.Conversation> visible) {
        foreach (MainWindow window in this.application.get_main_windows()) {
            window.folder_list.set_has_new(source, false);
        }
        foreach (NotificationPluginContext context in
                 this.plugins.get_notification_contexts()) {
            context.clear_new_messages(source, visible);
        }
    }

    /** Notifies plugins of new email being displayed. */
    internal void email_loaded(Geary.AccountInformation account,
                               Geary.Email loaded) {
        foreach (EmailPluginContext plugin in
                 this.plugins.get_email_contexts()) {
            plugin.email_displayed(account, loaded);
        }
    }

    /**
     * Track a window receiving focus, for idle background work.
     */
    public void window_focus_in() {
        this.all_windows_backgrounded_timeout.reset();

        if (this.storage_cleanup_cancellable != null) {
            this.storage_cleanup_cancellable.cancel();

            // Cleanup was still running and we don't know where we got to so
            // we'll clear each of these so it runs next time we're in the
            // background
            foreach (AccountContext context in this.accounts.values) {
                context.cancellable.cancelled.disconnect(this.storage_cleanup_cancellable.cancel);

                Geary.Account account = context.account;
                account.last_storage_cleanup = null;
            }
            this.storage_cleanup_cancellable = null;
        }
    }

    /**
     * Track a window going unfocused, for idle background work.
     */
    public void window_focus_out() {
        this.all_windows_backgrounded_timeout.start();
    }

    /** Attempts to make the composer visible on the active monitor. */
    internal void present_composer(Composer.Widget composer) {
        if (composer.current_mode == CLOSED ||
            composer.current_mode == NONE) {
            var target = this.application.get_active_main_window();
            target.show_composer(composer);
        }
        composer.set_focus();
        composer.present();
    }

    internal bool check_open_composers() {
        var do_quit = true;
        foreach (var composer in this.composer_widgets) {
            if (composer.conditional_close(true, true) == CANCELLED) {
                do_quit = false;
                break;
            }
        }
        return do_quit;
    }

    internal void register_composer(Composer.Widget widget) {
        if (!(widget in this.composer_widgets)) {
            debug(@"Registered composer of type $(widget.context_type); " +
              @"$(this.composer_widgets.size) composers total");
            widget.destroy.connect_after(this.on_composer_widget_destroy);
            this.composer_widgets.add(widget);
            composer_registered(widget);
        }
    }

    private void on_composer_widget_destroy(Gtk.Widget sender) {
        Composer.Widget? composer = sender as Composer.Widget;
        if (composer != null && composer_widgets.remove(composer)) {
            debug(@"Composer type $(composer.context_type) destroyed; " +
                  @"$(this.composer_widgets.size) composers remaining");
            composer_deregistered(composer);
        }
    }

    private void on_sent(Geary.Smtp.ClientService service,
                         Geary.Email sent) {
        /// Translators: The label for an in-app notification.
        string message = _("Email sent");
        Components.InAppNotification notification =
            new Components.InAppNotification(
                message, application.config.brief_notification_duration
                );
        foreach (MainWindow window in this.application.get_main_windows()) {
            window.add_notification(notification);
        }

        AccountContext? context = this.accounts.get(service.account);
        if (context != null) {
            foreach (EmailPluginContext plugin in
                     this.plugins.get_email_contexts()) {
                plugin.email_sent(context.account.information, sent);
            }
        }
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

    private Gee.Collection<Geary.EmailIdentifier>
        to_all_email_ids(Gee.Collection<Geary.App.Conversation> conversations) {
        Gee.Collection<Geary.EmailIdentifier> messages =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        foreach (Geary.App.Conversation conversation in conversations) {
            foreach (Geary.Email email in conversation.get_emails(NONE)) {
                messages.add(email.id);
            }
        }
        return messages;
    }

    private void on_account_available(Geary.AccountInformation info) {
        Geary.Account? account = null;
        try {
            account = this.application.engine.get_account(info);
        } catch (GLib.Error error) {
            report_problem(new Geary.ProblemReport(error));
            warning(
                "Error creating account %s instance: %s",
                info.id,
                error.message
            );
        }

        if (account != null) {
            this.open_account.begin(account);
        }
    }

    private void on_account_added(Geary.AccountInformation added,
                                  Accounts.Manager.Status status) {
        if (status == Accounts.Manager.Status.ENABLED) {
            this.add_account(added);
        }
    }

    private void on_account_status_changed(Geary.AccountInformation changed,
                                           Accounts.Manager.Status status) {
        switch (status) {
        case Accounts.Manager.Status.ENABLED:
            this.add_account(changed);
            break;

        case Accounts.Manager.Status.UNAVAILABLE:
        case Accounts.Manager.Status.DISABLED:
            this.remove_account.begin(changed);
            break;

        case Accounts.Manager.Status.REMOVED:
            // Account is gone, no further action is required
            break;
        }
    }

    private void on_account_removed(Geary.AccountInformation removed) {
        this.remove_account.begin(removed);
    }

    private void on_report_problem(Geary.ProblemReport problem) {
        report_problem(problem);
    }

    private void on_retry_problem(Components.ProblemReportInfoBar info_bar) {
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

                default:
                    // No special action required for other statuses
                    break;
                }

                if (do_restart) {
                    has_restarted = true;
                    service.restart.begin(context.cancellable);
                }
            }
        }
    }

    private void on_unfocused_idle() {
        // Schedule later, catching cases where work should occur later while still in background
        this.all_windows_backgrounded_timeout.reset();
        window_focus_out();

        if (this.storage_cleanup_cancellable == null)
            do_background_storage_cleanup.begin();
    }

    private async void do_background_storage_cleanup() {
        debug("Checking for backgrounded idle work");
        this.storage_cleanup_cancellable = new GLib.Cancellable();

        foreach (AccountContext context in this.accounts.values) {
            Geary.Account account = context.account;
            context.cancellable.cancelled.connect(this.storage_cleanup_cancellable.cancel);
            try {
                yield account.cleanup_storage(this.storage_cleanup_cancellable);
            } catch (GLib.Error err) {
                report_problem(new Geary.ProblemReport(err));
            }
            context.cancellable.cancelled.disconnect(this.storage_cleanup_cancellable.cancel);
            if (this.storage_cleanup_cancellable.is_cancelled())
                break;
        }
        this.storage_cleanup_cancellable = null;
    }

}


/** Base class for all application controller commands. */
internal class Application.ControllerCommandStack : CommandStack {


    private EmailCommand? last_executed = null;
    private Geary.TimeoutManager last_executed_timeout;


    public ControllerCommandStack() {
        this.last_executed_timeout = new Geary.TimeoutManager.milliseconds(
            250,
            () => { this.last_executed = null; }
        );
    }

    /** {@inheritDoc} */
    public override async void execute(Command target,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.last_executed_timeout.reset();
        // Guard against things like Delete being held down by only
        // executing a command if it is different to the last one.
        if (this.last_executed == null || !this.last_executed.equal_to(target)) {
            this.last_executed = target as EmailCommand;
            this.last_executed_timeout.start();
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
        this.location.account.cancel_remote_update();

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
        this.executed_notification_brief = true;
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
                if (folder.used_as == ARCHIVE) {
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
            location.used_as == ARCHIVE
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


private abstract class Application.ComposerCommand : Command {


    public override bool can_redo {
        get { return false; }
    }

    protected Composer.Widget? composer { get; private set; }


    protected ComposerCommand(Composer.Widget composer) {
        this.composer = composer;
    }

    protected void clear_composer() {
        this.composer = null;
    }

    protected void close_composer() {
        // Calling close then immediately erasing the reference looks
        // sketchy, but works since Controller still maintains a
        // reference to the composer until it destroys itself.
        this.composer.close.begin();
        this.composer = null;
    }

}


private class Application.SendComposerCommand : ComposerCommand {


    public override bool can_undo {
        get { return this.application.config.undo_send_delay > 0; }
    }

    private Client application;
    private AccountContext context;
    private Geary.Smtp.ClientService smtp;
    private Geary.TimeoutManager commit_timer;
    private Geary.EmailIdentifier? saved = null;


    public SendComposerCommand(Client application,
                               AccountContext context,
                               Composer.Widget composer) {
        base(composer);
        this.application = application;
        this.context = context;
        this.smtp = (Geary.Smtp.ClientService) context.account.outgoing;

        int send_delay = this.application.config.undo_send_delay;
        this.commit_timer = new Geary.TimeoutManager.seconds(
            send_delay > 0 ? send_delay : 0,
            on_commit_timeout
        );
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.ComposedEmail email = yield this.composer.to_composed_email();
        if (this.can_undo) {
            /// Translators: The label for an in-app notification. The
            /// string substitution is a list of recipients of the email.
            this.executed_label = _(
                "Email to %s queued for delivery"
            ).printf(Util.Email.to_short_recipient_display(email));

            this.saved = yield this.smtp.save_email(email, cancellable);
            this.commit_timer.start();
        } else {
            yield this.smtp.send_email(email, cancellable);
        }
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.commit_timer.reset();
        yield this.smtp.outbox.remove_email_async(
            Geary.Collection.single(this.saved),
            cancellable
        );
        this.saved = null;

        this.composer.set_enabled(true);
        this.application.controller.present_composer(this.composer);
        clear_composer();
    }

    private void on_commit_timeout() {
        this.smtp.queue_email(this.saved);
        this.saved = null;
        close_composer();
    }

}


private class Application.SaveComposerCommand : ComposerCommand {


    private const int DESTROY_TIMEOUT_SEC = 30 * 60;

    public override bool can_redo {
        get { return false; }
    }

    private Controller controller;

    private Geary.TimeoutManager destroy_timer;


    public SaveComposerCommand(Controller controller,
                               Composer.Widget composer) {
        base(composer);
        this.controller = controller;

        this.destroy_timer = new Geary.TimeoutManager.seconds(
            DESTROY_TIMEOUT_SEC,
            on_destroy_timeout
        );
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        /// Translators: The label for an in-app notification.
        this.executed_label = _("Email saved as draft");
        this.destroy_timer.start();
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.composer != null) {
            this.destroy_timer.reset();
            this.composer.set_enabled(true);
            this.controller.present_composer(this.composer);
            clear_composer();
        } else {
            /// Translators: A label for an in-app notification.
            this.undone_label = _(
                "Composer could not be restored"
            );
        }
    }

    private void on_destroy_timeout() {
        close_composer();
    }

}


private class Application.DiscardComposerCommand : ComposerCommand {


    private const int DESTROY_TIMEOUT_SEC = 30 * 60;

    public override bool can_redo {
        get { return false; }
    }

    private Controller controller;

    private Geary.TimeoutManager destroy_timer;


    public DiscardComposerCommand(Controller controller,
                                  Composer.Widget composer) {
        base(composer);
        this.controller = controller;

        this.destroy_timer = new Geary.TimeoutManager.seconds(
            DESTROY_TIMEOUT_SEC,
            on_destroy_timeout
        );
    }

    public override async void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        /// Translators: The label for an in-app notification. The
        /// string substitution is a list of recipients of the email.
        this.executed_label = _("Email discarded");
        this.destroy_timer.start();
    }

    public override async void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.composer != null) {
            this.destroy_timer.reset();
            this.composer.set_enabled(true);
            this.controller.present_composer(this.composer);
            clear_composer();
        } else {
            /// Translators: A label for an in-app notification.
            this.undone_label = _(
                "Composer could not be restored"
            );
        }
    }

    private void on_destroy_timeout() {
        close_composer();
    }

}
