/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Geary.SmartReference {
    public string name { get; private set; }
    public int count { get; private set; }
    public bool is_readonly { get; private set; }
    
    private SelectedContext context;
    
    public signal void closed();
    
    public signal void disconnected(bool local);
    
    internal Mailbox(SelectedContext context) {
        base (context);
        
        this.context = context;
        context.exists_changed.connect(on_exists_changed);
        context.closed.connect(on_closed);
        context.disconnected.connect(on_disconnected);
        
        name = context.name;
        count = context.exists;
        is_readonly = context.is_readonly;
    }
    
    public async Gee.List<EmailHeader>? read(int low, int count, Cancellable? cancellable = null)
        throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        CommandResponse resp = yield context.session.send_command_async(
            new FetchCommand(context.session.generate_tag(), new MessageSet.range(low, count),
                { FetchDataType.ENVELOPE }), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        Gee.List<EmailHeader> msgs = new Gee.ArrayList<EmailHeader>();
        
        FetchResults[] results = FetchResults.decode(resp);
        foreach (FetchResults res in results) {
            Envelope envelope = (Envelope) res.get_data(FetchDataType.ENVELOPE);
            msgs.add(new EmailHeader(res.msg_num, envelope));
        }
        
        return msgs;
    }
    
    public async Geary.Email fetch(Geary.EmailHeader hdr, Cancellable? cancellable = null)
        throws Error {
        Geary.Imap.EmailHeader? header = hdr as Geary.Imap.EmailHeader;
        assert(header != null);
        
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        CommandResponse resp = yield context.session.send_command_async(
            new FetchCommand(context.session.generate_tag(), new MessageSet(hdr.msg_num),
                { FetchDataType.RFC822_TEXT }), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        FetchResults[] results = FetchResults.decode(resp);
        if (results.length != 1)
            throw new ImapError.SERVER_ERROR("Too many responses from server: %d", results.length);
        
        Geary.RFC822.Text text = (Geary.RFC822.Text) results[0].get_data(FetchDataType.RFC822_TEXT);
        
        return new Email(header, text.buffer.to_ascii_string());
    }
    
    private void on_exists_changed(int exists) {
        count = exists;
    }
    
    private void on_closed() {
        closed();
    }
    
    private void on_disconnected(bool local) {
        disconnected(local);
    }
}

internal class Geary.Imap.SelectedContext : Object, Geary.ReferenceSemantics {
    public ClientSession? session { get; private set; }
    
    protected int manual_ref_count { get; protected set; }
    
    public string name { get; protected set; }
    public int exists { get; protected set; }
    public int recent { get; protected set; }
    public bool is_readonly { get; protected set; }
    
    public signal void exists_changed(int exists);
    
    public signal void recent_changed(int recent);
    
    public signal void closed();
    
    public signal void disconnected(bool local);
    
    internal SelectedContext(ClientSession session, SelectExamineResults results) {
        this.session = session;
        
        name = session.get_current_mailbox();
        is_readonly = results.readonly;
        exists = results.exists;
        recent = results.recent;
        
        session.current_mailbox_changed.connect(on_session_mailbox_changed);
        session.unsolicited_exists.connect(on_unsolicited_exists);
        session.unsolicited_recent.connect(on_unsolicited_recent);
        session.logged_out.connect(on_session_logged_out);
        session.disconnected.connect(on_session_disconnected);
    }
    
    ~SelectedContext() {
        if (session != null) {
            session.current_mailbox_changed.disconnect(on_session_mailbox_changed);
            session.unsolicited_exists.disconnect(on_unsolicited_exists);
            session.unsolicited_recent.disconnect(on_unsolicited_recent);
            session.logged_out.disconnect(on_session_logged_out);
            session.disconnected.disconnect(on_session_disconnected);
        }
    }
    
    public bool is_closed() {
        return (session == null);
    }
    
    private void on_unsolicited_exists(int exists) {
        this.exists = exists;
        exists_changed(exists);
    }
    
    private void on_unsolicited_recent(int recent) {
        this.recent = recent;
        recent_changed(recent);
    }
    
    private void on_session_mailbox_changed(string? old_mailbox, string? new_mailbox, bool readonly) {
        session = null;
        closed();
    }
    
    private void on_session_logged_out() {
        session = null;
        disconnected(true);
    }
    
    private void on_session_disconnected(ClientSession.DisconnectReason reason) {
        session = null;
        
        switch (reason) {
            case ClientSession.DisconnectReason.LOCAL_CLOSE:
            case ClientSession.DisconnectReason.LOCAL_ERROR:
                disconnected(true);
            break;
            
            case ClientSession.DisconnectReason.REMOTE_CLOSE:
            case ClientSession.DisconnectReason.REMOTE_ERROR:
                disconnected(false);
            break;
            
            default:
                assert_not_reached();
        }
    }
}

