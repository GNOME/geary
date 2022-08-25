/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Manages email account instances and their life-cycle.
 *
 * An engine represents and contains interfaces into the rest of the
 * email library. Instances are initialized by constructing them and
 * closed by calling {@link close}. Also use this class for verifying
 * and adding {@link AccountInformation} objects to check and start
 * using email accounts.
 */
public class Geary.Engine : BaseObject {


    // Set low to avoid leaving the user hanging too long when
    // validating a service.
    private const uint VALIDATION_TIMEOUT = 15;


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


    private static bool is_initialized = false;

    static construct {
        // Work around GNOME/glib#541
        typeof(Imap.MailboxAttributes).name();
    }

    // This can't be called from within the ctor, as initialization
    // code may want to access the Engine instance to make their own
    // calls and, in particular, subscribe to signals.
    //
    // TODO: It would make sense to have a terminate_library() call,
    // but it technically should not be called until the application
    // is exiting, not merely if the Engine is closed, as termination
    // means shutting down resources for good
    private static void initialize_library() {
        if (!Engine.is_initialized) {
            Engine.is_initialized = true;

            Logging.init();
            RFC822.init();
            Imap.init();
            HTML.init();
        }
    }


    /** Determines if any accounts have been added to this instance. */
    public bool has_accounts {
        get { return this.is_open && !this.accounts.is_empty; }
    }

    /** Determines the number of accounts added to this instance. */
    public uint accounts_count {
        get { return this.accounts.size; }
    }

    /** Location of the directory containing shared resource files. */
    public File resource_dir { get; private set; }

    private bool is_open = true;
    private Gee.List<Account> accounts = new Gee.ArrayList<Account>();

    // Would use a `weak Endpoint` value type for this map instead of
    // the custom class, but we can't currently reassign built-in
    // weak refs back to a strong ref at the moment, nor use a
    // GLib.WeakRef as a generics param. See Vala issue #659.
    private Gee.Map<string,EndpointWeakRef?> shared_endpoints =
        new Gee.HashMap<string,EndpointWeakRef?>();

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


    /** Constructs a new engine instance. */
    public Engine(GLib.File resource_dir) {
        Engine.initialize_library();
        this.resource_dir = resource_dir;
   }

    /**
     * Uninitializes the engine, and removes all known accounts.
     */
    public void close()
        throws GLib.Error {
        if (is_open) {
            // Copy the collection of accounts so they can be removed
            // from it
            foreach (var account in traverse(this.accounts).to_linked_list()) {
                remove_account(account.information);
            }
            this.accounts.clear();
            this.is_open = false;
        }
    }

    /**
     * Determines if an account with a specific configuration has been added.
     */
    public bool has_account(AccountInformation config) {
        return this.accounts.any_match(account => account.information == config);
    }

    /**
     * Returns the account for the given configuration, if present.
     *
     * Throws an error if the engine has not been opened or if the
     * requested account does not exist.
     */
    public Account get_account(AccountInformation config) throws GLib.Error {
        check_opened();

        Account? account = this.accounts.first_match(
            account => account.information == config
        );
        if (account == null) {
            throw new EngineError.NOT_FOUND("No such account");
        }
        return account;
    }

    /**
     * Returns the account for the given configuration id, if present.
     *
     * Throws an error if the engine has not been opened or if the
     * requested account does not exist.
     */
    public Account get_account_for_id(string id) throws GLib.Error {
        check_opened();

        Account? account = this.accounts.first_match(
            account => account.information.id == id
        );
        if (account == null) {
            throw new EngineError.NOT_FOUND("No such account");
        }
        return account;
    }

    /**
     * Returns a read-only collection of current accounts.
     *
     * The collection is guaranteed to be ordered by {@link
     * AccountInformation.compare_ascending}.
     *
     * Throws an error if the engine has not been opened.
     */
    public Gee.Collection<Account> get_accounts() throws GLib.Error {
        check_opened();

        return accounts.read_only_view;
    }

    /**
     * Adds the account to the engine.
     *
     * The account will not be automatically opened, this must be done
     * once added.
     */
    public void add_account(AccountInformation config) throws GLib.Error {
        check_opened();

        if (has_account(config)) {
            throw new EngineError.ALREADY_EXISTS("Account already exists");
        }

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

            case ServiceProvider.OUTLOOK:
                account = new ImapEngine.OutlookAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;

            default:
                account = new ImapEngine.OtherAccount(
                    config, local, incoming_remote, outgoing_remote
                );
            break;
        }

        config.notify["ordinal"].connect(on_account_ordinal_changed);
        this.accounts.add(account);
        sort_accounts();
        account_available(config);
    }

    /**
     * Removes an account from the engine.
     *
     * The account must be closed before removing it.
     */
    public void remove_account(AccountInformation config) throws GLib.Error {
        check_opened();

        Account account = get_account(config);
        if (account.is_open()) {
            throw new EngineError.CLOSE_REQUIRED(
                "Account must be closed before removal"
            );
        }

        config.notify["ordinal"].disconnect(on_account_ordinal_changed);
        this.accounts.remove(account);

        account_unavailable(config);
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

        var client = new Imap.ClientSession(endpoint, new Imap.Quirks());
        GLib.Error? imap_err = null;
        try {
            yield client.connect_async(
                Imap.ClientSession.DEFAULT_GREETING_TIMEOUT_SEC, cancellable
            );
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
        case NONE:
            // no-op
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
     * Changes the service configuration for an account.
     *
     * This updates an account's service configuration with the given
     * configuration, by replacing the account's existing
     * configuration for that service. The corresponding {@link
     * Account.incoming} or {@link Account.outgoing} client service
     * will also be updated so that the new configuration will start
     * taking effect immediately.
     */
    public async void update_account_service(AccountInformation config,
                                             ServiceInformation updated,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        Account account = get_account(config);

        ClientService? service = null;
        switch (updated.protocol) {
        case Protocol.IMAP:
            config.incoming = updated;
            service = account.incoming;
            break;

        case Protocol.SMTP:
            config.outgoing = updated;
            service = account.outgoing;
            break;
        }

        Endpoint remote = get_shared_endpoint(config.service_provider, updated);
        yield service.update_configuration(updated, remote, cancellable);
        config.changed();
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
            this.shared_endpoints.set(key, new EndpointWeakRef(shared));
        }

        return shared;
    }

    private void check_opened() throws EngineError {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Geary.Engine instance not open");
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

    private void sort_accounts() {
        this.accounts.sort((a, b) => {
                return AccountInformation.compare_ascending(
                    a.information, b.information
                );
            });
    }

    private void on_account_ordinal_changed() {
        sort_accounts();
    }

}
