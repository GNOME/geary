/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Manages a pool of IMAP client sessions.
 *
 * When started and when the remote host is reachable, the manager
 * will establish a pool of {@link ClientSession} instances that are
 * connected to the service's endpoint, ensuring there are at least
 * {@link min_pool_size} available. A connected, authorised client
 * session can be obtained from the connection pool by calling {@link
 * claim_authorized_session_async}, and when finished with returned by
 * calling {@link release_session_async}.
 *
 * This class is not thread-safe.
 */
internal class Geary.Imap.ClientService : Geary.ClientService {


    private const int DEFAULT_MIN_POOL_SIZE = 1;
    private const int DEFAULT_MAX_FREE_SIZE = 1;
    private const int POOL_START_TIMEOUT_SEC = 1;
    private const int POOL_STOP_TIMEOUT_SEC = 3;
    private const int CHECK_NOOP_THRESHOLD_SEC = 5;

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
     * Specifies the minimum number of sessions to keep open.
     *
     * The manager will attempt to keep at least this number of
     * connections open at all times.
     *
     * Setting this does not immediately adjust the pool size in
     * either direction.  Adjustment will happen as connections are
     * needed or closed.
     */
    public int min_pool_size { get; set; default = DEFAULT_MIN_POOL_SIZE; }

    /**
     * Specifies the maximum number of free sessions to keep open.
     *
     * If there are already this number of free sessions available,
     * the manager will close any additional sessions that are
     * released, instead of keeping them for re-use. However it will
     * not close sessions if doing so would reduce the size of the
     * pool below {@link min_pool_size}.
     *
     * Setting this does not immediately adjust the pool size in
     * either direction.  Adjustment will happen as connections are
     * needed or closed.
     */
    public int max_free_size { get; set; default = DEFAULT_MAX_FREE_SIZE; }

    /**
     * Determines if returned sessions should be kept or discarded.
     */
    public bool discard_returned_sessions = false;

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
     * Fired when the manager's ready state changes.
     *
     * This will be fired after opening if online and once at least
     * one connection has been established, after the server has
     * become reachable again after being unreachable, and if the
     * server becomes unreachable.
     */
    public signal void ready(bool is_ready);

    /** Fired when a network or non-auth error occurs opening a session. */
    public signal void connection_failed(Error err);

    /** Fired when an authentication error occurs opening a session. */
    public signal void login_failed(StatusResponse? response);


    public ClientService(AccountInformation account,
                         ServiceInformation service,
                         Endpoint remote) {
        base(account, service, remote);

        this.pool_start = new TimeoutManager.seconds(
            POOL_START_TIMEOUT_SEC,
            () => { this.check_pool.begin(); }
        );

        this.pool_stop = new TimeoutManager.seconds(
            POOL_STOP_TIMEOUT_SEC,
            () => { this.close_pool.begin(); }
        );
    }

    /**
     * Starts the manager opening IMAP client sessions.
     */
    public override async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (this.is_running) {
            throw new EngineError.ALREADY_OPEN(
                "IMAP client service already open"
            );
        }

        this.is_running = true;
        this.authentication_failed = false;
        this.pool_cancellable = new Cancellable();

        this.remote.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].connect(
            on_imap_trust_untrusted_host
        );
        this.remote.untrusted_host.connect(on_imap_untrusted_host);
		this.remote.connectivity.notify["is-reachable"].connect(
            on_connectivity_change
        );
        this.remote.connectivity.address_error_reported.connect(
            on_connectivity_error
        );
        if (this.remote.connectivity.is_reachable.is_certain()) {
            this.check_pool.begin();
        } else {
            this.remote.connectivity.check_reachable.begin();
        }
    }

    /**
     * Stops the manager running, closing any existing sessions.
     */
    public override async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (!this.is_running) {
            return;
        }

        this.is_running = false;
        this.pool_cancellable.cancel();

        this.remote.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].disconnect(
            on_imap_trust_untrusted_host
        );
        this.remote.untrusted_host.disconnect(on_imap_untrusted_host);
		this.remote.connectivity.notify["is-reachable"].disconnect(
            on_connectivity_change
        );
        this.remote.connectivity.address_error_reported.disconnect(
            on_connectivity_error
        );

        yield close_pool();

        // TODO: This isn't the best (deterministic) way to deal with
        // this, but it's easy and works for now
        int attempts = 0;
        while (this.all_sessions.size > 0) {
            debug("[%s] Waiting for client sessions to disconnect...",
                  this.account.id);
            Timeout.add(250, this.stop.callback);
            yield;

            // give up after three seconds
            if (++attempts > 12)
                break;
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
        debug("[%s] Claiming session with %d of %d free",
              this.account.id, this.free_queue.size, this.all_sessions.size);

        if (this.authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");

        if (this.untrusted_host)
            throw new ImapError.UNAVAILABLE("Untrusted host %s", remote.to_string());

        if (!this.remote.connectivity.is_reachable.is_certain())
            throw new ImapError.UNAVAILABLE("Host at %s is unreachable", remote.to_string());

        ClientSession? claimed = null;
        while (claimed == null) {
            // This isn't racy since this is class is not accessed by
            // multiple threads. Don't wait for it to return though
            // because we only want to kick off establishing the
            // connection, and wait for it via the queue.
            if (this.free_queue.size == 0) {
                this.check_pool.begin(true);
            }

            claimed = yield this.free_queue.receive(cancellable);

            // Connection may have gone bad sitting in the queue, so
            // check it before using it
            if (!(yield check_session(claimed, true))) {
                claimed = null;
            }
        }

        return claimed;
    }

    public async void release_session_async(ClientSession session)
        throws Error {
        // Don't check_open(), it's valid for this to be called when
        // is_running is false, that happens during mop-up

        debug("[%s] Returning session with %d of %d free",
              this.account.id, this.free_queue.size, this.all_sessions.size);

        bool too_many_free = (
            this.free_queue.size >= this.max_free_size &&
            this.all_sessions.size > this.min_pool_size
        );

        if (!this.is_running || this.discard_returned_sessions || too_many_free) {
            yield force_disconnect(session);
        } else if (yield check_session(session, false)) {
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
                          this.account.id, session.to_string(), imap_error.message);
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
                debug("[%s] Unreserving session %s",
                      this.account.id, session.to_string());
                this.free_queue.send(session);
            }
        }
    }

    private void check_open() throws Error {
        if (!this.is_running) {
            throw new EngineError.OPEN_REQUIRED(
                "IMAP client service is not running"
            );
        }
    }

    private async void check_pool(bool is_claiming = false) {
        debug("[%s] Checking session pool with %d of %d free",
              this.account.id, this.free_queue.size, this.all_sessions.size);

        this.pool_start.reset();

        if (this.is_running &&
            !this.authentication_failed &&
            !this.untrusted_host &&
            this.remote.connectivity.is_reachable.is_certain()) {

            int needed = this.min_pool_size - this.all_sessions.size;
            if (needed <= 0 && is_claiming) {
                needed = 1;
            }

            // Open as many as needed in parallel
            while (needed > 0) {
                add_pool_session.begin();
                needed--;
            }
        }
    }

    private async void add_pool_session() {
        try {
            ClientSession free = yield this.create_new_authorized_session(
                this.pool_cancellable
            );
            yield this.sessions_mutex.execute_locked(() => {
                    this.all_sessions.add(free);
                });
            this.free_queue.send(free);
        } catch (Error err) {
            debug("[%s] Error adding new session to the pool: %s",
                  this.account.id, err.message);
            this.close_pool.begin();
        }
    }

    /** Determines if a session is valid, disposing of it if not. */
    private async bool check_session(ClientSession target, bool claiming) {
        bool valid = false;
        switch (target.get_protocol_state(null)) {
        case ClientSession.ProtocolState.AUTHORIZED:
        case ClientSession.ProtocolState.CLOSING_MAILBOX:
            valid = true;
            break;

        case ClientSession.ProtocolState.SELECTED:
        case ClientSession.ProtocolState.SELECTING:
            if (claiming) {
                yield force_disconnect(target);
            } else {
                valid = true;
            }
            break;

        case ClientSession.ProtocolState.UNCONNECTED:
            // Already disconnected, so drop it on the floor
            try {
                yield remove_session_async(target);
            } catch (Error err) {
                debug("[%s] Error removing unconnected session: %s",
                      this.account.id, err.message);
            }
            break;

        default:
            yield force_disconnect(target);
            break;
        }

        // We now know if the session /thinks/ it is in a reasonable
        // state, but if we're claiming a new session it *needs* to be
        // good, and in particular we want to ensure the connection
        // hasn't timed out or otherwise been dropped. So send a NOOP
        // and wait for it to find out. Only do this if we haven't
        // seen a response from the server in a little while, however.
        //
        // XXX This is problematic since the server may send untagged
        // responses to the NOOP, but at least since it won't be in
        // the Selected state, we won't lose notifications of new
        // messages, etc, only folder status, which should eventually
        // get picked up by UpdateRemoteFolders. :/
        if (claiming &&
            target.last_seen + (CHECK_NOOP_THRESHOLD_SEC * 1000000) < GLib.get_real_time()) {
            try {
                debug("Sending NOOP when claiming a session");
                yield target.send_command_async(
                    new NoopCommand(), this.pool_cancellable
                );
            } catch (Error err) {
                debug("Error sending NOOP: %s", err.message);
                valid = false;
            }
        }

        return valid;
    }

    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        debug("[%s] Opening new session", this.account.id);
        ClientSession new_session = new ClientSession(remote);

        // Listen for auth failures early so the client is notified if
        // there is an error, even though we won't want to keep the
        // session around.
        new_session.login_failed.connect(on_login_failed);

        try {
            yield new_session.connect_async(cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                connection_failed(err);
            }
            throw err;
        }

        try {
            yield new_session.initiate_session_async(
                this.configuration.credentials, cancellable
            );
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                connection_failed(err);
            }

            // need to disconnect before throwing error ... don't honor Cancellable here, it's
            // important to disconnect the client before dropping the ref
            try {
                yield new_session.disconnect_async();
            } catch (Error disconnect_err) {
                debug("[%s] Error disconnecting due to session initiation failure, ignored: %s",
                    new_session.to_string(), disconnect_err.message);
            }

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
            debug("[%s] Became ready", this.account.id);
            notify_ready(true);
        }

        return new_session;
    }

    private async void close_pool() {
        debug("[%s] Closing the pool, disconnecting %d sessions",
              this.account.id, this.all_sessions.size);

        this.pool_start.reset();
        this.pool_stop.reset();
        notify_ready(false);

        // Take a copy and work off that while scheduling disconnects,
        // since as they disconnect they'll remove themselves from the
        // sessions list and cause the loop below to explode.
        ClientSession[]? to_close = null;
        try {
            yield this.sessions_mutex.execute_locked(() => {
                    to_close = this.all_sessions.to_array();
                });
        } catch (Error err) {
            debug("Error occurred copying sessions: %s", err.message);
        }

        // Disconnect all existing sessions at once. Don't block
        // waiting for any since we don't want to delay closing the
        // others.
        foreach (ClientSession session in to_close) {
            session.disconnect_async.begin();
        }
    }

    private async void force_disconnect(ClientSession session) {
        debug("[%s] Dropping session %s", this.account.id, session.to_string());

        try {
            yield remove_session_async(session);
        } catch (Error err) {
            debug("[%s] Error removing session: %s",
                  this.account.id, err.message);
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

    private void notify_ready(bool is_ready) {
        this.is_ready = is_ready;
        ready(is_ready);
    }

    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        this.remove_session_async.begin(
            session,
            (obj, res) => {
                try {
                    this.remove_session_async.end(res);
                } catch (Error err) {
                    debug("[%s] Error removing disconnected session: %s",
                          this.account.id, err.message);
                }
            }
        );
    }

    private void on_login_failed(ClientSession session, StatusResponse? response) {
        this.authentication_failed = true;
        login_failed(response);
        this.close_pool.begin();
    }

    private void on_imap_untrusted_host() {
        this.untrusted_host = true;
        this.close_pool.begin();
    }

    private void on_imap_trust_untrusted_host() {
        // fired when the trust_untrusted_host property changes, indicating if the user has agreed
        // to ignore the trust problems and continue connecting
        if (untrusted_host && remote.trust_untrusted_host == Trillian.TRUE) {
            untrusted_host = false;

            if (this.is_running) {
                check_pool.begin();
            }
        }
    }

	private void on_connectivity_change() {
		bool is_reachable = this.remote.connectivity.is_reachable.is_certain();
		if (is_reachable) {
            this.pool_start.start();
            this.pool_stop.reset();
		} else {
            this.pool_start.reset();
            this.pool_stop.start();
        }
	}

	private void on_connectivity_error(Error error) {
        connection_failed(error);
        this.close_pool.begin();
	}

}
