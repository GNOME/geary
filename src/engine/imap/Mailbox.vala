/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Geary.SmartReference {
    public string name { get; private set; }
    public int count { get; private set; }
    public bool is_readonly { get; private set; }
    public UID uid_validity { get; private set; }
    
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
        uid_validity = context.uid_validity;
    }
    
    public async Gee.List<Geary.Email>? list_set_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        if (fields == Geary.Email.Field.NONE)
            throw new EngineError.BAD_PARAMETERS("No email fields specify for list");
        
        CommandResponse resp = yield context.session.send_command_async(
            new FetchCommand(context.session.generate_tag(), msg_set,
                fields_to_fetch_data_types(fields)), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        Gee.List<Geary.Email> msgs = new Gee.ArrayList<Geary.Email>();
        
        FetchResults[] results = FetchResults.decode(resp);
        foreach (FetchResults res in results) {
            UID? uid = res.get_data(FetchDataType.UID) as UID;
            assert(uid != null);
            
            Geary.Email email = new Geary.Email(new Geary.Imap.EmailLocation(res.msg_num, uid));
            fetch_results_to_email(res, fields, email);
            msgs.add(email);
        }
        
        return (msgs != null && msgs.size > 0) ? msgs : null;
    }
    
    public async Geary.Email fetch_async(int msg_num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        CommandResponse resp = yield context.session.send_command_async(
            new FetchCommand(context.session.generate_tag(), new MessageSet(msg_num),
                fields_to_fetch_data_types(fields)), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        FetchResults[] results = FetchResults.decode(resp);
        if (results.length != 1)
            throw new ImapError.SERVER_ERROR("Too many responses from server: %d", results.length);
        
        if (results[0].msg_num != msg_num) {
            throw new ImapError.SERVER_ERROR("Server returns message #%d, requested %d",
                results[0].msg_num, msg_num);
        }
        
        UID? uid = results[0].get_data(FetchDataType.UID) as UID;
        assert(uid != null);
        
        Geary.Email email = new Geary.Email(new Geary.Imap.EmailLocation(results[0].msg_num, uid));
        fetch_results_to_email(results[0], fields, email);
        
        return email;
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
    
    private static FetchDataType[] fields_to_fetch_data_types(Geary.Email.Field fields) {
        Gee.HashSet<FetchDataType> data_type_set = new Gee.HashSet<FetchDataType>();
        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            switch (fields & field) {
                case Geary.Email.Field.DATE:
                case Geary.Email.Field.ORIGINATORS:
                case Geary.Email.Field.RECEIVERS:
                case Geary.Email.Field.REFERENCES:
                case Geary.Email.Field.SUBJECT:
                    data_type_set.add(FetchDataType.ENVELOPE);
                break;
                
                case Geary.Email.Field.HEADER:
                    data_type_set.add(FetchDataType.RFC822_HEADER);
                break;
                
                case Geary.Email.Field.BODY:
                    data_type_set.add(FetchDataType.RFC822_TEXT);
                break;
                
                case Geary.Email.Field.PROPERTIES:
                    data_type_set.add(FetchDataType.FLAGS);
                break;
                
                case Geary.Email.Field.NONE:
                    // not set
                break;
                
                default:
                    assert_not_reached();
            }
        }
        
        assert(data_type_set.size > 0);
        FetchDataType[] data_types = new FetchDataType[data_type_set.size + 1];
        int ctr = 0;
        foreach (FetchDataType data_type in data_type_set)
            data_types[ctr++] = data_type;
        
        // UID is always fetched, no matter what the caller requests
        data_types[ctr] = FetchDataType.UID;
        
        return data_types;
    }
    
    private static void fetch_results_to_email(FetchResults res, Geary.Email.Field fields,
        Geary.Email email) {
        foreach (FetchDataType data_type in res.get_all_types()) {
            MessageData? data = res.get_data(data_type);
            if (data == null)
                continue;
            
            switch (data_type) {
                case FetchDataType.ENVELOPE:
                    Envelope envelope = (Envelope) data;
                    
                    if ((fields & Geary.Email.Field.DATE) != 0)
                        email.set_send_date(envelope.sent);
                    
                    if ((fields & Geary.Email.Field.SUBJECT) != 0)
                        email.set_message_subject(envelope.subject);
                    
                    if ((fields & Geary.Email.Field.ORIGINATORS) != 0)
                        email.set_originators(envelope.from, envelope.sender, envelope.reply_to);
                    
                    if ((fields & Geary.Email.Field.RECEIVERS) != 0)
                        email.set_receivers(envelope.to, envelope.cc, envelope.bcc);
                    
                    if ((fields & Geary.Email.Field.REFERENCES) != 0)
                        email.set_references(envelope.message_id, envelope.in_reply_to);
                break;
                
                case FetchDataType.RFC822_HEADER:
                    email.set_message_header((RFC822.Header) data);
                break;
                
                case FetchDataType.RFC822_TEXT:
                    email.set_message_body((RFC822.Text) data);
                break;
                
                case FetchDataType.FLAGS:
                    email.set_email_properties(new Imap.EmailProperties((MessageFlags) data));
                break;
                
                default:
                    // everything else dropped on the floor (not applicable to Geary.Email)
                break;
            }
        }
    }
}

internal class Geary.Imap.SelectedContext : Object, Geary.ReferenceSemantics {
    public ClientSession? session { get; private set; }
    
    protected int manual_ref_count { get; protected set; }
    
    public string name { get; protected set; }
    public int exists { get; protected set; }
    public int recent { get; protected set; }
    public bool is_readonly { get; protected set; }
    public UID uid_validity { get; protected set; }
    
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
        uid_validity = results.uid_validity;
        
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

