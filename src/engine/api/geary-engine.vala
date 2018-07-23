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
     * Determines if an account with a specific id has added.
     */
    public bool has_account(string id) {
        return (this.accounts != null && this.accounts.has_key(id));
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
     * Determines if an account's IMAP service can be connected to.
     */
    public async void validate_imap(AccountInformation account,
                                    GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_opened();

        if (account.imap.port == 0) {
            account.imap.port = account.imap.use_ssl
                ? Imap.ClientConnection.DEFAULT_PORT_SSL
                : Imap.ClientConnection.DEFAULT_PORT;
        }

        account.untrusted_host.connect(on_untrusted_host);
        account.connect_imap_endpoint();

        // validate IMAP, which requires logging in and establishing
        // an AUTHORIZED cx state
        Geary.Imap.ClientSession? imap_session = new Imap.ClientSession(
            account.imap.endpoint
        );

        // XXX initiate_session_async doesn't seem to actually throw
        // an imap error on login failed. This is not worth fixing
        // until wip/26-proton-mail-bridge lands though, so use
        // signals as a workaround instead.
        bool login_failed = false;
        imap_session.login_failed.connect(() => login_failed = true);

        try {
            yield imap_session.connect_async(cancellable);
            yield imap_session.initiate_session_async(
                account.imap.credentials, cancellable
            );
        } finally {
            try {
                yield imap_session.disconnect_async(cancellable);
            } catch {
                // Oh well
            }
            account.disconnect_endpoints();
            account.untrusted_host.disconnect(on_untrusted_host);
        }

        if (login_failed) {
            // XXX This should be a LOGIN_FAILED error or something
            throw new ImapError.UNAUTHENTICATED("Login failed");
        }
    }

    /**
     * Determines if an account's SMTP service can be connected to.
     */
    public async void validate_smtp(AccountInformation account,
                                    GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_opened();

        if (account.smtp.port == 0) {
            if (account.smtp.use_ssl) {
                account.smtp.port = Smtp.ClientConnection.DEFAULT_PORT_SSL;
            } else if (account.smtp.use_starttls) {
                account.smtp.port = account.smtp.smtp_noauth
                    ? Smtp.ClientConnection.DEFAULT_PORT
                    : Smtp.ClientConnection.DEFAULT_PORT_STARTTLS;
            } else {
                account.smtp.port = Smtp.ClientConnection.DEFAULT_PORT;
            }
        }

        account.untrusted_host.connect(on_untrusted_host);
        account.connect_smtp_endpoint();

        Geary.Smtp.ClientSession? smtp_session = new Geary.Smtp.ClientSession(
            account.smtp.endpoint
        );

        try {
            yield smtp_session.login_async(
                account.get_smtp_credentials(), cancellable
            );
        } finally {
            try {
                yield smtp_session.logout_async(true, cancellable);
            } catch {
                // Oh well
            }
            account.disconnect_endpoints();
            account.untrusted_host.disconnect(on_untrusted_host);
        }
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

        account.connect_imap_endpoint();
        account.connect_smtp_endpoint();
        account.untrusted_host.connect(on_untrusted_host);
        account_available(account);
    }

    /**
     * Removes an account from the engine.
     */
    public void remove_account(AccountInformation account)
        throws GLib.Error {
        check_opened();

        // Ensure account is closed.
        if (this.account_instances.has_key(account.id) &&
            this.account_instances.get(account.id).is_open()) {
            throw new EngineError.CLOSE_REQUIRED(
                "Account %s must be closed before removal", account.id
            );
        }

        if (this.accounts.has_key(account.id)) {
            account.untrusted_host.disconnect(on_untrusted_host);
            account.disconnect_endpoints();

            // Removal *MUST* be done in the following order:
            // 1. Send the account-unavailable signal.
            // Account will be removed client side.
            account_unavailable(account);

            // 2. Remove the account data from the engine.
            this.accounts.unset(account.id);
            this.account_instances.unset(account.id);
        }
    }

    private void on_untrusted_host(AccountInformation account,
                                   ServiceInformation service,
                                   Endpoint.SecurityType security,
                                   TlsConnection cx) {
        untrusted_host(account, service, security, cx);
    }
}
