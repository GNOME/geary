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
    
    public bool is_open { get; private set; default = false; }
    public FolderPath path { get; private set; }
    public Imap.FolderProperties properties { get; private set; }
    public MailboxInformation info { get; private set; }
    
    private ClientSessionManager session_mgr;
    private ClientSession? session = null;
    private Nonblocking.Mutex fetch_mutex = new Nonblocking.Mutex();
    private Gee.HashMap<MessageNumber, FetchedData> fetch_accumulator = new Gee.HashMap<
        MessageNumber, FetchedData>();
    
    public signal void exists(int total);
    
    public signal void expunge(int position);
    
    public signal void fetched(FetchedData fetched_data);
    
    public signal void recent(int total);
    
    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void appended(int total);
    
    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void removed(int pos, int total);
    
    /**
     * Note that close_async() still needs to be called after this signal is fired.
     */
    public signal void disconnected(ClientSession.DisconnectReason reason);
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, StatusData status,
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
        
        fetch_accumulator.clear();
        
        session = yield session_mgr.claim_authorized_session_async(cancellable);
        
        // connect to interesting signals *before* selecting
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
        
        yield release_session_async(cancellable);
        
        fetch_accumulator.clear();
        
        is_open = false;
    }
    
    private async void release_session_async(Cancellable? cancellable) {
        if (session == null)
            return;
        
        session.exists.disconnect(on_exists);
        session.expunge.disconnect(on_expunge);
        session.fetch.disconnect(on_fetch);
        session.recent.disconnect(on_recent);
        session.coded_response_received.disconnect(on_coded_status_response);
        session.disconnected.disconnect(on_disconnected);
        
        try {
            yield session_mgr.release_session_async(session, cancellable);
        } catch (Error err) {
            debug("Unable to release session %s: %s", session.to_string(), err.message);
        } finally {
            session = null;
        }
    }
    
    private void on_exists(int total) {
        debug("%s EXISTS %d", to_string(), total);
        
        int old_total = properties.select_examine_messages;
        properties.set_select_examine_message_count(total);
        
        exists(total);
        if (old_total < total)
            appended(total);
    }
    
    private void on_expunge(MessageNumber pos) {
        debug("%s EXPUNGE %s", to_string(), pos.to_string());
        
        properties.set_select_examine_message_count(properties.select_examine_messages - 1);
        
        expunge(pos.value);
        removed(pos.value, properties.select_examine_messages);
    }
    
    private void on_fetch(FetchedData fetched_data) {
        // add if not found, merge if already received data for this email
        FetchedData? already_present = fetch_accumulator.get(fetched_data.msg_num);
        fetch_accumulator.set(fetched_data.msg_num,
            (already_present != null) ? fetched_data.combine(already_present) : fetched_data);
        
        fetched(fetched_data);
    }
    
    private void on_recent(int total) {
        debug("%s RECENT %d", to_string(), total);
        
        properties.recent = total;
        
        recent(total);
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
                
                default:
                    debug("%s: Ignoring coded status response %s", to_string(),
                        coded_response.to_string());
                break;
            }
        } catch (ImapError ierr) {
            debug("Unable to parse CodedStatusResponse %s: %s", coded_response.to_string(),
                ierr.message);
        }
    }
    
    private void on_disconnected(ClientSession.DisconnectReason reason) {
        debug("%s DISCONNECTED %s", to_string(), reason.to_string());
        
        disconnected(reason);
    }
    
    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Imap.Folder %s not open", to_string());
    }
    
    // For FETCH or STORE commands, both of which return FETCH results.
    private async Gee.HashMap<MessageNumber, FetchedData> store_fetch_commands_async(MessageSet msg_set,
        Gee.Collection<Command> store_fetch_cmds, bool lock_mutex, Cancellable? cancellable)
        throws Error {
        // watch for deadlock
        assert(fetch_mutex.is_locked() != lock_mutex);
        
        int token = Nonblocking.Mutex.INVALID_TOKEN;
        if (lock_mutex) 
            token = yield fetch_mutex.claim_async(cancellable);
        
        // execute commands with mutex locked
        Gee.Map<Command, CompletionStatusResponse>? responses = null;
        Error? err = null;
        try {
            responses = yield session.send_multiple_commands_async(store_fetch_cmds, cancellable);
        } catch (Error store_fetch_err) {
            err = store_fetch_err;
        }
        
        // swap out results and clear accumulator
        Gee.HashMap<MessageNumber, FetchedData> results = fetch_accumulator;
        fetch_accumulator = new Gee.HashMap<MessageNumber, FetchedData>();
        
        // unlock after clearing accumulator
        if (token != Nonblocking.Mutex.INVALID_TOKEN)
            fetch_mutex.release(ref token);
        
        if (err != null)
            throw err;
        
        assert(responses != null);
        
        // process response stati after unlocking and clearing accumulator
        foreach (Command cmd in responses.keys)
            throw_on_failed_status(responses.get(cmd), cmd);
        
        return results;
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
    
    public async Gee.List<Geary.Email>? list_email_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        check_open();
        
        // getting all the fields can require multiple FETCH commands (some servers don't handle
        // well putting every required data item into single command), so aggregate FetchCommands
        Gee.Collection<FetchCommand> cmds = new Gee.ArrayList<FetchCommand>();
        
        // convert bulk of the "basic" fields into a single FETCH command
        FetchBodyDataIdentifier? partial_header_identifier = null;
        if (fields.requires_any(BASIC_FETCH_FIELDS)) {
            Gee.List<FetchDataType> data_types = new Gee.ArrayList<FetchDataType>();
            FetchBodyDataType? header_body_type;
            fields_to_fetch_data_types(fields, data_types, out header_body_type);
            
            Gee.List<FetchBodyDataType>? body_data_types = null;
            if (header_body_type != null) {
                body_data_types = new Gee.ArrayList<FetchBodyDataType>();
                body_data_types.add(header_body_type);
                
                // save identifier for later
                partial_header_identifier = header_body_type.get_identifier();
            }
            
            if (data_types.size > 0 || body_data_types != null)
                cmds.add(new FetchCommand(msg_set, data_types, body_data_types));
        }
        
        // RFC822 BODY is a separate command
        FetchBodyDataIdentifier? body_identifier = null;
        if (fields.require(Email.Field.BODY)) {
            FetchBodyDataType body = new FetchBodyDataType.peek(FetchBodyDataType.SectionPart.TEXT,
                null, -1, -1, null);
            
            // save identifier for later retrieval from responses
            body_identifier = body.get_identifier();
            
            cmds.add(new FetchCommand.body_data_type(msg_set, body));
        }
        
        // PREVIEW requires two separate commands
        FetchBodyDataIdentifier? preview_identifier = null;
        FetchBodyDataIdentifier? preview_charset_identifier = null;
        if (fields.require(Email.Field.PREVIEW)) {
            // Get the preview text (the initial MAX_PREVIEW_BYTES of the first MIME section
            FetchBodyDataType preview = new FetchBodyDataType.peek(FetchBodyDataType.SectionPart.NONE,
                { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES, null);
            preview_identifier = preview.get_identifier();
            cmds.add(new FetchCommand.body_data_type(msg_set, preview));
            
            // Also get the character set to properly decode it
            FetchBodyDataType preview_charset = new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.MIME, { 1 }, -1, -1, null);
            preview_charset_identifier = preview_charset.get_identifier();
            cmds.add(new FetchCommand.body_data_type(msg_set, preview_charset));
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
            
            cmds.add(new FetchCommand(msg_set, data_types, null));
        }
        
        Gee.HashMap<MessageNumber, UID>? pos_uid_map = null;
        Gee.HashMap<MessageNumber, FetchedData>? fetched = null;
        Error? fetch_err = null;
        
        // Commands prepped, do the actual fetching with the mutex in place
        int token = yield fetch_mutex.claim_async(cancellable);
        try {
            // If positional addressing is used, get all UIDs first in a non-pipelined request so they
            // can be matched against the remaining calls ... this has to be done because it's possible
            // for responses to come back in any order, broken up in any way, with only positional
            // addressing, and there's no way to build Email's without the UID.
            if (!msg_set.is_uid) {
                pos_uid_map = new Gee.HashMap<MessageNumber, UID>();
                
                FetchCommand cmd = new FetchCommand.data_type(msg_set, FetchDataType.UID);
                Gee.HashMap<MessageData, FetchedData> uids = yield store_fetch_commands_async(
                    msg_set, new Collection.SingleItem<FetchCommand>(cmd), false, cancellable);
                
                // convert fetched UIDs into easy-lookup map
                foreach (FetchedData fetched_data in uids.values) {
                    if (fetched_data.data_map.has_key(FetchDataType.UID))
                        pos_uid_map.set(fetched_data.msg_num, (UID) fetched_data.data_map.get(FetchDataType.UID));
                    else
                        debug("No UID in FetchedData for %s on %s", fetched_data.msg_num.to_string(), to_string());
                }
            }
            
            // now execute the remaining FETCH commands
            fetched = yield store_fetch_commands_async(msg_set, cmds, false, cancellable);
        } catch (Error err) {
            fetch_err = err;
        }
        fetch_mutex.release(ref token);
        
        if (fetch_err != null)
            throw fetch_err;
        
        if (fetched == null || fetched.size == 0)
            return null;
        
        // Convert fetched data into Geary.Email objects
        Gee.List<Geary.Email> email_list = new Gee.ArrayList<Geary.Email>();
        foreach (MessageNumber msg_num in fetched.keys) {
            FetchedData fetched_data = fetched.get(msg_num);
            
            // the UID should either have been looked up (if using positional addressing) or should
            // have come back with the response (if using UID addressing)
            UID? uid = null;
            if (pos_uid_map != null)
                uid = pos_uid_map.get(msg_num);
            else
                uid = (UID) fetched_data.data_map.get(FetchDataType.UID);
            assert(uid != null);
            
            try {
                email_list.add(fetched_data_to_email(uid, fetched_data, partial_header_identifier,
                    body_identifier, preview_identifier, preview_charset_identifier));
            } catch (Error err) {
                debug("Unable to fetch email for %s from %s: %s", uid.to_string(), to_string(),
                    err.message);
            }
        }
        
        return (email_list.size > 0) ? email_list : null;
    }
    
    public async void remove_email_async(MessageSet msg_set, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);
        
        Gee.List<Command> cmds = new Gee.ArrayList<Command>();
        
        StoreCommand store_cmd = new StoreCommand(msg_set, flags, true, false);
        cmds.add(store_cmd);
        
        if (session.capabilities.has_capability(Capabilities.UIDPLUS))
            cmds.add(new ExpungeCommand.uid(msg_set));
        else
            cmds.add(new ExpungeCommand());
        
        yield store_fetch_commands_async(msg_set, cmds, true, cancellable);
    }
    
    public async void mark_email_async(MessageSet msg_set, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add, 
            out msg_flags_remove);
        
        if (msg_flags_add.size == 0 && msg_flags_remove.size == 0)
            return;
        
        Gee.Collection<Command> cmds = new Gee.ArrayList<Command>();
        
        if (msg_flags_add.size > 0)
            cmds.add(new StoreCommand(msg_set, msg_flags_add, true, false));
        
        if (msg_flags_remove.size > 0)
            cmds.add(new StoreCommand(msg_set, msg_flags_remove, false, false));
        
        yield store_fetch_commands_async(msg_set, cmds, true, cancellable);
    }
    
    public async void copy_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable) throws Error {
        check_open();
        
        CopyCommand cmd = new CopyCommand(msg_set, new Imap.MailboxParameter(destination.get_fullpath()));
        CompletionStatusResponse response = yield session.send_command_async(cmd, cancellable);
        
        throw_on_failed_status(response, cmd);
    }
    
    public async void move_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable) throws Error {
        check_open();
        
        // TODO: Support MOVE extension
        
        yield copy_email_async(msg_set, destination, cancellable);
        yield remove_email_async(msg_set, cancellable);
    }
    
    // NOTE: If fields are added or removed from this method, BASIC_FETCH_FIELDS *must* be updated
    // as well
    private void fields_to_fetch_data_types(Geary.Email.Field fields,
        Gee.List<FetchDataType> data_types_list, out FetchBodyDataType? header_body_type) {
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
                    // TODO: If the entire header is being pulled, then no need to pull down partial
                    // headers; simply get them all and decode what is needed directly
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
        
        // convert field names into single FetchBodyDataType object
        if (field_names.length > 0) {
            header_body_type = new FetchBodyDataType.peek(
                FetchBodyDataType.SectionPart.HEADER_FIELDS, null, -1, -1, field_names);
        } else {
            header_body_type = null;
        }
    }
    
    private Geary.Email fetched_data_to_email(UID uid, FetchedData fetched_data,
        FetchBodyDataIdentifier? partial_header_identifier, FetchBodyDataIdentifier? body_identifier,
        FetchBodyDataIdentifier? preview_identifier, FetchBodyDataIdentifier? preview_charset_identifier)
        throws Error {
        Geary.Email email = new Geary.Email(fetched_data.msg_num.value,
            new Imap.EmailIdentifier(uid, path));
        
        // accumulate these to submit Imap.EmailProperties all at once
        InternalDate? internaldate = null;
        RFC822.Size? rfc822_size = null;
        
        // accumulate these to submit References all at once
        RFC822.MessageID? message_id = null;
        RFC822.MessageID? in_reply_to = null;
        RFC822.MessageIDList? references = null;
        
        // loop through all available FetchDataTypes and gather converted data
        foreach (FetchDataType data_type in fetched_data.data_map.keys) {
            MessageData? data = fetched_data.data_map.get(data_type);
            if (data == null)
                continue;
            
            switch (data_type) {
                case FetchDataType.ENVELOPE:
                    Envelope envelope = (Envelope) data;
                    
                    email.set_send_date(envelope.sent);
                    email.set_message_subject(envelope.subject);
                    email.set_originators(envelope.from, envelope.sender, envelope.reply_to);
                    email.set_receivers(envelope.to, envelope.cc, envelope.bcc);
                    
                    // store these to add to References all at once
                    message_id = envelope.message_id;
                    in_reply_to = envelope.in_reply_to;
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
                    email.set_flags(new Imap.EmailFlags((MessageFlags) data));
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
        if (internaldate != null && rfc822_size != null)
            email.set_email_properties(new Geary.Imap.EmailProperties(internaldate, rfc822_size));
        
        // if the header was requested, convert its fields now
        if (partial_header_identifier != null) {
            assert(fetched_data.body_data_map.has_key(partial_header_identifier));
            
            RFC822.Header headers = new RFC822.Header(
                fetched_data.body_data_map.get(partial_header_identifier));
            
            // DATE
            if (!email.fields.is_all_set(Geary.Email.Field.DATE)) {
                string? value = headers.get_header("Date");
                if (!String.is_empty(value))
                    email.set_send_date(new RFC822.Date(value));
            }
            
            // ORIGINATORS
            if (!email.fields.is_all_set(Geary.Email.Field.ORIGINATORS)) {
                RFC822.MailboxAddresses? from = null;
                string? value = headers.get_header("From");
                if (!String.is_empty(value))
                    from = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                RFC822.MailboxAddresses? sender = null;
                value = headers.get_header("Sender");
                if (!String.is_empty(value))
                    sender = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                RFC822.MailboxAddresses? reply_to = null;
                value = headers.get_header("Reply-To");
                if (!String.is_empty(value))
                    reply_to = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                if (from != null || sender != null || reply_to != null)
                    email.set_originators(from, sender, reply_to);
            }
            
            // RECEIVERS
            if (!email.fields.is_all_set(Geary.Email.Field.RECEIVERS)) {
                RFC822.MailboxAddresses? to = null;
                string? value = headers.get_header("To");
                if (!String.is_empty(value))
                    to = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                RFC822.MailboxAddresses? cc = null;
                value = headers.get_header("Cc");
                if (!String.is_empty(value))
                    cc = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                RFC822.MailboxAddresses? bcc = null;
                value = headers.get_header("Bcc");
                if (!String.is_empty(value))
                    bcc = new RFC822.MailboxAddresses.from_rfc822_string(value);
                
                if (to != null || cc != null || bcc != null)
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
            if (!email.fields.is_all_set(Geary.Email.Field.SUBJECT)) {
                string? value = headers.get_header("Subject");
                if (!String.is_empty(value))
                    email.set_message_subject(new RFC822.Subject.decode(value));
            }
        }
        
        if (message_id != null || in_reply_to != null || references != null)
            email.set_full_references(message_id, in_reply_to, references);
        
        // if body was requested, get it now
        if (body_identifier != null) {
            assert(fetched_data.body_data_map.has_key(body_identifier));
            
            email.set_message_body(new Geary.RFC822.Text(
                fetched_data.body_data_map.get(body_identifier)));
        }
        
        // if preview was requested, get it now ... both identifiers must be supplied if one is
        if (preview_identifier != null || preview_charset_identifier != null) {
            assert(preview_identifier != null && preview_charset_identifier != null);
            assert(fetched_data.body_data_map.has_key(preview_identifier));
            assert(fetched_data.body_data_map.has_key(preview_charset_identifier));
            
            email.set_message_preview(new RFC822.PreviewText.with_header(
                fetched_data.body_data_map.get(preview_identifier),
                fetched_data.body_data_map.get(preview_charset_identifier)));
        }
        
        return email;
    }
    
    public string to_string() {
        return path.to_string();
    }
}

