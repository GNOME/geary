/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


/**
 * Current supported credential providers.
 */
public enum Accounts.CredentialsProvider {
    /** Credentials are provided and stored by libsecret. */
    LIBSECRET,

    /** Credentials are provided and stored by gnome-online-accounts. */
    GOA;

    public string to_string() {
        switch (this) {
            case LIBSECRET:
                return "libsecret";

            case GOA:
                return "goa";

            default:
                assert_not_reached();
        }
    }

    public static CredentialsProvider from_string(string str)
        throws GLib.Error {
        switch (str.ascii_down()) {
            case "libsecret":
                return LIBSECRET;

            case "goa":
                return GOA;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials provider type: %s", str
                );
        }
    }
}

public errordomain Accounts.Error {
    INVALID,
    LOCAL_REMOVED,
    GOA_REMOVED;
}


/**
 * Manages email account lifecycle for Geary.
 *
 * This class is responsible for creating, loading, saving and
 * removing accounts and their persisted data (configuration,
 * databases, caches, authentication tokens). The manager supports
 * both locally-specified accounts (i.e. those created by the user in
 * the app) and from SSO systems such as GOA.
 *
 * Newly loaded and newly created accounts are first added to the
 * manager with a particular status (enabled, disabled, etc). Accounts
 * can have their enabled or disabled status updated manually,
 */
public class Accounts.Manager : GLib.Object {


    private const string LOCAL_ID_PREFIX = "account_";
    private const string LOCAL_ID_FORMAT = "account_%02u";
    private const string GOA_ID_PREFIX = "goa_";

    private const string ACCOUNT_CONFIG_GROUP = "AccountInformation";
    private const string ACCOUNT_MANAGER_GROUP = "AccountManager";
    private const string IMAP_CONFIG_GROUP = "IMAP";
    private const string SMTP_CONFIG_GROUP = "SMTP";

    private const string ALTERNATE_EMAILS_KEY = "alternate_emails";
    private const string ARCHIVE_FOLDER_KEY = "archive_folder";
    private const string CREDENTIALS_METHOD_KEY = "credentials_method";
    private const string CREDENTIALS_PROVIDER_KEY = "credentials_provider";
    private const string DRAFTS_FOLDER_KEY = "drafts_folder";
    private const string EMAIL_SIGNATURE_KEY = "email_signature";
    private const string NICKNAME_KEY = "nickname";
    private const string ORDINAL_KEY = "ordinal";
    private const string PREFETCH_PERIOD_DAYS_KEY = "prefetch_period_days";
    private const string PRIMARY_EMAIL_KEY = "primary_email";
    private const string REMOVED_KEY = "removed";
    private const string REAL_NAME_KEY = "real_name";
    private const string SAVE_DRAFTS_KEY = "save_drafts";
    private const string SAVE_SENT_MAIL_KEY = "save_sent_mail";
    private const string SENT_MAIL_FOLDER_KEY = "sent_mail_folder";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string SPAM_FOLDER_KEY = "spam_folder";
    private const string TRASH_FOLDER_KEY = "trash_folder";
    private const string USE_EMAIL_SIGNATURE_KEY = "use_email_signature";


    /**
     * Specifies the overall status of an account.
     */
    public enum Status {
        /** The account is enabled and operational. */
        ENABLED,

        /** The account was disabled by the user. */
        DISABLED,

        /** The account is unavailable to be used, by may come back. */
        UNAVAILABLE;
    }


    /** Specifies an account's current state. */
    private class AccountState {


        /** The account represented by this object. */
        public Geary.AccountInformation account { get; private set; }

        /** Determines the account's overall state. */
        public Status status {
            get {
                Status status = Status.ENABLED;
                if (!this.enabled) {
                    status = Status.DISABLED;
                }
                if (!this.available) {
                    status = Status.UNAVAILABLE;
                }
                return status;
            }
        }

        /** Whether this account is enabled. */
        public bool enabled { get; set; default = true; }

        /** Whether this account is available. */
        public bool available { get; set; default = true; }


        internal AccountState(Geary.AccountInformation account) {
            this.account = account;
        }

    }


    /** Returns the number of currently known accounts. */
    public int size { get { return this.accounts.size; } }


    private Gee.Map<string,AccountState> accounts =
        new Gee.HashMap<string,AccountState>();

    private Gee.LinkedList<Geary.AccountInformation> removed =
        new Gee.LinkedList<Geary.AccountInformation>();


    private GearyApplication application;
    private GLib.File user_config_dir;
    private GLib.File user_data_dir;

    private Geary.CredentialsMediator? libsecret = null;
    private Goa.Client? goa_service = null;


    /** Fired when a new account is created. */
    public signal void account_added(Geary.AccountInformation added, Status status);

    /** Fired when an existing account's state has changed. */
    public signal void account_status_changed(Geary.AccountInformation changed,
                                              Status new_status);

    /** Fired when an account is deleted. */
    public signal void account_removed(Geary.AccountInformation removed);

    /** Emitted to notify an account problem has occurred. */
    public signal void report_problem(Geary.ProblemReport problem);


    public Manager(GearyApplication application,
                   GLib.File user_config_dir,
                   GLib.File user_data_dir) {
        this.application = application;
        this.user_config_dir = user_config_dir;
        this.user_data_dir = user_data_dir;
    }

    /** Returns the account with the given id. */
    public Geary.AccountInformation? get_account(string id) {
        AccountState? state = this.accounts.get(id);
        return (state != null) ? state.account : null;
    }

    /** Returns the status for the given account. */
    public Status get_status(Geary.AccountInformation account) {
        AccountState? state = this.accounts.get(account.id);
        return (state != null) ? state.status : Status.UNAVAILABLE;
    }

    /** Returns a read-only iterable of all currently known accounts. */
    public Geary.Iterable<Geary.AccountInformation> iterable() {
        return Geary.traverse<AccountState>(
            this.accounts.values
        ).map<Geary.AccountInformation>(
            ((state) => { return state.account; })
        );
    }

    public async void connect_libsecret(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.libsecret = yield new SecretMediator(this.application, cancellable);
    }

    public async void connect_goa(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.goa_service = yield new Goa.Client(cancellable);
        this.goa_service.account_added.connect(on_goa_account_added);
        this.goa_service.account_changed.connect(on_goa_account_changed);
        this.goa_service.account_removed.connect(on_goa_account_removed);
    }

    /**
     * Returns a new account, not yet stored on disk.
     */
    public Geary.AccountInformation
        new_orphan_account(Geary.ServiceProvider provider,
                           Geary.ServiceInformation imap,
                           Geary.ServiceInformation smtp) {
        string? last_account = this.accounts.keys.fold<string?>((next, last) => {
                string? result = last;
                if (next.has_prefix(LOCAL_ID_PREFIX)) {
                    result = (last == null || strcmp(last, next) < 0) ? next : last;
                }
                return result;
            },
            null);
        uint next_id = 1;
        if (last_account != null) {
            next_id = int.parse(last_account.substring(LOCAL_ID_PREFIX.length)) + 1;
        }
        string id = LOCAL_ID_FORMAT.printf(next_id);

        return new Geary.AccountInformation(id, provider, imap, smtp);
    }

    public LocalServiceInformation new_libsecret_service(Geary.Protocol service) {
        return new LocalServiceInformation(service, libsecret);
    }

    /**
     * Creates new account's disk and credential storage as needed.
     */
    public async void create_account(Geary.AccountInformation account,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield create_account_dirs(account, cancellable);
        yield save_account(account, cancellable);
        set_enabled(account, true);

        SecretMediator? mediator = account.imap.mediator as SecretMediator;
        if (mediator != null) {
            try {
                yield mediator.update_token(account, account.imap, cancellable);
            } catch (Error e) {
                debug("Error saving IMAP password: %s", e.message);
            }
        }

        if (account.smtp.credentials != null) {
            mediator = account.smtp.mediator as SecretMediator;
            if (mediator != null) {
                try {
                    yield mediator.update_token(account, account.smtp, cancellable);
                } catch (Error e) {
                    debug("Error saving IMAP password: %s", e.message);
                }
            }
        }
    }

    public async void load_accounts(GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Step 1. Load existing accounts from the user config dir
        GLib.FileEnumerator? enumerator = null;
        try {
            enumerator = yield this.user_config_dir.enumerate_children_async(
                "standard::*",
                FileQueryInfoFlags.NONE,
                Priority.DEFAULT,
                cancellable
            );
        } catch (GLib.IOError.NOT_FOUND err) {
            // Don't worry about the dir not being found, it just
            // means we have no accounts to load.
        }

        while (enumerator != null && !cancellable.is_cancelled()) {
            // Get 10 at a time to batch the IO together
            GLib.List<GLib.FileInfo> info_list = yield enumerator.next_files_async(
                10, GLib.Priority.DEFAULT, cancellable
            );

            uint len = info_list.length();
            for (uint i = 0; i < len && !cancellable.is_cancelled(); i++) {
                GLib.FileInfo file = info_list.nth_data(i);
                if (file.get_file_type() == FileType.DIRECTORY) {
                    try {
                        Geary.AccountInformation info = yield load_account(
                            file.get_name(), cancellable
                        );

                        GoaMediator? mediator = info.imap.mediator as GoaMediator;
                        if (mediator == null || mediator.is_valid) {
                            set_enabled(info, true);
                        } else {
                            set_available(info, false);
                        }
                    } catch (GLib.Error err) {
                        report_problem(
                            new Geary.ProblemReport(
                                Geary.ProblemType.GENERIC_ERROR,
                                err
                            ));
                    }
                }
            }

            if (len == 0) {
                // We're done
                enumerator = null;
            }
        }

        // Step 2. Load previously unseen accounts from GOA, if available.
        if (this.goa_service != null) {
            GLib.List<Goa.Object> list = this.goa_service.get_accounts();
            for (int i=0; i < list.length() && !cancellable.is_cancelled(); i++) {
                Goa.Object account = list.nth_data(i);
                string id = to_geary_id(account);
                if (!this.accounts.has_key(id)) {
                    yield this.create_goa_account(account, cancellable);
                }
            }
        }
    }

    /**
     * Removes an account from the manager's set of known accounts.
     *
     * This removes the account from the known set, marks the account
     * as deleted, and queues it for deletion. The account will not
     * actually be deleted until {@link expunge_accounts} is called,
     * and until then the account can be re-added using {@link
     * restore_account}.
     */
    public async void remove_account(Geary.AccountInformation account,
                                     GLib.Cancellable cancellable)
        throws GLib.Error {
        this.accounts.unset(account.id);
        this.removed.add(account);
        yield save_account(account, cancellable);
        account_removed(account);
    }

    /**
     * Restores an account that has previously been removed.
     *
     * This restores an account previously removed via a call to
     * {@link remove_account}, adding it back to the known set, as
     * long as {@link expunge_accounts} has not been called since
     * he account was removed.
     */
    public async void restore_account(Geary.AccountInformation account,
                                      GLib.Cancellable cancellable)
        throws GLib.Error {
        if (this.removed.remove(account)) {
            yield save_account(account, cancellable);
            set_enabled(account, true);
        }
    }

    /**
     * Deletes all local data for all accounts that have been removed.
     */
    public async void expunge_accounts(GLib.Cancellable? cancellable)
        throws GLib.Error {
        while (!this.removed.is_empty && !cancellable.is_cancelled()) {
            yield delete_account(this.removed.remove_at(0), cancellable);
        }
    }

    public async void save_account(Geary.AccountInformation info,
                                   GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Ensure only one async task is saving an info at once, since
        // at least the Engine can cause multiple saves to be called
        // in quick succession when updating special folder config.
        int token = yield info.write_lock.claim_async(cancellable);

        GLib.Error? thrown = null;
        try {
            yield save_account_locked(info, cancellable);
        } catch (GLib.Error err) {
            thrown = err;
        }

        info.write_lock.release(ref token);

        if (thrown != null) {
            throw thrown;
        }
    }

    /**
     * Determines if an account is a GOA account or not.
     */
    public bool is_goa_account(Geary.AccountInformation account) {
        return (account.imap is GoaServiceInformation);
    }

    /**
     * Opens GNOME Settings to add an account of a particular type.
     *
     * Throws an error if it was not possible to open GNOME Settings,
     * or if the given type is not supported for by GOA.
     */
    public async void add_goa_account(Geary.ServiceProvider type,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        switch (type) {
        case Geary.ServiceProvider.GMAIL:
            yield open_goa_settings("add", "google", cancellable);
            break;

        case Geary.ServiceProvider.OUTLOOK:
            yield open_goa_settings("add", "windows_live", cancellable);
            break;

        default:
            throw new Error.INVALID("Not supported for GOA");
        }
    }

    /**
     * Opens GOA settings for the given account in GNOME Settings.
     *
     * Throws an error if it was not possible to open GNOME Settings,
     * or if the given account is not backed by GOA.
     */
    public async void show_goa_account(Geary.AccountInformation account,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        GoaServiceInformation? goa_service =
           account.imap as GoaServiceInformation;
        if (goa_service == null) {
            throw new Error.INVALID("Not a GOA Account");
        }

        yield open_goa_settings(
            goa_service.account.account.id, null, cancellable
        );
    }

    /**
     * Loads an account info from a config directory.
     *
     * Throws an error if the config file was not found, could not be
     * parsed, or doesn't have all required fields.
     */
    private async Geary.AccountInformation
        load_account(string id, GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.File config_dir = this.user_config_dir.get_child(id);
        GLib.File data_dir = this.user_data_dir.get_child(id);

        Geary.ConfigFile config_file = new Geary.ConfigFile(
            config_dir.get_child(Geary.AccountInformation.SETTINGS_FILENAME)
        );

        yield config_file.load(cancellable);

        Geary.ConfigFile.Group config = config_file.get_group(ACCOUNT_CONFIG_GROUP);
        CredentialsProvider provider = CredentialsProvider.from_string(
            config.get_string(
                CREDENTIALS_PROVIDER_KEY,
                CredentialsProvider.LIBSECRET.to_string()
            )
        );

        string primary_email = config.get_string(PRIMARY_EMAIL_KEY);

        Geary.AccountInformation? info = null;
        switch (provider) {
        case CredentialsProvider.LIBSECRET:
            info = new_libsecret_account(id, config, primary_email);
            break;

        case CredentialsProvider.GOA:
            if (this.goa_service != null) {
                Goa.Object? object = this.goa_service.lookup_by_id(to_goa_id(id));
                if (object != null) {
                    info = new_goa_account(id, object);
                    GoaMediator mediator = (GoaMediator) info.imap.mediator;
                    try {
                        yield mediator.update(info, cancellable);
                    } catch (GLib.Error err) {
                        report_problem(
                            new Geary.ProblemReport(
                                Geary.ProblemType.GENERIC_ERROR,
                                err
                            ));
                    }
                } else {
                    // Could not find the GOA object for this account,
                    // but have a working GOA connection, so it must
                    // have been removed. Not much else that we can do
                    // except remove it.
                    throw new Error.GOA_REMOVED("GOA account not found");
                }
            }

            if (info == null) {
                // We have a GOA account, but either GOA is
                // unavailable or the account has changed. Keep it
                // around in case GOA comes back.
                throw new Error.INVALID("GOA not available");
            }
            break;
        }

        info.set_account_directories(config_dir, data_dir);

        info.ordinal = config.get_int(ORDINAL_KEY, info.ordinal);
        if (info.ordinal >= Geary.AccountInformation.next_ordinal)
            Geary.AccountInformation.next_ordinal = info.ordinal + 1;

        info.primary_mailbox = new Geary.RFC822.MailboxAddress(
            config.get_string(REAL_NAME_KEY), primary_email
        );

        info.nickname = config.get_string(NICKNAME_KEY);

        // Store alternate emails in a list of case-insensitive strings
        Gee.List<string> alt_email_list = config.get_string_list(
            ALTERNATE_EMAILS_KEY
        );
        if (alt_email_list.size != 0) {
            foreach (string alt_email in alt_email_list) {
                Geary.RFC822.MailboxAddresses mailboxes = new Geary.RFC822.MailboxAddresses.from_rfc822_string(alt_email);
                foreach (Geary.RFC822.MailboxAddress mailbox in mailboxes.get_all())
                info.add_alternate_mailbox(mailbox);
            }
        }

        info.prefetch_period_days = config.get_int(
            PREFETCH_PERIOD_DAYS_KEY, info.prefetch_period_days
        );
        info.save_sent_mail = config.get_bool(
            SAVE_SENT_MAIL_KEY, info.save_sent_mail
        );
        info.use_email_signature = config.get_bool(
            USE_EMAIL_SIGNATURE_KEY, info.use_email_signature
        );
        info.email_signature = config.get_escaped_string(
            EMAIL_SIGNATURE_KEY, info.email_signature
        );

        info.drafts_folder_path = Geary.AccountInformation.build_folder_path(
            config.get_string_list(DRAFTS_FOLDER_KEY)
        );
        info.sent_mail_folder_path = Geary.AccountInformation.build_folder_path(
            config.get_string_list(SENT_MAIL_FOLDER_KEY)
        );
        info.spam_folder_path = Geary.AccountInformation.build_folder_path(
            config.get_string_list(SPAM_FOLDER_KEY)
        );
        info.trash_folder_path = Geary.AccountInformation.build_folder_path(
            config.get_string_list(TRASH_FOLDER_KEY)
        );
        info.archive_folder_path = Geary.AccountInformation.build_folder_path(
            config.get_string_list(ARCHIVE_FOLDER_KEY)
        );

        info.save_drafts = config.get_bool(SAVE_DRAFTS_KEY, true);

        // If the account has been removed, add it to the removed list
        // and bail out
        Geary.ConfigFile.Group manager_config =
            config_file.get_group(ACCOUNT_MANAGER_GROUP);
        if (manager_config.exists &&
            manager_config.get_bool(REMOVED_KEY, false)) {
            this.removed.add(info);
            throw new Error.LOCAL_REMOVED("Account marked for removal");
        }

        return info;
    }

    private async void save_account_locked(Geary.AccountInformation info,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        File? file = info.settings_file;
        if (file == null) {
            throw new Error.INVALID(
                "Account information does not have a settings file"
            );
        }

        Geary.ConfigFile config_file = new Geary.ConfigFile(file);

        // Load the file first so we maintain old settings
        try {
            yield config_file.load(cancellable);
        } catch (GLib.Error err) {
            // Oh well, just create a new one when saving
            debug("Could not load existing config file: %s", err.message);
        }

        // If the account has been removed, set it as such. Otherwise
        // ensure it is not set as such.
        Geary.ConfigFile.Group manager_config =
            config_file.get_group(ACCOUNT_MANAGER_GROUP);
        if (this.removed.contains(info)) {
            manager_config.set_bool(REMOVED_KEY, true);
        } else if (manager_config.exists) {
            manager_config.remove();
        }

        Geary.ConfigFile.Group config = config_file.get_group(ACCOUNT_CONFIG_GROUP);
        if (info.imap is LocalServiceInformation) {
            config.set_string(
                CREDENTIALS_PROVIDER_KEY,
                CredentialsProvider.LIBSECRET.to_string()
            );
            config.set_string(
                CREDENTIALS_METHOD_KEY,
                info.imap.credentials.supported_method.to_string()
            );

            if (info.service_provider == Geary.ServiceProvider.OTHER) {
                Geary.ConfigFile.Group imap_config = config_file.get_group(
                    IMAP_CONFIG_GROUP
                );
                ((LocalServiceInformation) info.imap).save_settings(imap_config);

                Geary.ConfigFile.Group smtp_config = config_file.get_group(
                    SMTP_CONFIG_GROUP
                );
                ((LocalServiceInformation) info.smtp).save_settings(smtp_config);
            }
        } else if (info.imap is GoaServiceInformation) {
            config.set_string(
                CREDENTIALS_PROVIDER_KEY, CredentialsProvider.GOA.to_string()
            );
        }

        config.set_string(REAL_NAME_KEY, info.primary_mailbox.name);
        config.set_string(PRIMARY_EMAIL_KEY, info.primary_mailbox.address);
        config.set_string(NICKNAME_KEY, info.nickname);
        config.set_string(SERVICE_PROVIDER_KEY, info.service_provider.to_value());
        config.set_int(ORDINAL_KEY, info.ordinal);
        config.set_int(PREFETCH_PERIOD_DAYS_KEY, info.prefetch_period_days);
        config.set_bool(SAVE_SENT_MAIL_KEY, info.save_sent_mail);
        config.set_bool(USE_EMAIL_SIGNATURE_KEY, info.use_email_signature);
        config.set_escaped_string(EMAIL_SIGNATURE_KEY, info.email_signature);
        if (info.alternate_mailboxes != null && info.alternate_mailboxes.size > 0) {
            string[] list = new string[info.alternate_mailboxes.size];
            for (int ctr = 0; ctr < info.alternate_mailboxes.size; ctr++)
                list[ctr] = info.alternate_mailboxes[ctr].to_rfc822_string();

            config.set_string_list(
                ALTERNATE_EMAILS_KEY, Geary.Collection.array_list_wrap<string>(list)
            );
        }

        Gee.LinkedList<string> empty = new Gee.LinkedList<string>();
        config.set_string_list(DRAFTS_FOLDER_KEY, (info.drafts_folder_path != null
            ? info.drafts_folder_path.as_list() : empty));
        config.set_string_list(SENT_MAIL_FOLDER_KEY, (info.sent_mail_folder_path != null
            ? info.sent_mail_folder_path.as_list() : empty));
        config.set_string_list(SPAM_FOLDER_KEY, (info.spam_folder_path != null
            ? info.spam_folder_path.as_list() : empty));
        config.set_string_list(TRASH_FOLDER_KEY, (info.trash_folder_path != null
            ? info.trash_folder_path.as_list() : empty));
        config.set_string_list(ARCHIVE_FOLDER_KEY, (info.archive_folder_path != null
            ? info.archive_folder_path.as_list() : empty));

        config.set_bool(SAVE_DRAFTS_KEY, info.save_drafts);

        debug("Writing config to: %s", file.get_path());
        yield config_file.save(cancellable);
    }

    private async void delete_account(Geary.AccountInformation info,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        SecretMediator? mediator = info.imap.mediator as SecretMediator;
        if (mediator != null) {
            try {
                yield mediator.clear_token(info, info.imap, cancellable);
            } catch (Error e) {
                debug("Error clearing IMAP password: %s", e.message);
            }
        }

        mediator = info.smtp.mediator as SecretMediator;
        if (mediator != null) {
            try {
                yield mediator.clear_token(info, info.smtp, cancellable);
            } catch (Error e) {
                debug("Error clearing IMAP password: %s", e.message);
            }
        }

        if (info.data_dir != null) {
            yield Geary.Files.recursive_delete_async(
                info.data_dir, GLib.Priority.LOW, cancellable
            );
        }

        // Delete config last so if there are any errors above, it
        // will be re-tried at next startup.
        if (info.config_dir != null) {
            yield Geary.Files.recursive_delete_async(
                info.config_dir, GLib.Priority.LOW, cancellable
            );
        }
    }

    private inline AccountState lookup_state(Geary.AccountInformation account) {
        AccountState? state = this.accounts.get(account.id);
        if (state == null) {
            state = new AccountState(account);
            this.accounts.set(account.id, state);
        }
        return state;
    }

    private bool set_enabled(Geary.AccountInformation account, bool is_enabled) {
        bool was_added = !this.accounts.has_key(account.id);
        AccountState state = lookup_state(account);
        Status existing_status = state.status;
        state.enabled = is_enabled;

        bool ret = false;
        if (was_added) {
            account_added(state.account, state.status);
            ret = true;
        } else if (state.status != existing_status) {
            account_status_changed(state.account, state.status);
            ret = true;
        }
        return ret;
    }

    private bool set_available(Geary.AccountInformation account, bool is_available) {
        bool was_added = !this.accounts.has_key(account.id);
        AccountState state = lookup_state(account);
        Status existing_status = state.status;
        state.available = is_available;

        bool ret = false;
        if (was_added) {
            account_added(state.account, state.status);
            ret = true;
        } else if (state.status != existing_status) {
            account_status_changed(state.account, state.status);
            ret = true;
        }
        return ret;
    }

    private async void create_account_dirs(Geary.AccountInformation info,
                                          Cancellable? cancellable)
        throws GLib.Error {
        GLib.File config = this.user_config_dir.get_child(info.id);
        GLib.File data = this.user_data_dir.get_child(info.id);

        yield Geary.Files.make_directory_with_parents(config, cancellable);
        yield Geary.Files.make_directory_with_parents(data, cancellable);

        info.set_account_directories(config, data);
    }

    private inline string to_geary_id(Goa.Object account) {
        return GOA_ID_PREFIX + account.get_account().id;
    }

    private inline string to_goa_id(string id) {
        return id.has_prefix(GOA_ID_PREFIX)
            ? id.substring(GOA_ID_PREFIX.length)
            : id;
    }

    private Geary.AccountInformation
        new_libsecret_account(string id,
                              Geary.ConfigFile.Group config,
                              string fallback_login)
        throws GLib.Error {

        Geary.ServiceProvider provider = Geary.ServiceProvider.for_value(
            config.get_string(SERVICE_PROVIDER_KEY,
                              Geary.ServiceProvider.GMAIL.to_string())
        );
        Geary.Credentials.Method method = Geary.Credentials.Method.from_string(
            config.get_string(CREDENTIALS_METHOD_KEY,
                              Geary.Credentials.Method.PASSWORD.to_string())
        );

        Geary.ConfigFile.Group imap_config =
        config.file.get_group(IMAP_CONFIG_GROUP);
        LocalServiceInformation imap = new_libsecret_service(
            Geary.Protocol.IMAP
        );
        imap_config.set_fallback(config.name, "imap_");
        imap.load_credentials(imap_config, method, fallback_login);

        Geary.ConfigFile.Group smtp_config =
        config.file.get_group(SMTP_CONFIG_GROUP);
        LocalServiceInformation smtp = new_libsecret_service(
            Geary.Protocol.SMTP
        );
        smtp_config.set_fallback(config.name, "smtp_");
        smtp.load_credentials(smtp_config, method, fallback_login);

        // Generic IMAP accounts must load their settings from their
        // config, GMail and others have it hard-coded hence don't
        // need to load it.
        if (provider == Geary.ServiceProvider.OTHER) {
            imap.load_settings(imap_config);
            smtp.load_settings(smtp_config);
        } else {
            provider.setup_service(imap);
            provider.setup_service(smtp);
        }

        return new Geary.AccountInformation(
            id, provider, imap, smtp
        );
    }

    private Geary.AccountInformation new_goa_account(string id,
                                                     Goa.Object account) {
        GoaMediator mediator = new GoaMediator(account);

        Geary.ServiceProvider provider = Geary.ServiceProvider.OTHER;
        switch (account.get_account().provider_type) {
        case "google":
            provider = Geary.ServiceProvider.GMAIL;
            break;

        case "windows_live":
            provider = Geary.ServiceProvider.OUTLOOK;
            break;
        }

        Geary.AccountInformation info = new Geary.AccountInformation(
            id,
            provider,
            new GoaServiceInformation(Geary.Protocol.IMAP, mediator, account),
            new GoaServiceInformation(Geary.Protocol.SMTP, mediator, account)
        );
        info.service_label = account.get_account().provider_name;

        return info;
    }

    private async void create_goa_account(Goa.Object account,
                                          GLib.Cancellable? cancellable) {
        Geary.AccountInformation info = new_goa_account(
            to_geary_id(account), account
        );

        GoaMediator mediator = (GoaMediator) info.imap.mediator;
        // Goa.Account.mail_disabled doesn't seem to reflect if we get
        // get a valid mail object here, so just rely on that instead.
        Goa.Mail? mail = account.get_mail();
        if (mail != null) {
            info.ordinal = Geary.AccountInformation.next_ordinal++;
            info.primary_mailbox = new Geary.RFC822.MailboxAddress(
                mail.name, mail.email_address
            );
            info.nickname = account.get_account().presentation_identity;

            try {
                yield create_account_dirs(info, cancellable);
                yield save_account(info, cancellable);
                yield mediator.update(info, cancellable);
            } catch (GLib.Error err) {
                report_problem(
                    new Geary.ProblemReport(
                        Geary.ProblemType.GENERIC_ERROR,
                        err
                    ));
            }

            if (mediator.is_valid) {
                set_enabled(info, true);
            } else {
                set_available(info, false);
            }
        } else {
            debug(
                "Ignoring GOA %s account %s, mail service not enabled",
                account.get_account().provider_type,
                account.get_account().id
            );
        }
    }

    private async void open_goa_settings(string action,
                                         string? param,
                                         GLib.Cancellable? cancellable)
        throws GLib.Error {
        // This method was based on the implementation from:
        // https://gitlab.gnome.org/GNOME/gnome-calendar/blob/master/src/gcal-source-dialog.c,
        // Courtesy Georges Basile Stavracas Neto <georges.stavracas@gmail.com>
        GLib.DBusProxy settings = yield new GLib.DBusProxy.for_bus(
            GLib.BusType.SESSION,
            GLib.DBusProxyFlags.NONE,
            null,
            "org.gnome.ControlCenter",
            "/org/gnome/ControlCenter",
            "org.gtk.Actions",
            cancellable
        );

        // @s "launch-panel"
        // @av [<@(sav) ("online-accounts", [<@s "add">, <@s "google">])>]
        // @a{sv} {}

        GLib.Variant[] args = new GLib.Variant[] {
            new GLib.Variant.variant(new GLib.Variant.string(action))
        };
        if (param != null) {
            args += new GLib.Variant.variant(new GLib.Variant.string(param));
        }

        GLib.Variant command = new GLib.Variant.tuple(
            new GLib.Variant[] {
                new GLib.Variant.string("online-accounts"),
                new GLib.Variant.array(GLib.VariantType.VARIANT, args)
            }
        );

        GLib.Variant params = new GLib.Variant.tuple(
            new GLib.Variant[] {
                new GLib.Variant.string("launch-panel"),
                new GLib.Variant.array(
                    GLib.VariantType.VARIANT,
                    new GLib.Variant[] {
                        new GLib.Variant.variant(command)
                    }
                ),
                new GLib.Variant("a{sv}")
            }
        );

        yield settings.call(
            "Activate", params, GLib.DBusCallFlags.NONE, -1, cancellable
        );
    }

    private void on_goa_account_added(Goa.Object account) {
        // XXX get a cancellable for this.
        this.create_goa_account.begin(account, null);
    }

    private void on_goa_account_changed(Goa.Object account) {
        string id = to_geary_id(account);
        AccountState? state = this.accounts.get(id);

        if (state != null) {
            // We already know about this account, so check that it is
            // still valid. If not, the account should be disabled,
            // not deleted, since it may be re-enabled at some point.
            GoaMediator mediator = (GoaMediator) state.account.imap.mediator;
            mediator.update.begin(
                state.account,
                null, // XXX Get a cancellable to this somehow
                (obj, res) => {
                    try {
                        mediator.update.end(res);
                    } catch (GLib.Error err) {
                        report_problem(
                            new Geary.AccountProblemReport(
                                Geary.ProblemType.GENERIC_ERROR,
                                state.account,
                                err
                            ));
                    }

                    set_available(state.account, mediator.is_valid);
                }
            );
        } else {
            // We haven't created an account for this GOA account
            // before, so try doing so now.
            //
            // XXX get a cancellable for this.
            this.create_goa_account.begin(account, null);
        }
    }

    private void on_goa_account_removed(Goa.Object account) {
        AccountState? state = this.accounts.get(
            to_geary_id(account)
        );

        if (state != null) {
            set_available(state.account, false);
        }
    }

}
