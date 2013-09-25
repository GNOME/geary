/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientSessionManager : BaseObject {
    public const int DEFAULT_MIN_POOL_SIZE = 2;
    private const int AUTHORIZED_SESSION_ERROR_RETRY_TIMEOUT_MSEC = 1000;
    
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
    
    private AccountInformation account_information;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private int pending_sessions = 0;
    private Nonblocking.Mutex sessions_mutex = new Nonblocking.Mutex();
    private Gee.HashSet<ClientSession> reserved_sessions = new Gee.HashSet<ClientSession>();
    private bool authentication_failed = false;
    private uint authorized_session_error_retry_timeout_id = 0;
    
    public signal void login_failed();
    
    public ClientSessionManager(AccountInformation account_information) {
        this.account_information = account_information;
        
        account_information.notify["imap-credentials"].connect(on_imap_credentials_notified);
    }
    
    ~ClientSessionManager() {
        if (is_open)
            warning("Destroying opened ClientSessionManager");
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
        
        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error claim_err) {
            debug("Unable to claim session table mutex for closing pool: %s", claim_err.message);
            
            return;
        }
        
        // disconnect all existing sessions at once; don't wait for each, since as they disconnect
        // they'll remove themselves from the sessions list and cause this foreach to explode
        foreach (ClientSession session in sessions)
            session.disconnect_async.begin();
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after closing pool: %s", release_err.message);
        }
        
        // TODO: This isn't the best (deterministic) way to deal with this, but it's easy and works
        // for now
        while (sessions.size > 0) {
            debug("Waiting for ClientSessions to disconnect from ClientSessionManager...");
            Timeout.add(250, close_async.callback);
            yield;
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
        
        while ((sessions.size + pending_sessions) < min_pool_size && !authentication_failed && is_open)
            schedule_new_authorized_session();
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after adjusting pool: %s", release_err.message);
        }
    }
    
    private void schedule_new_authorized_session() {
        pending_sessions++;
        
        create_new_authorized_session.begin(false, null, on_created_new_authorized_session);
    }
    
    private void on_created_new_authorized_session(Object? source, AsyncResult result) {
        pending_sessions--;
        
        try {
            create_new_authorized_session.end(result);
        } catch (Error err) {
            debug("Unable to create authorized session to %s: %s",
                account_information.get_imap_endpoint().to_string(), err.message);
            
            // try again after a slight delay
            if (authorized_session_error_retry_timeout_id != 0)
                Source.remove(authorized_session_error_retry_timeout_id);
            authorized_session_error_retry_timeout_id
                = Timeout.add(AUTHORIZED_SESSION_ERROR_RETRY_TIMEOUT_MSEC,
                on_authorized_session_error_retry_timeout);
        }
    }
    
    private bool on_authorized_session_error_retry_timeout() {
        authorized_session_error_retry_timeout_id = 0;
        
        adjust_session_pool.begin();
        
        return false;
    }
    
    // The locked parameter indicates if this is called while the sessions_mutex is locked
    private async ClientSession create_new_authorized_session(bool locked, Cancellable? cancellable)
        throws Error {
        if (authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");
        
        ClientSession new_session = new ClientSession(account_information.get_imap_endpoint());
        
        // add session to pool before launching all the connect activity so error cases can properly
        // back it out
        if (locked)
            locked_add_session(new_session);
        else
            yield unlocked_add_session_async(new_session);
        
        try {
            yield new_session.connect_async(cancellable);
        } catch (Error err) {
            debug("[%s] Connect failure: %s", new_session.to_string(), err.message);
            
            bool removed;
            if (locked)
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
            if (locked)
                removed = locked_remove_session(new_session);
            else
                removed = yield unlocked_remove_session_async(new_session);
            assert(removed);
            
            throw err;
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
                (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)) {
                found_session = session;
                
                break;
            }
        }
        
        Error? err = null;
        try {
            if (found_session == null)
                found_session = yield create_new_authorized_session(true, cancellable);
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
        check_open();
        
        MailboxSpecifier? mailbox;
        ClientSession.Context context = session.get_context(out mailbox);
        
        bool unreserve = false;
        switch (context) {
            case ClientSession.Context.AUTHORIZED:
                // keep as-is, but remove from the reserved list
                unreserve = true;
            break;
            
            case ClientSession.Context.UNAUTHORIZED:
                yield force_disconnect_async(session, true);
            break;
            
            case ClientSession.Context.UNCONNECTED:
                yield force_disconnect_async(session, false);
            break;
            
            case ClientSession.Context.IN_PROGRESS:
            case ClientSession.Context.EXAMINED:
            case ClientSession.Context.SELECTED:
                // always close mailbox to return to authorized state
                try {
                    yield session.close_mailbox_async(cancellable);
                } catch (ImapError imap_error) {
                    debug("Error attempting to close released session %s: %s", session.to_string(),
                        imap_error.message);
                }
                
                // if not in authorized state now, drop it, otherwise remove from reserved list
                if (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)
                    unreserve = true;
                else
                    yield force_disconnect_async(session, true);
            break;
            
            default:
                assert_not_reached();
        }
        
        if (unreserve) {
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
    
    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return account_information.get_imap_endpoint().to_string();
    }
}

