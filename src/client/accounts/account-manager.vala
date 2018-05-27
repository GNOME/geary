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
    LIBSECRET;

    public string to_string() {
        switch (this) {
            case LIBSECRET:
                return "libsecret";

            default:
                assert_not_reached();
        }
    }

    public static CredentialsProvider from_string(string str) throws Error {
        switch (str) {
            case "libsecret":
                return LIBSECRET;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials provider type: %s", str
                );
        }
    }
}

errordomain AccountError {
    INVALID;
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

    private Geary.Engine engine;
    private GLib.File user_config_dir;
    private GLib.File user_data_dir;

    private Geary.CredentialsMediator libsecret;


    public AccountManager(Geary.Engine engine,
                          GLib.File user_config_dir,
                          GLib.File user_data_dir) {
        this.engine = engine;
        this.user_config_dir = user_config_dir;
        this.user_data_dir = user_data_dir;

        this.libsecret = new SecretMediator();
    }

    public Geary.ServiceInformation new_libsecret_service(Geary.Service service,
                                                          Geary.CredentialsMethod method) {
        return new LocalServiceInformation(service, method, libsecret);
    }


    public async void create_account_dirs(Geary.AccountInformation info,
                                          Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.File config = this.user_config_dir.get_child(info.id);
        GLib.File data = this.user_data_dir.get_child(info.id);

        yield Geary.Files.make_directory_with_parents(config, cancellable);
        yield Geary.Files.make_directory_with_parents(data, cancellable);

        info.set_account_directories(config, data);
    }

    public async void add_existing_accounts_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
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
                GLib.FileInfo info = info_list.nth_data(i);
                if (info.get_file_type() == FileType.DIRECTORY) {
                    try {
                        string id = info.get_name();
                        this.engine.add_account(yield load_account(id, cancellable));
                    } catch (GLib.Error err) {
                        // XXX want to report this problem to the user
                        // somehow, but at this point in the app's
                        // lifecycle we don't even have a main window.
                        warning("Ignoring empty/bad config in %s: %s",
                                info.get_name(), err.message);
                    }
                }
            }

            if (len == 0) {
                // We're done
                enumerator = null;
            }
        }
     }

    /**
     * Loads an account info from a config directory.
     *
     * Throws an error if the config file was not found, could not be
     * parsed, or doesn't have all required fields.
     */
    public async Geary.AccountInformation?
        load_account(string id, GLib.Cancellable? cancellable)
        throws Error {
        GLib.File config_dir = this.user_config_dir.get_child(id);
        GLib.File data_dir = this.user_data_dir.get_child(id);

        Geary.ConfigFile config_file = new Geary.ConfigFile(
            config_dir.get_child(Geary.AccountInformation.SETTINGS_FILENAME)
        );

        yield config_file.load(cancellable);

        Geary.ConfigFile.Group config = config_file.get_group(ACCOUNT_CONFIG_GROUP);

        Geary.ConfigFile.Group imap_config = config_file.get_group(IMAP_CONFIG_GROUP);
        imap_config.set_fallback(ACCOUNT_CONFIG_GROUP, "imap_");

        Geary.ConfigFile.Group smtp_config = config_file.get_group(SMTP_CONFIG_GROUP);
        smtp_config.set_fallback(ACCOUNT_CONFIG_GROUP, "smtp_");

        CredentialsProvider provider = CredentialsProvider.from_string(
            config.get_string(
                CREDENTIALS_PROVIDER_KEY,
                CredentialsProvider.LIBSECRET.to_string()
            )
        );

        Geary.CredentialsMethod method = Geary.CredentialsMethod.from_string(
            config.get_string(CREDENTIALS_METHOD_KEY,
                              Geary.CredentialsMethod.PASSWORD.to_string())
        );

        Geary.ServiceInformation imap_info;
        Geary.ServiceInformation smtp_info;
        switch (provider) {
        case CredentialsProvider.LIBSECRET:
            imap_info = new_libsecret_service(Geary.Service.IMAP, method);
            smtp_info = new_libsecret_service(Geary.Service.SMTP, method);
            break;

        default:
            throw new AccountError.INVALID("Unhandled credentials provider");
        }

        Geary.AccountInformation info = new Geary.AccountInformation(
            id, imap_info, smtp_info
        );
        info.set_account_directories(config_dir, data_dir);

        // This is the only required value at the moment?
        string primary_email = config.get_string(PRIMARY_EMAIL_KEY);
        string real_name = config.get_string(REAL_NAME_KEY);

        info.primary_mailbox = new Geary.RFC822.MailboxAddress(
            real_name, primary_email
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

        info.imap.load_credentials(imap_config, primary_email);
        info.smtp.load_credentials(smtp_config, primary_email);

        info.service_provider = Geary.ServiceProvider.from_string(
            config.get_string(SERVICE_PROVIDER_KEY,
                              Geary.ServiceProvider.GMAIL.to_string())
        );
        info.prefetch_period_days = config.get_int(
            PREFETCH_PERIOD_DAYS_KEY, info.prefetch_period_days
        );
        info.save_sent_mail = config.get_bool(
            SAVE_SENT_MAIL_KEY, info.save_sent_mail
        );
        info.ordinal = config.get_int(
            ORDINAL_KEY, info.ordinal
        );
        info.use_email_signature = config.get_bool(
            USE_EMAIL_SIGNATURE_KEY, info.use_email_signature
        );
        info.email_signature = config.get_escaped_string(
            EMAIL_SIGNATURE_KEY, info.email_signature
        );

        if (info.ordinal >= Geary.AccountInformation.next_ordinal)
            Geary.AccountInformation.next_ordinal = info.ordinal + 1;

        if (info.service_provider == Geary.ServiceProvider.OTHER) {
            info.imap.load_settings(imap_config);
            info.smtp.load_settings(smtp_config);

            if (info.smtp.smtp_use_imap_credentials) {
                info.smtp.credentials.user = info.imap.credentials.user;
                info.smtp.credentials.pass = info.imap.credentials.pass;
            }
        }

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
                                   GLib.Cancellable? cancellable = null)
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
                                           GLib.Cancellable? cancellable = null)
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
        Geary.ConfigFile.Group imap_config = config_file.get_group(IMAP_CONFIG_GROUP);
        Geary.ConfigFile.Group smtp_config = config_file.get_group(SMTP_CONFIG_GROUP);

        config.set_string(
            CREDENTIALS_PROVIDER_KEY, CredentialsProvider.LIBSECRET.to_string()
        );
        config.set_string(
            CREDENTIALS_METHOD_KEY, info.imap.credentials_method.to_string()
        );
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

        if (info.service_provider == Geary.ServiceProvider.OTHER) {
            info.imap.save_settings(imap_config);
            info.smtp.save_settings(smtp_config);
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

        yield config_file.save(cancellable);
    }

    /**
     * Deletes an account from disk.  This is used by Geary.Engine and should not
     * normally be invoked directly.
     */
    public async void remove_async(Geary.AccountInformation info, Cancellable? cancellable = null) {
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
            yield info.clear_stored_passwords_async(Geary.ServiceFlag.IMAP | Geary.ServiceFlag.SMTP);
        } catch (Error e) {
            debug("Error clearing passwords: %s", e.message);
        }
    }

}
