/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSessionManager {
    public const int MIN_POOL_SIZE = 2;
    
    private Credentials cred;
    private uint default_port;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private Geary.Common.NonblockingMutex sessions_mutex = new Geary.Common.NonblockingMutex();
    private Gee.HashSet<SelectedContext> examined_contexts = new Gee.HashSet<SelectedContext>();
    private Gee.HashSet<SelectedContext> selected_contexts = new Gee.HashSet<SelectedContext>();
    private int keepalive_sec = ClientSession.DEFAULT_KEEPALIVE_SEC;
    
    public ClientSessionManager(Credentials cred, uint default_port) {
        this.cred = cred;
        this.default_port = default_port;
        
        adjust_session_pool.begin();
    }
    
    // TODO: Need a more thorough and bulletproof system for maintaining a pool of ready
    // authorized sessions.
    private async void adjust_session_pool() {
        while (sessions.size < MIN_POOL_SIZE) {
            try {
                yield create_new_authorized_session(null);
            } catch (Error err) {
                debug("Unable to create authorized session to %s: %s", cred.server, err.message);
            }
        }
    }
    
    /**
     * Set to zero or negative value if keepalives should be disabled.  (This is not recommended.)
     */
    public void set_keepalive(int keepalive_sec) {
        // set for future connections
        this.keepalive_sec = keepalive_sec;
        
        // set for all current connections
        foreach (ClientSession session in sessions)
            session.enable_keepalives(keepalive_sec);
    }
    
    public async Gee.Collection<Geary.Imap.MailboxInformation> list_roots(
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand.wildcarded(session.generate_tag(), "%", "%"), cancellable));
        
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
            new ListCommand(session.generate_tag(), specifier), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return results.get_all();
    }
    
    public async bool folder_exists_async(string path, Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), path), cancellable));
        
        return (results.status_response.status == Status.OK) && (results.get_count() == 1);
    }
    
    public async Geary.Imap.MailboxInformation? fetch_async(string path,
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), path), cancellable));
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        return (results.get_count() > 0) ? results.get_all()[0] : null;
    }
    
    public async Geary.Imap.StatusResults status_async(string path, StatusDataType[] types,
        Cancellable? cancellable = null) throws Error {
        ClientSession session = yield get_authorized_session(cancellable);
        
        StatusResults results = StatusResults.decode(yield session.send_command_async(
            new StatusCommand(session.generate_tag(), path, types), cancellable));
        
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
        
        foreach (SelectedContext context in contexts) {
            if (context.name == path)
                return new Mailbox(context);
        }
        
        SelectExamineResults results;
        ClientSession session = yield select_examine_async(path, is_select, out results, cancellable);
        
        if (results.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", results.to_string());
        
        SelectedContext new_context = new SelectedContext(session, results);
        
        // Can't use the ternary operator due to this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=599349
        if (is_select)
            new_context.freed.connect(on_selected_context_freed);
        else
            new_context.freed.connect(on_examined_context_freed);
        
        bool added = contexts.add(new_context);
        assert(added);
        
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
        
        if (context.session != null)
            context.session.close_mailbox_async.begin();
    }
    
    // This should only be called when sessions_mutex is locked.
    private async ClientSession create_new_authorized_session(Cancellable? cancellable) throws Error {
        ClientSession new_session = new ClientSession(cred.server, default_port);
        new_session.disconnected.connect(on_disconnected);
        
        yield new_session.connect_async(cancellable);
        yield new_session.login_async(cred.user, cred.pass, cancellable);
        
        // do this after logging in
        new_session.enable_keepalives(keepalive_sec);
        
        sessions.add(new_session);
        
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
        
        if (found_session == null)
            found_session = yield create_new_authorized_session(cancellable);
        
        sessions_mutex.release(token);
        
        return found_session;
    }
    
    private async ClientSession select_examine_async(string folder, bool is_select,
        out SelectExamineResults results, Cancellable? cancellable) throws Error {
        ClientSession.Context needed_context = (is_select) ? ClientSession.Context.SELECTED
            : ClientSession.Context.EXAMINED;
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == needed_context && mailbox == folder)
                return session;
        }
        
        ClientSession authd = yield get_authorized_session(cancellable);
        
        results = yield authd.select_examine_async(folder, is_select, cancellable);
        
        return authd;
    }
    
    private void on_disconnected(ClientSession session, ClientSession.DisconnectReason reason) {
        bool removed = sessions.remove(session);
        assert(removed);
    }
    
    /**
     * Use only for debugging and logging.
     */
    public string to_string() {
        return cred.to_string();
    }
}

