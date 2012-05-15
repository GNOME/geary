/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Geary.SmartReference {
    private class MailboxOperation : NonblockingBatchOperation {
        public SelectedContext context;
        public Command cmd;
        
        public MailboxOperation(SelectedContext context, Command cmd) {
            this.context = context;
            this.cmd = cmd;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            return yield context.session.send_command_async(cmd, cancellable);
        }
    }
    
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
    
    public signal void flags_altered(MailboxAttributes flags);
    
    public signal void expunged(MessageNumber msg_num, int total);
    
    public signal void closed();
    
    public signal void disconnected(Geary.Folder.CloseReason reason);
    
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
    
    // This helper function is tightly tied to list_set_async().  It assumes that if a new Email
    // must be created from the FETCH results, a UID is available in the results, either because it
    // was queried for or because UID addressing was used.  It adds the new email to the msgs list
    // and maps it into the positional map.  fields_to_fetch_data_types() is a key part of this
    // arrangement.
    private Geary.Email accumulate_email(FetchResults results, Gee.List<Email> msgs,
        Gee.HashMap<int, Email> pos_map) {
        // TODO: It's always assumed that the FetchResults will have a UID (due to UID addressing
        // or because it was requested as part of the FETCH command); however; some servers
        // (i.e. Dovecot) may split up their FetchResults to multiple lines.  If the UID comes in
        // first, no problem here, otherwise this scheme will fail
        UID? uid = results.get_data(FetchDataType.UID) as UID;
        assert(uid != null);
        
        Geary.Email email = new Geary.Email(results.msg_num, new Geary.Imap.EmailIdentifier(uid));
        msgs.add(email);
        pos_map.set(email.position, email);
        
        return email;
    }
    
    public async Gee.List<Geary.Email>? list_set_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        if (fields == Geary.Email.Field.NONE)
            throw new EngineError.BAD_PARAMETERS("No email fields specified");
        
        NonblockingBatch batch = new NonblockingBatch();
        
        Gee.List<FetchDataType> data_type_list = new Gee.ArrayList<FetchDataType>();
        Gee.List<FetchBodyDataType> body_data_type_list = new Gee.ArrayList<FetchBodyDataType>();
        fields_to_fetch_data_types(msg_set.is_uid, fields, data_type_list, body_data_type_list);
        
        // if nothing else, should always fetch the UID, which is gotten via data_type_list
        // (necessary to create the EmailIdentifier, also provides mappings of position -> UID)
        // *unless* MessageSet is UID addressing
        int plain_id = NonblockingBatch.INVALID_ID;
        if (data_type_list.size > 0 || body_data_type_list.size > 0) {
            FetchCommand fetch_cmd = new FetchCommand.from_collection(msg_set, data_type_list,
                body_data_type_list);
            plain_id = batch.add(new MailboxOperation(context, fetch_cmd));
        }
        
        int body_id = NonblockingBatch.INVALID_ID;
        if (fields.require(Geary.Email.Field.BODY)) {
            // Fetch the body.
            Gee.List<FetchBodyDataType> types = new Gee.ArrayList<FetchBodyDataType>();
            types.add(new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.TEXT, null, -1, -1, null));
            FetchCommand fetch_body = new FetchCommand(msg_set, null, types);
            
            body_id = batch.add(new MailboxOperation(context, fetch_body));
        }
        
        int preview_id = NonblockingBatch.INVALID_ID;
        int preview_charset_id = NonblockingBatch.INVALID_ID;
        if (fields.require(Geary.Email.Field.PREVIEW)) {
            // Preview text.
            FetchBodyDataType fetch_preview = new FetchBodyDataType.peek(FetchBodyDataType.SectionPart.NONE,
                { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES, null);
            Gee.List<FetchBodyDataType> list = new Gee.ArrayList<FetchBodyDataType>();
            list.add(fetch_preview);
            
            FetchCommand preview_cmd = new FetchCommand(msg_set, null, list);
            
            preview_id = batch.add(new MailboxOperation(context, preview_cmd));
            
            // Preview character set.
            FetchBodyDataType fetch_preview_charset = new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.MIME,
                { 1 }, -1, -1, null);
            Gee.List<FetchBodyDataType> list_charset = new Gee.ArrayList<FetchBodyDataType>();
            list_charset.add(fetch_preview_charset);
            
            FetchCommand preview_charset_cmd = new FetchCommand(msg_set, null, list_charset);
            
            preview_charset_id = batch.add(new MailboxOperation(context, preview_charset_cmd));
        }
        
        int properties_id = NonblockingBatch.INVALID_ID;
        if (fields.require(Geary.Email.Field.PROPERTIES)) {
            // Properties.
            Gee.List<FetchDataType> properties_data_types_list = new Gee.ArrayList<FetchDataType>();
            properties_data_types_list.add(FetchDataType.FLAGS);
            properties_data_types_list.add(FetchDataType.INTERNALDATE);
            properties_data_types_list.add(FetchDataType.RFC822_SIZE);
            
            FetchCommand properties_cmd = new FetchCommand.from_collection(msg_set,
                properties_data_types_list, null);
            
            properties_id = batch.add(new MailboxOperation(context, properties_cmd));
        }
        
        yield batch.execute_all_async(cancellable);
        
        // Keep list of generated messages (which are returned) and a map of the messages according
        // to their position addressing (which is built up as results are processed)
        Gee.List<Geary.Email> msgs = new Gee.ArrayList<Geary.Email>();
        Gee.HashMap<int, Geary.Email> pos_map = new Gee.HashMap<int, Geary.Email>();
        
        // process "plain" fetch results (i.e. simple IMAP data)
        if (plain_id != NonblockingBatch.INVALID_ID) {
            MailboxOperation plain_op = (MailboxOperation) batch.get_operation(plain_id);
            CommandResponse plain_resp = (CommandResponse) batch.get_result(plain_id);
            
            if (plain_resp.status_response.status != Status.OK) {
                throw new ImapError.SERVER_ERROR("Server error for %s: %s", plain_op.cmd.to_string(),
                    plain_resp.to_string());
            }
            
            FetchResults[] plain_results = FetchResults.decode(plain_resp);
            foreach (FetchResults plain_res in plain_results) {
                // even though msgs and pos_map are empty before this loop, it's possible the server
                // will send back multiple FetchResults for the same message, so always merge results
                // whenever possible
                Geary.Email? email = pos_map.get(plain_res.msg_num);
                if (email == null)
                    email = accumulate_email(plain_res, msgs, pos_map);
                
                fetch_results_to_email(plain_res, fields, email);
            }
        }
        
        // Process body results.
        if (body_id != NonblockingBatch.INVALID_ID) {
            MailboxOperation body_op = (MailboxOperation) batch.get_operation(body_id);
            CommandResponse body_resp = (CommandResponse) batch.get_result(body_id);
            
            if (body_resp.status_response.status != Status.OK) {
                throw new ImapError.SERVER_ERROR("Server error for %s: %s", 
                    body_op.cmd.to_string(), body_resp.to_string());
            }
            
            FetchResults[] body_results = FetchResults.decode(body_resp);
            foreach (FetchResults body_res in body_results) {
                Geary.Email? body_email = pos_map.get(body_res.msg_num);
                if (body_email == null)
                    body_email = accumulate_email(body_res, msgs, pos_map);
                
                body_email.set_message_body(new Geary.RFC822.Text(body_res.get_body_data().get(0)));
            }
        }
        
        // Process properties results.
        if (properties_id != NonblockingBatch.INVALID_ID) {
            MailboxOperation properties_op = (MailboxOperation) batch.get_operation(properties_id);
            CommandResponse properties_resp = (CommandResponse) batch.get_result(properties_id);
            
            if (properties_resp.status_response.status != Status.OK) {
                throw new ImapError.SERVER_ERROR("Server error for %s: %s", 
                    properties_op.cmd.to_string(), properties_resp.to_string());
            }
            
            FetchResults[] properties_results = FetchResults.decode(properties_resp);
            foreach (FetchResults properties_res in properties_results) {
                Geary.Email? properties_email = pos_map.get(properties_res.msg_num);
                if (properties_email == null)
                    properties_email = accumulate_email(properties_res, msgs, pos_map);
                
                fetch_results_to_email(properties_res, Geary.Email.Field.PROPERTIES, properties_email);
            }
        }
        
        // process preview FETCH results
        if (preview_id != NonblockingBatch.INVALID_ID && 
            preview_charset_id != NonblockingBatch.INVALID_ID) {
            
            MailboxOperation preview_op = (MailboxOperation) batch.get_operation(preview_id);
            CommandResponse preview_resp = (CommandResponse) batch.get_result(preview_id);
            
            MailboxOperation preview_charset_op = (MailboxOperation) 
                batch.get_operation(preview_charset_id);
            CommandResponse preview_charset_resp = (CommandResponse) 
                batch.get_result(preview_charset_id);
            
            if (preview_resp.status_response.status != Status.OK) {
                throw new ImapError.SERVER_ERROR("Server error for %s: %s", preview_op.cmd.to_string(),
                    preview_resp.to_string());
            }
            
            if (preview_charset_resp.status_response.status != Status.OK) {
                throw new ImapError.SERVER_ERROR("Server error for %s: %s", 
                    preview_charset_op.cmd.to_string(), preview_charset_resp.to_string());
            }
            
            FetchResults[] preview_results = FetchResults.decode(preview_resp);
            FetchResults[] preview_header_results = FetchResults.decode(preview_charset_resp);
            int i = 0;
            foreach (FetchResults preview_res in preview_results) {
                Geary.Email? preview_email = pos_map.get(preview_res.msg_num);
                if (preview_email == null)
                    preview_email = accumulate_email(preview_res, msgs, pos_map);
                
                preview_email.set_message_preview(new RFC822.PreviewText(
                    preview_res.get_body_data()[0], preview_header_results[i].get_body_data()[0]));
                i++;
            }
        }
        
        return (msgs.size > 0) ? msgs : null;
    }
    
    private void on_closed() {
        closed();
    }
    
    private void on_disconnected(Geary.Folder.CloseReason reason) {
        disconnected(reason);
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
    
    private void on_flags_altered(MailboxAttributes flags) {
        flags_altered(flags);
    }
    
    private void fields_to_fetch_data_types(bool is_uid, Geary.Email.Field fields,
        Gee.List<FetchDataType> data_types_list, Gee.List<FetchBodyDataType> body_data_types_list) {
        // always fetch UID because it's needed for EmailIdentifier UNLESS UID addressing is being
        // used, in which case UID will return with the response
        if (!is_uid)
            data_types_list.add(FetchDataType.UID);
        
        // pack all the needed headers into a single FetchBodyDataType
        string[] field_names = new string[0];
        
        // The assumption here is that because ENVELOPE is such a common fetch command, the
        // server will have optimizations for it, whereas if we called for each header in the
        // envelope separately, the server has to chunk harder parsing the RFC822 header ... have
        // to add References because IMAP ENVELOPE doesn't return them for some reason (but does
        // return Message-ID and In-Reply-To)
        if (fields.is_all_set(Geary.Email.Field.ENVELOPE)) {
            data_types_list.add(FetchDataType.ENVELOPE);
            field_names += "References";
            
            // remove those flags and process any remaining
            fields = fields.clear(Geary.Email.Field.ENVELOPE);
        }
        
        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            switch (fields & field) {
                case Geary.Email.Field.DATE:
                    field_names += "Date";
                break;
                
                case Geary.Email.Field.ORIGINATORS:
                    field_names += "From";
                    field_names += "Sender";
                    field_names += "Reply-To";
                break;
                
                case Geary.Email.Field.RECEIVERS:
                    field_names += "To";
                    field_names += "Cc";
                    field_names += "Bcc";
                break;
                
                case Geary.Email.Field.REFERENCES:
                    field_names += "References";
                    field_names += "Message-ID";
                    field_names += "In-Reply-To";
                break;
                
                case Geary.Email.Field.SUBJECT:
                    field_names += "Subject";
                break;
                
                case Geary.Email.Field.HEADER:
                    data_types_list.add(FetchDataType.RFC822_HEADER);
                break;
                
                case Geary.Email.Field.BODY:
                case Geary.Email.Field.PROPERTIES:
                case Geary.Email.Field.NONE:
                case Geary.Email.Field.PREVIEW:
                    // not set (or, for body previews and properties, fetched separately)
                break;
                
                default:
                    assert_not_reached();
            }
        }
        
        if (field_names.length > 0) {
            body_data_types_list.add(new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.HEADER_FIELDS, null, -1, -1, field_names));
        }
    }
    
    private static void fetch_results_to_email(FetchResults res, Geary.Email.Field fields,
        Geary.Email email) throws Error {
        // accumulate these to submit Imap.EmailProperties all at once
        Geary.Imap.MessageFlags? flags = null;
        InternalDate? internaldate = null;
        RFC822.Size? rfc822_size = null;
        
        // accumulate these to submit References all at once
        RFC822.MessageID? message_id = null;
        RFC822.MessageID? in_reply_to = null;
        RFC822.MessageIDList? references = null;
        
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
                    
                    if ((fields & Geary.Email.Field.REFERENCES) != 0) {
                        message_id = envelope.message_id;
                        in_reply_to = envelope.in_reply_to;
                    }
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
        
        // Only set PROPERTIES if all have been found
        if (flags != null && internaldate != null && rfc822_size != null)
            email.set_email_properties(new Geary.Imap.EmailProperties(flags, internaldate, rfc822_size));
        
        // fields_to_fetch_data_types() will always generate a single FetchBodyDataType for all
        // the header fields it needs
        Gee.List<Memory.AbstractBuffer> body_data = res.get_body_data();
        if (body_data.size > 0) {
            assert(body_data.size == 1);
            RFC822.Header headers = new RFC822.Header(body_data[0]);
            
            // DATE
            if (!email.fields.is_all_set(Geary.Email.Field.DATE) && fields.require(Geary.Email.Field.DATE)) {
                string? value = headers.get_header("Date");
                email.set_send_date(!String.is_empty(value) ? new RFC822.Date(value) : null);
            }
            
            // ORIGINATORS
            if (!email.fields.is_all_set(Geary.Email.Field.ORIGINATORS) && fields.require(Geary.Email.Field.ORIGINATORS)) {
                RFC822.MailboxAddresses? from = null;
                RFC822.MailboxAddresses? sender = null;
                RFC822.MailboxAddresses? reply_to = null;
                
                string? value = headers.get_header("From");
                if (!String.is_empty(value))
                    from = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                value = headers.get_header("Sender");
                if (!String.is_empty(value))
                    sender = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                value = headers.get_header("Reply-To");
                if (!String.is_empty(value))
                    reply_to = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                email.set_originators(from, sender, reply_to);
            }
            
            // RECEIVERS
            if (!email.fields.is_all_set(Geary.Email.Field.RECEIVERS) && fields.require(Geary.Email.Field.RECEIVERS)) {
                RFC822.MailboxAddresses? to = null;
                RFC822.MailboxAddresses? cc = null;
                RFC822.MailboxAddresses? bcc = null;
                
                string? value = headers.get_header("To");
                if (!String.is_empty(value))
                    to = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                value = headers.get_header("Cc");
                if (!String.is_empty(value))
                    cc = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                value = headers.get_header("Bcc");
                if (!String.is_empty(value))
                    bcc = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                email.set_receivers(to, cc, bcc);
            }
            
            // REFERENCES
            // (Note that it's possible the request used an IMAP ENVELOPE, in which case only the
            // References header will be present if REFERENCES were required, which is why
            // REFERENCES is set at the bottom of the method, when all information has been gathered
            if (message_id == null) {
                string? value = headers.get_header("Message-ID");
                if (!String.is_empty(value))
                    message_id = new RFC822.MessageID(value);
            }
            
            if (in_reply_to == null) {
                string? value = headers.get_header("In-Reply-To");
                if (!String.is_empty(value))
                    in_reply_to = new RFC822.MessageID(value);
            }
            
            if (references == null) {
                string? value = headers.get_header("References");
                if (!String.is_empty(value))
                    references = new RFC822.MessageIDList.from_rfc822_string(value);
            }
            
            // SUBJECT
            if (!email.fields.is_all_set(Geary.Email.Field.SUBJECT) && fields.require(Geary.Email.Field.SUBJECT)) {
                string? value = headers.get_header("Subject");
                email.set_message_subject(!String.is_empty(value) ? new RFC822.Subject.decode(value) : null);
            }
        }
        
        if (fields.require(Geary.Email.Field.REFERENCES))
            email.set_full_references(message_id, in_reply_to, references);
    }
    
    public async Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> mark_email_async(
        MessageSet to_mark, Gee.List<MessageFlag>? flags_to_add, Gee.List<MessageFlag>? flags_to_remove,
        Cancellable? cancellable = null) throws Error {
        
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ret = 
            new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>();
        
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        NonblockingBatch batch = new NonblockingBatch();
        int add_flags_id = NonblockingBatch.INVALID_ID;
        int remove_flags_id = NonblockingBatch.INVALID_ID;
        
        if (flags_to_add != null && flags_to_add.size > 0)
            add_flags_id = batch.add(new MailboxOperation(context, new StoreCommand(
                to_mark, flags_to_add, true, false)));
        
        if (flags_to_remove != null && flags_to_remove.size > 0)
            remove_flags_id = batch.add(new MailboxOperation(context, new StoreCommand(
                to_mark, flags_to_remove, false, false)));
        
        yield batch.execute_all_async(cancellable);
        
        if (add_flags_id != NonblockingBatch.INVALID_ID) {
            gather_flag_results((MailboxOperation) batch.get_operation(add_flags_id),
                (CommandResponse) batch.get_result(add_flags_id), ref ret);
        }
        
        if (remove_flags_id != NonblockingBatch.INVALID_ID) {
            gather_flag_results((MailboxOperation) batch.get_operation(remove_flags_id),
                (CommandResponse) batch.get_result(remove_flags_id), ref ret);
        }
        
        return ret;
    }
    
    // Helper function for building results for mark_email_async
    private void gather_flag_results(MailboxOperation operation, CommandResponse response, 
        ref Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map) throws Error {
        
        if (response.status_response == null)
            throw new ImapError.SERVER_ERROR("Server error. Command: %s No status response. %s", 
                operation.cmd.to_string(), response.to_string());
        
        if (response.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error. Command: %s Response: %s Error: %s", 
                operation.cmd.to_string(), response.to_string(),
                response.status_response.status.to_string());
        
        FetchResults[] results = FetchResults.decode(response);
        foreach (FetchResults res in results) {
            UID? uid = res.get_data(FetchDataType.UID) as UID;
            assert(uid != null);
            
            Geary.Imap.MessageFlags? msg_flags = res.get_data(FetchDataType.FLAGS) as MessageFlags;
            if (msg_flags != null) {
                Geary.Imap.EmailFlags email_flags = new Geary.Imap.EmailFlags(msg_flags);
                
                map.set(new Geary.Imap.EmailIdentifier(uid) , email_flags);
            } else {
                debug("No flags returned");
            }
        }
    }
    
    public async void expunge_email_async(MessageSet? msg_set, Cancellable? cancellable = null) throws Error {
        if (context.is_closed())
            throw new ImapError.NOT_SELECTED("Mailbox %s closed", name);
        
        // Response automatically handled by unsolicited server data. ... use UID EXPUNGE whenever
        // possible
        if (msg_set == null || !context.session.get_capabilities().has_capability("uidplus"))
            yield context.session.send_command_async(new ExpungeCommand(), cancellable);
        else
            yield context.session.send_command_async(new ExpungeCommand.uid(msg_set), cancellable);
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
    
    public signal void flags_altered(MailboxAttributes flags);
    
    public signal void closed();
    
    public signal void disconnected(Geary.Folder.CloseReason reason);
    
    public signal void login_failed();
    
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
        session.login_failed.connect(on_login_failed);
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
            session.login_failed.disconnect(on_login_failed);
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
    
    private void on_unsolicited_flags(MailboxAttributes flags) {
        flags_altered(flags);
    }
    
    private void on_session_mailbox_changed(string? old_mailbox, string? new_mailbox, bool readonly) {
        session = null;
        closed();
    }
    
    private void on_session_logged_out() {
        session = null;
        disconnected(Geary.Folder.CloseReason.REMOTE_CLOSE);
    }
    
    private void on_session_disconnected(ClientSession.DisconnectReason reason) {
        if (session == null)
            return;
        
        session = null;
        
        switch (reason) {
            case ClientSession.DisconnectReason.LOCAL_CLOSE:
            case ClientSession.DisconnectReason.REMOTE_CLOSE:
                disconnected(Geary.Folder.CloseReason.REMOTE_CLOSE);
            break;
            
            case ClientSession.DisconnectReason.LOCAL_ERROR:
            case ClientSession.DisconnectReason.REMOTE_ERROR:
                disconnected(Geary.Folder.CloseReason.REMOTE_ERROR);
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    private void on_login_failed() {
        login_failed();
    }
}

