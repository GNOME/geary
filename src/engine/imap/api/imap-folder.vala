/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// this is used internally to indicate a recoverable failure
private errordomain Geary.Imap.FolderError {
    RETRY
}

private class Geary.Imap.Folder : BaseObject {
    private const Geary.Email.Field BASIC_FETCH_FIELDS = Email.Field.ENVELOPE | Email.Field.DATE
        | Email.Field.ORIGINATORS | Email.Field.RECEIVERS | Email.Field.REFERENCES
        | Email.Field.SUBJECT | Email.Field.HEADER;
    
    public bool is_open { get; private set; default = false; }
    public FolderPath path { get; private set; }
    public Imap.FolderProperties properties { get; private set; }
    public MailboxInformation info { get; private set; }
    public MessageFlags? permanent_flags { get; private set; default = null; }
    public Trillian readonly { get; private set; default = Trillian.UNKNOWN; }
    public Trillian accepts_user_flags { get; private set; default = Trillian.UNKNOWN; }
    /**
     * Set to true when it's detected that the server doesn't allow a space between "header.fields"
     * and the list of email headers to be requested via FETCH; see
     * https://bugzilla.gnome.org/show_bug.cgi?id=714902
     */
    public bool imap_header_fields_hack { get; private set; default = false; }
    
    private ClientSessionManager session_mgr;
    private ClientSession? session = null;
    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.HashMap<SequenceNumber, FetchedData> fetch_accumulator = new Gee.HashMap<
        SequenceNumber, FetchedData>();
    private Gee.Set<Imap.UID> search_accumulator = new Gee.HashSet<Imap.UID>();
    
    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.3.1]]
     */
    public signal void exists(int total);
    
    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.4.1]]
     */
    public signal void expunge(SequenceNumber position);
    
    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.3.2]]
     */
    public signal void recent(int total);
    
    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void appended(int total);
    
    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void removed(SequenceNumber pos, int total);
    
    /**
     * Note that close_async() still needs to be called after this signal is fired.
     */
    public signal void disconnected(ClientSession.DisconnectReason reason);
    
    internal Folder(FolderPath path, ClientSessionManager session_mgr, StatusData status, MailboxInformation info) {
        // Used to assert() here, but that meant that any issue with internationalization/encoding
        // made Geary unusable for a subset of servers accessed/configured in a non-English language...
        // this is not the end of the world, but it does suggest an I18N issue, potentially with
        // how XLIST returns folder names on different servers.
        if (!status.mailbox.equal_to(info.mailbox)) {
            message("%s: IMAP folder created with differing mailbox names (STATUS=%s LIST=%s)",
                path.to_string(), status.to_string(), info.to_string());
        }
        
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        properties = new Imap.FolderProperties.status(status, info.attrs);
    }
    
    internal Folder.unselectable(FolderPath path, ClientSessionManager session_mgr, MailboxInformation info) {
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
        session.search.connect(on_search);
        session.status_response_received.connect(on_status_response);
        session.disconnected.connect(on_disconnected);
        
        properties.set_from_session_capabilities(session.capabilities);
        
        StatusResponse? response = null;
        Error? select_err = null;
        try {
            response = yield session.select_async(
                new MailboxSpecifier.from_folder_path(path, info.delim), cancellable);
        } catch (Error err) {
            select_err = err;
        }
        
        // if select_err is null, then response can not be null
        if (select_err != null || response.status != Status.OK) {
            // don't use user-supplied cancellable; it may be cancelled, and even if not, do not want
            // to cancel this operation
            yield release_session_async(null);
            
            if (select_err != null)
                throw select_err;
            
            switch (response.status) {
                case Status.BAD:
                case Status.NO:
                    throw new ImapError.NOT_SUPPORTED("Server disallowed SELECT %s: %s", path.to_string(),
                        response.to_string());
                
                default:
                    throw new ImapError.SERVER_ERROR("Unable to SELECT %s: %s", path.to_string(),
                        response.to_string());
            }
        }
        
        // if at end of SELECT command accepts_user_flags is still UNKKNOWN, treat as TRUE because,
        // according to IMAP spec, if PERMANENTFLAGS are not returned, then assume OK
        if (accepts_user_flags == Trillian.UNKNOWN)
            accepts_user_flags = Trillian.TRUE;
        
        is_open = true;
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (!is_open)
            return;
        
        yield release_session_async(cancellable);
        
        fetch_accumulator.clear();
        
        readonly = Trillian.UNKNOWN;
        accepts_user_flags = Trillian.UNKNOWN;
        
        is_open = false;
    }
    
    private async void release_session_async(Cancellable? cancellable) {
        if (session == null)
            return;
        
        // set this.session to null before yielding to ClientSessionManager
        ClientSession release_session = session;
        session = null;
        
        release_session.exists.disconnect(on_exists);
        release_session.expunge.disconnect(on_expunge);
        release_session.fetch.disconnect(on_fetch);
        release_session.recent.disconnect(on_recent);
        release_session.search.disconnect(on_search);
        release_session.status_response_received.disconnect(on_status_response);
        release_session.disconnected.disconnect(on_disconnected);
        
        try {
            yield session_mgr.release_session_async(release_session, cancellable);
        } catch (Error err) {
            debug("Unable to release session %s: %s", release_session.to_string(), err.message);
        }
    }
    
    private void on_exists(int total) {
        debug("%s EXISTS %d", to_string(), total);
        
        int old_total = properties.select_examine_messages;
        properties.set_select_examine_message_count(total);
        
        // don't fire signals until opened
        if (!is_open)
            return;
        
        exists(total);
        if (old_total < total)
            appended(total);
    }
    
    private void on_expunge(SequenceNumber pos) {
        debug("%s EXPUNGE %s", to_string(), pos.to_string());
        
        properties.set_select_examine_message_count(properties.select_examine_messages - 1);
        
        // don't fire signals until opened
        if (!is_open)
            return;
        
        expunge(pos);
        removed(pos, properties.select_examine_messages);
    }
    
    private void on_fetch(FetchedData fetched_data) {
        // add if not found, merge if already received data for this email
        FetchedData? already_present = fetch_accumulator.get(fetched_data.seq_num);
        fetch_accumulator.set(fetched_data.seq_num,
            (already_present != null) ? fetched_data.combine(already_present) : fetched_data);
    }
    
    private void on_recent(int total) {
        debug("%s RECENT %d", to_string(), total);
        
        properties.recent = total;
        
        // don't fire signal until opened
        if (is_open)
            recent(total);
    }
    
    private void on_search(int64[] seq_or_uid) {
        // All SEARCH from this class are UID SEARCH, so can reliably convert and add to
        // accumulator
        foreach (int64 uid in seq_or_uid) {
            try {
                search_accumulator.add(new UID.checked(uid));
            } catch (ImapError imaperr) {
                debug("%s Unable to process SEARCH UID result: %s", to_string(), imaperr.message);
            }
        }
    }
    
    private void on_status_response(StatusResponse status_response) {
        // only interested in ResponseCodes here
        ResponseCode? response_code = status_response.response_code;
        if (response_code == null)
            return;
        
        try {
            // Have to take a copy of the string property before evaluation due to this bug:
            // https://bugzilla.gnome.org/show_bug.cgi?id=703818
            string value = response_code.get_response_code_type().value;
            switch (value) {
                case ResponseCodeType.READONLY:
                    readonly = Trillian.TRUE;
                break;
                
                case ResponseCodeType.READWRITE:
                    readonly = Trillian.FALSE;
                break;
                
                case ResponseCodeType.UIDNEXT:
                    properties.uid_next = response_code.get_uid_next();
                break;
                
                case ResponseCodeType.UIDVALIDITY:
                    properties.uid_validity = response_code.get_uid_validity();
                break;
                
                case ResponseCodeType.UNSEEN:
                    // do NOT update properties.unseen, as the UNSEEN response code (here) means
                    // the sequence number of the first unseen message, not the total count of
                    // unseen messages
                break;
                
                case ResponseCodeType.PERMANENT_FLAGS:
                    permanent_flags = response_code.get_permanent_flags();
                    accepts_user_flags = Trillian.from_boolean(
                        permanent_flags.contains(MessageFlag.ALLOWS_NEW));
                break;
                
                default:
                    // ignored
                break;
            }
        } catch (ImapError ierr) {
            debug("Unable to parse ResponseCode %s: %s", response_code.to_string(),
                ierr.message);
        }
    }
    
    private void on_disconnected(ClientSession.DisconnectReason reason) {
        debug("%s DISCONNECTED %s", to_string(), reason.to_string());
        
        disconnected(reason);
    }
    
    private void check_open() throws Error {
        if (!is_open || session == null)
            throw new EngineError.OPEN_REQUIRED("Imap.Folder %s not open", to_string());
    }
    
    // All commands must executed inside the cmd_mutex; returns FETCH or STORE results
    //
    // FETCH commands can generate a FolderError.RETRY.  State will be updated to accomodate retry,
    // but all Commands must be regenerated to ensure new state is reflected in requests.
    private async Gee.Map<Command, StatusResponse>? exec_commands_async(Gee.Collection<Command> cmds,
        out Gee.HashMap<SequenceNumber, FetchedData>? fetched, out Gee.Set<Imap.UID>? search_results,
        Cancellable? cancellable) throws Error {
        int token = yield cmd_mutex.claim_async(cancellable);
        Gee.Map<Command, StatusResponse>? responses = null;
        // execute commands with mutex locked
        Error? err = null;
        try {
            // check open after acquiring mutex, so that if an error is thrown it's caught and
            // mutex can be closed
            check_open();
            
            responses = yield session.send_multiple_commands_async(cmds, cancellable);
        } catch (Error store_fetch_err) {
            err = store_fetch_err;
        }
        
        // swap out results and clear accumulators
        if (fetch_accumulator.size > 0) {
            fetched = fetch_accumulator;
            fetch_accumulator = new Gee.HashMap<SequenceNumber, FetchedData>();
        } else {
            fetched = null;
        }
        
        if (search_accumulator.size > 0) {
            search_results = search_accumulator;
            search_accumulator = new Gee.HashSet<Imap.UID>();
        } else {
            search_results = null;
        }
        
        // unlock after clearing accumulators
        cmd_mutex.release(ref token);
        
        if (err != null)
            throw err;
        
        // process response stati after unlocking and clearing accumulators
        assert(responses != null);
        foreach (Command cmd in responses.keys)
            throw_on_failed_status(responses.get(cmd), cmd);
        
        return responses;
    }
    
    // HACK: See https://bugzilla.gnome.org/show_bug.cgi?id=714902
    //
    // Detect when a server has returned a BAD response to FETCH BODY[HEADER.FIELDS (HEADER-LIST)]
    // due to space between HEADER.FIELDS and (HEADER-LIST)
    private bool retry_bad_header_fields_response(Command cmd, StatusResponse response) {
        if (response.status != Status.BAD)
            return false;
        
        FetchCommand? fetch = cmd as FetchCommand;
        if (fetch == null)
            return false;
        
        foreach (FetchBodyDataSpecifier body_specifier in fetch.for_body_data_specifiers) {
            switch (body_specifier.section_part) {
                case FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS:
                case FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS_NOT:
                    // use value stored in specifier, not this folder's setting, as it's possible
                    // the folder's setting was enabled after sending command but before response
                    // returned
                    if (body_specifier.request_header_fields_space)
                        return true;
                break;
            }
        }
        
        return false;
    }
    
    private void throw_on_failed_status(StatusResponse response, Command cmd) throws Error {
        assert(response.is_completion);
        
        switch (response.status) {
            case Status.OK:
                return;
            
            case Status.NO:
                throw new ImapError.SERVER_ERROR("Request %s failed on %s: %s", cmd.to_string(),
                    to_string(), response.to_string());
            
            case Status.BAD: {
                // if a FetchBodyDataSpecifier is used to request for a header field BAD is returned,
                // could be a specific formatting mistake some servers make of not allowing a space
                // between the "header.fields" and list of email header names, i.e.
                //
                // "body[header.fields (references)]"
                //
                // If so, then enable a hack to work around this and retry the FETCH
                if (retry_bad_header_fields_response(cmd, response)) {
                    imap_header_fields_hack = true;
                    
                    throw new FolderError.RETRY("BAD response to header.fields FETCH BODY, retry with hack");
                }
                
                throw new ImapError.INVALID("Bad request %s on %s: %s", cmd.to_string(),
                    to_string(), response.to_string());
            }
            
            default:
                throw new ImapError.NOT_SUPPORTED("Unknown response status to %s on %s: %s",
                    cmd.to_string(), to_string(), response.to_string());
        }
    }
    
    // Utility method for listing UIDs on the remote within the supplied range
    public async Gee.Set<Imap.UID>? list_uids_async(MessageSet msg_set, Cancellable? cancellable)
        throws Error {
        check_open();
        
        // Although FETCH could be used, SEARCH is more efficient in returning pure UID results,
        // which is all we're interested in here
        SearchCriteria criteria = new SearchCriteria(SearchCriterion.message_set(msg_set));
        SearchCommand cmd = new SearchCommand.uid(criteria);
        
        Gee.Set<Imap.UID>? search_results;
        yield exec_commands_async(Geary.iterate<Command>(cmd).to_array_list(), null, out search_results,
            cancellable);
        
        return (search_results != null && search_results.size > 0) ? search_results : null;
    }
    
    private Gee.Collection<FetchCommand> assemble_list_commands(Imap.MessageSet msg_set,
        Geary.Email.Field fields, out FetchBodyDataSpecifier? header_specifier,
        out FetchBodyDataSpecifier? body_specifier, out FetchBodyDataSpecifier? preview_specifier,
        out FetchBodyDataSpecifier? preview_charset_specifier) {
        // getting all the fields can require multiple FETCH commands (some servers don't handle
        // well putting every required data item into single command), so aggregate FetchCommands
        Gee.Collection<FetchCommand> cmds = new Gee.ArrayList<FetchCommand>();
        
        // if not a UID FETCH, request UIDs for all messages so their EmailIdentifier can be
        // created without going back to the database (assuming the messages have already been
        // pulled down, not a guarantee); if request is for NONE, that guarantees that the
        // EmailIdentifier will be set, and so fetch UIDs (which looks funny but works when
        // listing a range for contents: UID FETCH x:y UID)
        if (!msg_set.is_uid || fields == Geary.Email.Field.NONE)
            cmds.add(new FetchCommand.data_type(msg_set, FetchDataSpecifier.UID));
        
        // convert bulk of the "basic" fields into a one or two FETCH commands (some servers have
        // exhibited bugs or return NO when too many FETCH data types are combined on a single
        // command)
        if (fields.requires_any(BASIC_FETCH_FIELDS)) {
            Gee.List<FetchDataSpecifier> data_types = new Gee.ArrayList<FetchDataSpecifier>();
            fields_to_fetch_data_types(fields, data_types, out header_specifier);
            
            // Add all simple data types as one FETCH command
            if (data_types.size > 0)
                cmds.add(new FetchCommand(msg_set, data_types, null));
            
            // Add all body data types as separate FETCH command
            if (header_specifier != null)
                cmds.add(new FetchCommand.body_data_type(msg_set, header_specifier));
        } else {
            header_specifier = null;
        }
        
        // RFC822 BODY is a separate command
        if (fields.require(Email.Field.BODY)) {
            body_specifier = new FetchBodyDataSpecifier.peek(FetchBodyDataSpecifier.SectionPart.TEXT,
                null, -1, -1, null);
            
            cmds.add(new FetchCommand.body_data_type(msg_set, body_specifier));
        } else {
            body_specifier = null;
        }
        
        // PREVIEW requires two separate commands
        if (fields.require(Email.Field.PREVIEW)) {
            // Get the preview text (the initial MAX_PREVIEW_BYTES of the first MIME section
            preview_specifier = new FetchBodyDataSpecifier.peek(FetchBodyDataSpecifier.SectionPart.NONE,
                { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES, null);
            cmds.add(new FetchCommand.body_data_type(msg_set, preview_specifier));
            
            // Also get the character set to properly decode it
            preview_charset_specifier = new FetchBodyDataSpecifier.peek(
                FetchBodyDataSpecifier.SectionPart.MIME, { 1 }, -1, -1, null);
            cmds.add(new FetchCommand.body_data_type(msg_set, preview_charset_specifier));
        } else {
            preview_specifier = null;
            preview_charset_specifier = null;
        }
        
        // PROPERTIES and FLAGS are a separate command
        if (fields.requires_any(Email.Field.PROPERTIES | Email.Field.FLAGS)) {
            Gee.List<FetchDataSpecifier> data_types = new Gee.ArrayList<FetchDataSpecifier>();
            
            if (fields.require(Geary.Email.Field.PROPERTIES)) {
                data_types.add(FetchDataSpecifier.INTERNALDATE);
                data_types.add(FetchDataSpecifier.RFC822_SIZE);
            }
            
            if (fields.require(Geary.Email.Field.FLAGS))
                data_types.add(FetchDataSpecifier.FLAGS);
            
            cmds.add(new FetchCommand(msg_set, data_types, null));
        }
        
        return cmds;
    }
    
    // Returns a no-message-id ImapDB.EmailIdentifier with the UID stored in it.
    public async Gee.List<Geary.Email>? list_email_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.HashMap<SequenceNumber, FetchedData>? fetched = null;
        FetchBodyDataSpecifier? header_specifier = null;
        FetchBodyDataSpecifier? body_specifier = null;
        FetchBodyDataSpecifier? preview_specifier = null;
        FetchBodyDataSpecifier? preview_charset_specifier = null;
        for (;;) {
            Gee.Collection<FetchCommand> cmds = assemble_list_commands(msg_set, fields,
                out header_specifier, out body_specifier, out preview_specifier,
                out preview_charset_specifier);
            if (cmds.size == 0) {
                throw new ImapError.INVALID("No FETCH commands generate for list request %s %s",
                    msg_set.to_string(), fields.to_list_string());
            }
            
            // Commands prepped, do the fetch and accumulate all the responses
            try {
                yield exec_commands_async(cmds, out fetched, null, cancellable);
            } catch (Error err) {
                if (err is FolderError.RETRY) {
                    debug("Retryable server failure detected for %s: %s", to_string(), err.message);
                    
                    continue;
                }
                
                throw err;
            }
            
            break;
        }
        
        if (fetched == null || fetched.size == 0)
            return null;
        
        // Convert fetched data into Geary.Email objects
        // because this could be for a lot of email, do in a background thread
        Gee.List<Geary.Email> email_list = new Gee.ArrayList<Geary.Email>();
        yield Nonblocking.Concurrent.global.schedule_async(() => {
            foreach (SequenceNumber seq_num in fetched.keys) {
                FetchedData fetched_data = fetched.get(seq_num);
                
                // the UID should either have been fetched (if using positional addressing) or should
                // have come back with the response (if using UID addressing)
                UID? uid = fetched_data.data_map.get(FetchDataSpecifier.UID) as UID;
                if (uid == null) {
                    message("Unable to list message #%s on %s: No UID returned from server",
                        seq_num.to_string(), to_string());
                    
                    continue;
                }
                
                try {
                    Geary.Email email = fetched_data_to_email(to_string(), uid, fetched_data, fields,
                        header_specifier, body_specifier, preview_specifier, preview_charset_specifier);
                    if (!email.fields.fulfills(fields)) {
                        message("%s: %s missing=%s fetched=%s", to_string(), email.id.to_string(),
                            fields.clear(email.fields).to_list_string(), fetched_data.to_string());
                        
                        continue;
                    }
                    
                    email_list.add(email);
                } catch (Error err) {
                    debug("%s: Unable to convert email for %s %s: %s", to_string(), uid.to_string(),
                        fetched_data.to_string(), err.message);
                }
            }
        }, cancellable);
        
        return (email_list.size > 0) ? email_list : null;
    }
    
    public async Gee.Map<UID, SequenceNumber>? uid_to_position_async(MessageSet msg_set,
        Cancellable? cancellable) throws Error {
        check_open();
        
        // MessageSet better be UID addressing
        assert(msg_set.is_uid);
        
        Gee.List<Command> cmds = new Gee.ArrayList<Command>();
        cmds.add(new FetchCommand.data_type(msg_set, FetchDataSpecifier.UID));
        
        Gee.HashMap<SequenceNumber, FetchedData>? fetched;
        yield exec_commands_async(cmds, out fetched, null, cancellable);
        
        if (fetched == null || fetched.size == 0)
            return null;
        
        Gee.Map<UID, SequenceNumber> map = new Gee.HashMap<UID, SequenceNumber>();
        foreach (SequenceNumber seq_num in fetched.keys)
            map.set((UID) fetched.get(seq_num).data_map.get(FetchDataSpecifier.UID), seq_num);
        
        return map;
    }
    
    public async void remove_email_async(Gee.List<MessageSet> msg_sets, Cancellable? cancellable)
        throws Error {
        check_open();
        
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);
        
        Gee.List<Command> cmds = new Gee.ArrayList<Command>();
        
        // Build STORE command for all MessageSets, see if all are UIDs so we can use UID EXPUNGE
        bool all_uid = true;
        foreach (MessageSet msg_set in msg_sets) {
            if (!msg_set.is_uid)
                all_uid = false;
            
            cmds.add(new StoreCommand(msg_set, flags, StoreCommand.Option.ADD_FLAGS));
        }
        
        // TODO: Only use old-school EXPUNGE when closing folder (or rely on CLOSE to do that work
        // for us).  See:
        // http://redmine.yorba.org/issues/7532
        //
        // However, current client implementation doesn't properly close INBOX when application
        // shuts down, which means deleted messages return at application start.  See:
        // http://redmine.yorba.org/issues/6865
        if (all_uid && session.capabilities.supports_uidplus()) {
            foreach (MessageSet msg_set in msg_sets)
                cmds.add(new ExpungeCommand.uid(msg_set));
        } else {
            cmds.add(new ExpungeCommand());
        }
        
        yield exec_commands_async(cmds, null, null, cancellable);
    }
    
    public async void mark_email_async(Gee.List<MessageSet> msg_sets, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add, 
            out msg_flags_remove);
        
        if (msg_flags_add.size == 0 && msg_flags_remove.size == 0)
            return;
        
        Gee.Collection<Command> cmds = new Gee.ArrayList<Command>();
        foreach (MessageSet msg_set in msg_sets) {
            if (msg_flags_add.size > 0)
                cmds.add(new StoreCommand(msg_set, msg_flags_add, StoreCommand.Option.ADD_FLAGS));
            
            if (msg_flags_remove.size > 0)
                cmds.add(new StoreCommand(msg_set, msg_flags_remove, StoreCommand.Option.REMOVE_FLAGS));
        }
        
        yield exec_commands_async(cmds, null, null, cancellable);
    }
    
    // Returns a mapping of the source UID to the destination UID.  If the MessageSet is not for
    // UIDs, then null is returned.  If the server doesn't support COPYUID, null is returned.
    public async Gee.Map<UID, UID>? copy_email_async(MessageSet msg_set, FolderPath destination,
        Cancellable? cancellable) throws Error {
        check_open();
        
        CopyCommand cmd = new CopyCommand(msg_set,
            new MailboxSpecifier.from_folder_path(destination, null));
        
        Gee.Map<Command, StatusResponse>? responses = yield exec_commands_async(
            Geary.iterate<Command>(cmd).to_array_list(), null, null, cancellable);
        
        if (!responses.has_key(cmd))
            return null;
        
        StatusResponse response = responses.get(cmd);
        if (response.response_code != null && msg_set.is_uid) {
            Gee.List<UID>? src_uids = null;
            Gee.List<UID>? dst_uids = null;
            try {
                response.response_code.get_copyuid(null, out src_uids, out dst_uids);
            } catch (ImapError ierr) {
                debug("Unable to retrieve COPYUID UIDs: %s", ierr.message);
            }
            
            if (!Collection.is_empty(src_uids) && !Collection.is_empty(dst_uids)) {
                Gee.Map<UID, UID> copyuids = new Gee.HashMap<UID, UID>();
                int ctr = 0;
                for (;;) {
                    UID? src_uid = (ctr < src_uids.size) ? src_uids[ctr] : null;
                    UID? dst_uid = (ctr < dst_uids.size) ? dst_uids[ctr] : null;
                    
                    if (src_uid != null && dst_uid != null)
                        copyuids.set(src_uid, dst_uid);
                    else
                        break;
                    
                    ctr++;
                }
                
                if (copyuids.size > 0)
                    return copyuids;
            }
        }
        
        return null;
    }
    
    public async Gee.SortedSet<Imap.UID>? search_async(SearchCriteria criteria, Cancellable? cancellable)
        throws Error {
        check_open();
        
        // always perform a UID SEARCH
        Gee.Collection<Command> cmds = new Gee.ArrayList<Command>();
        cmds.add(new SearchCommand.uid(criteria));
        
        Gee.Set<Imap.UID>? search_results;
        yield exec_commands_async(cmds, null, out search_results, cancellable);
        if (search_results == null || search_results.size == 0)
            return null;
        
        Gee.SortedSet<Imap.UID> tree = new Gee.TreeSet<Imap.UID>();
        tree.add_all(search_results);
        
        return tree;
    }
    
    // NOTE: If fields are added or removed from this method, BASIC_FETCH_FIELDS *must* be updated
    // as well
    private void fields_to_fetch_data_types(Geary.Email.Field fields,
        Gee.List<FetchDataSpecifier> data_types_list, out FetchBodyDataSpecifier? header_specifier) {
        // pack all the needed headers into a single FetchBodyDataType
        string[] field_names = new string[0];
        
        // The assumption here is that because ENVELOPE is such a common fetch command, the
        // server will have optimizations for it, whereas if we called for each header in the
        // envelope separately, the server has to chunk harder parsing the RFC822 header ... have
        // to add References because IMAP ENVELOPE doesn't return them for some reason (but does
        // return Message-ID and In-Reply-To)
        if (fields.is_all_set(Geary.Email.Field.ENVELOPE)) {
            data_types_list.add(FetchDataSpecifier.ENVELOPE);
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
                    data_types_list.add(FetchDataSpecifier.RFC822_HEADER);
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
            header_specifier = new FetchBodyDataSpecifier.peek(
                FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS, null, -1, -1, field_names);
            if (imap_header_fields_hack)
                header_specifier.omit_request_header_fields_space();
        } else {
            header_specifier = null;
        }
    }
    
    private static Geary.Email fetched_data_to_email(string folder_name, UID uid,
        FetchedData fetched_data, Geary.Email.Field required_fields,
        FetchBodyDataSpecifier? header_specifier, FetchBodyDataSpecifier? body_specifier,
        FetchBodyDataSpecifier? preview_specifier, FetchBodyDataSpecifier? preview_charset_specifier) throws Error {
        // note the use of INVALID_ROWID, as the rowid for this email (if one is present in the
        // database) is unknown at this time; this means ImapDB *must* create a new EmailIdentifier
        // for this email after create/merge is completed
        Geary.Email email = new Geary.Email(new ImapDB.EmailIdentifier.no_message_id(uid));
        
        // accumulate these to submit Imap.EmailProperties all at once
        InternalDate? internaldate = null;
        RFC822.Size? rfc822_size = null;
        
        // accumulate these to submit References all at once
        RFC822.MessageID? message_id = null;
        RFC822.MessageIDList? in_reply_to = null;
        RFC822.MessageIDList? references = null;
        
        // loop through all available FetchDataTypes and gather converted data
        foreach (FetchDataSpecifier data_type in fetched_data.data_map.keys) {
            MessageData? data = fetched_data.data_map.get(data_type);
            if (data == null)
                continue;
            
            switch (data_type) {
                case FetchDataSpecifier.ENVELOPE:
                    Envelope envelope = (Envelope) data;
                    
                    email.set_send_date(envelope.sent);
                    email.set_message_subject(envelope.subject);
                    email.set_originators(envelope.from, envelope.sender, envelope.reply_to);
                    email.set_receivers(envelope.to, envelope.cc, envelope.bcc);
                    
                    // store these to add to References all at once
                    message_id = envelope.message_id;
                    in_reply_to = envelope.in_reply_to;
                break;
                
                case FetchDataSpecifier.RFC822_HEADER:
                    email.set_message_header((RFC822.Header) data);
                break;
                
                case FetchDataSpecifier.RFC822_TEXT:
                    email.set_message_body((RFC822.Text) data);
                break;
                
                case FetchDataSpecifier.RFC822_SIZE:
                    rfc822_size = (RFC822.Size) data;
                break;
                
                case FetchDataSpecifier.FLAGS:
                    email.set_flags(new Imap.EmailFlags((MessageFlags) data));
                break;
                
                case FetchDataSpecifier.INTERNALDATE:
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
        bool has_header_specifier = fetched_data.body_data_map.has_key(header_specifier);
        if (header_specifier != null && !has_header_specifier) {
            message("[%s] No header specifier \"%s\" found:", folder_name,
                header_specifier.to_string());
            foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys)
                message("[%s] has %s", folder_name, specifier.to_string());
        } else if (header_specifier != null && has_header_specifier) {
            RFC822.Header headers = new RFC822.Header(
                fetched_data.body_data_map.get(header_specifier));
            
            // DATE
            if (required_but_not_set(Geary.Email.Field.DATE, required_fields, email)) {
                string? value = headers.get_header("Date");
                if (!String.is_empty(value))
                    email.set_send_date(new RFC822.Date(value));
                else
                    email.set_send_date(null);
            }
            
            // ORIGINATORS
            if (required_but_not_set(Geary.Email.Field.ORIGINATORS, required_fields, email)) {
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
                
                email.set_originators(from, sender, reply_to);
            }
            
            // RECEIVERS
            if (required_but_not_set(Geary.Email.Field.RECEIVERS, required_fields, email)) {
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
                    in_reply_to = new RFC822.MessageIDList.from_rfc822_string(value);
            }
            
            if (references == null) {
                string? value = headers.get_header("References");
                if (!String.is_empty(value))
                    references = new RFC822.MessageIDList.from_rfc822_string(value);
            }
            
            // SUBJECT
            // Unlike DATE, allow for empty subjects
            if (required_but_not_set(Geary.Email.Field.SUBJECT, required_fields, email)) {
                string? value = headers.get_header("Subject");
                if (value != null)
                    email.set_message_subject(new RFC822.Subject.decode(value));
                else
                    email.set_message_subject(null);
            }
        }
        
        // It's possible for all these fields to be null even though they were requested from
        // the server, so use requested fields for determination
        if (required_but_not_set(Geary.Email.Field.REFERENCES, required_fields, email))
            email.set_full_references(message_id, in_reply_to, references);
        
        // if body was requested, get it now
        if (body_specifier != null) {
            if (fetched_data.body_data_map.has_key(body_specifier)) {
                email.set_message_body(new Geary.RFC822.Text(
                    fetched_data.body_data_map.get(body_specifier)));
            } else {
                message("[%s] No body specifier \"%s\" found", folder_name,
                    body_specifier.to_string());
                foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys)
                    message("[%s] has %s", folder_name, specifier.to_string());
            }
        }
        
        // if preview was requested, get it now ... both identifiers must be supplied if one is
        if (preview_specifier != null || preview_charset_specifier != null) {
            assert(preview_specifier != null && preview_charset_specifier != null);
            
            if (fetched_data.body_data_map.has_key(preview_specifier)
                && fetched_data.body_data_map.has_key(preview_charset_specifier)) {
                email.set_message_preview(new RFC822.PreviewText.with_header(
                    fetched_data.body_data_map.get(preview_specifier),
                    fetched_data.body_data_map.get(preview_charset_specifier)));
            } else {
                message("[%s] No preview specifiers \"%s\" and \"%s\" found", folder_name,
                    preview_specifier.to_string(), preview_charset_specifier.to_string());
                foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys)
                    message("[%s] has %s", folder_name, specifier.to_string());
            }
        }
        
        return email;
    }
    
    // Returns a no-message-id ImapDB.EmailIdentifier with the UID stored in it.
    // This method does not take a cancellable; there is currently no way to tell if an email was
    // created or not if exec_commands_async() is cancelled during the append.  For atomicity's sake,
    // callers need to remove the returned email ID if a cancel occurred.
    public async Geary.EmailIdentifier? create_email_async(RFC822.Message message, Geary.EmailFlags? flags,
        DateTime? date_received) throws Error {
        check_open();
        
        MessageFlags? msg_flags = null;
        if (flags != null) {
            Imap.EmailFlags imap_flags = Imap.EmailFlags.from_api_email_flags(flags);
            msg_flags = imap_flags.message_flags;
        } else {
            msg_flags = new MessageFlags(Geary.iterate<MessageFlag>(MessageFlag.SEEN).to_array_list());
        }
        
        InternalDate? internaldate = null;
        if (date_received != null)
            internaldate = new InternalDate.from_date_time(date_received);
        
        AppendCommand cmd = new AppendCommand(new MailboxSpecifier.from_folder_path(path, null),
            msg_flags, internaldate, message.get_network_buffer(false));
        
        Gee.Map<Command, StatusResponse> responses = yield exec_commands_async(
            Geary.iterate<AppendCommand>(cmd).to_array_list(), null, null, null);
        
        // Grab the response and parse out the UID, if available.
        StatusResponse response = responses.get(cmd);
        if (response.status == Status.OK && response.response_code != null &&
            response.response_code.get_response_code_type().is_value("appenduid")) {
            UID new_id = new UID.checked(response.response_code.get_as_string(2).as_int64());
            
            return new ImapDB.EmailIdentifier.no_message_id(new_id);
        }
        
        // We didn't get a UID back from the server.
        return null;
    }
    
    private static bool required_but_not_set(Geary.Email.Field check, Geary.Email.Field users_fields, Geary.Email email) {
        return users_fields.require(check) ? !email.fields.is_all_set(check) : false;
    }
    
    public string to_string() {
        return path.to_string();
    }
}

