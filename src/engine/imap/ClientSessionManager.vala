/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSessionManager : Object, Geary.Account {
    private string server;
    private uint default_port;
    private string user;
    private string pass;
    private Gee.HashSet<ClientSession> sessions = new Gee.HashSet<ClientSession>();
    private Gee.HashSet<MailboxContext> examined_contexts = new Gee.HashSet<MailboxContext>();
    private Gee.HashSet<MailboxContext> selected_contexts = new Gee.HashSet<MailboxContext>();
    private int keepalive_sec = ClientSession.DEFAULT_KEEPALIVE_SEC;
    
    public ClientSessionManager(string server, uint default_port, string user, string pass) {
        this.server = server;
        this.default_port = default_port;
        this.user = user;
        this.pass = pass;
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
    
    public async Gee.Collection<Geary.FolderDetail> list(Geary.FolderDetail? parent,
        Cancellable? cancellable = null) throws Error {
        string specifier = (parent != null) ? parent.name : "/";
        specifier += (specifier.has_suffix("/")) ? "%" : "/%";
        
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), specifier), cancellable));
        
        return results.get_all();
    }
    
    public async Mailbox select_mailbox(string path, Cancellable? cancellable = null) throws Error {
        return yield select_examine_mailbox(path, true, cancellable);
    }
    
    public async Mailbox examine_mailbox(string path, Cancellable? cancellable = null) throws Error {
        return yield select_examine_mailbox(path, false, cancellable);
    }
    
    private async Mailbox select_examine_mailbox(string path, bool is_select,
        Cancellable? cancellable = null) throws Error {
        Gee.HashSet<MailboxContext> contexts = is_select ? selected_contexts : examined_contexts;
        
        foreach (MailboxContext mailbox_context in contexts) {
            if (mailbox_context.name == path)
                return new Mailbox(mailbox_context);
        }
        
        SelectExamineResults results;
        ClientSession session = yield select_examine_async(path, is_select, out results, cancellable);
        
        MailboxContext new_mailbox_context = new MailboxContext(session, results);
        
        // Can't use the ternary operator due to this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=599349
        if (is_select)
            new_mailbox_context.freed.connect(on_selected_context_freed);
        else
            new_mailbox_context.freed.connect(on_examined_context_freed);
        
        bool added = contexts.add(new_mailbox_context);
        assert(added);
        
        return new Mailbox(new_mailbox_context);
    }
    
    private void on_selected_context_freed(Geary.ReferenceSemantics semantics) {
        on_context_freed(semantics, selected_contexts);
    }
    
    private void on_examined_context_freed(Geary.ReferenceSemantics semantics) {
        on_context_freed(semantics, examined_contexts);
    }
    
    private void on_context_freed(Geary.ReferenceSemantics semantics, 
        Gee.HashSet<MailboxContext> contexts) {
        MailboxContext mailbox_context = (MailboxContext) semantics;
        
        debug("Mailbox %s freed, closing select/examine", mailbox_context.name);
        
        // last reference to the Mailbox has been dropped, so drop the mailbox and move the
        // ClientSession back to the authorized state
        bool removed = contexts.remove(mailbox_context);
        assert(removed);
        
        if (mailbox_context.session != null)
            mailbox_context.session.close_mailbox_async.begin();
    }
    
    public async Geary.Folder open(string folder, Cancellable? cancellable = null) throws Error {
        return yield examine_mailbox(folder, cancellable);
    }
    
    private async ClientSession get_authorized_session(Cancellable? cancellable = null) throws Error {
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)
                return session;
        }
        
        debug("Creating new session to %s", server);
        
        ClientSession new_session = new ClientSession(server, default_port);
        new_session.disconnected.connect(on_disconnected);
        
        yield new_session.connect_async(cancellable);
        yield new_session.login_async(user, pass, cancellable);
        
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

