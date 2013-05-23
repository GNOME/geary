/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.Imap.Folder : BaseObject {
    public const bool CASE_SENSITIVE = true;
    
    private const Geary.Email.Field BASIC_FETCH_FIELDS = Email.Field.ENVELOPE | Email.Field.DATE
        | Email.Field.ORIGINATORS | Email.Field.RECEIVERS | Email.Field.REFERENCES
        | Email.Field.SUBJECT | Email.Field.HEADER;
    
    private class ImapOperation : Nonblocking.BatchOperation {
        // IN
        public ClientSession session;
        public Command cmd;
        
        // OUT
        public CompletionStatusResponse? response = null;
        
        public ImapOperation(ClientSession session, Command cmd) {
            this.session = session;
            this.cmd = cmd;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            response = yield session.send_command_async(cmd, cancellable);
            
            return response;
        }
    }
    
    public bool is_open { get; private set; default = false; }
    public FolderPath path { get; private set; }
    public Imap.FolderProperties properties { get; private set; }
    public MailboxInformation info { get; private set; }
    
    private ClientSessionManager session_mgr;
    private ClientSession? session = null;
    
    public signal void exists(int count);
    
    public signal void expunge(MessageNumber num);
    
    public signal void fetch(FetchedData fetched);
    
    public signal void recent(int count);
    
    /**
     * Note that close_async() still needs to be called after this signal is fired.
     */
    public signal void disconnected(ClientSession.DisconnectReason reason);
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, StatusData? status,
        MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        properties = new Imap.FolderProperties.status(status, info.attrs);
    }
    
    internal Folder.unselectable(ClientSessionManager session_mgr, Geary.FolderPath path,
        MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        properties = new Imap.FolderProperties(0, 0, 0, null, null, info.attrs);
    }
    
    public async void open_async(Cancellable? cancellable) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        session = yield session_mgr.claim_authorized_session_async(cancellable);
        
        // connect to interesting signals *before* SELECTing
        session.exists.connect(on_exists);
        session.expunge.connect(on_expunge);
        session.fetch.connect(on_fetch);
        session.recent.connect(on_recent);
        session.coded_response_received.connect(on_coded_status_response);
        session.disconnected.connect(on_disconnected);
        
        CompletionStatusResponse response = yield session.select_async(path.get_fullpath(info.delim),
            cancellable);
        if (response.status != Status.OK) {
            yield release_session_async(cancellable);
            
            throw new ImapError.SERVER_ERROR("Unable to SELECT %s: %s", path.to_string(), response.to_string());
        }
        
        is_open = true;
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (!is_open)
            return;
        
        session.exists.disconnect(on_exists);
        session.expunge.disconnect(on_expunge);
        session.fetch.disconnect(on_fetch);
        session.recent.disconnect(on_recent);
        session.coded_response_received.disconnect(on_coded_status_response);
        session.disconnected.disconnect(on_disconnected);
        
        yield release_session_async(cancellable);
        
        is_open = false;
    }
    
    private async void release_session_async(Cancellable? cancellable) {
        if (session == null)
            return;
        
        try {
            yield session_mgr.release_session_async(session, cancellable);
        } catch (Error err) {
            debug("Unable to release session %s: %s", session.to_string(), err.message);
        } finally {
            session = null;
        }
    }
    
    private void on_exists(int count) {
        properties.set_select_examine_message_count(count);
        
        exists(count);
    }
    
    private void on_expunge(MessageNumber num) {
        expunge(num);
    }
    
    private void on_fetch(FetchedData fetched) {
        fetch(fetched);
    }
    
    private void on_recent(int count) {
        properties.recent = count;
        
        recent(count);
    }
    
    private void on_coded_status_response(CodedStatusResponse coded_response) {
        try {
            switch (coded_response.response_code_type) {
                case ResponseCodeType.UIDNEXT:
                    properties.uid_next = coded_response.get_uid_next();
                break;
                
                case ResponseCodeType.UIDVALIDITY:
                    properties.uid_validity = coded_response.get_uid_validity();
                break;
                
                case ResponseCodeType.UNSEEN:
                    properties.unseen = coded_response.get_unseen();
                break;
            }
        } catch (ImapError ierr) {
            debug("Unable to parse CodedStatusResponse %s: %s", coded_response.to_string(),
                ierr.message);
        }
    }
    
    private void on_disconnected(ClientSession.DisconnectReason reason) {
        disconnected(reason);
    }
    
    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Imap.Folder %s not open", to_string());
    }
    
    private async void send_command(Command cmd, Cancellable? cancellable) throws Error {
        check_open();
        
        CompletionStatusResponse response = yield session.send_command_async(cmd, cancellable);
        throw_on_failed_status(response, cmd);
    }
    
    private void throw_on_failed_status(CompletionStatusResponse response, Command cmd) throws Error {
        switch (response.status) {
            case Status.OK:
                return;
            
            case Status.NO:
                throw new ImapError.SERVER_ERROR("Request %s failed on %s: %s", cmd.to_string(),
                    to_string(), response.to_string());
            
            case Status.BAD:
                throw new ImapError.INVALID("Bad request %s on %s: %s", cmd.to_string(),
                    to_string(), response.to_string());
            
            default:
                throw new ImapError.NOT_SUPPORTED("Unknown response status to %s on %s: %s",
                    cmd.to_string(), to_string(), response.to_string());
        }
    }
    
    public async void list_email_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        check_open();
        
        // getting all the fields can require multiple FETCH commands (some servers don't handle
        // well putting every required data item into single command), so use a Nonblocking.Batch
        // to pipeline the requests
        Nonblocking.Batch batch = new Nonblocking.Batch();
        
        // TODO: For all commands, if not UID, then request UID?
        
        // convert bulk of the "basic" fields into a single FETCH command
        if (fields.requires_any(BASIC_FETCH_FIELDS)) {
            Gee.List<FetchDataType> data_types = new Gee.ArrayList<FetchDataType>();
            Gee.List<FetchBodyDataType> body_data_types = new Gee.ArrayList<FetchBodyDataType>();
            fields_to_fetch_data_types(msg_set.is_uid, fields, data_types, body_data_types);
            
            if (data_types.size > 0 || body_data_types.size > 0)
                batch.add(new ImapOperation(session, new FetchCommand(msg_set, data_types, body_data_types)));
        }
        
        // RFC822 BODY is a separate command
        if (fields.require(Email.Field.BODY)) {
            FetchBodyDataType body = new FetchBodyDataType.peek(FetchBodyDataType.SectionPart.TEXT,
                null, -1, -1, null);
            batch.add(new ImapOperation(session, new FetchCommand.body_data_type(msg_set, body)));
        }
        
        // PREVIEW requires two separate commands
        if (fields.require(Email.Field.PREVIEW)) {
            // Get the preview text (the initial MAX_PREVIEW_BYTES of the first MIME section
            FetchBodyDataType preview = new FetchBodyDataType.peek(FetchBodyDataType.SectionPart.NONE,
                { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES, null);
            batch.add(new ImapOperation(session, new FetchCommand.body_data_type(msg_set, preview)));
            
            // Also get the character set to properly decode it
            FetchBodyDataType preview_charset = new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.MIME, { 1 }, -1, -1, null);
            batch.add(new ImapOperation(session, new FetchCommand.body_data_type(msg_set,
                preview_charset)));
        }
        
        // PROPERTIES and FLAGS are a separate command
        if (fields.requires_any(Email.Field.PROPERTIES | Email.Field.FLAGS)) {
            Gee.List<FetchDataType> data_types = new Gee.ArrayList<FetchDataType>();
            
            if (fields.require(Geary.Email.Field.PROPERTIES)) {
                data_types.add(FetchDataType.INTERNALDATE);
                data_types.add(FetchDataType.RFC822_SIZE);
            }
            
            if (fields.require(Geary.Email.Field.FLAGS))
                data_types.add(FetchDataType.FLAGS);
            
            batch.add(new ImapOperation(session, new FetchCommand(msg_set, data_types, null)));
        }
        
        // execute all at once to pipeline
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        // throw error if any command returned a server error
        foreach (int id in batch.get_ids()) {
            ImapOperation op = (ImapOperation) batch.get_operation(id);
            throw_on_failed_status(op.response, op.cmd);
        }
    }
    
    public async void remove_email_async(MessageSet msg_set, Cancellable? cancellable) throws Error {
        check_open();
        /*
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);
        
        // true, false?
        // TODO: Pipeline
        yield send_command(new StoreCommand(msg_set, flags, true, false), cancellable);
        
        ExpungeCommand expunge_cmd = msg_set.is_uid ? new ExpungeCommand.uid(msg_set)
            : new ExpungeCommand();
        yield send_command(expunge_cmd, cancellable);
        */
    }
    
    public async void mark_email_async(MessageSet msg_set, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable) throws Error {
        /*
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add, 
            out msg_flags_remove);
        
        yield mailbox.mark_email_async(msg_set, msg_flags_add, msg_flags_remove, cancellable);
        */
    }
    
    public async void copy_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable) throws Error {
        check_open();
        
        /*
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        yield mailbox.copy_email_async(msg_set, destination, cancellable);
        */
    }
    
    public async void move_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable) throws Error {
        check_open();
        
        /*
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        yield copy_email_async(msg_set, destination, cancellable);
        yield remove_email_async(msg_set, cancellable);
        */
    }
    
    // NOTE: If fields are added or removed from this method, BASIC_FETCH_FIELDS *must* be updated
    // as well
    private void fields_to_fetch_data_types(bool is_uid_request, Geary.Email.Field fields,
        Gee.List<FetchDataType> data_types_list, Gee.List<FetchBodyDataType> body_data_types_list) {
        // always fetch UID because it's needed for EmailIdentifier UNLESS UID addressing is being
        // used, in which case UID will return with the response
        if (!is_uid_request)
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
                
                case Geary.Email.Field.NONE:
                case Geary.Email.Field.BODY:
                case Geary.Email.Field.PROPERTIES:
                case Geary.Email.Field.FLAGS:
                case Geary.Email.Field.PREVIEW:
                    // not set or fetched separately
                break;
                
                default:
                    assert_not_reached();
            }
        }
        
        // convert field names into FetchBodyDataType object
        if (field_names.length > 0) {
            body_data_types_list.add(new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.HEADER_FIELDS, null, -1, -1, field_names));
        }
    }
    
    public string to_string() {
        return path.to_string();
    }
}

