/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Object, Geary.Folder {
    public string name { get; protected set; }
    public int count { get; protected set; }
    public bool is_readonly { get; protected set; }
    
    private ClientSession? session;
    private SelectExamineResults select_results;
    private Geary.Delegate.DestructorNotifier<Mailbox>? dtor_notifier;
    
    internal Mailbox(ClientSession session, SelectExamineResults results, 
        Geary.Delegate.DestructorNotifier<Mailbox>? dtor_notifier) {
        this.session = session;
        this.select_results = results;
        this.dtor_notifier = dtor_notifier;
        
        name = session.get_current_mailbox();
        is_readonly = results.readonly;
        count = results.exists;
        
        session.current_mailbox_changed.connect(on_session_mailbox_changed);
        session.logged_out.connect(on_session_logged_out);
        session.disconnected.connect(on_session_disconnected);
    }
    
    ~Mailbox() {
        if (session != null) {
            session.current_mailbox_changed.disconnect(on_session_mailbox_changed);
            session.logged_out.disconnect(on_session_logged_out);
            session.disconnected.disconnect(on_session_disconnected);
        }
        
        if (dtor_notifier != null)
            dtor_notifier(this);
    }
    
    internal ClientSession? get_client_session() {
        return session;
    }
    
    public bool is_closed() {
        return (session == null);
    }
    
    public async Gee.List<Message>? read(int low, int count, Cancellable? cancellable = null) throws Error {
        if (is_closed())
            throw new IOError.NOT_FOUND("Folder closed");
        
        string span = (count > 1) ? "%d:%d".printf(low, low + count - 1) : "%d".printf(low);
        
        CommandResponse resp = yield session.send_command_async(new FetchCommand(session.generate_tag(),
            span, { FetchDataType.ENVELOPE }), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        Gee.List<Message> msgs = new Gee.ArrayList<Message>();
        
        FetchResults[] results = FetchResults.decode(resp);
        foreach (FetchResults res in results) {
            Envelope envelope = (Envelope) res.get_data(FetchDataType.ENVELOPE);
            msgs.add(new Message(res.msg_num, envelope.from, envelope.subject, envelope.sent));
        }
        
        return msgs;
    }
    
    private void close(Geary.Folder.CloseReason reason) {
        if (session == null)
            return;
        
        session = null;
        closed(reason);
    }
    
    private void on_session_mailbox_changed(string? old_mailbox, string? new_mailbox, bool readonly) {
        // this always mean one thing: this object is no longer valid
        close(CloseReason.FOLDER_CLOSED);
    }
    
    private void on_session_logged_out() {
        close(CloseReason.LOCAL_CLOSE);
    }
    
    private void on_session_disconnected(ClientSession.DisconnectReason reason) {
        switch (reason) {
            case ClientSession.DisconnectReason.LOCAL_CLOSE:
            case ClientSession.DisconnectReason.LOCAL_ERROR:
                close(CloseReason.LOCAL_CLOSE);
            break;
            
            case ClientSession.DisconnectReason.REMOTE_CLOSE:
            case ClientSession.DisconnectReason.REMOTE_ERROR:
                close(CloseReason.REMOTE_CLOSE);
            break;
            
            default:
                assert_not_reached();
        }
    }
}

