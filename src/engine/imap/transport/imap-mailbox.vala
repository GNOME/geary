/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Geary.SmartReference {
    public string name { get { return context.name; } }
    public int exists { get { return context.exists; } }
    public int recent { get { return context.recent; } }
    public int unseen { get { return context.unseen; } }
    public bool is_readonly { get { return context.is_readonly; } }
    public UIDValidity? uid_validity { get { return context.uid_validity; } }
    public UID? uid_next { get { return context.uid_next; } }
    
    private SelectedContext context;
    
    public signal void exists_altered(int old_exists, int new_exists);
    
    public signal void recent_altered(int recent);
    
    public signal void flags_altered(FetchResults flags);
    
    public signal void expunged(MessageNumber msg_num, int total);
    
    public signal void closed();
    
    public signal void disconnected(bool local);
    
    internal Mailbox(SelectedContext context) {
        base (context);
        
        this.context = context;
        
        context.closed.connect(on_closed);
        context.disconnected.connect(on_disconnected);
        context.exists_altered.connect(on_exists_altered);
        context.expunged.connect(on_expunged);
        context.flags_altered.connect(on_flags_altered);
        context.recent_altered.connect(on_recent_altered);
    }
    
    ~Mailbox() {
        context.closed.disconnect(on_closed);
        context.disconnected.disconnect(on_disconnected);
        context.exists_altered.disconnect(on_exists_altered);
        context.expunged.disconnect(on_expunged);
        context.flags_altered.disconnect(on_flags_altered);
        context.recent_altered.disconnect(on_recent_altered);
    }
    
    public async Gee.List<Geary.Email>? list_set_async(Geary.Folder folder, MessageSet msg_set,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        if (fields == Geary.Email.Field.NONE)
            throw new EngineError.BAD_PARAMETERS("No email fields specified");
        
        Gee.Set<FetchDataType> data_type_set = new Gee.HashSet<FetchDataType>();
        fields_to_fetch_data_types(fields, data_type_set);
        
        FetchCommand fetch_cmd = new FetchCommand.from_collection(context.session.generate_tag(),
            msg_set, data_type_set);
        
        CommandResponse resp = yield context.session.send_command_async(fetch_cmd, cancellable);
        
        if (resp.status_response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server error for %s: %s", fetch_cmd.to_string(),
                resp.to_string());
        }
        
        Gee.List<Geary.Email> msgs = new Gee.ArrayList<Geary.Email>();
        
        FetchResults[] results = FetchResults.decode(resp);
        foreach (FetchResults res in results) {
            UID? uid = res.get_data(FetchDataType.UID) as UID;
            // see fields_to_fetch_data_types() for why this is guaranteed
            assert(uid != null);
            
            Geary.Email email = new Geary.Email(new Geary.Imap.EmailLocation(folder, res.msg_num, uid),
                new Geary.Imap.EmailIdentifier(uid));
            fetch_results_to_email(res, fields, email);
            
            msgs.add(email);
        }
        
        return (msgs != null && msgs.size > 0) ? msgs : null;
    }
    
    public async Geary.Email fetch_async(Geary.Folder folder, Geary.Imap.UID uid, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        Gee.Set<FetchDataType> data_type_set = new Gee.HashSet<FetchDataType>();
        fields_to_fetch_data_types(fields, data_type_set);
        
        // no need to fetch the UID we're asking for
        data_type_set.remove(FetchDataType.UID);
        
        FetchCommand fetch_cmd = new FetchCommand.from_collection(context.session.generate_tag(),
            new MessageSet.uid(uid), data_type_set);
        
        CommandResponse resp = yield context.session.send_command_async(fetch_cmd, cancellable);
        
        if (resp.status_response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server error for %s: %s", fetch_cmd.to_string(),
                resp.to_string());
        }
        
        FetchResults[] results = FetchResults.decode(resp);
        if (results.length != 1)
            throw new ImapError.SERVER_ERROR("Too many responses from server: %d", results.length);
        
        Geary.Email email = new Geary.Email(new Geary.Imap.EmailLocation(folder, results[0].msg_num, uid),
            new Geary.Imap.EmailIdentifier(uid));
        fetch_results_to_email(results[0], fields, email);
        
        return email;
    }
    
    private void on_closed() {
        closed();
    }
    
    private void on_disconnected(bool local) {
        disconnected(local);
    }
    
    private void on_exists_altered(int old_exists, int new_exists) {
        exists_altered(old_exists, new_exists);
    }
    
    private void on_recent_altered(int recent) {
        recent_altered(recent);
    }
    
    private void on_expunged(MessageNumber msg_num, int total) {
        expunged(msg_num, total);
    }
    
    private void on_flags_altered(FetchResults flags) {
        flags_altered(flags);
    }
    
    // store FetchDataTypes in a set because the same data type may be requested multiple times
    // by different fields (i.e. ENVELOPE)
    private static void fields_to_fetch_data_types(Geary.Email.Field fields,
        Gee.Set<FetchDataType> data_type_set) {
        // UID is always fetched
        // TODO: Detect when FETCH is addressed by UID instead of position and *not* fetch the
        // UID, on the assumption that the caller will not need it
        data_type_set.add(FetchDataType.UID);
        
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
                    // Gmail doesn't like using FAST when combined with other fetch types, so
                    // do this manually
                    data_type_set.add(FetchDataType.FLAGS);
                    data_type_set.add(FetchDataType.INTERNALDATE);
                    data_type_set.add(FetchDataType.RFC822_SIZE);
                break;
                
                case Geary.Email.Field.NONE:
                    // not set
                break;
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    private static void fetch_results_to_email(FetchResults res, Geary.Email.Field fields,
        Geary.Email email) {
        // accumulate these to submit Imap.EmailProperties all at once
        Geary.Imap.MessageFlags? flags = null;
        InternalDate? internaldate = null;
        RFC822.Size? rfc822_size = null;
        
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
                
                case FetchDataType.RFC822_SIZE:
                    rfc822_size = (RFC822.Size) data;
                break;
                
                case FetchDataType.FLAGS:
                    flags = (MessageFlags) data;
                break;
                
                case FetchDataType.INTERNALDATE:
                    internaldate = (InternalDate) data;
                break;
                
                default:
                    // everything else dropped on the floor (not applicable to Geary.Email)
                break;
            }
        }
        
        if (flags != null && internaldate != null && rfc822_size != null)
            email.set_email_properties(new Geary.Imap.EmailProperties(flags, internaldate, rfc822_size));
    }
}

// A SelectedContext is a ReferenceSemantics object wrapping a ClientSession that is in a SELECTED
// or EXAMINED state (i.e. it has "cd'd" into a folder).  Multiple Mailbox objects may be created
// that refer to this SelectedContext.  When they're all destroyed, the session is returned to 
// the AUTHORIZED state by the ClientSessionManager.
//
// This means there is some duplication between the SelectedContext and the Mailbox.  In particular
// signals must be reflected to ensure order-of-operation is preserved (i.e. when the ClientSession
// "unsolicited-exists" signal is fired, a signal subscriber may then query SelectedContext for
// its exists count before it has received the notification).
//
// All this fancy stepping should not be exposed to a user of the IMAP portion of Geary, who should
// only see Geary.Imap.Mailbox, nor should it be exposed to the user of Geary.Engine, where all this
// should only be exposed via Geary.Folder.
private class Geary.Imap.SelectedContext : Object, Geary.ReferenceSemantics {
    public ClientSession? session { get; private set; }
    
    public string name { get; protected set; }
    public int exists { get; protected set; }
    public int recent { get; protected set; }
    public int unseen { get; protected set; }
    public bool is_readonly { get; protected set; }
    public UIDValidity? uid_validity { get; protected set; }
    public UID? uid_next { get; protected set; }
    
    protected int manual_ref_count { get; protected set; }
    
    public signal void exists_altered(int old_exists, int new_exists);
    
    public signal void recent_altered(int recent);
    
    public signal void expunged(MessageNumber msg_num, int total);
    
    public signal void flags_altered(FetchResults flags);
    
    public signal void closed();
    
    public signal void disconnected(bool local);
    
    internal SelectedContext(ClientSession session, SelectExamineResults results) {
        this.session = session;
        
        name = session.get_current_mailbox();
        is_readonly = results.readonly;
        exists = results.exists;
        recent = results.recent;
        unseen = results.unseen;
        uid_validity = results.uid_validity;
        uid_next = results.uid_next;
        
        session.current_mailbox_changed.connect(on_session_mailbox_changed);
        session.unsolicited_exists.connect(on_unsolicited_exists);
        session.unsolicited_recent.connect(on_unsolicited_recent);
        session.unsolicited_expunged.connect(on_unsolicited_expunged);
        session.unsolicited_flags.connect(on_unsolicited_flags);
        session.logged_out.connect(on_session_logged_out);
        session.disconnected.connect(on_session_disconnected);
    }
    
    ~SelectedContext() {
        if (session != null) {
            session.current_mailbox_changed.disconnect(on_session_mailbox_changed);
            session.unsolicited_exists.disconnect(on_unsolicited_exists);
            session.unsolicited_recent.disconnect(on_unsolicited_recent);
            session.unsolicited_recent.disconnect(on_unsolicited_recent);
            session.unsolicited_expunged.disconnect(on_unsolicited_expunged);
            session.logged_out.disconnect(on_session_logged_out);
            session.disconnected.disconnect(on_session_disconnected);
        }
    }
    
    public bool is_closed() {
        return (session == null);
    }
    
    private void on_unsolicited_exists(int exists) {
        // only report if changed; note that on_solicited_expunged also fires this signal
        if (this.exists == exists)
            return;
        
        int old_exists = this.exists;
        this.exists = exists;
        
        exists_altered(old_exists, this.exists);
    }
    
    private void on_unsolicited_recent(int recent) {
        this.recent = recent;
        
        recent_altered(recent);
    }
    
    private void on_unsolicited_expunged(MessageNumber msg_num) {
        assert(exists > 0);
        
        // update exists count along with reporting the deletion
        int old_exists = exists;
        exists--;
        
        exists_altered(old_exists, exists);
        expunged(msg_num, exists);
    }
    
    private void on_unsolicited_flags(FetchResults results) {
        flags_altered(results);
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

