/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/** LibSecret password adapter. */
public class SecretMediator : Geary.CredentialsMediator, Object {

    private const string ATTR_LOGIN = "login";
    private const string ATTR_HOST = "host";
    private const string ATTR_PROTO = "proto";

    private static Secret.Schema schema = new Secret.Schema(
        GearyApplication.APP_ID,
        Secret.SchemaFlags.NONE,
        ATTR_LOGIN, Secret.SchemaAttributeType.STRING,
        ATTR_HOST, Secret.SchemaAttributeType.STRING,
        ATTR_PROTO, Secret.SchemaAttributeType.STRING,
        null
    );

    // See Bug 697681
    private static Secret.Schema compat_schema = new Secret.Schema(
        "org.gnome.keyring.NetworkPassword",
        Secret.SchemaFlags.NONE,
        "user", Secret.SchemaAttributeType.STRING,
        "domain", Secret.SchemaAttributeType.STRING,
        "object", Secret.SchemaAttributeType.STRING,
        "protocol", Secret.SchemaAttributeType.STRING,
        "port", Secret.SchemaAttributeType.INTEGER,
        "server", Secret.SchemaAttributeType.STRING,
        "authtype", Secret.SchemaAttributeType.STRING,
        null
    );

    private GearyApplication instance;
    private Geary.Nonblocking.Mutex dialog_mutex = new Geary.Nonblocking.Mutex();


    public SecretMediator() {
        this.instance = GearyApplication.instance;
    }

    public virtual async string? get_password_async(Geary.Service service,
                                                    Geary.AccountInformation account,
                                                    Cancellable? cancellable = null)
    throws Error {
        yield check_unlocked(cancellable);

        string? password = yield Secret.password_lookupv(
            SecretMediator.schema, new_attrs(service, account), cancellable
        );

        if (password == null) {
            password = yield migrate_old_password(service, account, cancellable);
        }

        if (password == null)
            debug("Unable to fetch password in libsecret keyring for %s", account.id);

        return password;
    }

    public virtual async void set_password_async(Geary.Service service,
                                                 Geary.AccountInformation account,
                                                 Cancellable? cancellable = null)
    throws Error {
        yield check_unlocked(cancellable);

        Geary.Credentials credentials = get_credentials(service, account);
        try {
            yield do_store(service, account, credentials.pass, cancellable);
        } catch (Error e) {
            debug("Unable to store password for \"%s\" %s in libsecret keyring: %s",
                  account.id, service.name(), e.message);
        }
    }

    public virtual async void clear_password_async(Geary.Service service,
                                                   Geary.AccountInformation account,
                                                   Cancellable? cancellable = null)
    throws Error {
        yield check_unlocked(cancellable);

        Geary.Credentials credentials = get_credentials(service, account);
        yield Secret.password_clearv(SecretMediator.schema,
                                     new_attrs(service, account),
                                     cancellable);

        // Remove legacy formats
        // <= 0.11
        yield Secret.password_clear(
            compat_schema,
            cancellable,
            "user", get_legacy_user(service, account.primary_mailbox.address)
        );
        // <= 0.6
        yield Secret.password_clear(
            compat_schema,
            cancellable,
            "user", get_legacy_user(service, credentials.user)
         );
    }

    public virtual async bool prompt_passwords_async(Geary.ServiceFlag services,
        Geary.AccountInformation account_information,
        out string? imap_password, out string? smtp_password,
        out bool imap_remember_password, out bool smtp_remember_password) throws Error {
        // Our dialog doesn't support asking for both at once, even though this
        // API would indicate it does.  We need to revamp the API.
        assert(!services.has_imap() || !services.has_smtp());
        
        // to prevent multiple dialogs from popping up at the same time, use a nonblocking mutex
        // to serialize the code
        int token = yield dialog_mutex.claim_async(null);

        // Ensure main window present to the window
        this.instance.present();

        PasswordDialog password_dialog = new PasswordDialog(
            this.instance.get_active_window(),
            services.has_smtp(),
            account_information,
            services
        );
        bool result = password_dialog.run();

        dialog_mutex.release(ref token);

        if (!result) {
            // user cancelled the dialog
            imap_password = null;
            smtp_password = null;
            imap_remember_password = false;
            smtp_remember_password = false;
            return false;
        }
        
        // password_dialog.password should never be null at this point. It will only be null when
        // password_dialog.run() returns false, in which case we have already returned.
        if (services.has_smtp()) {
            imap_password = null;
            imap_remember_password = false;
            smtp_password = password_dialog.password;
            smtp_remember_password = password_dialog.remember_password;
        } else {
            imap_password = password_dialog.password;
            imap_remember_password = password_dialog.remember_password;
            smtp_password = null;
            smtp_remember_password = false;
        }
        return true;
    }

    // Ensure the default collection unlocked.  Try to unlock it since
    // the user may be running in a limited environment and it would
    // prevent us from prompting the user multiple times in one
    // session. See Bug 784300.
    private async void check_unlocked(Cancellable? cancellable = null)
    throws Error {
        Secret.Service service = yield Secret.Service.get(
            Secret.ServiceFlags.OPEN_SESSION, cancellable
        );
        Secret.Collection? collection = yield Secret.Collection.for_alias(
            service,
            Secret.COLLECTION_DEFAULT,
            Secret.CollectionFlags.NONE,
            cancellable
        );

        // For custom desktop setups, it is possible that the current
        // session has a service responding on DBus but no password
        // keyring. There's no much we can do in this case except just
        // check for the collection being null so we don't crash. See
        // Bug 795328.
        if (collection != null && collection.get_locked()) {
            List<Secret.Collection> to_lock = new List<Secret.Collection>();
            to_lock.append(collection);
            List<DBusProxy> unlocked;
            yield service.unlock(to_lock, cancellable, out unlocked);
            if (unlocked.length() != 0) {
                // XXX
            }
        }
    }

    private async void do_store(Geary.Service service,
                                Geary.AccountInformation account,
                                string password,
                                Cancellable? cancellable)
    throws Error {
        yield Secret.password_storev(
            SecretMediator.schema,
            new_attrs(service, account),
            Secret.COLLECTION_DEFAULT,
            "Geary %s password".printf(service.name()),
            password,
            cancellable
        );
    }

    private HashTable<string,string> new_attrs(Geary.Service service,
                                               Geary.AccountInformation account,
                                               Cancellable? cancellable = null) {
        string login = "";
        string host = "";
        switch (service) {
        case Geary.Service.IMAP:
            login = account.imap.credentials.user;
            host = account.imap.endpoint.remote_address.get_hostname();
            break;

        case Geary.Service.SMTP:
            login = account.smtp.credentials.user;
            host = account.smtp.endpoint.remote_address.get_hostname();
            break;

        default:
            warning("Unknown service type");
            break;
        }

        HashTable<string,string> table = new HashTable<string,string>(str_hash, str_equal);
        table.insert(ATTR_PROTO, service.name());
        table.insert(ATTR_HOST, host);
        table.insert(ATTR_LOGIN, login);
        return table;
    }

    private Geary.Credentials get_credentials(Geary.Service service, Geary.AccountInformation account) {
        switch (service) {
        case Geary.Service.IMAP:
            return account.imap.credentials;

        case Geary.Service.SMTP:
            return account.smtp.credentials;

        default:
            assert_not_reached();
        }
    }

    private async string? migrate_old_password(Geary.Service service,
                                               Geary.AccountInformation account,
                                               Cancellable? cancellable = null)
    throws Error {
        // <= 0.11
        string? password = yield Secret.password_lookup(
            compat_schema,
            cancellable,
            "user", get_legacy_user(service, account.primary_mailbox.address)
        );

        // <= 0.6
        if (password == null) {
            Geary.Credentials creds = get_credentials(service, account);
            string user = get_legacy_user(service, creds.user);
            password = yield Secret.password_lookup(
                compat_schema,
                cancellable,
                "user", user
            );

            // Clear the old password
            if (password != null) {
                yield Secret.password_clear(
                    compat_schema,
                    cancellable,
                    "user", user
                );
            }
        }

        if (password != null)
            yield do_store(service, account, password, cancellable);

        return password;
    }

    private string get_legacy_user(Geary.Service service, string user) {
        switch (service) {
        case Geary.Service.IMAP:
            return "org.yorba.geary imap_username:" + user;
        case Geary.Service.SMTP:
            return "org.yorba.geary smtp_username:" + user;
        default:
            warning("Unknown service type");
            return "";
        }
    }

}
