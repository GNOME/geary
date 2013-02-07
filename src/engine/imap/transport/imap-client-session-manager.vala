/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSessionManager {
    public const int DEFAULT_MIN_POOL_SIZE = 2;
    
    public bool is_opened { get; private set; default = false; }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a connection has not
     * selected a mailbox.  (This is not recommended.)
     *
     * This only affects newly created sessions or sessions leaving the selected/examined state
     * and returning to an authorized state.
     */
    public int unselected_keepalive_sec { get; set; default = ClientSession.DEFAULT_UNSELECTED_KEEPALIVE_SEC; }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public int selected_keepalive_sec { get; set; default = ClientSession.DEFAULT_SELECTED_KEEPALIVE_SEC; }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined and IDLE is supported.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public int selected_with_idle_keepalive_sec { get; set; default = ClientSession.DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC; }
    
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
    private Geary.NonblockingMutex sessions_mutex = new Geary.NonblockingMutex();
    private Gee.HashSet<ClientSession> reserved_sessions = new Gee.HashSet<ClientSession>();
    private bool authentication_failed = false;
    
    public signal void login_failed();
    
    public ClientSessionManager(AccountInformation account_information) {
        this.account_information = account_information;
    }
    
    ~ClientSessionManager() {
        if (is_opened)
            warning("Destroying opened ClientSessionManager");
    }
    
    public async void open_async() throws Error {
        if (is_opened)
            throw ImapError.ALREADY_OPEN("ClientSessionManager is already open");
        
        is_opened = true;
        
        account_information.notify["imap-credentials"].connect(on_imap_credentials_notified);
        
        adjust_session_pool.begin();
    }
    
    public async void close_async() throws Error {
        if (!is_opened)
            return;
        
        is_opened = false;
        
        account_information.notify["imap-credentials"].disconnect(on_imap_credentials_notified);
        
        // TODO: Tear down all connections
    }
    
    private void on_imap_credentials_notified() {
        authentication_failed = false;
        adjust_session_pool.begin();
    }
    
    // TODO: Need a more thorough and bulletproof system for maintaining a pool of ready
    // authorized sessions.
    private async void adjust_session_pool() {
        if (!is_opened)
            return;
        
        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error claim_err) {
            debug("Unable to claim session table mutex for adjusting pool: %s", claim_err.message);
            
            return;
        }
        
        while (sessions.size < min_pool_size && !authentication_failed) {
            try {
                yield create_new_authorized_session(null);
            } catch (Error err) {
                debug("Unable to create authorized session to %s: %s",
                    account_information.get_imap_endpoint().to_string(), err.message);
                
                break;
            }
        }
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after adjusting pool: %s", release_err.message);
        }
    }
    
    // This should only be called when sessions_mutex is locked.
    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        if (authentication_failed)
            throw new ImapError.UNAUTHENTICATED("Invalid ClientSessionManager credentials");
        
        ClientSession new_session = new ClientSession(account_information.get_imap_endpoint());
        
        // add session to pool before launching all the connect activity so error cases can properly
        // back it out
        add_session(new_session);
        
        try {
            yield new_session.connect_async(cancellable);
        } catch (Error err) {
            debug("[%s] Connect failure: %s", new_session.to_string(), err.message);
            
            bool removed = remove_session(new_session);
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
            
            bool removed = remove_session(new_session);
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
        int token = yield sessions_mutex.claim_async(cancellable);
        
        ClientSession? found_session = null;
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (!reserved_sessions.contains(session) &&
                (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)) {
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
            debug("Error releasing mutex: %s", release_err.message);
        }
        
        if (err != null)
            throw err;
        
        return found_session;
    }
    
    public async void release_session_async(ClientSession session, Cancellable? cancellable) throws Error {
        string? mailbox;
        ClientSession.Context context = session.get_context(out mailbox);
        
        switch (context) {
            case ClientSession.Context.AUTHORIZED:
                // keep as-is
            break;
            
            case ClientSession.Context.UNAUTHORIZED:
            case ClientSession.Context.UNCONNECTED:
                // drop ... this will remove it from the session pool
                session.disconnect_async.begin();
                
                return;
            
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
                
                // if not in authorized state now, drop it
                if (session.get_context(out mailbox) != ClientSession.Context.AUTHORIZED) {
                    session.disconnect_async.begin();
                    
                    return;
                }
            break;
            
            default:
                assert_not_reached();
        }
        
        int token = yield session_mutex.claim_async(cancellable);
        
        if (!sessions.contains(session))
            debug("Attempting to release a session not owned by client session manager: %s", session.to_string());
        
        if (!reserved_sessions.remove(session))
            debug("Attempting to release an unreserved session: %s", session.to_string());
        
        session_mutex.release(ref token);
    }
    
    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        bool removed = remove_session(session);
        assert(removed);
        
        adjust_session_pool.begin();
    }
    
    private void on_login_failed(ClientSession session) {
        authentication_failed = true;
        
        login_failed();
        
        session.disconnect_async.begin();
    }
    
    private void add_session(ClientSession session) {
        sessions.add(session);
        
        // See create_new_authorized_session() for why the "disconnected" signal is not subscribed
        // to here (but *is* unsubscribed to in remove_session())
        session.login_failed.connect(on_login_failed);
    }
    
    private bool remove_session(ClientSession session) {
        bool removed = sessions.remove(session);
        if (removed) {
            session.disconnected.disconnect(on_disconnected);
            session.login_failed.disconnect(on_login_failed);
        }
        
        reserved_sessions.remove(session);
        
        return removed;
    }
    
    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return account_information.get_imap_endpoint().to_string();
    }
}

