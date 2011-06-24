/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSessionManager {
    private Credentials cred;
    private uint default_port;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private Gee.HashSet<SelectedContext> examined_contexts = new Gee.HashSet<SelectedContext>();
    private Gee.HashSet<SelectedContext> selected_contexts = new Gee.HashSet<SelectedContext>();
    private int keepalive_sec = ClientSession.DEFAULT_KEEPALIVE_SEC;
    
    public ClientSessionManager(Credentials cred, uint default_port) {
        this.cred = cred;
        this.default_port = default_port;
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
    
    public async Gee.Collection<Geary.Imap.MailboxInformation> list(string? parent_name,
        Cancellable? cancellable = null) throws Error {
        // build a proper IMAP specifier
        string specifier = parent_name ?? "/";
        specifier += (specifier.has_suffix("/")) ? "%" : "/%";
        
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), specifier), cancellable));
        
        return results.get_all();
    }
    
    public async Geary.Imap.MailboxInformation? fetch_async(string? parent_name, string folder_name,
        Cancellable? cancellable = null) throws Error {
        // build a proper IMAP specifier
        string specifier = parent_name ?? "/";
        specifier += (specifier.has_suffix("/")) ? folder_name : "/%s".printf(folder_name);
        
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), specifier), cancellable));
        
        return (results.get_count() > 0) ? results.get_all()[0] : null;
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
        
        debug("Mailbox %s freed, closing select/examine", context.name);
        
        // last reference to the Mailbox has been dropped, so drop the mailbox and move the
        // ClientSession back to the authorized state
        bool removed = contexts.remove(context);
        assert(removed);
        
        if (context.session != null)
            context.session.close_mailbox_async.begin();
    }
    
    private async ClientSession get_authorized_session(Cancellable? cancellable = null) throws Error {
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)
                return session;
        }
        
        debug("Creating new session to %s", cred.server);
        
        ClientSession new_session = new ClientSession(cred.server, default_port);
        new_session.disconnected.connect(on_disconnected);
        
        yield new_session.connect_async(cancellable);
        yield new_session.login_async(cred.user, cred.pass, cancellable);
        
        // do this after logging in
        new_session.enable_keepalives(keepalive_sec);
        
        sessions.add(new_session);
        
        return new_session;
    }
    
    private async ClientSession select_examine_async(string folder, bool is_select,
        out SelectExamineResults results, Cancellable? cancellable = null) throws Error {
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
        debug("Client session %s disconnected: %s", session.to_string(), reason.to_string());
        
        bool removed = sessions.remove(session);
        assert(removed);
    }
}

