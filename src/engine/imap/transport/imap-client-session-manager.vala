/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientSessionManager : BaseObject {
    private const int DEFAULT_MIN_POOL_SIZE = 1;
    private const int AUTHORIZED_SESSION_ERROR_MIN_RETRY_TIMEOUT_SEC = 1;
    private const int AUTHORIZED_SESSION_ERROR_MAX_RETRY_TIMEOUT_SEC = 10;
    
    public bool is_open { get; private set; default = false; }
    
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
     * Indicates if the {@link Endpoint} the {@link ClientSessionManager} connects to is reachable,
     * according to the NetworkMonitor.
     *
     * By default, this is true, optimistic the network is reachable.  It is updated even if the
     * {@link ClientSessionManager} is not open, maintained for the lifetime of the object.
     */
    public bool is_endpoint_reachable { get; private set; default = true; }
    
    private AccountInformation account_information;
    private Endpoint endpoint;
    private NetworkMonitor network_monitor;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private int pending_sessions = 0;
    private Nonblocking.Mutex sessions_mutex = new Nonblocking.Mutex();
    private Gee.HashSet<ClientSession> reserved_sessions = new Gee.HashSet<ClientSession>();
    private bool authentication_failed = false;
    private bool untrusted_host = false;
    private uint authorized_session_error_retry_timeout_id = 0;
    private int authorized_session_retry_sec = AUTHORIZED_SESSION_ERROR_MIN_RETRY_TIMEOUT_SEC;
    private bool checking_reachable = false;
    
    public signal void login_failed();
    
    public ClientSessionManager(AccountInformation account_information) {
        this.account_information = account_information;
        // NOTE: This works because AccountInformation guarantees the IMAP endpoint not to change
        // for the lifetime of the AccountInformation object; if this ever changes, will need to
        // refactor for that
        endpoint = account_information.get_imap_endpoint();
        network_monitor = NetworkMonitor.get_default();
        
        account_information.notify["imap-credentials"].connect(on_imap_credentials_notified);
        endpoint.untrusted_host.connect(on_imap_untrusted_host);
        endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].connect(on_imap_trust_untrusted_host);
        
        network_monitor.network_changed.connect(on_network_changed);
        network_monitor.notify["network-available"].connect(on_network_available_changed);
        
        // get this started now
        check_endpoint_reachable(null);
    }
    
    ~ClientSessionManager() {
        if (is_open)
            warning("Destroying opened ClientSessionManager");
        
        account_information.notify["imap-credentials"].disconnect(on_imap_credentials_notified);
        endpoint.untrusted_host.disconnect(on_imap_untrusted_host);
        endpoint.notify[Endpoint.PROP_TRUST_UNTRUSTED_HOST].disconnect(on_imap_trust_untrusted_host);
        
        network_monitor.network_changed.disconnect(on_network_changed);
        network_monitor.notify["network-available"].disconnect(on_network_available_changed);
    }
    
    public async void open_async(Cancellable? cancellable) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("ClientSessionManager already open");
        
        is_open = true;
        
        adjust_session_pool.begin();
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (!is_open)
            return;
        
        is_open = false;
        
        // to avoid locking down the sessions table while scheduling disconnects, make a copy
        // and work off of that
        ClientSession[]? sessions_copy = sessions.to_array();
        
        // disconnect all existing sessions at once; don't wait for each, since as they disconnect
        // they'll remove themselves from the sessions list and cause this foreach to explode
        foreach (ClientSession session in sessions_copy)
            session.disconnect_async.begin();
        
        // free copy
        sessions_copy = null;
        
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
    
    private void on_imap_credentials_notified() {
        authentication_failed = false;
        
        if (is_open)
            adjust_session_pool.begin();
    }
    
    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("ClientSessionManager is not open");
    }
    
    // TODO: Need a more thorough and bulletproof system for maintaining a pool of ready
    // authorized sessions.
    private async void adjust_session_pool() {
        if (!is_open)
            return;
        
        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error claim_err) {
            debug("Unable to claim session table mutex for adjusting pool: %s", claim_err.message);
            
            return;
        }
        
        while ((sessions.size + pending_sessions) < min_pool_size
            && !authentication_failed
            && is_open
            && !untrusted_host
            && is_endpoint_reachable) {
            pending_sessions++;
            create_new_authorized_session.begin(null, on_created_new_authorized_session);
        }
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after adjusting pool: %s", release_err.message);
        }
    }
    
    private void on_created_new_authorized_session(Object? source, AsyncResult result) {
        pending_sessions--;
        
        try {
            create_new_authorized_session.end(result);
        } catch (Error err) {
            debug("Unable to create authorized session to %s: %s", endpoint.to_string(), err.message);
            
            // try again after a slight delay and bump up delay
            if (authorized_session_error_retry_timeout_id != 0)
                Source.remove(authorized_session_error_retry_timeout_id);
            
            authorized_session_error_retry_timeout_id = Timeout.add_seconds(
                authorized_session_retry_sec, on_authorized_session_error_retry_timeout);
            
            authorized_session_retry_sec = (authorized_session_retry_sec * 2).clamp(
                AUTHORIZED_SESSION_ERROR_MIN_RETRY_TIMEOUT_SEC, AUTHORIZED_SESSION_ERROR_MAX_RETRY_TIMEOUT_SEC);
        }
    }
    
    private bool on_authorized_session_error_retry_timeout() {
        authorized_session_error_retry_timeout_id = 0;
        
        adjust_session_pool.begin();
        
        return false;
    }
    
    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        if (authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");
        
        if (untrusted_host)
            throw new ImapError.UNAUTHENTICATED("Untrusted host %s", endpoint.to_string());
        
        if (!is_endpoint_reachable)
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
        
        // reset delay
        authorized_session_retry_sec = AUTHORIZED_SESSION_ERROR_MIN_RETRY_TIMEOUT_SEC;
        
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
        // Don't check_open(), it's valid for this to be called when is_open is false, that happens
        // during mop-up
        
        MailboxSpecifier? mailbox;
        ClientSession.ProtocolState context = session.get_protocol_state(out mailbox);
        
        bool unreserve = false;
        switch (context) {
            case ClientSession.ProtocolState.AUTHORIZED:
            case ClientSession.ProtocolState.CLOSING_MAILBOX:
                // keep as-is, but remove from the reserved list
                unreserve = true;
            break;
            
            // ClientSessionManager is tasked with holding onto a pool of authorized connections,
            // so if one is released outside that state, pessimistically drop it
            case ClientSession.ProtocolState.CONNECTING:
            case ClientSession.ProtocolState.AUTHORIZING:
            case ClientSession.ProtocolState.UNAUTHORIZED:
                yield force_disconnect_async(session, true);
            break;
            
            case ClientSession.ProtocolState.UNCONNECTED:
                yield force_disconnect_async(session, false);
            break;
            
            case ClientSession.ProtocolState.SELECTED:
            case ClientSession.ProtocolState.SELECTING:
                debug("[%s] Closing mailbox for released session %s", to_string(), session.to_string());
                
                // always close mailbox to return to authorized state
                try {
                    yield session.close_mailbox_async(cancellable);
                } catch (ImapError imap_error) {
                    debug("Error attempting to close released session %s: %s", session.to_string(),
                        imap_error.message);
                }
                
                // if not in authorized state now, drop it, otherwise remove from reserved list
                if (session.get_protocol_state(out mailbox) == ClientSession.ProtocolState.AUTHORIZED)
                    unreserve = true;
                else
                    yield force_disconnect_async(session, true);
            break;
            
            default:
                assert_not_reached();
        }
        
        if (!unreserve)
            return;
        
        // if not open, disconnect, which will remove from the reserved pool anyway
        if (!is_open) {
            yield force_disconnect_async(session, true);
        } else {
            debug("[%s] Unreserving session %s", to_string(), session.to_string());
            
            try {
                // don't respect Cancellable because this *must* happen; don't want this lingering
                // on the reserved list forever
                int token = yield sessions_mutex.claim_async();
                
                bool removed = reserved_sessions.remove(session);
                assert(removed);
                
                sessions_mutex.release(ref token);
            } catch (Error err) {
                message("Unable to remove %s from reserved list: %s", session.to_string(), err.message);
            }
        }
    }
    
    // It's possible this will be called more than once on the same session, especially in the case of a
    // remote close on reserved ClientSession, so this code is forgiving.
    private async void force_disconnect_async(ClientSession session, bool do_disconnect) {
        debug("[%s] Dropping session %s (disconnecting=%s)", to_string(),
            session.to_string(), do_disconnect.to_string());
        
        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error err) {
            debug("Unable to acquire sessions mutex: %s", err.message);
            
            return;
        }
        
        locked_remove_session(session);
        
        if (do_disconnect) {
            try {
                yield session.disconnect_async();
            } catch (Error err) {
                // ignored
            }
        }
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error err) {
            debug("Unable to release sessions mutex: %s", err.message);
        }
        
        adjust_session_pool.begin();
    }
    
    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        force_disconnect_async.begin(session, false);
    }
    
    private void on_login_failed(ClientSession session) {
        authentication_failed = true;
        
        login_failed();
        
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
    
    private void on_network_changed() {
        // Always check if reachable because IMAP server could be on localhost.  (This is a Linux
        // program, after all...)
        check_endpoint_reachable(null);
    }
    
    private void on_network_available_changed() {
        // If network is available and endpoint is reachable, do nothing more, all is good,
        // otherwise check (see note in on_network_changed)
        if (network_monitor.network_available && is_endpoint_reachable)
            return;
        
        check_endpoint_reachable(null);
    }
    
    private void check_endpoint_reachable(Cancellable? cancellable) {
        if (checking_reachable)
            return;
        
        debug("Checking if IMAP host %s reachable...", endpoint.to_string());
        
        checking_reachable = true;
        check_endpoint_reachable_async.begin(cancellable);
    }
    
    // Use check_endpoint_reachable to properly schedule
    private async void check_endpoint_reachable_async(Cancellable? cancellable) {
        try {
            is_endpoint_reachable = yield network_monitor.can_reach_async(endpoint.remote_address,
                cancellable);
            message("IMAP host %s considered %s", endpoint.to_string(),
                is_endpoint_reachable ? "reachable" : "unreachable");
        } catch (Error err) {
            // If cancelled, don't change anything
            if (err is IOError.CANCELLED)
                return;
            
            message("Error determining if IMAP host %s is reachable, treating as unreachable: %s",
                endpoint.to_string(), err.message);
            is_endpoint_reachable = false;
        } finally {
            checking_reachable = false;
        }
        
        if (is_endpoint_reachable)
            adjust_session_pool.begin();
    }
    
    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return "ClientSessionManager/%s %d sessions, %d reserved".printf(endpoint.to_string(),
            sessions.size, reserved_sessions.size);
    }
}

