/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides a context for notification plugins.
 *
 * The context provides an interface for notification plugins to
 * interface with the Geary client application. Plugins that implement
 * the plugins will be passed an instance of this class as the
 * `context` property.
 *
 * Plugins should register folders they wish to monitor by calling
 * {@link start_monitoring_folder}. The context will then start
 * keeping track of email being delivered to the folder and being seen
 * in a main window updating {@link total_new_messages} and emitting
 * the {@link new_messages_arrived} and {@link new_messages_retired}
 * signals as appropriate.
 *
 * @see Plugin.NotificationPlugin
 */
public class Application.NotificationContext : Geary.BaseObject {


    private const Geary.Email.Field REQUIRED_FIELDS  = FLAGS;


    private class ApplicationImpl : Geary.BaseObject, Plugin.Application {


        private Client backing;
        private FolderStoreFactory folders;


        public ApplicationImpl(Client backing,
                               FolderStoreFactory folders) {
            this.backing = backing;
            this.folders = folders;
        }

        public override void show_folder(Plugin.Folder folder) {
            Geary.Folder? target = this.folders.get_engine_folder(folder);
            if (target != null) {
                this.backing.show_folder.begin(target);
            }
        }

    }


    private class EmailStoreImpl : Geary.BaseObject, Plugin.EmailStore {


        private class EmailImpl : Geary.BaseObject, Plugin.Email {


            public Plugin.EmailIdentifier identifier {
                get {
                    if (this._id == null) {
                        this._id = new IdImpl(this.backing.id, this.account);
                    }
                    return this._id;
                }
            }
            private IdImpl? _id = null;

            public string subject {
                get { return this._subject; }
            }
            string _subject;

            internal Geary.Email backing;
            // Remove this when EmailIdentifier is updated to include
            // the account
            internal Geary.AccountInformation account { get; private set; }


            public EmailImpl(Geary.Email backing,
                             Geary.AccountInformation account) {
                this.backing = backing;
                this.account = account;
                Geary.RFC822.Subject? subject = this.backing.subject;
                this._subject = subject != null ? subject.to_string() : "";
            }

            public Geary.RFC822.MailboxAddress? get_primary_originator() {
                return Util.Email.get_primary_originator(this.backing);
            }

        }


        private class IdImpl : Geary.BaseObject,
            Gee.Hashable<Plugin.EmailIdentifier>, Plugin.EmailIdentifier {


            internal Geary.EmailIdentifier backing { get; private set; }
            // Remove this when EmailIdentifier is updated to include
            // the account
            internal Geary.AccountInformation account { get; private set; }


            public IdImpl(Geary.EmailIdentifier backing,
                          Geary.AccountInformation account) {
                this.backing = backing;
                this.account = account;
            }

            public GLib.Variant to_variant() {
                return this.backing.to_variant();
            }

            public bool equal_to(Plugin.EmailIdentifier other) {
                if (this == other) {
                    return true;
                }
                IdImpl? impl = other as IdImpl;
                return (
                    impl != null &&
                    this.backing.equal_to(impl.backing) &&
                    this.account.equal_to(impl.account)
                );
            }

            public uint hash() {
                return this.backing.hash();
            }

        }


        private Client backing;


        public EmailStoreImpl(Client backing) {
            this.backing = backing;
        }

        public async Gee.Collection<Plugin.Email> get_email(
            Gee.Collection<Plugin.EmailIdentifier> plugin_ids,
            GLib.Cancellable? cancellable
        ) throws GLib.Error {
            var emails = new Gee.HashSet<Plugin.Email>();

            // The email could theoretically come from any account, so
            // group them by account up front. The common case will be
            // only a single account, so optimise for that a bit.

            var accounts = new Gee.HashMap<
                Geary.AccountInformation,
                    Gee.Set<Geary.EmailIdentifier>
            >();
            Geary.AccountInformation? current_account = null;
            Gee.Set<Geary.EmailIdentifier>? engine_ids = null;
            foreach (Plugin.EmailIdentifier plugin_id in plugin_ids) {
                IdImpl? id_impl = plugin_id as IdImpl;
                if (id_impl != null) {
                    if (id_impl.account != current_account) {
                        current_account = id_impl.account;
                        engine_ids = accounts.get(current_account);
                        if (engine_ids == null) {
                            engine_ids = new Gee.HashSet<Geary.EmailIdentifier>();
                            accounts.set(current_account, engine_ids);
                        }
                    }
                    engine_ids.add(id_impl.backing);
                }
            }

            foreach (var account in accounts.keys) {
                AccountContext context =
                    this.backing.controller.get_context_for_account(account);
                Gee.Collection<Geary.Email> batch =
                    yield context.emails.list_email_by_sparse_id_async(
                        accounts.get(account),
                        ENVELOPE,
                        NONE,
                        context.cancellable
                    );
                if (batch != null) {
                    foreach (var email in batch) {
                        emails.add(new EmailImpl(email, account));
                    }
                }
            }

            return emails;
        }

        internal Gee.Collection<Plugin.EmailIdentifier> get_plugin_ids(
            Gee.Collection<Geary.EmailIdentifier> engine_ids,
            Geary.AccountInformation account
        ) {
            var plugin_ids = new Gee.HashSet<Plugin.EmailIdentifier>();
            foreach (var id in engine_ids) {
                plugin_ids.add(new IdImpl(id, account));
            }
            return plugin_ids;
        }

    }


    private class ContactStoreImpl : Geary.BaseObject, Plugin.ContactStore {


        private Application.ContactStore backing;


        public ContactStoreImpl(Application.ContactStore backing) {
            this.backing = backing;
        }

        public async Gee.Collection<Contact> search(string query,
                                                    uint min_importance,
                                                    uint limit,
                                                    GLib.Cancellable? cancellable
        ) throws GLib.Error {
            return yield this.backing.search(
                query, min_importance, limit, cancellable
            );
        }

        public async Contact load(Geary.RFC822.MailboxAddress mailbox,
                                  GLib.Cancellable? cancellable
        ) throws GLib.Error {
            return yield this.backing.load(mailbox, cancellable);
        }

    }


    private class MonitorInformation : Geary.BaseObject {

        public Geary.Folder folder;
        public GLib.Cancellable? cancellable = null;
        public Gee.Set<Geary.EmailIdentifier> recent_ids =
            new Gee.HashSet<Geary.EmailIdentifier>();

        public MonitorInformation(Geary.Folder folder,
                                  GLib.Cancellable? cancellable) {
            this.folder = folder;
            this.cancellable = cancellable;
        }
    }

    /**
     * Returns the plugin application object.
     *
     * No special permissions are required to use access this.
     */
    public Plugin.Application plugin_application {
        get; private set;
    }

    /**
     * Current total new message count for all monitored folders.
     *
     * This is the sum of the the counts returned by {@link
     * get_new_message_count} for all folders that are being monitored
     * after a call to {@link start_monitoring_folder}.
     */
    public int total_new_messages { get; private set; default = 0; }

    private Gee.Map<Geary.Folder,MonitorInformation> folder_information =
        new Gee.HashMap<Geary.Folder,MonitorInformation>();

    private unowned Client application;
    private FolderStoreFactory folders_factory;
    private Plugin.FolderStore folders;
    private EmailStoreImpl email;
    private PluginManager.PluginFlags flags;


    /**
     * Emitted when new messages have been downloaded.
     *
     * This will only be emitted for folders that are being monitored
     * by calling {@link start_monitoring_folder}.
     */
    public signal void new_messages_arrived(
        Plugin.Folder parent,
        int total,
        Gee.Collection<Plugin.EmailIdentifier> added
    );

    /**
     * Emitted when a folder has been cleared of new messages.
     *
     * This will only be emitted for folders that are being monitored
     * after a call to {@link start_monitoring_folder}.
     */
    public signal void new_messages_retired(Plugin.Folder parent, int total);


    /** Constructs a new context instance. */
    internal NotificationContext(Client application,
                                 FolderStoreFactory folders_factory,
                                 PluginManager.PluginFlags flags) {
        this.application = application;
        this.folders_factory = folders_factory;
        this.folders = folders_factory.new_folder_store();
        this.email = new EmailStoreImpl(application);
        this.flags = flags;

        this.plugin_application = new ApplicationImpl(
            application, folders_factory
        );
    }

    /**
     * Returns a store to lookup folders for notifications.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Geary.EngineError.PERMISSIONS if permission to access
     * this resource was not given
     */
    public async Plugin.FolderStore get_folders()
        throws Geary.EngineError.PERMISSIONS {
        return this.folders;
    }

    /**
     * Returns a store to lookup email for notifications.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Geary.EngineError.PERMISSIONS if permission to access
     * this resource was not given
     */
    public async Plugin.EmailStore get_email()
        throws Geary.EngineError.PERMISSIONS {
        return this.email;
    }

    /**
     * Returns a store to lookup contacts for notifications.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Geary.EngineError.NOT_FOUND if the given account does
     * not exist
     * @throws Geary.EngineError.PERMISSIONS if permission to access
     * this resource was not given
     */
    public async Plugin.ContactStore get_contacts_for_folder(Plugin.Folder source)
        throws Geary.EngineError.NOT_FOUND,
            Geary.EngineError.PERMISSIONS {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(source);
        AccountContext? context = null;
        if (folder != null) {
            context = this.application.controller.get_context_for_account(
                folder.account.information
            );
        }
        if (context == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No account for folder: %s", source.display_name
            );
        }
        return new ContactStoreImpl(context.contacts);
    }

    /**
     * Returns the client's application object.
     *
     * Only plugins that are trusted by the client will be provided
     * access to the application instance.
     *
     * @throws Geary.EngineError.PERMISSIONS if permission to access
     * this resource was not given
     */
    public Client get_client_application()
        throws Geary.EngineError.PERMISSIONS {
        if (!(PluginManager.PluginFlags.TRUSTED in this.flags)) {
            throw new Geary.EngineError.PERMISSIONS("Plugin is not trusted");
        }
        return this.application;
    }

    /**
     * Determines if notifications should be made for a specific folder.
     *
     * Notification plugins should call this to first before
     * displaying a "new mail" notification for mail in a specific
     * folder. It will return true for any monitored folder that is
     * not currently visible in the currently focused main window, if
     * any.
     */
    public bool should_notify_new_messages(Plugin.Folder target) {
        // Don't show notifications if the top of a monitored folder's
        // conversations are visible. That is, if there is a main
        // window, it's focused, the folder is selected, and the
        // conversation list is at the top.
        Geary.Folder? folder = this.folders_factory.get_engine_folder(target);
        MainWindow? window = this.application.last_active_main_window;
        return (
            folder != null &&
            this.folder_information.has_key(folder) && (
                window == null ||
                !window.has_toplevel_focus ||
                window.selected_folder != folder ||
                window.conversation_list_view.vadjustment.value > 0.0
            )
        );
    }

    /**
     * Returns the new message count for a specific folder.
     *
     * The context must have already been requested to monitor the
     * folder by a call to {@link start_monitoring_folder}.
     */
    public int get_new_message_count(Plugin.Folder target)
        throws Geary.EngineError.NOT_FOUND {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(target);
        MonitorInformation? info = null;
        if (folder != null) {
            info = folder_information.get(folder);
        }
        if (info == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No such folder: %s", folder.path.to_string()
            );
        }
        return info.recent_ids.size;
    }

    /**
     * Starts monitoring a folder for new messages.
     *
     * Notification plugins should call this to start the context
     * recording new messages for a specific folder.
     */
    public void start_monitoring_folder(Plugin.Folder target) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(target);
        AccountContext? context =
            this.application.controller.get_context_for_account(
                folder.account.information
            );
        if (folder != null &&
            context != null &&
            !this.folder_information.has_key(folder)) {
            folder.email_locally_appended.connect(on_email_locally_appended);
            folder.email_flags_changed.connect(on_email_flags_changed);
            folder.email_removed.connect(on_email_removed);

            this.folder_information.set(
                folder, new MonitorInformation(folder, context.cancellable)
            );
        }
    }

    /** Stops monitoring a folder for new messages. */
    public void stop_monitoring_folder(Plugin.Folder target) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(target);
        if (folder != null) {
            remove_folder(folder);
        }
    }

    /** Determines if a folder is curently being monitored. */
    public bool is_monitoring_folder(Plugin.Folder target) {
        return this.folder_information.has_key(
            this.folders_factory.get_engine_folder(target)
        );
    }

    internal void destroy() {
        this.folders_factory.destroy_folder_store(this.folders);
        // Get an array so the loop does not blow up when removing values.
        foreach (Geary.Folder monitored in this.folder_information.keys.to_array()) {
            remove_folder(monitored);
        }
    }

    internal void clear_new_messages(Geary.Folder location,
                                     Gee.Set<Geary.App.Conversation>? visible) {
        MonitorInformation? info = this.folder_information.get(location);
        if (info != null) {
            foreach (Geary.App.Conversation conversation in visible) {
                if (Geary.traverse(
                        conversation.get_email_ids()
                    ).any((id) => info.recent_ids.contains(id))) {
                    Gee.Set<Geary.EmailIdentifier> old_ids = info.recent_ids;
                    info.recent_ids = new Gee.HashSet<Geary.EmailIdentifier>();
                    update_count(info, false, old_ids);
                    break;
                }
            }
        }
    }

    private void new_messages(MonitorInformation info,
                              Gee.Collection<Geary.Email> emails) {
        Gee.Collection<Geary.EmailIdentifier> added =
            new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (Geary.Email email in emails) {
            if (email.email_flags.is_unread() &&
                info.recent_ids.add(email.id)) {
                added.add(email.id);
            }
        }
        if (added.size > 0) {
            update_count(info, true, added);
        }
    }

    private void retire_new_messages(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids
    ) {
        MonitorInformation info = folder_information.get(folder);
        Gee.Collection<Geary.EmailIdentifier> removed =
            new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (Geary.EmailIdentifier email_id in email_ids) {
            if (info.recent_ids.remove(email_id)) {
                removed.add(email_id);
            }
        }

        if (removed.size > 0) {
            update_count(info, false, removed);
        }
    }

    private void update_count(MonitorInformation info,
                              bool arrived,
                              Gee.Collection<Geary.EmailIdentifier> delta) {
        Plugin.Folder folder =
            this.folders_factory.get_plugin_folder(info.folder);
        if (arrived) {
            this.total_new_messages += delta.size;
            new_messages_arrived(
                folder,
                info.recent_ids.size,
                this.email.get_plugin_ids(delta, info.folder.account.information)
            );
        } else {
            this.total_new_messages -= delta.size;
            new_messages_retired(
                folder, info.recent_ids.size
            );
        }
    }

    private void remove_folder(Geary.Folder target) {
        MonitorInformation? info = this.folder_information.get(target);
        if (info != null) {
            target.email_locally_appended.disconnect(on_email_locally_appended);
            target.email_flags_changed.disconnect(on_email_flags_changed);
            target.email_removed.disconnect(on_email_removed);

            this.total_new_messages -= info.recent_ids.size;

            this.folder_information.unset(target);
        }

    }

    private async void do_process_new_email(
        Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids
    ) {
        MonitorInformation info = this.folder_information.get(folder);
        if (info != null) {
            Gee.List<Geary.Email>? list = null;
            try {
                list = yield folder.list_email_by_sparse_id_async(
                    email_ids,
                    REQUIRED_FIELDS,
                    NONE,
                    info.cancellable
                );
            } catch (GLib.Error err) {
                warning(
                    "Unable to list new email for notification: %s", err.message
                );
            }
            if (list != null && !list.is_empty) {
                new_messages(info, list);
            } else {
                warning(
                    "%d new emails, but none could be listed for notification",
                    email_ids.size
                );
            }
        }
    }

    private void on_email_locally_appended(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        do_process_new_email.begin(folder, email_ids);
    }

    private void on_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ids) {
        retire_new_messages(folder, ids.keys);
    }

    private void on_email_removed(Geary.Folder folder,
                                  Gee.Collection<Geary.EmailIdentifier> ids) {
        retire_new_messages(folder, ids);
    }

}
