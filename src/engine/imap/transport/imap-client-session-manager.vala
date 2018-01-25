/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Manages a pool of IMAP client sessions.
 *
 * When opened and when reachable, the manager will establish a pool
 * of {@link ClientSession} instances that are connected to the IMAP
 * endpoint of an account, ensuring there are at least {@link
 * min_pool_size} available. A connected, authorised client session
 * can be obtained from the connection pool by calling {@link
 * claim_authorized_session_async}, and when finished with returned by
 * calling {@link release_session_async}.
 *
 * This class is not thread-safe.
 */
public class Geary.Imap.ClientSessionManager : BaseObject {


    private const int DEFAULT_MIN_POOL_SIZE = 1;
    private const int POOL_START_TIMEOUT_SEC = 1;
    private const int POOL_STOP_TIMEOUT_SEC = 3;


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

    private string id;
    private Endpoint endpoint;
    private Credentials credentials;

    private Nonblocking.Mutex sessions_mutex = new Nonblocking.Mutex();
    private Gee.Set<ClientSession> all_sessions =
        new Gee.HashSet<ClientSession>();
    private Nonblocking.Queue<ClientSession> free_queue =
        new Nonblocking.Queue<ClientSession>.fifo();

    private TimeoutManager pool_start;
    private TimeoutManager pool_stop;
    private Cancellable? pool_cancellable = null;

    private bool authentication_failed = false;
    private bool untrusted_host = false;

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


    public ClientSessionManager(string id,
                                Endpoint imap_endpoint,
                                Credentials imap_credentials) {
        this.id = "%s:%s".printf(id, imap_endpoint.to_string());

        this.endpoint = imap_endpoint;
        this.endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].connect(on_imap_trust_untrusted_host);
        this.endpoint.untrusted_host.connect(on_imap_untrusted_host);

        this.credentials = imap_credentials;

        this.pool_start = new TimeoutManager.seconds(
            POOL_START_TIMEOUT_SEC,
            () => { this.check_pool.begin(); }
        );

        this.pool_stop = new TimeoutManager.seconds(
            POOL_STOP_TIMEOUT_SEC,
            () => { this.force_disconnect_all.begin(); }
        );
    }

    ~ClientSessionManager() {
        if (is_open)
            warning("[%s] Destroying opened ClientSessionManager", this.id);

        this.endpoint.untrusted_host.disconnect(on_imap_untrusted_host);
        this.endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].disconnect(on_imap_trust_untrusted_host);
    }

    public async void open_async(Cancellable? cancellable) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("ClientSessionManager already open");

        this.is_open = true;
        this.authentication_failed = false;
        this.pool_cancellable = new Cancellable();

		this.endpoint.connectivity.notify["is-reachable"].connect(on_connectivity_change);
        this.endpoint.connectivity.address_error_reported.connect(on_connectivity_error);
        if (this.endpoint.connectivity.is_reachable.is_certain()) {
            this.check_pool.begin();
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
        this.pool_cancellable.cancel();

		this.endpoint.connectivity.notify["is-reachable"].disconnect(on_connectivity_change);
        this.endpoint.connectivity.address_error_reported.disconnect(on_connectivity_error);

        yield force_disconnect_all();

        // TODO: This isn't the best (deterministic) way to deal with this, but it's easy and works
        // for now
        int attempts = 0;
        while (this.all_sessions.size > 0) {
            debug("[%s] Waiting for client sessions to disconnect...", this.id);
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
    public void credentials_updated(Credentials new_creds) {
        this.authentication_failed = false;
        this.credentials = new_creds;
        if (this.is_open) {
            this.check_pool.begin();
        }
    }

    /**
     * Claims a free session, blocking until one becomes available.
     *
     * This call will fail fast if the pool is known to not in the
     * right state (bad authorisation credentials, host not ready,
     * etc), but then will block while attempting to obtain a
     * connection if the free queue is empty. If an error occurs when
     * this connection is in progress, then the call will block until
     * another becomes available (host becomes reachable again, user
     * enters password, etc). If this is undesirable, then the caller
     * may cancel the call.
     *
     * @throws ImapError.UNAUTHENTICATED if the stored credentials are
     * invalid.
     * @throws ImapError.UNAVAILABLE if the IMAP endpoint is not
     * trusted or is not reachable.
     */
    public async ClientSession claim_authorized_session_async(Cancellable? cancellable)
        throws Error {
        check_open();
        debug("[%s] Claiming session from %d of %d free",
              this.id, this.free_queue.size, this.all_sessions.size);

        if (this.authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");

        if (this.untrusted_host)
            throw new ImapError.UNAVAILABLE("Untrusted host %s", endpoint.to_string());

        if (!this.endpoint.connectivity.is_reachable.is_certain())
            throw new ImapError.UNAVAILABLE("Host at %s is unreachable", endpoint.to_string());

        ClientSession? claimed = null;
        while (claimed == null) {
            // This isn't racy since this is class is not accessed by
            // multiple threads. Don't wait for it though because we
            // only want to kick off establishing the connection, and
            // wait for it via the queue.
            if (this.free_queue.size == 0) {
                check_pool.begin();
            }

            claimed = yield this.free_queue.receive(cancellable);

            // Connection may have gone bad sitting in the queue, so
            // check it before using it
            if (!(yield check_session(claimed, false))) {
                claimed = null;
            }
        }

        return claimed;
    }

    public async void release_session_async(ClientSession session)
        throws Error {
        // Don't check_open(), it's valid for this to be called when
        // is_open is false, that happens during mop-up

        debug("[%s] Returning session with %d of %d free",
              this.id, this.free_queue.size, this.all_sessions.size);

        if (!this.is_open || this.discard_returned_sessions) {
            yield force_disconnect(session);
        } else if (yield check_session(session, true)) {
            bool free = true;
            MailboxSpecifier? mailbox = null;
            ClientSession.ProtocolState proto = session.get_protocol_state(out mailbox);
            // If the session has a mailbox selected, close it before
            // adding it back to the pool
            if (proto == ClientSession.ProtocolState.SELECTED ||
                proto == ClientSession.ProtocolState.SELECTING) {
                // always close mailbox to return to authorized state
                try {
                    yield session.close_mailbox_async(pool_cancellable);
                } catch (ImapError imap_error) {
                    debug("[%s] Error attempting to close released session %s: %s",
                          this.id, session.to_string(), imap_error.message);
                    free = false;
                }

                if (session.get_protocol_state(null) !=
                    ClientSession.ProtocolState.AUTHORIZED) {
                    // Closing it didn't work, so drop it
                    yield force_disconnect(session);
                    free = false;
                }
            }

            if (free) {
                debug("[%s] Unreserving session %s", this.id, session.to_string());
                this.free_queue.send(session);
            }
        }
    }

    /**
     * Returns a string representation of this object for debugging.
     */
    public string to_string() {
        return this.id;
    }

    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("ClientSessionManager is not open");
    }

    private async void check_pool() {
        debug("[%s] Checking session pool with %d of %d free",
              this.id, this.free_queue.size, this.all_sessions.size);

        while (this.is_open &&
               !this.authentication_failed &&
               !this.untrusted_host &&
               this.endpoint.connectivity.is_reachable.is_certain()) {
            // Open pool sessions serially to avoid hammering the server
            try {
                ClientSession free = yield this.create_new_authorized_session(
                    this.pool_cancellable
                );
                yield this.sessions_mutex.execute_locked(() => {
                        this.all_sessions.add(free);
                    });

                this.free_queue.send(free);
            } catch (Error err) {
                debug("[%s] Error adding free session pool: %s",
                      this.id, err.message);
                break;
            }

            if (this.all_sessions.size >= this.min_pool_size) {
                break;
            }
        }
    }

    /** Determines if a session is valid, disposing of it if not. */
    private async bool check_session(ClientSession target, bool allow_selected) {
        bool valid = false;
        switch (target.get_protocol_state(null)) {
        case ClientSession.ProtocolState.AUTHORIZED:
        case ClientSession.ProtocolState.CLOSING_MAILBOX:
            valid = true;
            break;

        case ClientSession.ProtocolState.SELECTED:
        case ClientSession.ProtocolState.SELECTING:
            if (allow_selected) {
                valid = true;
            } else {
                yield force_disconnect(target);
            }
            break;

        case ClientSession.ProtocolState.UNCONNECTED:
            // Already disconnected, so drop it on the floor
            try {
                yield remove_session_async(target);
            } catch (Error err) {
                debug("[%s] Error removing unconnected session: %s",
                      this.id, err.message);
            }
            break;

        default:
            yield force_disconnect(target);
            break;
        }

        return valid;
    }

    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        debug("[%s] Opening new session", this.id);
        ClientSession new_session = new ClientSession(endpoint);

        // Listen for auth failures early so the client is notified if
        // there is an error, even though we won't want to keep the
        // session around.
        new_session.login_failed.connect(on_login_failed);

        try {
            yield new_session.connect_async(cancellable);
        } catch (Error err) {
            debug("[%s] Connect failure: %s", new_session.to_string(), err.message);
            connection_failed(err);
            throw err;
        }

        try {
            yield new_session.initiate_session_async(this.credentials, cancellable);
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

            connection_failed(err);
            throw err;
        }

        // Only bother tracking disconnects and enabling keeping alive
        // now the session is properly established.
        new_session.disconnected.connect(on_disconnected);
        new_session.enable_keepalives(selected_keepalive_sec,
                                      unselected_keepalive_sec,
                                      selected_with_idle_keepalive_sec);

        // We now have a good connection, so signal us as ready if not
        // already done so.
        if (!this.is_ready) {
            debug("[%s] Became ready", this.id);
            this.is_ready = true;
            ready();
        }

        return new_session;
    }

    /** Disconnects all sessions in the pool. */
    private async void force_disconnect_all()
        throws Error {
        debug("[%s] Dropping and disconnecting %d sessions",
              this.id, this.all_sessions.size);

        // Take a copy and work off that while scheduling disconnects,
        // since as they disconnect they'll remove themselves from the
        // sessions list and cause the loop below to explode.
        ClientSession[]? to_close = null;
        yield this.sessions_mutex.execute_locked(() => {
                to_close = this.all_sessions.to_array();
            });

        // Disconnect all existing sessions at once. Don't block
        // waiting for any since we don't want to delay closing the
        // others.
        foreach (ClientSession session in to_close) {
            session.disconnect_async.begin();
        }
    }

    private async void force_disconnect(ClientSession session) {
        debug("[%s] Dropping session %s", this.id, session.to_string());

        try {
            yield remove_session_async(session);
        } catch (Error err) {
            debug("[%s] Error removing session: %s", this.id, err.message);
        }

        // Don't wait for this to finish because we don't want to
        // block claiming a new session, shutdown, etc.
        session.disconnect_async.begin();
    }

    private async bool remove_session_async(ClientSession session) throws Error {
        // Ensure the session isn't held on to, anywhere

        this.free_queue.revoke(session);

        bool removed = false;
        yield this.sessions_mutex.execute_locked(() => {
                removed = this.all_sessions.remove(session);
            });

        if (removed) {
            session.disconnected.disconnect(on_disconnected);
            session.login_failed.disconnect(on_login_failed);
        }
        return removed;
    }

    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        this.remove_session_async.begin(
            session,
            (obj, res) => {
                try {
                    this.remove_session_async.end(res);
                } catch (Error err) {
                    debug("[%s] Error removing disconnected session: %s",
                          this.id, err.message);
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
                check_pool.begin();
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

}
