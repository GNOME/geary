/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSessionManager {
    private const int MIN_POOL_SIZE = 2;
    
    private Endpoint endpoint;
    private Credentials credentials;
    private AccountInformation account_info;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private Geary.NonblockingMutex sessions_mutex = new Geary.NonblockingMutex();
    private Gee.HashSet<SelectedContext> examined_contexts = new Gee.HashSet<SelectedContext>();
    private Gee.HashSet<SelectedContext> selected_contexts = new Gee.HashSet<SelectedContext>();
    private uint unselected_keepalive_sec = ClientSession.DEFAULT_UNSELECTED_KEEPALIVE_SEC;
    private uint selected_keepalive_sec = ClientSession.DEFAULT_SELECTED_KEEPALIVE_SEC;
    private uint selected_with_idle_keepalive_sec = ClientSession.DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC;
    
    public signal void login_failed();
    
    public ClientSessionManager(Endpoint endpoint, Credentials credentials,
        AccountInformation account_info) {
        this.endpoint = endpoint;
        this.credentials = credentials;
        this.account_info = account_info;
        
        adjust_session_pool.begin();
    }
    
    // TODO: Need a more thorough and bulletproof system for maintaining a pool of ready
    // authorized sessions.
    private async void adjust_session_pool() {
        int token;
        try {
            token = yield sessions_mutex.claim_async();
        } catch (Error claim_err) {
            debug("Unable to claim session table mutex for adjusting pool: %s", claim_err.message);
            
            return;
        }
        
        while (sessions.size < MIN_POOL_SIZE) {
            try {
                yield create_new_authorized_session(null);
            } catch (Error err) {
                debug("Unable to create authorized session to %s: %s", endpoint.to_string(), err.message);
                
                break;
            }
        }
        
        try {
            sessions_mutex.release(ref token);
        } catch (Error release_err) {
            debug("Unable to release session table mutex after adjusting pool: %s", release_err.message);
        }
    }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a connection has not
     * selected a mailbox.  (This is not recommended.)
     *
     * This only affects newly created sessions or sessions leaving the selected/examined state
     * and returning to an authorized state.
     */
    public void set_unselected_keepalive(int unselected_keepalive_sec) {
        // set for future connections
        this.unselected_keepalive_sec = unselected_keepalive_sec;
    }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public void set_selected_keepalive(int selected_keepalive_sec) {
        this.selected_keepalive_sec = selected_keepalive_sec;
    }
    
    /**
     * Set to zero or negative value if keepalives should be disabled when a mailbox is selected
     * or examined and IDLE is supported.  (This is not recommended.)
     *
     * This only affects newly selected/examined sessions.
     */
    public void set_selected_with_idle_keepalive(int selected_with_idle_keepalive_sec) {
        this.selected_with_idle_keepalive_sec = selected_with_idle_keepalive_sec;
    }
    
    public async Gee.Collection<Geary.Imap.MailboxInformation> list_roots(
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand.wildcarded("", "%"), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return results.get_all();
    }
    
    public async Gee.Collection<Geary.Imap.MailboxInformation> list(string parent,
        string delim, Cancellable? cancellable = null) throws Error {
        // build a proper IMAP specifier
        string specifier = parent;
        specifier += specifier.has_suffix(delim) ? "%" : (delim + "%");
        
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(specifier), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return results.get_all();
    }
    
    public async bool folder_exists_async(string path, Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(path), cancellable));
        
        return (results.status_response.status == Status.OK) && (results.get_count() == 1);
    }
    
    public async Geary.Imap.MailboxInformation? fetch_async(string path,
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(path), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return (results.get_count() > 0) ? results.get_all()[0] : null;
    }
    
    public async Geary.Imap.StatusResults status_async(string path, StatusDataType[] types,
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        StatusResults results = StatusResults.decode(yield session.send_command_async(
            new StatusCommand(path, types), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return results;
    }
    
    public async Mailbox select_mailbox(string path, Cancellable? cancellable = null) throws Error {
        return yield select_examine_mailbox(path, true, cancellable);
    }
    
    public async Mailbox examine_mailbox(string path, Cancellable? cancellable = null) throws Error {
        return yield select_examine_mailbox(path, false, cancellable);
    }
    
    public async Mailbox select_examine_mailbox(string path, bool is_select,
        Cancellable? cancellable = null) throws Error {
        Gee.HashSet<SelectedContext> contexts = is_select ? selected_contexts : examined_contexts;
        SelectedContext new_context = yield select_examine_async(path, is_select, cancellable);
        
        if (!contexts.contains(new_context)) {
            // Can't use the ternary operator due to this bug:
            // https://bugzilla.gnome.org/show_bug.cgi?id=599349
            if (is_select)
                new_context.freed.connect(on_selected_context_freed);
            else
                new_context.freed.connect(on_examined_context_freed);
            
            bool added = contexts.add(new_context);
            assert(added);
        }
        
        return new Mailbox(new_context);
    }
    
    private void on_selected_context_freed(Geary.ReferenceSemantics semantics) {
        on_context_freed(semantics, selected_contexts);
    }
    
    private void on_examined_context_freed(Geary.ReferenceSemantics semantics) {
        on_context_freed(semantics, examined_contexts);
    }
    
    private void on_context_freed(Geary.ReferenceSemantics semantics, 
        Gee.HashSet<SelectedContext> contexts) {
        SelectedContext context = (SelectedContext) semantics;
        
        // last reference to the Mailbox has been dropped, so drop the mailbox and move the
        // ClientSession back to the authorized state
        bool removed = contexts.remove(context);
        assert(removed);
        
        do_close_mailbox_async.begin(context);
    }
    
    private async void do_close_mailbox_async(SelectedContext context) {
        try {
            if (context.session != null)
                yield context.session.close_mailbox_async();
        } catch (Error err) {
            debug("Error closing IMAP mailbox: %s", err.message);
            
            if (context.session != null)
                remove_session(context.session);
        }
    }
    
    // This should only be called when sessions_mutex is locked.
    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        ClientSession new_session = new ClientSession(endpoint, account_info);
        
        // add session to pool before launching all the connect activity so error cases can properly
        // back it out
        add_session(new_session);
        
        try {
            yield new_session.connect_async(cancellable);
            yield new_session.login_async(credentials, cancellable);
            
            // If no capabilities were returned at login, ask for them now
            if (new_session.get_capabilities().is_empty())
                yield new_session.send_command_async(new CapabilityCommand());
            
            // Attempt compression
            if (new_session.get_capabilities().has_setting("compress", "deflate")) {
                CommandResponse resp = yield new_session.send_command_async(
                    new Command("COMPRESS", { "DEFLATE" }));
                if (resp.status_response.status == Status.OK) {
                    assert(new_session.install_send_converter(new ZlibCompressor(ZlibCompressorFormat.RAW)));
                    assert(new_session.install_recv_converter(new ZlibDecompressor(ZlibCompressorFormat.RAW)));
                    debug("Compression started on %s", new_session.to_string());
                } else {
                    debug("Unable to start compression on %s: %s", new_session.to_string(), resp.to_string());
                }
            } else {
                debug("No compression available on %s", new_session.to_string());
            }
        } catch (Error err) {
            debug("Connect failure on %s: %s", new_session.to_string(), err.message);
            
            // possible session was already removed in error handling inside a signal call;
            // don't assert on the removal
            remove_session(new_session);
            
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
    
    private async ClientSession get_authorized_session(Cancellable? cancellable) throws Error {
        int token = yield sessions_mutex.claim_async(cancellable);
        
        ClientSession? found_session = null;
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED) {
                found_session = session;
                
                break;
            }
        }
        
        Error? c = null;
        try {
            if (found_session == null)
                found_session = yield create_new_authorized_session(cancellable);
        } catch (Error e2) {
            debug("Error creating session %s", e2.message);
            c = e2;
        } finally {
            try {
                sessions_mutex.release(ref token);
            } catch (Error e) {
                debug("Error releasing mutex: %s", e.message);
                c = e;
            }
        }
        
        if (c != null)
            throw c;
        
        return found_session;
    }
    
    private async SelectedContext select_examine_async(string folder, bool is_select,
        Cancellable? cancellable) throws Error {
        ClientSession.Context needed_context = (is_select) ? ClientSession.Context.SELECTED
            : ClientSession.Context.EXAMINED;
        
        Gee.HashSet<SelectedContext> contexts = is_select ? selected_contexts : examined_contexts;
        foreach (SelectedContext c in contexts) {
            string? mailbox;
            if (c.session != null && (c.session.get_context(out mailbox) == needed_context &&
                mailbox == folder))
                return c;
        }
        
        ClientSession authd = yield get_authorized_session(cancellable);
        
        SelectExamineResults results = yield authd.select_examine_async(folder, is_select, cancellable);
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return new SelectedContext(authd, results);
    }
    
    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        bool removed = remove_session(session);
        assert(removed);
        
        adjust_session_pool.begin();
    }
    
    private void on_login_failed() {
        login_failed();
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
        
        return removed;
    }
    
    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return endpoint.to_string();
    }
}

