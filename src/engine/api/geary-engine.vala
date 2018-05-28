/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The Geary email engine initial entry points.
 *
 * Engine represents and contains interfaces into the rest of the email library.  It's a singleton
 * class (see {@link instance}) with various signals for event notification.  Engine is initialized
 * by calling {@link open_async} and closed with {@link close_async}.
 *
 * Engine can list existing {@link Account} objects and create/delete them.  It can also validate
 * changes to Accounts prior to saving those changes.
 */
public class Geary.Engine : BaseObject {

    private const string ID_PREFIX = "account_";
    private const string ID_FORMAT = "account_%02u";

    [Flags]
    public enum ValidationOption {
        NONE = 0,
        CHECK_CONNECTIONS,
        UPDATING_EXISTING;
        
        public inline bool is_all_set(ValidationOption options) {
            return (options & this) == options;
        }
    }
    
    [Flags]
    public enum ValidationResult {
        OK = 0,
        INVALID_NICKNAME,
        EMAIL_EXISTS,
        IMAP_CONNECTION_FAILED,
        IMAP_CREDENTIALS_INVALID,
        SMTP_CONNECTION_FAILED,
        SMTP_CREDENTIALS_INVALID;
        
        public inline bool is_all_set(ValidationResult result) {
            return (result & this) == result;
        }
    }
    
    private static Engine? _instance = null;
    public static Engine instance {
        get {
            return (_instance != null) ? _instance : (_instance = new Engine());
        }
    }

    /** Location of the directory containing shared resource files. */
    public File? resource_dir { get; private set; default = null; }

    private Gee.HashMap<string, AccountInformation>? accounts = null;
    private Gee.HashMap<string, Account>? account_instances = null;
    private bool is_initialized = false;
    private bool is_open = false;

    /**
     * Fired when the engine is opened and all the existing accounts are loaded.
     */
    public signal void opened();

    /**
     * Fired when the engine is closed.
     */
    public signal void closed();

    /**
     * Fired when an account becomes available in the engine.
     *
     * Accounts are made available as soon as they're added to the
     * engine.
     */
    public signal void account_available(AccountInformation account);

    /**
     * Fired when an account becomes unavailable in the engine.
     *
     * Accounts are become available as soon when they are removed from the
     * engine or the engine is closed.
     */
    public signal void account_unavailable(AccountInformation account);

    /**
     * Fired when an {@link Endpoint} associated with the {@link AccountInformation} reports
     * TLS certificate warnings during connection.
     *
     * This may be fired during normal operation or while validating the AccountInformation, in
     * which case there is no {@link Account} associated with it.
     */
    public signal void untrusted_host(AccountInformation account,
                                      ServiceInformation service,
                                      Endpoint.SecurityType security,
                                      TlsConnection cx);

    // Public so it can be tested
    public Engine() {
    }

    private void check_opened() throws EngineError {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Geary.Engine instance not open");
    }
    
    // This can't be called from within the ctor, as initialization code may want to access the
    // Engine instance to make their own calls and, in particular, subscribe to signals.
    //
    // TODO: It would make sense to have a terminate_library() call, but it technically should not
    // be called until the application is exiting, not merely if the Engine is closed, as termination
    // means shutting down resources for good
    private void initialize_library() {
        if (is_initialized)
            return;
        
        is_initialized = true;

        Logging.init();
        RFC822.init();
        Imap.init();
        HTML.init();
    }

    /**
     * Initializes the engine so that accounts can be added to it.
     */
    public async void open_async(GLib.File resource_dir,
                                 GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        // initialize *before* opening the Engine ... all initialize code should assume the Engine
        // is closed
        initialize_library();

        if (is_open)
            throw new EngineError.ALREADY_OPEN("Geary.Engine instance already open");

        this.resource_dir = resource_dir;

        accounts = new Gee.HashMap<string, AccountInformation>();
        account_instances = new Gee.HashMap<string, Account>();

        is_open = true;

        opened();
   }

    /**
     * Uninitializes the engine, and removes all known accounts.
     */
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;

        Gee.Collection<AccountInformation> unavailable_accounts = accounts.values;
        accounts.clear();

        foreach(AccountInformation account in unavailable_accounts)
            account_unavailable(account);

        resource_dir = null;
        accounts = null;
        account_instances = null;

        is_open = false;
        closed();
    }

    /**
     * Returns a current account given its id.
     *
     * Throws an error if the engine has not been opened or if the
     * requested account does not exist.
     */
    public AccountInformation get_account(string id) throws Error {
        check_opened();

        AccountInformation? info = accounts.get(id);
        if (info == null) {
            throw new EngineError.NOT_FOUND("No such account: %s", id);
        }
        return info;
    }

    /**
     * Returns the current accounts list as a map keyed by account id.
     *
     * Throws an error if the engine has not been opened.
     */
    public Gee.Map<string, AccountInformation> get_accounts() throws Error {
        check_opened();

        return accounts.read_only_view;
    }

    /**
     * Returns a new account, not yet stored on disk.
     *
     * Throws an error if the engine has not been opened or if an
     * invalid account id is generated.
     */
    public AccountInformation create_orphan_account(ServiceInformation imap,
                                                    ServiceInformation smtp)
        throws GLib.Error {
        check_opened();

        // We might want to allow the client to specify the id, but
        // just generate one here for now: Use a common prefix and a
        // numeric suffix, starting at 1. To generate the next id,
        // find the last account and increment its suffix.

        string? last_account = this.accounts.keys.fold<string?>((next, last) => {
                string? result = last;
                if (next.has_prefix(ID_PREFIX)) {
                    result = (last == null || strcmp(last, next) < 0) ? next : last;
                }
                return result;
            },
            null);
        uint next_id = 1;
        if (last_account != null) {
            next_id = int.parse(last_account.substring(ID_PREFIX.length)) + 1;
        }
        string id = ID_FORMAT.printf(next_id);

        if (this.accounts.has_key(id))
            throw new EngineError.ALREADY_EXISTS("Account %s already exists", id);

        return new AccountInformation(id, imap, smtp);
    }

    /**
     * Returns whether the account information "validates."  If validate_connection is true,
     * we check if we can connect to the endpoints and authenticate using the supplied credentials.
     */
    public async ValidationResult validate_account_information_async(AccountInformation account,
        ValidationOption options, Cancellable? cancellable = null) throws Error {
        check_opened();
        
        ValidationResult error_code = ValidationResult.OK;
        
        // Make sure the account nickname and email is not in use.
        foreach (AccountInformation a in get_accounts().values) {
            // Don't need to check a's alternate_emails since they
            // can't be set at account creation time
            bool has_email = account.has_email_address(a.primary_mailbox);

            if (!has_email && Geary.String.stri_equal(account.nickname, a.nickname))
                error_code |= ValidationResult.INVALID_NICKNAME;

            // if creating a new Account, don't allow an existing email address
            if (!options.is_all_set(ValidationOption.UPDATING_EXISTING) && has_email)
                error_code |= ValidationResult.EMAIL_EXISTS;
        }
        
        // If we don't need to validate the connection, exit out here.
        if (!options.is_all_set(ValidationOption.CHECK_CONNECTIONS))
            return error_code;

        account.untrusted_host.connect(on_untrusted_host);
        account.connect_endpoints();

        // validate IMAP, which requires logging in and establishing an AUTHORIZED cx state
        Geary.Imap.ClientSession? imap_session = new Imap.ClientSession(
            account.imap.endpoint
        );
        try {
            yield imap_session.connect_async(cancellable);
        } catch (Error err) {
            debug("Error connecting to IMAP server: %s", err.message);
            error_code |= ValidationResult.IMAP_CONNECTION_FAILED;
        }

        if (!error_code.is_all_set(ValidationResult.IMAP_CONNECTION_FAILED)) {
            try {
                yield imap_session.initiate_session_async(account.imap.credentials, cancellable);
                
                // Connected and initiated, still need to be sure connection authorized
                Imap.MailboxSpecifier current_mailbox;
                if (imap_session.get_protocol_state(out current_mailbox) != Imap.ClientSession.ProtocolState.AUTHORIZED)
                    error_code |= ValidationResult.IMAP_CREDENTIALS_INVALID;
            } catch (Error err) {
                debug("Error validating IMAP account info: %s", err.message);
                if (err is ImapError.UNAUTHENTICATED)
                    error_code |= ValidationResult.IMAP_CREDENTIALS_INVALID;
                else
                    error_code |= ValidationResult.IMAP_CONNECTION_FAILED;
            }
        }

        try {
            yield imap_session.disconnect_async(cancellable);
        } catch (Error err) {
            // ignored
        } finally {
            imap_session = null;
        }

        // SMTP is simpler, merely see if login works and done (throws
        // an SmtpError if not)
        Geary.Smtp.ClientSession? smtp_session = new Geary.Smtp.ClientSession(
            account.smtp.endpoint
        );
        try {
            yield smtp_session.login_async(account.smtp.credentials, cancellable);
        } catch (Error err) {
            debug("Error validating SMTP account info: %s", err.message);
            if (err is SmtpError.AUTHENTICATION_FAILED)
                error_code |= ValidationResult.SMTP_CREDENTIALS_INVALID;
            else
                error_code |= ValidationResult.SMTP_CONNECTION_FAILED;
        }
        
        try {
            yield smtp_session.logout_async(true, cancellable);
        } catch (Error err) {
            // ignored
        } finally {
            smtp_session = null;
        }

        account.disconnect_endpoints();
        account.untrusted_host.disconnect(on_untrusted_host);

        return error_code;
    }
    
    /**
     * Creates a Geary.Account from a Geary.AccountInformation (which is what
     * other methods in this interface deal in).
     */
    public Geary.Account get_account_instance(AccountInformation account_information)
        throws Error {
        check_opened();

        if (account_instances.has_key(account_information.id))
            return account_instances.get(account_information.id);

        ImapDB.Account local_account = new ImapDB.Account(account_information);
        Geary.Account account;
        switch (account_information.service_provider) {
            case ServiceProvider.GMAIL:
                account = new ImapEngine.GmailAccount(
                    "Gmail:%s".printf(account_information.id),
                    account_information,
                    local_account
                );
            break;

            case ServiceProvider.YAHOO:
                account = new ImapEngine.YahooAccount(
                    "Yahoo:%s".printf(account_information.id),
                    account_information,
                    local_account
                );
            break;

            case ServiceProvider.OUTLOOK:
                account = new ImapEngine.OutlookAccount(
                    "Outlook:%s".printf(account_information.id),
                    account_information,
                    local_account
                );
            break;

            case ServiceProvider.OTHER:
                account = new ImapEngine.OtherAccount(
                    "Other:%s".printf(account_information.id),
                    account_information,
                    local_account
                );
            break;

            default:
                assert_not_reached();
        }

        account_instances.set(account_information.id, account);
        return account;
    }

    /**
     * Adds the account to be tracked by the engine.
     */
    public void add_account(AccountInformation account) throws Error {
        check_opened();

        if (accounts.has_key(account.id)) {
            throw new EngineError.ALREADY_EXISTS(
                "Account id '%s' already exists", account.id
            );
        }

        accounts.set(account.id, account);

        account.connect_endpoints();
        account.untrusted_host.connect(on_untrusted_host);
        account_available(account);
    }

    /**
     * Removes an account from the engine.
     */
    public async void remove_account_async(AccountInformation account,
                                           Cancellable? cancellable = null) throws Error {
        check_opened();

        // Ensure account is closed.
        if (account_instances.has_key(account.id) && account_instances.get(account.id).is_open()) {
            throw new EngineError.CLOSE_REQUIRED("Account %s must be closed before removal",
                account.id);
        }

        if (accounts.has_key(account.id)) {
            account.untrusted_host.disconnect(on_untrusted_host);
            account.disconnect_endpoints();

            // Removal *MUST* be done in the following order:
            // 1. Send the account-unavailable signal.
            // Account will be removed client side.
            account_unavailable(account);

            // 2. Remove the account data from the engine.
            account_instances.unset(account.id);
        }
    }

    private void on_untrusted_host(AccountInformation account,
                                   ServiceInformation service,
                                   Endpoint.SecurityType security,
                                   TlsConnection cx) {
        untrusted_host(account, service, security, cx);
    }
}
