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
    
    public async Gee.Collection<string> list(string parent, Cancellable? cancellable = null) throws Error {
        string specifier = String.is_empty(parent) ? "/" : parent;
        specifier += (specifier.has_suffix("/")) ? "%" : "/%";
        
        ClientSession session = yield get_authorized_session(cancellable);
        
        ListResults results = ListResults.decode(yield session.send_command_async(
            new ListCommand(session.generate_tag(), specifier), cancellable));
        
        return results.get_names();
    }
    
    public async Geary.Folder open(string folder, Cancellable? cancellable = null) throws Error {
        return new Mailbox(yield examine_async(folder, cancellable), on_destroying_mailbox);
    }
    
    private async ClientSession get_authorized_session(Cancellable? cancellable = null) throws Error {
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == ClientSession.Context.AUTHORIZED)
                return session;
        }
        
        ClientSession new_session = new ClientSession(server, default_port);
        
        yield new_session.connect_async(cancellable);
        yield new_session.login_async(user, pass, cancellable);
        
        // do this after logging in
        new_session.enable_keepalives(keepalive_sec);
        
        sessions.add(new_session);
        
        return new_session;
    }
    
    public async ClientSession select_async(string folder, Cancellable? cancellable = null)
        throws Error {
        return yield select_examine_async(folder, true, cancellable);
    }
    
    public async ClientSession examine_async(string folder, Cancellable? cancellable = null)
        throws Error {
        return yield select_examine_async(folder, false, cancellable);
    }
    
    public async ClientSession select_examine_async(string folder, bool is_select,
        Cancellable? cancellable = null) throws Error {
        ClientSession.Context needed_context = (is_select) ? ClientSession.Context.SELECTED
            : ClientSession.Context.EXAMINED;
        foreach (ClientSession session in sessions) {
            string? mailbox;
            if (session.get_context(out mailbox) == needed_context && mailbox == folder)
                return session;
        }
        
        ClientSession authd = yield get_authorized_session(cancellable);
        
        yield authd.select_examine_async(folder, is_select, cancellable);
        
        return authd;
    }
    
    private void on_destroying_mailbox(Mailbox mailbox) {
        ClientSession? session = mailbox.get_client_session();
        if (session != null)
            session.close_mailbox_async.begin(null);
    }
}

