/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AccountManager : GLib.Object {


    private Geary.Engine engine;
    private GLib.File user_config_dir;
    private GLib.File user_data_dir;


    public AccountManager(Geary.Engine engine,
                          GLib.File user_config_dir,
                          GLib.File user_data_dir) {
        this.engine = engine;
        this.user_config_dir = user_config_dir;
        this.user_data_dir = user_data_dir;
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
                        this.engine.add_account(load_from_file(id));
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
    public Geary.AccountInformation? load_from_file(string id)
        throws Error {

        File file = this.user_config_dir.get_child(id).get_child(Geary.Config.SETTINGS_FILENAME);

        KeyFile key_file = new KeyFile();
        key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);

        Geary.CredentialsMediator mediator;
        Geary.ServiceInformation imap_information;
        Geary.ServiceInformation smtp_information;
        Geary.CredentialsProvider provider;
        Geary.CredentialsMethod method;

        provider = Geary.CredentialsProvider.from_string(Geary.Config.get_string_value(key_file, Geary.Config.GROUP, Geary.Config.CREDENTIALS_PROVIDER_KEY, Geary.CredentialsProvider.LIBSECRET.to_string()));
        method = Geary.CredentialsMethod.from_string(Geary.Config.get_string_value(key_file, Geary.Config.GROUP, Geary.Config.CREDENTIALS_METHOD_KEY, Geary.CredentialsMethod.PASSWORD.to_string()));
        switch (provider) {
            case Geary.CredentialsProvider.LIBSECRET:
                mediator = new SecretMediator();
                imap_information = new Geary.LocalServiceInformation(
                    Geary.Service.IMAP, file, mediator
                );
                smtp_information = new Geary.LocalServiceInformation(
                    Geary.Service.SMTP, file, mediator
                );
                break;
            default:
                mediator = null;
                imap_information = null;
                smtp_information = null;
                break;
        }

        Geary.AccountInformation info = new Geary.AccountInformation(
            id, imap_information, smtp_information
        );
        info.set_account_directories(
            this.user_config_dir.get_child(id),
            this.user_data_dir.get_child(id)
        );

        // This is the only required value at the moment?
        string primary_email = key_file.get_value(Geary.Config.GROUP, Geary.Config.PRIMARY_EMAIL_KEY);
        string real_name = Geary.Config.get_string_value(key_file, Geary.Config.GROUP, Geary.Config.REAL_NAME_KEY);

        info.primary_mailbox = new Geary.RFC822.MailboxAddress(real_name, primary_email);
        info.nickname = Geary.Config.get_string_value(key_file, Geary.Config.GROUP, Geary.Config.NICKNAME_KEY);

        // Store alternate emails in a list of case-insensitive strings
        Gee.List<string> alt_email_list = Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.ALTERNATE_EMAILS_KEY);
        if (alt_email_list.size != 0) {
            foreach (string alt_email in alt_email_list) {
                Geary.RFC822.MailboxAddresses mailboxes = new Geary.RFC822.MailboxAddresses.from_rfc822_string(alt_email);
                foreach (Geary.RFC822.MailboxAddress mailbox in mailboxes.get_all())
                info.add_alternate_mailbox(mailbox);
            }
        }

        info.imap.load_credentials(key_file, primary_email);
        info.smtp.load_credentials(key_file, primary_email);

        info.service_provider = Geary.ServiceProvider.from_string(
            Geary.Config.get_string_value(
                key_file, Geary.Config.GROUP, Geary.Config.SERVICE_PROVIDER_KEY, Geary.ServiceProvider.GMAIL.to_string()));
        info.prefetch_period_days = Geary.Config.get_int_value(
            key_file, Geary.Config.GROUP, Geary.Config.PREFETCH_PERIOD_DAYS_KEY, info.prefetch_period_days);
        info.save_sent_mail = Geary.Config.get_bool_value(
            key_file, Geary.Config.GROUP, Geary.Config.SAVE_SENT_MAIL_KEY, info.save_sent_mail);
        info.ordinal = Geary.Config.get_int_value(
            key_file, Geary.Config.GROUP, Geary.Config.ORDINAL_KEY, info.ordinal);
        info.use_email_signature = Geary.Config.get_bool_value(
            key_file, Geary.Config.GROUP, Geary.Config.USE_EMAIL_SIGNATURE_KEY, info.use_email_signature);
        info.email_signature = Geary.Config.get_escaped_string(
            key_file, Geary.Config.GROUP, Geary.Config.EMAIL_SIGNATURE_KEY, info.email_signature);

        if (info.ordinal >= Geary.AccountInformation.default_ordinal)
            Geary.AccountInformation.default_ordinal = info.ordinal + 1;

        if (info.service_provider == Geary.ServiceProvider.OTHER) {
            info.imap.load_settings(key_file);
            info.smtp.load_settings(key_file);

            if (info.smtp.smtp_use_imap_credentials) {
                info.smtp.credentials.user = info.imap.credentials.user;
                info.smtp.credentials.pass = info.imap.credentials.pass;
            }
        }

        info.drafts_folder_path = Geary.AccountInformation.build_folder_path(
            Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.DRAFTS_FOLDER_KEY));
        info.sent_mail_folder_path = Geary.AccountInformation.build_folder_path(
            Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.SENT_MAIL_FOLDER_KEY));
        info.spam_folder_path = Geary.AccountInformation.build_folder_path(
            Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.SPAM_FOLDER_KEY));
        info.trash_folder_path = Geary.AccountInformation.build_folder_path(
            Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.TRASH_FOLDER_KEY));
        info.archive_folder_path = Geary.AccountInformation.build_folder_path(
            Geary.Config.get_string_list_value(key_file, Geary.Config.GROUP, Geary.Config.ARCHIVE_FOLDER_KEY));

        info.save_drafts = Geary.Config.get_bool_value(key_file, Geary.Config.GROUP, Geary.Config.SAVE_DRAFTS_KEY, true);

        return info;
    }

    public async void store_to_file(Geary.AccountInformation info,
                                    GLib.Cancellable? cancellable = null) {
        // Ensure only one async task is saving an info at once, since
        // at least the Engine can cause multiple saves to be called
        // in quick succession when updating special folder config.
        try {
            int token = yield info.write_lock.claim_async(cancellable);
            yield store_to_file_locked(info, cancellable);
            info.write_lock.release(ref token);
        } catch (Error err) {
            debug("Error locking account info for saving: %s", err.message);
        }
    }

    private async void store_to_file_locked(Geary.AccountInformation info,
                                            GLib.Cancellable? cancellable = null) {
        File? file = info.settings_file;
        if (file == null) {
            debug("Account information does not have a settings filed");
            return;
        }

        if (!file.query_exists(cancellable)) {
            try {
                yield file.create_async(FileCreateFlags.REPLACE_DESTINATION);
            } catch (Error err) {
                debug("Error creating account info file: %s", err.message);
            }
        }

        KeyFile key_file = new KeyFile();
        key_file.set_value(Geary.Config.GROUP, Geary.Config.CREDENTIALS_METHOD_KEY, info.imap.credentials_method.to_string());
        key_file.set_value(Geary.Config.GROUP, Geary.Config.CREDENTIALS_PROVIDER_KEY, info.imap.credentials_provider.to_string());
        key_file.set_value(Geary.Config.GROUP, Geary.Config.REAL_NAME_KEY, info.primary_mailbox.name);
        key_file.set_value(Geary.Config.GROUP, Geary.Config.PRIMARY_EMAIL_KEY, info.primary_mailbox.address);
        key_file.set_value(Geary.Config.GROUP, Geary.Config.NICKNAME_KEY, info.nickname);
        key_file.set_value(Geary.Config.GROUP, Geary.Config.SERVICE_PROVIDER_KEY, info.service_provider.to_string());
        key_file.set_integer(Geary.Config.GROUP, Geary.Config.ORDINAL_KEY, info.ordinal);
        key_file.set_integer(Geary.Config.GROUP, Geary.Config.PREFETCH_PERIOD_DAYS_KEY, info.prefetch_period_days);
        key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SAVE_SENT_MAIL_KEY, info.save_sent_mail);
        key_file.set_boolean(Geary.Config.GROUP, Geary.Config.USE_EMAIL_SIGNATURE_KEY, info.use_email_signature);
        key_file.set_string(Geary.Config.GROUP, Geary.Config.EMAIL_SIGNATURE_KEY, info.email_signature);
        if (info.alternate_mailboxes != null && info.alternate_mailboxes.size > 0) {
            string[] list = new string[info.alternate_mailboxes.size];
            for (int ctr = 0; ctr < info.alternate_mailboxes.size; ctr++)
                list[ctr] = info.alternate_mailboxes[ctr].to_rfc822_string();

            key_file.set_string_list(Geary.Config.GROUP, Geary.Config.ALTERNATE_EMAILS_KEY, list);
        }

        if (info.service_provider == Geary.ServiceProvider.OTHER) {
            info.imap.save_settings(key_file);
            info.smtp.save_settings(key_file);
        }

        key_file.set_string_list(Geary.Config.GROUP, Geary.Config.DRAFTS_FOLDER_KEY, (info.drafts_folder_path != null
            ? info.drafts_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(Geary.Config.GROUP, Geary.Config.SENT_MAIL_FOLDER_KEY, (info.sent_mail_folder_path != null
            ? info.sent_mail_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(Geary.Config.GROUP,Geary. Config.SPAM_FOLDER_KEY, (info.spam_folder_path != null
            ? info.spam_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(Geary.Config.GROUP, Geary.Config.TRASH_FOLDER_KEY, (info.trash_folder_path != null
            ? info.trash_folder_path.as_list().to_array() : new string[] {}));
        key_file.set_string_list(Geary.Config.GROUP, Geary.Config.ARCHIVE_FOLDER_KEY, (info.archive_folder_path != null
            ? info.archive_folder_path.as_list().to_array() : new string[] {}));

        key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SAVE_DRAFTS_KEY, info.save_drafts);

        string data = key_file.to_data();
        string new_etag;

        try {
            yield file.replace_contents_async(data.data, null, false, FileCreateFlags.NONE,
                cancellable, out new_etag);

            this.engine.add_account(info, true);
        } catch (Error err) {
            debug("Error writing to account info file: %s", err.message);
        }
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
