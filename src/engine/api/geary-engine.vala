/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Manages email account instances and their life-cycle.
 *
 * An engine represents and contains interfaces into the rest of the
 * email library. Instances are initialized by calling {@link
 * open_async} and closed with {@link close_async}. Use this class for
 * verifying and adding {@link AccountInformation} objects to check
 * and start using email accounts.
 */
public class Geary.Engine : BaseObject {


    // Set low to avoid leaving the user hanging too long when
    // validating a service.
    private const uint VALIDATION_TIMEOUT = 15;


    public static Engine instance {
        get {
            return (_instance != null) ? _instance : (_instance = new Engine());
        }
    }
    private static Engine? _instance = null;


    // Workaround for Vala issue #659. See shared_endpoints below.
    private class EndpointWeakRef {

        GLib.WeakRef weak_ref;

        public EndpointWeakRef(Endpoint endpoint) {
            this.weak_ref = GLib.WeakRef(endpoint);
        }

        public Endpoint? get() {
            return this.weak_ref.get() as Endpoint;
        }

    }


    /** Determines if any accounts have been added to this instance. */
    public bool has_accounts {
        get { return this.accounts != null && !this.accounts.is_empty; }
    }

    /** Location of the directory containing shared resource files. */
    public File? resource_dir { get; private set; default = null; }

    private Gee.HashMap<string, AccountInformation>? accounts = null;
    private Gee.HashMap<string, Account>? account_instances = null;
    private bool is_initialized = false;
    private bool is_open = false;

    // Would use a `weak Endpoint` value type for this map instead of
    // the custom class, but we can't currently reassign built-in
    // weak refs back to a strong ref at the moment, nor use a
    // GLib.WeakRef as a generics param. See Vala issue #659.
    private Gee.Map<string,EndpointWeakRef?> shared_endpoints =
        new Gee.HashMap<string,EndpointWeakRef?>();

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
                                    ServiceInformation service,
                                    GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_opened();

        // Use a new endpoint since we use a different socket timeout
        Endpoint endpoint = new_endpoint(
            account.service_provider, service, VALIDATION_TIMEOUT
        );
        ulong untrusted_id = endpoint.untrusted_host.connect(
            (security, cx) => account.untrusted_host(service, security, cx)
        );

        Geary.Imap.ClientSession client = new Imap.ClientSession(endpoint);
        GLib.Error? imap_err = null;
        try {
            yield client.connect_async(cancellable);
        } catch (GLib.Error err) {
            imap_err = err;
        }

        if (imap_err == null) {
            try {
                yield client.initiate_session_async(
                    service.credentials, cancellable
                );
            } catch (GLib.Error err) {
                imap_err = err;
            }

            try {
                yield client.disconnect_async(cancellable);
            } catch {
                // Oh well
            }
        }

        // This always needs to be disconnected, even when there's an
        // error
        endpoint.disconnect(untrusted_id);

        if (imap_err != null) {
            throw imap_err;
        }
    }

    /**
     * Determines if an account's SMTP service can be connected to.
     */
    public async void validate_smtp(AccountInformation account,
                                    ServiceInformation service,
                                    Credentials? incoming_credentials,
                                    GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_opened();

        // Use a new endpoint since we use a different socket timeout
        Endpoint endpoint = new_endpoint(
            account.service_provider, service, VALIDATION_TIMEOUT
        );
        ulong untrusted_id = endpoint.untrusted_host.connect(
            (security, cx) => account.untrusted_host(service, security, cx)
        );

        Credentials? credentials = null;
        switch (service.credentials_requirement) {
        case USE_INCOMING:
            credentials = incoming_credentials;
            break;
        case CUSTOM:
            credentials = service.credentials;
            break;
        }

        Geary.Smtp.ClientSession client = new Geary.Smtp.ClientSession(endpoint);
        GLib.Error? login_err = null;
        try {
            yield client.login_async(credentials, cancellable);
        } catch (GLib.Error err) {
            login_err = err;
        }

        try {
            yield client.logout_async(true, cancellable);
        } catch {
            // Oh well
        }

        // This always needs to be disconnected, even when there's an
        // error
        endpoint.disconnect(untrusted_id);

        if (login_err != null) {
            throw login_err;
        }
    }

    /**
     * Creates a Geary.Account from a Geary.AccountInformation (which is what
     * other methods in this interface deal in).
     */
    public Geary.Account get_account_instance(AccountInformation config)
        throws Error {
        check_opened();

        if (account_instances.has_key(config.id))
            return account_instances.get(config.id);

        ImapDB.Account local = new ImapDB.Account(
            config,
            config.data_dir,
            this.resource_dir.get_child("sql")
        );
        Endpoint incoming_remote = get_shared_endpoint(
            config.service_provider, config.incoming
        );
        Endpoint outgoing_remote = get_shared_endpoint(
            config.service_provider, config.outgoing
        );

        Geary.Account account;
        switch (config.service_provider) {
            case ServiceProvider.GMAIL:
                account = new ImapEngine.GmailAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;

            case ServiceProvider.YAHOO:
                account = new ImapEngine.YahooAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;

            case ServiceProvider.OUTLOOK:
                account = new ImapEngine.OutlookAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;

            case ServiceProvider.OTHER:
                account = new ImapEngine.OtherAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;

            default:
                assert_not_reached();
        }

        account_instances.set(config.id, account);
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
            // Send the account-unavailable signal, account will be
            // removed client side.
            account_unavailable(account);

            // Then remove the account data from the engine.
            this.accounts.unset(account.id);
            this.account_instances.unset(account.id);
        }
    }

    /**
     * Changes the service configuration for an account.
     *
     * This updates an account's service configuration with the given
     * configuration, by replacing the account's existing
     * configuration for that service. The corresponding {@link
     * Account.incoming} or {@link Account.outgoing} client service
     * will also be updated so that the new configuration will start
     * taking effect immediately.
     */
    public async void update_account_service(AccountInformation account,
                                             ServiceInformation updated,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        Account? impl = this.account_instances.get(account.id);
        if (impl == null) {
            throw new EngineError.BAD_PARAMETERS(
                "Account has not been added to the engine: %s", account.id
            );
        }

        ClientService? service = null;
        switch (updated.protocol) {
        case Protocol.IMAP:
            account.incoming = updated;
            service = impl.incoming;
            break;

        case Protocol.SMTP:
            account.outgoing = updated;
            service = impl.outgoing;
            break;
        }

        Endpoint remote = get_shared_endpoint(account.service_provider, updated);
        yield service.update_configuration(updated, remote, cancellable);
        account.changed();
    }

    private Geary.Endpoint get_shared_endpoint(ServiceProvider provider,
                                               ServiceInformation service) {
        // Key includes TLS method since endpoints encapsulate
        // TLS-specific state
        string key = "%s:%u/%s".printf(
            service.host,
            service.port,
            service.transport_security.to_value()
        );

        Endpoint? shared = null;
        EndpointWeakRef? cached = this.shared_endpoints.get(key);
        if (cached != null) {
            shared = cached.get() as Endpoint;
        }
        if (shared == null) {
            uint timeout = service.protocol == Protocol.IMAP
                ? Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC
                : Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC;

            shared = new_endpoint(provider, service, timeout);

            // XXX this is pretty hacky, move this back into the
            // OutlookAccount somehow
            if (provider == ServiceProvider.OUTLOOK) {
                // As of June 2016, outlook.com's IMAP servers have a bug
                // where a large number (~50) of pipelined STATUS commands on
                // mailboxes with many messages will eventually cause it to
                // break command parsing and return a BAD response, causing us
                // to drop the connection. Limit the number of pipelined
                // commands per batch to work around this.  See b.g.o Bug
                // 766552
                shared.max_pipeline_batch_size = 25;
            }

            this.shared_endpoints.set(key, new EndpointWeakRef(shared));
        }

        return shared;
    }

    private inline Geary.Endpoint new_endpoint(ServiceProvider provider,
                                               ServiceInformation service,
                                               uint timeout) {
        return new Endpoint(
            new NetworkAddress(service.host, service.port),
            service.transport_security,
            timeout
        );
    }

}
