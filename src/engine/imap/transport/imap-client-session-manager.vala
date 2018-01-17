/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientSessionManager : BaseObject {

    private const int DEFAULT_MIN_POOL_SIZE = 1;
    private const int POOL_START_TIMEOUT_SEC = 4;
    private const int POOL_STOP_TIMEOUT_SEC = 1;

    /** Determines if the manager has been opened. */
    public bool is_open { get; private set; default = false; }

    /**
     * Determines if the manager has a working connection.
     *
     * This will be true once at least one connection has been
     * established, and after the server has become reachable again
     * after being unreachable.
     */
    public bool is_ready { get; private set; default = false; }

    /**
     * Set to zero or negative value if keepalives should be disabled when a connection has not
     * selected a mailbox.  (This is not recommended.)
     *
     * This only affects newly created sessions or sessions leaving the selected/examined state
     * and returning to an authorized state.
     */
    public uint unselected_keepalive_sec { get; set; default = ClientSession.DEFAULT_UNSELECTED_KEEPALIVE_SEC; }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public uint selected_keepalive_sec { get; set; default = ClientSession.DEFAULT_SELECTED_KEEPALIVE_SEC; }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined and IDLE is supported.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public uint selected_with_idle_keepalive_sec { get; set; default = ClientSession.DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC; }
    
    /**
     * ClientSessionManager attempts to maintain a minimum number of open sessions with the server
     * so they're immediately ready for use.
     *
     * Setting this does not immediately adjust the pool size in either direction.  Adjustment will
     * happen as connections are needed or closed.
     */
    public int min_pool_size { get; set; default = DEFAULT_MIN_POOL_SIZE; }

    /**
     * Determines if returned sessions should be kept or discarded.
     */
    public bool discard_returned_sessions = false;

    private AccountInformation account_information;
    private Endpoint endpoint;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private int pending_sessions = 0;
    private Nonblocking.Mutex sessions_mutex = new Nonblocking.Mutex();
    private Gee.HashSet<ClientSession> reserved_sessions = new Gee.HashSet<ClientSession>();
    private bool authentication_failed = false;
    private bool untrusted_host = false;

    private TimeoutManager pool_start;
    private TimeoutManager pool_stop;

    /**
     * Fired after when the manager has a working connection.
     *
     * This will be fired both after opening if online and once at
     * least one connection has been established, and after the server
     * has become reachable again after being unreachable.
     */
    public signal void ready();

    /** Fired when a network or non-auth error occurs opening a session. */
    public signal void connection_failed(Error err);

    /** Fired when an authentication error occurs opening a session. */
    public signal void login_failed(StatusResponse? response);


    public ClientSessionManager(AccountInformation account_information) {
        this.account_information = account_information;

        // NOTE: This works because AccountInformation guarantees the IMAP endpoint not to change
        // for the lifetime of the AccountInformation object; if this ever changes, will need to
        // refactor for that
        this.endpoint = account_information.get_imap_endpoint();
        this.endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].connect(on_imap_trust_untrusted_host);
        this.endpoint.untrusted_host.connect(on_imap_untrusted_host);

        this.pool_start = new TimeoutManager.seconds(
            POOL_START_TIMEOUT_SEC,
            () => { this.adjust_session_pool.begin(); }
        );

        this.pool_stop = new TimeoutManager.seconds(
            POOL_STOP_TIMEOUT_SEC,
            () => { this.force_disconnect_all.begin(); }
        );
    }

    ~ClientSessionManager() {
        if (is_open)
            warning("Destroying opened ClientSessionManager");

        this.endpoint.untrusted_host.disconnect(on_imap_untrusted_host);
        this.endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].disconnect(on_imap_trust_untrusted_host);
    }

    public async void open_async(Cancellable? cancellable) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("ClientSessionManager already open");

        this.is_open = true;
        this.authentication_failed = false;

		this.endpoint.connectivity.notify["is-reachable"].connect(on_connectivity_change);
        this.endpoint.connectivity.address_error_reported.connect(on_connectivity_error);
        if (this.endpoint.connectivity.is_reachable.is_certain()) {
            this.adjust_session_pool.begin();
        } else {
            this.endpoint.connectivity.check_reachable.begin();
        }
    }

    public async void close_async(Cancellable? cancellable) throws Error {
        if (!is_open)
            return;

        this.is_open = false;
        this.is_ready = false;

        this.pool_start.reset();
        this.pool_stop.reset();

		this.endpoint.connectivity.notify["is-reachable"].disconnect(on_connectivity_change);
        this.endpoint.connectivity.address_error_reported.disconnect(on_connectivity_error);

        yield force_disconnect_all();

        // TODO: This isn't the best (deterministic) way to deal with this, but it's easy and works
        // for now
        int attempts = 0;
        while (sessions.size > 0) {
            debug("Waiting for ClientSessions to disconnect from ClientSessionManager...");
            Timeout.add(250, close_async.callback);
            yield;
            
            // give up after three seconds
            if (++attempts > 12)
                break;
        }
    }

    /**
     * Informs the manager that the account's IMAP credentials have changed.
     *
     * This will reset the manager's authentication state and if open,
     * attempt to open a connection to the server.
     */
    public void credentials_updated() {
        this.authentication_failed = false;
        if (this.is_open) {
            this.adjust_session_pool.begin();
        }
    }

    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("ClientSessionManager is not open");
    }
    
    // TODO: Need a more thorough and bulletproof system for maintaining a pool of ready
    // authorized sessions.
    private async void adjust_session_pool() {
        if (!this.is_open)
            return;

        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error claim_err) {
            debug("Unable to claim session table mutex for adjusting pool: %s", claim_err.message);
            return;
        }

        while ((sessions.size + pending_sessions) < min_pool_size
            && this.is_open
            && !this.authentication_failed
            && !this.untrusted_host
            && this.endpoint.connectivity.is_reachable.is_certain()) {
            this.pending_sessions++;
            create_new_authorized_session.begin(
                null,
                (obj, res) => {
                    this.pending_sessions--;
                    try {
                        this.create_new_authorized_session.end(res);
                    } catch (Error err) {
                        connection_failed(err);
                    }
                });
        }

        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after adjusting pool: %s", release_err.message);
        }
    }

    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        if (authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");

        if (untrusted_host)
            throw new ImapError.UNAVAILABLE("Untrusted host %s", endpoint.to_string());

        if (!this.endpoint.connectivity.is_reachable.is_certain())
            throw new ImapError.UNAVAILABLE("Host at %s is unreachable", endpoint.to_string());

        ClientSession new_session = new ClientSession(endpoint);
        
        // add session to pool before launching all the connect activity so error cases can properly
        // back it out
        if (sessions_mutex.is_locked())
            locked_add_session(new_session);
        else
            yield unlocked_add_session_async(new_session);
        
        try {
            yield new_session.connect_async(cancellable);
        } catch (Error err) {
            debug("[%s] Connect failure: %s", new_session.to_string(), err.message);
            
            bool removed;
            if (sessions_mutex.is_locked())
                removed = locked_remove_session(new_session);
            else
                removed = yield unlocked_remove_session_async(new_session);
            assert(removed);
            
            throw err;
        }
        
        try {
            yield new_session.initiate_session_async(account_information.imap_credentials, cancellable);
        } catch (Error err) {
            debug("[%s] Initiate session failure: %s", new_session.to_string(), err.message);
            
            // need to disconnect before throwing error ... don't honor Cancellable here, it's
            // important to disconnect the client before dropping the ref
            try {
                yield new_session.disconnect_async();
            } catch (Error disconnect_err) {
                debug("[%s] Error disconnecting due to session initiation failure, ignored: %s",
                    new_session.to_string(), disconnect_err.message);
            }
            
            bool removed;
            if (sessions_mutex.is_locked())
                removed = locked_remove_session(new_session);
            else
                removed = yield unlocked_remove_session_async(new_session);
            assert(removed);
            
            throw err;
        }

        if (!this.is_ready) {
            this.is_ready = true;
            ready();
        }

        // do this after logging in
        new_session.enable_keepalives(selected_keepalive_sec, unselected_keepalive_sec,
            selected_with_idle_keepalive_sec);
        
        // since "disconnected" is used to remove the ClientSession from the sessions list, want
        // to only connect to the signal once the object has been added to the list; otherwise it's
        // possible a cancel during the connect or login will result in a "disconnected" signal,
        // removing the session before it's added
        new_session.disconnected.connect(on_disconnected);
        
        return new_session;
    }
    
    public async ClientSession claim_authorized_session_async(Cancellable? cancellable) throws Error {
        check_open();
        
        int token = yield sessions_mutex.claim_async(cancellable);
        
        ClientSession? found_session = null;
        foreach (ClientSession session in sessions) {
            MailboxSpecifier? mailbox;
            if (!reserved_sessions.contains(session) &&
                (session.get_protocol_state(out mailbox) == ClientSession.ProtocolState.AUTHORIZED)) {
                found_session = session;
                
                break;
            }
        }
        
        Error? err = null;
        try {
            if (found_session == null)
                found_session = yield create_new_authorized_session(cancellable);
        } catch (Error create_err) {
            debug("Error creating session: %s", create_err.message);
            err = create_err;
        }
        
        // claim it now
        if (found_session != null) {
            bool added = reserved_sessions.add(found_session);
            assert(added);
        }
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Error releasing sessions table mutex: %s", release_err.message);
        }
        
        if (err != null)
            throw err;
        
        return found_session;
    }

    public async void release_session_async(ClientSession session, Cancellable? cancellable)
        throws Error {
        // Don't check_open(), it's valid for this to be called when
        // is_open is false, that happens during mop-up
        MailboxSpecifier? mailbox = null;
        ClientSession.ProtocolState context = session.get_protocol_state(out mailbox);

        if (context == ClientSession.ProtocolState.UNCONNECTED) {
            // Already disconnected, so drop it on the floor
            try {
                yield unlocked_remove_session_async(session);
            } catch (Error err) {
                debug("[%s] Error removing unconnected session: %s",
                      to_string(), err.message);
            }
        } else if (this.is_open && !this.discard_returned_sessions) {
            bool free = false;
            switch (context) {
            case ClientSession.ProtocolState.AUTHORIZED:
            case ClientSession.ProtocolState.CLOSING_MAILBOX:
                // keep as-is, but add back to the free list
                free = true;
                break;

            case ClientSession.ProtocolState.SELECTED:
            case ClientSession.ProtocolState.SELECTING:
                debug("[%s] Closing %s for released session %s",
                      to_string(),
                      mailbox != null ? mailbox.to_string() : "(unknown)",
                      session.to_string());

                // always close mailbox to return to authorized state
                try {
                    yield session.close_mailbox_async(cancellable);
                } catch (ImapError imap_error) {
                    debug("[%s] Error attempting to close released session %s: %s",
                          to_string(), session.to_string(), imap_error.message);
                }

                if (session.get_protocol_state(out mailbox) == ClientSession.ProtocolState.AUTHORIZED) {
                    // Now in authorized state, free it up for re-use
                    free = true;
                } else {
                    // Closing it didn't work, so drop it
                    yield force_disconnect(session);
                }
                break;

            default:
                // This class is tasked with holding onto a pool of
                // authorized connections, so if one is released
                // outside that state, pessimistically drop it
                yield force_disconnect(session);
                break;
            }

            if (free) {
                debug("[%s] Unreserving session %s",
                      to_string(), session.to_string());
                try {
                    int token = yield sessions_mutex.claim_async(cancellable);
                    this.reserved_sessions.remove(session);
                    this.sessions_mutex.release(ref token);
                } catch (Error err) {
                    message("[%s] Unable to add %s to the free list: %s",
                            to_string(), session.to_string(), err.message);
                }
            }
        } else {
            // Not open, or we are discarding sessions, so close it.
            yield force_disconnect(session);
        }

        // If we're discarding returned sessions, we don't want to
        // create any more, so only twiddle the pool if not.
        if (!this.discard_returned_sessions) {
            this.adjust_session_pool.begin();
        }
    }

    private async void force_disconnect_all()
        throws Error {
        debug("[%s] Dropping and disconnecting %d sessions",
              to_string(), this.sessions.size);

        // Take a copy and work off that while scheduling disconnects,
        // since as they disconnect they'll remove themselves from the
        // sessions list and cause the loop below to explode.
        int token = yield this.sessions_mutex.claim_async();
        ClientSession[] to_close = this.sessions.to_array();
        this.sessions_mutex.release(ref token);

        // Disconnect all existing sessions at once. Don't block
        // waiting for any since we don't want to delay closing the
        // others.
        foreach (ClientSession session in to_close) {
            session.disconnect_async.begin();
        }
    }

    private async void force_disconnect(ClientSession session) {
        debug("[%s] Dropping session %s", to_string(), session.to_string());

        try {
            yield unlocked_remove_session_async(session);
        } catch (Error err) {
            debug("[%s] Error removing session: %s", to_string(), err.message);
        }

        // Don't wait for this to finish because we don't want to
        // block claiming a new session, shutdown, etc.
        session.disconnect_async.begin();
    }

    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        this.unlocked_remove_session_async.begin(
            session,
            (obj, res) => {
                try {
                    this.unlocked_remove_session_async.end(res);
                } catch (Error err) {
                    debug("[%s] Error removing disconnected session: %s",
                          to_string(),
                          err.message);
                }
            }
        );
    }

    private void on_login_failed(ClientSession session, StatusResponse? response) {
        this.is_ready = false;
        this.authentication_failed = true;
        login_failed(response);
        session.disconnect_async.begin();
    }

    // Only call with sessions mutex locked
    private void locked_add_session(ClientSession session) {
        sessions.add(session);
        
        // See create_new_authorized_session() for why the "disconnected" signal is not subscribed
        // to here (but *is* unsubscribed to in remove_session())
        session.login_failed.connect(on_login_failed);
    }
    
    private async void unlocked_add_session_async(ClientSession session) throws Error {
        int token = yield sessions_mutex.claim_async();
        locked_add_session(session);
        sessions_mutex.release(ref token);
    }
    
    // Only call with sessions mutex locked
    private bool locked_remove_session(ClientSession session) {
        bool removed = sessions.remove(session);
        if (removed) {
            session.disconnected.disconnect(on_disconnected);
            session.login_failed.disconnect(on_login_failed);
        }
        
        reserved_sessions.remove(session);
        
        return removed;
    }
    
    private async bool unlocked_remove_session_async(ClientSession session) throws Error {
        int token = yield sessions_mutex.claim_async();
        bool removed = locked_remove_session(session);
        sessions_mutex.release(ref token);
        
        return removed;
    }
    
    private void on_imap_untrusted_host() {
        // this is called any time trust issues are detected, so immediately clutch in to stop
        // retries
        untrusted_host = true;
    }
    
    private void on_imap_trust_untrusted_host() {
        // fired when the trust_untrusted_host property changes, indicating if the user has agreed
        // to ignore the trust problems and continue connecting
        if (untrusted_host && endpoint.trust_untrusted_host == Trillian.TRUE) {
            untrusted_host = false;
            
            if (is_open)
                adjust_session_pool.begin();
        }
    }

	private void on_connectivity_change() {
		bool is_reachable = this.endpoint.connectivity.is_reachable.is_certain();
		if (is_reachable) {
            this.pool_start.start();
            this.pool_stop.reset();
		} else {
            // Get a ready signal again once we are back online
            this.is_ready = false;
            this.pool_start.reset();
            this.pool_stop.start();
        }
	}

	private void on_connectivity_error(Error error) {
        this.is_ready = false;
        this.pool_start.reset();
        this.pool_stop.start();
        connection_failed(error);
	}

    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return "ClientSessionManager/%s %d sessions, %d reserved".printf(endpoint.to_string(),
            sessions.size, reserved_sessions.size);
    }
}
