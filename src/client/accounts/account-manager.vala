/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


/**
 * Current supported credential providers.
 */
public enum CredentialsProvider {
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

    public static CredentialsProvider from_string(string str) throws Error {
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

errordomain AccountError {
    INVALID,
    GOA_UNAVAILABLE,
    GOA_REMOVED;
}

public class AccountManager : GLib.Object {


    private const string ACCOUNT_CONFIG_GROUP = "AccountInformation";
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
    private const string REAL_NAME_KEY = "real_name";
    private const string SAVE_DRAFTS_KEY = "save_drafts";
    private const string SAVE_SENT_MAIL_KEY = "save_sent_mail";
    private const string SENT_MAIL_FOLDER_KEY = "sent_mail_folder";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string SPAM_FOLDER_KEY = "spam_folder";
    private const string TRASH_FOLDER_KEY = "trash_folder";
    private const string USE_EMAIL_SIGNATURE_KEY = "use_email_signature";

    private const string GOA_ID_PREFIX = "goa_";


    private Gee.Map<string,Geary.AccountInformation> enabled_accounts =
        new Gee.HashMap<string,Geary.AccountInformation>();

    private GearyApplication application;
    private GLib.File user_config_dir;
    private GLib.File user_data_dir;

    private Geary.CredentialsMediator? libsecret = null;
    private Goa.Client? goa_service = null;


    /** Fired when a new account is created. */
    public signal void account_added(Geary.AccountInformation added);

    /** Fired when an account is deleted. */
    public signal void account_removed(Geary.AccountInformation removed);

    /** Fired when a SSO account has been updated. */
    public signal void sso_account_updated(Geary.AccountInformation updated);

    /** Fired when a SSO account has been removed. */
    public signal void sso_account_removed(Geary.AccountInformation removed);


    public AccountManager(GearyApplication application,
                          GLib.File user_config_dir,
                          GLib.File user_data_dir) {
        this.application = application;
        this.user_config_dir = user_config_dir;
        this.user_data_dir = user_data_dir;
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

    public LocalServiceInformation new_libsecret_service(Geary.Protocol service) {
        return new LocalServiceInformation(service, libsecret);
    }

    public async void create_account_dirs(Geary.AccountInformation info,
                                          Cancellable? cancellable)
        throws GLib.Error {
        GLib.File config = this.user_config_dir.get_child(info.id);
        GLib.File data = this.user_data_dir.get_child(info.id);

        yield Geary.Files.make_directory_with_parents(config, cancellable);
        yield Geary.Files.make_directory_with_parents(data, cancellable);

        info.set_account_directories(config, data);
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
                        enable_account(info);
                    } catch (GLib.Error err) {
                        // XXX want to report this problem to the user
                        // somehow, but at this point in the app's
                        // lifecycle we don't even have a main window.
                        warning("Ignoring empty/bad config in %s: %s",
                                file.get_name(), err.message);
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
                if (!this.enabled_accounts.has_key(id)) {
                    Geary.AccountInformation? info = null;
                    try {
                        info = yield create_goa_account(account, cancellable);
                    } catch (GLib.Error err) {
                        // XXX want to report this problem to the user
                        // somehow, but at this point in the app's
                        // lifecycle we don't even have a main window.
                        warning("Error creating existing GOA account %s: %s",
                                account.get_account().id, err.message);
                    }
                    if (info != null) {
                        enable_account(info);
                    }
                }
            }
        }
    }

    /**
     * Loads an account info from a config directory.
     *
     * Throws an error if the config file was not found, could not be
     * parsed, or doesn't have all required fields.
     */
    private async Geary.AccountInformation
        load_account(string id, GLib.Cancellable? cancellable)
        throws Error {
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
                } else {
                    // Could not find the GOA object for this account,
                    // but have a working GOA connection, so it must
                    // have been removed.
                    throw new AccountError.GOA_REMOVED("Account not found");
                }
            }

            if (info == null) {
                // XXX We have a GOA account locally, but GOA is
                // unavailable or the GOA account type is no longer
                // supported. Create a dummy, disabled account and let
                // the user deal with it?
            }
            break;

        default:
            throw new AccountError.INVALID("Unhandled credentials provider");
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

        return info;
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

    private async void save_account_locked(Geary.AccountInformation info,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        File? file = info.settings_file;
        if (file == null) {
            throw new AccountError.INVALID(
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
        config.set_string(SERVICE_PROVIDER_KEY, info.service_provider.to_string());
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

    /**
     * Removes an account from the engine and deletes its files from disk.
     */
    public async void remove_account(Geary.AccountInformation info,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.application.engine.remove_account_async(info, cancellable);

        if (info.data_dir == null) {
            warning("Cannot remove account storage directory; nothing to remove");
        } else {
            yield Geary.Files.recursive_delete_async(info.data_dir, cancellable);
        }

        if (info.config_dir == null) {
            warning("Cannot remove account configuration directory; nothing to remove");
        } else {
            yield Geary.Files.recursive_delete_async(info.config_dir, cancellable);
        }

        try {
            yield info.clear_stored_passwords_async(
                Geary.ServiceFlag.IMAP | Geary.ServiceFlag.SMTP
            );
        } catch (Error e) {
            debug("Error clearing passwords: %s", e.message);
        }

        this.enabled_accounts.unset(info.id);
        account_removed(info);
    }

    private void enable_account(Geary.AccountInformation account)
        throws GLib.Error {
        this.enabled_accounts.set(account.id, account);
        this.application.engine.add_account(account);
        account_added(account);
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

        Geary.ServiceProvider provider = Geary.ServiceProvider.from_string(
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
        }

        Geary.AccountInformation info = new Geary.AccountInformation(
            id, imap, smtp
        );
        info.service_provider = provider;
        return info;
    }

    private Geary.AccountInformation? new_goa_account(string id,
                                                      Goa.Object account) {
        Geary.AccountInformation info = null;

        Goa.Mail? mail = account.get_mail();
        Goa.PasswordBased? password = account.get_password_based();
        if (mail != null && password != null) {
            Geary.CredentialsMediator mediator = new GoaMediator(password);
            info = new Geary.AccountInformation(
                id,
                new GoaServiceInformation(Geary.Protocol.IMAP, mediator, mail),
                new GoaServiceInformation(Geary.Protocol.SMTP, mediator, mail)
            );
            info.service_provider = Geary.ServiceProvider.OTHER;
        }

        return info;
    }

    private async Geary.AccountInformation?
        create_goa_account(Goa.Object account,
                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.AccountInformation? info = new_goa_account(
            to_geary_id(account), account
        );
        if (info != null) {
            debug("GOA id: %s", info.id);
            Goa.Mail? mail = account.get_mail();

            info.ordinal = Geary.AccountInformation.next_ordinal++;
            info.primary_mailbox = new Geary.RFC822.MailboxAddress(
                mail.name, mail.email_address
            );
            info.nickname = account.get_account().identity;

            yield create_account_dirs(info, cancellable);
            debug("Created dirs: %s", info.id);
            yield save_account(info, cancellable);
            debug("Saved: %s", info.id);
        }
        return info;
    }

    private void on_goa_account_added(Goa.Object account) {
        this.create_goa_account.begin(
            account, null,
            (obj, res) => {
                try {
                    Geary.AccountInformation? info =
                        this.create_goa_account.end(res);
                    if (info != null) {
                        enable_account(info);
                    }
                } catch (GLib.Error err) {
                    // XXX want to report this problem to the user
                    // somehow, but at this point in the app's
                    // lifecycle we don't even have a main window.
                    warning("Error creating added GOA account %s: %s",
                            account.get_account().id, err.message);
                }
            }
        );
    }

    private void on_goa_account_changed(Goa.Object account) {
        Geary.AccountInformation? info = this.enabled_accounts.get(
            to_geary_id(account)
        );

        if (info != null) {
            this.sso_account_updated(info);
        }
    }

    private void on_goa_account_removed(Goa.Object account) {
        Geary.AccountInformation? info = this.enabled_accounts.get(
            to_geary_id(account)
        );

        if (info != null) {
            this.sso_account_removed(info);
        }
    }

}
