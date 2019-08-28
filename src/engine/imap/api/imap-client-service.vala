/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2019 Michael Gratton <mike@vee.net>
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
    private const int CHECK_NOOP_THRESHOLD_SEC = 5;

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

    private Cancellable? pool_cancellable = null;


    public ClientService(AccountInformation account,
                         ServiceInformation service,
                         Endpoint remote) {
        base(account, service, remote);
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

        this.pool_cancellable = new Cancellable();
        notify_started();
    }

    /**
     * Stops the manager running, closing any existing sessions.
     */
    public override async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (!this.is_running) {
            return;
        }

        notify_stopped();

        this.pool_cancellable.cancel();
        yield close_pool();

        // TODO: This isn't the best (deterministic) way to deal with
        // this, but it's easy and works for now
        int attempts = 0;
        while (this.all_sessions.size > 0) {
            debug("Waiting for client sessions to disconnect...");
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
    public async ClientSession
        claim_authorized_session_async(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.is_running) {
            throw new EngineError.OPEN_REQUIRED(
                "IMAP client service is not running"
            );
        }

        debug("Claiming session with %d of %d free",
              this.free_queue.size, this.all_sessions.size);

        if (this.current_status == AUTHENTICATION_FAILED) {
            throw new ImapError.UNAUTHENTICATED("Invalid credentials");
        }

        if (this.current_status == TLS_VALIDATION_FAILED) {
            throw new ImapError.UNAVAILABLE(
                "Untrusted host %s", this.remote.to_string()
            );
        }

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

        debug("Returning session with %d of %d free",
              this.free_queue.size, this.all_sessions.size);

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
                    debug("Error attempting to close released session %s: %s",
                          session.to_string(), imap_error.message);
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
                debug("Unreserving session %s", session.to_string());
                this.free_queue.send(session);
            }
        }
    }

    /** Restarts the client session pool. */
    protected override void became_reachable() {
        this.check_pool.begin(false);
    }

    /** Closes the client session pool. */
    protected override void became_unreachable() {
        this.close_pool.begin();
    }

    private async void check_pool(bool is_claiming) {
        debug("Checking session pool with %d of %d free",
              this.free_queue.size, this.all_sessions.size);

        if (!is_claiming) {
            // To prevent spurious connection failures, ensure tokens
            // are up-to-date before attempting a connection, but
            // after we know we should be able to connect to it
            try {
                bool loaded = yield this.account.load_incoming_credentials(
                    this.pool_cancellable
                );
                if (!loaded) {
                    notify_authentication_failed();
                    return;
                }
            } catch (GLib.Error err) {
                notify_connection_failed(new ErrorContext(err));
                return;
            }
        }

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

    private async void add_pool_session() {
        ClientSession? new_session = null;
        try {
            new_session = yield this.create_new_authorized_session(
                this.pool_cancellable
            );
        } catch (ImapError.UNAUTHENTICATED err) {
            debug("Auth error adding new session to the pool: %s", err.message);
            notify_authentication_failed();
        } catch (GLib.TlsError.BAD_CERTIFICATE err) {
            // Don't notify of an error here, since the untrusted host
            // handler will be dealing with it already.
            debug("TLS validation error adding new session to the pool: %s",
                  err.message);
        } catch (GLib.IOError.CANCELLED err) {
            // Nothing to do here
        } catch (GLib.Error err) {
            Geary.ErrorContext context = new Geary.ErrorContext(err);
            debug("Error creating new session for the pool: %s",
                  context.format_full_error());
            notify_connection_failed(context);
        }

        if (new_session == null) {
            // An error was thrown, so close the pool
            this.close_pool.begin();
        } else {
            try {
                yield this.sessions_mutex.execute_locked(() => {
                        this.all_sessions.add(new_session);
                    });
                this.free_queue.send(new_session);
                notify_connected();
            } catch (GLib.Error err) {
                Geary.ErrorContext context = new Geary.ErrorContext(err);
                debug("Error adding new session to the pool: %s",
                      context.format_full_error());
                notify_connection_failed(context);
                new_session.disconnect_async.begin(null);
                this.close_pool.begin();
            }
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

        case ClientSession.ProtocolState.NOT_CONNECTED:
            // Already disconnected, so drop it on the floor
            try {
                yield remove_session_async(target);
            } catch (Error err) {
                debug("Error removing unconnected session: %s", err.message);
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
        debug("Opening new session");
        Credentials? login = this.configuration.credentials;
        if (login != null && !login.is_complete()) {
            throw new ImapError.UNAUTHENTICATED("Token not loaded");
        }

        ClientSession new_session = new ClientSession(remote);
        yield new_session.connect_async(cancellable);

        try {
            yield new_session.initiate_session_async(login, cancellable);
        } catch (Error err) {
            // need to disconnect before throwing error ... don't
            // honor Cancellable here, it's important to disconnect
            // the client before dropping the ref
            try {
                yield new_session.disconnect_async(null);
            } catch (Error disconnect_err) {
                debug("Error disconnecting due to session initiation failure, ignored: %s",
                      disconnect_err.message);
            }

            throw err;
        }

        // Only bother tracking disconnects and enabling keeping alive
        // now the session is properly established.
        new_session.disconnected.connect(on_disconnected);
        new_session.enable_keepalives(selected_keepalive_sec,
                                      unselected_keepalive_sec,
                                      selected_with_idle_keepalive_sec);

        return new_session;
    }

    private async void close_pool() {
        debug("Closing the pool, disconnecting %d sessions",
              this.all_sessions.size);

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
            session.disconnect_async.begin(null);
        }
    }

    private async void force_disconnect(ClientSession session) {
        debug("Dropping session %s", session.to_string());

        try {
            yield remove_session_async(session);
        } catch (Error err) {
            debug("Error removing session: %s", err.message);
        }

        // Don't wait for this to finish because we don't want to
        // block claiming a new session, shutdown, etc.
        session.disconnect_async.begin(null);
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
                    debug("Error removing disconnected session: %s",
                          err.message);
                }
            }
        );
    }

}
