/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018, 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * An interface between the high-level engine API and an IMAP mailbox.
 *
 * Because of the complexities of the IMAP protocol, class takes
 * common operations that a Geary.Folder implementation would need
 * (in particular, {@link Geary.ImapEngine.MinimalFolder}) and makes
 * them into simple async calls.
 *
 * When constructed, this class will issue an IMAP SELECT command for
 * the mailbox represented by this folder, placing the session in the
 * Selected state.
 */
private class Geary.Imap.FolderSession : Geary.Imap.SessionObject {

    private const Geary.Email.Field BASIC_FETCH_FIELDS = Email.Field.ENVELOPE | Email.Field.DATE
        | Email.Field.ORIGINATORS | Email.Field.RECEIVERS | Email.Field.REFERENCES
        | Email.Field.SUBJECT | Email.Field.HEADER;


    /** The folder this session operates on. */
    public Imap.Folder folder { get; private set; }

    /** Determines if this folder immutable. */
    public Trillian readonly { get; private set; default = Trillian.UNKNOWN; }

    /** This folder's set of permanent IMAP flags. */
    public MessageFlags? permanent_flags { get; private set; default = null; }

    /** Determines if this folder accepts custom IMAP flags. */
    public Trillian accepts_user_flags { get; private set; default = Trillian.UNKNOWN; }

    private MailboxSpecifier mailbox;

    private Quirks quirks;

    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.HashMap<SequenceNumber, FetchedData>? fetch_accumulator = null;
    private Gee.Set<Imap.UID>? search_accumulator = null;

    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.3.1]]
     */
    public signal void exists(int total);

    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.3.2]]
     */
    public signal void recent(int total);

    /**
     * A (potentially unsolicited) response from the server.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.4.1]]
     */
    public signal void expunge(SequenceNumber position);

    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void appended(int count);

    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void updated(SequenceNumber pos, FetchedData data);

    /**
     * Fabricated from the IMAP signals and state obtained at open_async().
     */
    public signal void removed(SequenceNumber pos);


    public async FolderSession(ClientSession session,
                               Imap.Folder folder,
                               GLib.Cancellable? cancellable)
        throws GLib.Error {
        base(session);
        this.folder = folder;
        this.quirks = session.quirks;

        if (folder.properties.attrs.is_no_select) {
            throw new ImapError.NOT_SUPPORTED(
                "Folder cannot be selected: %s",
                folder.path.to_string()
            );
        }

        // Update based on our current session
        folder.properties.set_from_session_capabilities(session.capabilities);

        // connect to interesting signals *before* selecting
        session.exists.connect(on_exists);
        session.expunge.connect(on_expunge);
        session.fetch.connect(on_fetch);
        session.recent.connect(on_recent);
        session.search.connect(on_search);
        session.status_response_received.connect(on_status_response);

        this.mailbox = session.get_mailbox_for_path(folder.path);
        StatusResponse? response = yield session.select_async(
            this.mailbox, cancellable
        );
        throw_on_not_ok(response, "SELECT " + this.folder.path.to_string());

        // if at end of SELECT command accepts_user_flags is still
        // UNKKNOWN, treat as TRUE because, according to IMAP spec, if
        // PERMANENTFLAGS are not returned, then assume OK
        if (this.accepts_user_flags == Trillian.UNKNOWN)
            this.accepts_user_flags = Trillian.TRUE;
    }

    /**
     * Enables IMAP IDLE for the session, if supported.
     */
    public async void enable_idle(Cancellable? cancellable)
        throws Error {
        ClientSession session = get_session();
        int token = yield this.cmd_mutex.claim_async(cancellable);
        Error? cmd_err = null;
        try {
            session.enable_idle();
        } catch (Error err) {
            cmd_err = err;
        }

        this.cmd_mutex.release(ref token);

        if (cmd_err != null) {
            throw cmd_err;
        }
    }

    /** {@inheritDoc} */
    public override ClientSession? close() {
        ClientSession? old_session = base.close();
        if (old_session != null) {
            old_session.exists.disconnect(on_exists);
            old_session.expunge.disconnect(on_expunge);
            old_session.fetch.disconnect(on_fetch);
            old_session.recent.disconnect(on_recent);
            old_session.search.disconnect(on_search);
            old_session.status_response_received.disconnect(on_status_response);
        }
        return old_session;
    }

    /** Sends a NOOP command. */
    public async void send_noop(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield exec_commands_async(
            Collection.single(new NoopCommand(cancellable)),
            null,
            null,
            cancellable
        );
    }

    private void on_exists(int total) {
        debug("EXISTS %d", total);

        int old_total = this.folder.properties.select_examine_messages;
        this.folder.properties.set_select_examine_message_count(total);

        exists(total);
        if (old_total >= 0 && old_total < total) {
            appended(total - old_total);
        }
    }

    private void on_expunge(SequenceNumber pos) {
        debug("EXPUNGE %s", pos.to_string());

        int old_total = this.folder.properties.select_examine_messages;
        if (old_total > 0) {
            this.folder.properties.set_select_examine_message_count(
                old_total - 1
            );
        }

        expunge(pos);
        removed(pos);
    }

    private void on_fetch(FetchedData data) {
        // add if not found, merge if already received data for this email
        if (this.fetch_accumulator != null) {
            FetchedData? existing = this.fetch_accumulator.get(data.seq_num);
            this.fetch_accumulator.set(
                data.seq_num, (existing != null) ? data.combine(existing) : data
            );
        } else {
            debug("FETCH (unsolicited): %s:", data.to_string());
            updated(data.seq_num, data);
        }
    }

    private void on_recent(int total) {
        debug("RECENT %d", total);
        this.folder.properties.recent = total;
        recent(total);
    }

    private void on_search(int64[] seq_or_uid) {
        // All SEARCH from this class are UID SEARCH, so can reliably convert and add to
        // accumulator
        if (this.search_accumulator != null) {
            foreach (int64 uid in seq_or_uid) {
                try {
                    this.search_accumulator.add(new UID.checked(uid));
                } catch (ImapError imaperr) {
                    warning("Unable to process SEARCH UID result: %s",
                            imaperr.message);
                }
            }
        } else {
            debug("Not handling unsolicited SEARCH response");
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
                    this.readonly = Trillian.TRUE;
                break;

                case ResponseCodeType.READWRITE:
                    this.readonly = Trillian.FALSE;
                break;

                case ResponseCodeType.UIDNEXT:
                    try {
                        this.folder.properties.uid_next = response_code.get_uid_next();
                    } catch (ImapError.INVALID err) {
                        // Some mail servers e.g hMailServer and
                        // whatever is used by home.pl (dovecot?)
                        // sends UIDNEXT 0. Just ignore these since
                        // there nothing else that can be done. See
                        // GNOME/geary#711
                        if (response_code.get_as_string(1).as_int64() == 0) {
                            warning("Ignoring bad UIDNEXT 0 from server");
                        } else {
                            throw err;
                        }
                    }
                break;

                case ResponseCodeType.UIDVALIDITY:
                    this.folder.properties.uid_validity = response_code.get_uid_validity();
                break;

                case ResponseCodeType.UNSEEN:
                    // do NOT update properties.unseen, as the UNSEEN response code (here) means
                    // the sequence number of the first unseen message, not the total count of
                    // unseen messages
                break;

                case ResponseCodeType.PERMANENT_FLAGS:
                    this.permanent_flags = response_code.get_permanent_flags();
                    this.accepts_user_flags = Trillian.from_boolean(
                        this.permanent_flags.contains(MessageFlag.ALLOWS_NEW)
                    );
                break;

                default:
                    // ignored
                break;
            }
        } catch (ImapError ierr) {
            warning("Unable to parse ResponseCode %s: %s", response_code.to_string(),
                    ierr.message);
        }
    }

    // Executes a set of commands.
    //
    // All commands must executed inside the cmd_mutex. Collects
    // results in fetch_results or store results.
    private async Gee.Map<Command,StatusResponse>?
        exec_commands_async(Gee.Collection<Command> cmds,
                            Gee.HashMap<SequenceNumber, FetchedData>? fetch_results,
                            Gee.Set<Imap.UID>? search_results,
                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        ClientSession session = get_session();
        Gee.Map<Command, StatusResponse>? responses = null;
        int token = yield this.cmd_mutex.claim_async(cancellable);

        this.fetch_accumulator = fetch_results;
        this.search_accumulator = search_results;

        Error? cmd_err = null;
        try {
            responses = yield session.send_multiple_commands_async(
                cmds, cancellable
            );
        } catch (Error err) {
            cmd_err = err;
        }

        this.fetch_accumulator = null;
        this.search_accumulator = null;

        this.cmd_mutex.release(ref token);

        if (cmd_err != null) {
            throw cmd_err;
        }

        foreach (Command cmd in responses.keys) {
            throw_on_not_ok(responses.get(cmd), cmd.to_string());
        }

        return responses;
    }

    // Utility method for listing UIDs on the remote within the supplied range
    public async Gee.Set<Imap.UID>? list_uids_async(MessageSet msg_set,
                                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Although FETCH could be used, SEARCH is more efficient in returning pure UID results,
        // which is all we're interested in here
        SearchCriteria criteria = new SearchCriteria(SearchCriterion.message_set(msg_set));
        SearchCommand cmd = new SearchCommand.uid(criteria, cancellable);

        Gee.Set<Imap.UID> search_results = new Gee.HashSet<Imap.UID>();
        yield exec_commands_async(
            Geary.iterate<Command>(cmd).to_array_list(),
            null,
            search_results,
            cancellable
        );

        return (search_results.size > 0) ? search_results : null;
    }

    private Gee.Collection<FetchCommand> assemble_list_commands(
        Imap.MessageSet msg_set,
        Geary.Email.Field fields,
        GLib.Cancellable? cancellable,
        out FetchBodyDataSpecifier[]? header_specifiers,
        out FetchBodyDataSpecifier? body_specifier,
        out FetchBodyDataSpecifier? preview_specifier,
        out FetchBodyDataSpecifier? preview_charset_specifier
    ) {
        // getting all the fields can require multiple FETCH commands (some servers don't handle
        // well putting every required data item into single command), so aggregate FetchCommands
        Gee.Collection<FetchCommand> cmds = new Gee.ArrayList<FetchCommand>();

        // if not a UID FETCH, request UIDs for all messages so their EmailIdentifier can be
        // created without going back to the database (assuming the messages have already been
        // pulled down, not a guarantee); if request is for NONE, that guarantees that the
        // EmailIdentifier will be set, and so fetch UIDs (which looks funny but works when
        // listing a range for contents: UID FETCH x:y UID)
        if (!msg_set.is_uid || fields == Geary.Email.Field.NONE) {
            cmds.add(
                new FetchCommand.data_type(
                    msg_set, FetchDataSpecifier.UID, cancellable
                )
            );
        }

        // convert bulk of the "basic" fields into a one or two FETCH commands (some servers have
        // exhibited bugs or return NO when too many FETCH data types are combined on a single
        // command)
        header_specifiers = null;
        if (fields.requires_any(BASIC_FETCH_FIELDS)) {
            Gee.List<FetchDataSpecifier> basic_types =
                new Gee.LinkedList<FetchDataSpecifier>();
            Gee.List<string> header_fields = new Gee.LinkedList<string>();

            fields_to_fetch_data_types(fields, basic_types, header_fields);

            // Add all simple data types as one FETCH command
            if (!basic_types.is_empty) {
                cmds.add(
                    new FetchCommand(msg_set, basic_types, null, cancellable)
                );
            }

            // Add all header field requests as separate FETCH
            // command(s). If the HEADER.FIELDS hack is enabled and
            // there is more than one header that needs fetching, we
            // need to send multiple commands since we can't separate
            // them by spaces in the same command.
            //
            // See <https://gitlab.gnome.org/GNOME/geary/issues/571>
            if (!header_fields.is_empty) {
                if (!this.quirks.fetch_header_part_no_space ||
                    header_fields.size == 1) {
                    header_specifiers = new FetchBodyDataSpecifier[1];
                    header_specifiers[0] = new FetchBodyDataSpecifier.peek(
                        FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS,
                        null,
                        -1,
                        -1,
                        header_fields.to_array()
                    );
                } else {
                    header_specifiers = new FetchBodyDataSpecifier[header_fields.size];
                    int i = 0;
                    foreach (string name in header_fields) {
                        header_specifiers[i++] = new FetchBodyDataSpecifier.peek(
                            FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS,
                            null,
                            -1,
                            -1,
                            new string[] { name }
                        );
                    }
                }

                foreach (FetchBodyDataSpecifier header in header_specifiers) {
                    if (this.quirks.fetch_header_part_no_space) {
                        header.omit_request_header_fields_space();
                    }
                    cmds.add(
                        new FetchCommand.body_data_type(
                            msg_set, header, cancellable
                        )
                    );
                }
            }
        }

        // RFC822 BODY is a separate command
        if (fields.require(Email.Field.BODY)) {
            body_specifier = new FetchBodyDataSpecifier.peek(FetchBodyDataSpecifier.SectionPart.TEXT,
                null, -1, -1, null);

            cmds.add(
                new FetchCommand.body_data_type(
                    msg_set, body_specifier, cancellable
                )
            );
        } else {
            body_specifier = null;
        }

        // PREVIEW obtains the content type and a truncated version of
        // the first part of the message, which often leads to poor
        // results. It can also be also be synthesised from the
        // email's RFC822 message in fetched_data_to_email, if the
        // fields needed for reconstructing the RFC822 message are
        // present. If so, rely on that and don't also request any
        // additional data for the preview here.
        if (fields.require(Email.Field.PREVIEW) &&
            !fields.require(Email.REQUIRED_FOR_MESSAGE)) {
            // Get the preview text (the initial MAX_PREVIEW_BYTES of
            // the first MIME section

            preview_specifier = new FetchBodyDataSpecifier.peek(FetchBodyDataSpecifier.SectionPart.NONE,
                { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES, null);
            cmds.add(
                new FetchCommand.body_data_type(
                    msg_set, preview_specifier, cancellable
                )
            );

            // Also get the character set to properly decode it
            preview_charset_specifier = new FetchBodyDataSpecifier.peek(
                FetchBodyDataSpecifier.SectionPart.MIME, { 1 }, -1, -1, null);
            cmds.add(
                new FetchCommand.body_data_type(
                    msg_set, preview_charset_specifier, cancellable
                )
            );
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

            cmds.add(new FetchCommand(msg_set, data_types, null, cancellable));
        }

        return cmds;
    }

    // Returns a no-message-id ImapDB.EmailIdentifier with the UID stored in it.
    public async Gee.List<Geary.Email>? list_email_async(MessageSet msg_set,
                                                         Geary.Email.Field fields,
                                                         Cancellable? cancellable)
        throws Error {
        Gee.HashMap<SequenceNumber, FetchedData> fetched =
            new Gee.HashMap<SequenceNumber, FetchedData>();
        FetchBodyDataSpecifier[]? header_specifiers = null;
        FetchBodyDataSpecifier? body_specifier = null;
        FetchBodyDataSpecifier? preview_specifier = null;
        FetchBodyDataSpecifier? preview_charset_specifier = null;
        bool success = false;
        while (!success) {
            Gee.Collection<FetchCommand> cmds = assemble_list_commands(
                msg_set,
                fields,
                cancellable,
                out header_specifiers,
                out body_specifier,
                out preview_specifier,
                out preview_charset_specifier
            );
            if (cmds.size == 0) {
                throw new ImapError.INVALID(
                    "No FETCH commands generate for list request %s %s",
                    msg_set.to_string(),
                    fields.to_string()
                );
            }

            // Commands prepped, do the fetch and accumulate all the responses
            try {
                yield exec_commands_async(cmds, fetched, null, cancellable);
                success = true;
            } catch (ImapError.SERVER_ERROR err) {
                if (retry_bad_header_fields_response(cmds)) {
                    // The command failed, but it wasn't using the
                    // header field hack, so retry it.
                    debug("Retryable server failure detected: %s", err.message);
                } else {
                    throw err;
                }
            }
        }

        if (fetched.size == 0)
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
                    message("Unable to list message #%s: No UID returned from server",
                            seq_num.to_string());

                    continue;
                }

                try {
                    Geary.Email email = fetched_data_to_email(
                        uid,
                        fetched_data,
                        fields,
                        header_specifiers,
                        body_specifier,
                        preview_specifier,
                        preview_charset_specifier
                    );
                    if (!email.fields.fulfills(fields)) {
                        warning(
                            "%s missing=%s fetched=%s",
                            email.id.to_string(),
                            fields.clear(email.fields).to_string(),
                            fetched_data.to_string()
                        );
                        continue;
                    }

                    email_list.add(email);
                } catch (Error err) {
                    warning("Unable to convert email for %s %s: %s",
                            uid.to_string(),
                            fetched_data.to_string(),
                            err.message);
                }
            }
        }, cancellable);

        return (email_list.size > 0) ? email_list : null;
    }

    /**
     * Returns the sequence numbers for a set of UIDs.
     *
     * The `msg_set` parameter must be a set containing UIDs. An error
     * is thrown if the sequence numbers cannot be determined.
     */
    public async Gee.Map<UID, SequenceNumber> uid_to_position_async(MessageSet msg_set,
                                                                    Cancellable? cancellable)
        throws Error {
        if (!msg_set.is_uid) {
            throw new ImapError.NOT_SUPPORTED("Message set must contain UIDs");
        }

        Gee.List<Command> cmds = new Gee.ArrayList<Command>();
        cmds.add(
            new FetchCommand.data_type(
                msg_set, FetchDataSpecifier.UID, cancellable
            )
        );

        Gee.HashMap<SequenceNumber, FetchedData> fetched =
            new Gee.HashMap<SequenceNumber, FetchedData>();
        yield exec_commands_async(cmds, fetched, null, cancellable);

        if (fetched.is_empty) {
            throw new ImapError.INVALID("Server returned no sequence numbers");
        }

        Gee.Map<UID,SequenceNumber> map = new Gee.HashMap<UID,SequenceNumber>();
        foreach (SequenceNumber seq_num in fetched.keys) {
            map.set(
                (UID) fetched.get(seq_num).data_map.get(FetchDataSpecifier.UID),
                seq_num
            );
        }
        return map;
    }

    public async void remove_email_async(Gee.List<MessageSet> msg_sets,
                                         GLib.Cancellable? cancellable)
        throws GLib.Error {
        ClientSession session = get_session();
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);

        Gee.List<Command> cmds = new Gee.ArrayList<Command>();

        // Build STORE command for all MessageSets, see if all are UIDs so we can use UID EXPUNGE
        bool all_uid = true;
        foreach (MessageSet msg_set in msg_sets) {
            if (!msg_set.is_uid)
                all_uid = false;

            cmds.add(
                new StoreCommand(msg_set, ADD_FLAGS, SILENT, flags, cancellable)
            );
        }

        // TODO: Only use old-school EXPUNGE when closing folder (or rely on CLOSE to do that work
        // for us).  See:
        // http://redmine.yorba.org/issues/7532
        //
        // However, current client implementation doesn't properly close INBOX when application
        // shuts down, which means deleted messages return at application start.  See:
        // http://redmine.yorba.org/issues/6865
        if (all_uid && session.capabilities.supports_uidplus()) {
            foreach (MessageSet msg_set in msg_sets) {
                cmds.add(new ExpungeCommand.uid(msg_set, cancellable));
            }
        } else {
            cmds.add(new ExpungeCommand(cancellable));
        }

        yield exec_commands_async(cmds, null, null, cancellable);
    }

    public async void mark_email_async(Gee.List<MessageSet> msg_sets, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable) throws Error {
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add,
            out msg_flags_remove);

        if (msg_flags_add.size == 0 && msg_flags_remove.size == 0)
            return;

        Gee.Collection<Command> cmds = new Gee.ArrayList<Command>();
        foreach (MessageSet msg_set in msg_sets) {
            if (msg_flags_add.size > 0) {
                cmds.add(
                    new StoreCommand(
                        msg_set,
                        ADD_FLAGS,
                        SILENT,
                        msg_flags_add,
                        cancellable
                    )
                );
            }

            if (msg_flags_remove.size > 0) {
                cmds.add(
                    new StoreCommand(
                        msg_set,
                        REMOVE_FLAGS,
                        SILENT,
                        msg_flags_remove,
                        cancellable
                    )
                );
            }
        }

        yield exec_commands_async(cmds, null, null, cancellable);
    }

    // Returns a mapping of the source UID to the destination UID.  If the MessageSet is not for
    // UIDs, then null is returned.  If the server doesn't support COPYUID, null is returned.
    public async Gee.Map<UID, UID>? copy_email_async(MessageSet msg_set,
                                                     FolderPath destination,
                                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        ClientSession session = get_session();

        MailboxSpecifier mailbox = session.get_mailbox_for_path(destination);
        CopyCommand cmd = new CopyCommand(msg_set, mailbox, cancellable);

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
                warning("Unable to retrieve COPYUID UIDs: %s", ierr.message);
            }

            if (src_uids != null && !src_uids.is_empty &&
                dst_uids != null && !dst_uids.is_empty) {
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

    public async Gee.SortedSet<Imap.UID>? search_async(SearchCriteria criteria,
                                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        // always perform a UID SEARCH
        Gee.Collection<Command> cmds = new Gee.ArrayList<Command>();
        cmds.add(new SearchCommand.uid(criteria, cancellable));

        Gee.Set<Imap.UID> search_results = new Gee.HashSet<Imap.UID>();
        yield exec_commands_async(cmds, null, search_results, cancellable);

        Gee.SortedSet<Imap.UID> tree = null;
        if (search_results.size > 0) {
            tree = new Gee.TreeSet<Imap.UID>();
            tree.add_all(search_results);
        }
        return tree;
    }

    // NOTE: If fields are added or removed from this method, BASIC_FETCH_FIELDS *must* be updated
    // as well
    private void fields_to_fetch_data_types(Geary.Email.Field fields,
                                            Gee.List<FetchDataSpecifier> basic_types,
                                            Gee.List<string> header_fields) {
        // The assumption here is that because ENVELOPE is such a common fetch command, the
        // server will have optimizations for it, whereas if we called for each header in the
        // envelope separately, the server has to chunk harder parsing the RFC822 header ... have
        // to add References because IMAP ENVELOPE doesn't return them for some reason (but does
        // return Message-ID and In-Reply-To)
        if (fields.is_all_set(Geary.Email.Field.ENVELOPE)) {
            basic_types.add(FetchDataSpecifier.ENVELOPE);
            header_fields.add("References");

            // remove those flags and process any remaining
            fields = fields.clear(Geary.Email.Field.ENVELOPE);
        }

        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            switch (fields & field) {
                case Geary.Email.Field.DATE:
                    header_fields.add("Date");
                break;

                case Geary.Email.Field.ORIGINATORS:
                    header_fields.add("From");
                    header_fields.add("Sender");
                    header_fields.add("Reply-To");
                break;

                case Geary.Email.Field.RECEIVERS:
                    header_fields.add("To");
                    header_fields.add("Cc");
                    header_fields.add("Bcc");
                break;

                case Geary.Email.Field.REFERENCES:
                    header_fields.add("References");
                    header_fields.add("Message-ID");
                    header_fields.add("In-Reply-To");
                break;

                case Geary.Email.Field.SUBJECT:
                    header_fields.add("Subject");
                break;

                case Geary.Email.Field.HEADER:
                    // TODO: If the entire header is being pulled, then no need to pull down partial
                    // headers; simply get them all and decode what is needed directly
                    basic_types.add(FetchDataSpecifier.RFC822_HEADER);
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
    }

    private Geary.Email fetched_data_to_email(
        UID uid,
        FetchedData fetched_data,
        Geary.Email.Field required_fields,
        FetchBodyDataSpecifier[]? header_specifiers,
        FetchBodyDataSpecifier? body_specifier,
        FetchBodyDataSpecifier? preview_specifier,
        FetchBodyDataSpecifier? preview_charset_specifier
    ) throws GLib.Error {
        // note the use of INVALID_ROWID, as the rowid for this email (if one is present in the
        // database) is unknown at this time; this means ImapDB *must* create a new EmailIdentifier
        // for this email after create/merge is completed
        Geary.Email email = new Geary.Email(new ImapDB.EmailIdentifier.no_message_id(uid));

        // accumulate these to submit Imap.EmailProperties all at once
        InternalDate? internaldate = null;
        RFC822Size? rfc822_size = null;

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
                    email.set_originators(
                        envelope.from,
                        envelope.sender.equal_to(envelope.from) || envelope.sender.size == 0 ? null : envelope.sender[0],
                        envelope.reply_to.equal_to(envelope.from) ? null : envelope.reply_to
                    );
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
                    rfc822_size = (RFC822Size) data;
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

        // if any headers were requested, convert its fields now
        if (header_specifiers != null) {
            // Header fields are case insensitive, so use a
            // case-insensitive map.
            //
            // XXX this is bogus because it doesn't take into the
            // presence of multiple headers. It's not common, but it's
            // possible for there to be two To headers, for example
            Gee.Map<string,string> headers = new Gee.HashMap<string,string>(
                String.stri_hash, String.stri_equal
            );
            foreach (FetchBodyDataSpecifier header_specifier in header_specifiers) {
                Memory.Buffer fetched_headers =
                    fetched_data.body_data_map.get(header_specifier);
                if (fetched_headers != null) {
                    RFC822.Header parsed_headers = new RFC822.Header(fetched_headers);
                    foreach (string name in parsed_headers.get_header_names()) {
                        headers.set(name, parsed_headers.get_raw_header(name));
                    }
                } else {
                    warning(
                        "No header specifier \"%s\" found in response:",
                        header_specifier.to_string()
                    );
                    foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys) {
                        warning(" - has %s", specifier.to_string());
                    }
                }
            }

            // When setting email properties below, the relevant
            // Geary.Email setter needs to be called regardless of
            // whether the value being set is null, since the setter
            // will update the email's flags so we know the email has
            // the field set and it is null.

            // DATE
            if (required_but_not_set(DATE, required_fields, email)) {
                email.set_send_date(unflatten_date(headers.get("Date")));
            }

            // ORIGINATORS
            if (required_but_not_set(ORIGINATORS, required_fields, email)) {
                // Allow sender to be a list (contra to the RFC), but
                // only take the first from it
                RFC822.MailboxAddresses? sender = unflatten_addresses(
                    headers.get("Sender")
                );
                email.set_originators(
                    unflatten_addresses(headers.get("From")),
                    (sender != null && !sender.is_empty) ? sender.get(0) : null,
                    unflatten_addresses(headers.get("Reply-To"))
                );
            }

            // RECEIVERS
            if (required_but_not_set(RECEIVERS, required_fields, email)) {
                email.set_receivers(
                    unflatten_addresses(headers.get("To")),
                    unflatten_addresses(headers.get("Cc")),
                    unflatten_addresses(headers.get("Bcc"))
                );
            }

            // REFERENCES
            // (Note that it's possible the request used an IMAP ENVELOPE, in which case only the
            // References header will be present if REFERENCES were required, which is why
            // REFERENCES is set at the bottom of the method, when all information has been gathered
            if (message_id == null) {
                message_id = unflatten_message_id(
                    headers.get("Message-ID")
                );
            }
            if (in_reply_to == null) {
                in_reply_to = unflatten_message_id_list(
                    headers.get("In-Reply-To")
                );
            }
            if (references == null) {
                references = unflatten_message_id_list(
                    headers.get("References")
                );
            }

            // SUBJECT
            if (required_but_not_set(Geary.Email.Field.SUBJECT, required_fields, email)) {
                RFC822.Subject? subject = null;
                string? value = headers.get("Subject");
                if (value != null) {
                    subject = new RFC822.Subject.from_rfc822_string(value);
                }
                email.set_message_subject(subject);
            }
        }

        // It's possible for all these fields to be null even though they were requested from
        // the server, so use requested fields for determination
        if (required_but_not_set(Geary.Email.Field.REFERENCES, required_fields, email))
            email.set_full_references(message_id, in_reply_to, references);

        // if preview was requested, get it now ... both identifiers
        // must be supplied if one is
        if (preview_specifier != null || preview_charset_specifier != null) {
            Memory.Buffer? preview_headers = fetched_data.body_data_map.get(
                preview_charset_specifier
            );
            Memory.Buffer? preview_body = fetched_data.body_data_map.get(
                preview_specifier
            );

            RFC822.PreviewText preview = new RFC822.PreviewText(new Memory.StringBuffer(""));
            if (preview_headers != null && preview_headers.size > 0 &&
                preview_body != null && preview_body.size > 0) {
                preview = new RFC822.PreviewText.with_header(
                    preview_headers, preview_body
                );
            } else {
                warning("No preview specifiers \"%s\" and \"%s\" found",
                    preview_specifier.to_string(), preview_charset_specifier.to_string());
                foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys)
                    warning(" - has %s", specifier.to_string());
            }
            email.set_message_preview(preview);
        }

        // If body was requested, get it now. We also set the preview
        // here from the body if possible since for HTML messages at
        // least there's a lot of boilerplate HTML to wade through to
        // get some actual preview text, which usually requires more
        // than Geary.Email.MAX_PREVIEW_BYTES will allow for
        if (body_specifier != null) {
            if (fetched_data.body_data_map.has_key(body_specifier)) {
                email.set_message_body(new Geary.RFC822.Text(
                    fetched_data.body_data_map.get(body_specifier)));

                // Try to set the preview
                Geary.RFC822.Message? message = null;
                try {
                    message = email.get_message();
                } catch (EngineError.INCOMPLETE_MESSAGE err) {
                    debug("Not enough fields to construct message for preview: %s", err.message);
                } catch (GLib.Error err) {
                    warning("Error constructing message for preview: %s", err.message);
                }
                if (message != null) {
                    string preview = message.get_preview();
                    if (preview.length > Geary.Email.MAX_PREVIEW_BYTES) {
                        preview = Geary.String.safe_byte_substring(
                            preview, Geary.Email.MAX_PREVIEW_BYTES
                        );
                    }
                    email.set_message_preview(
                        new RFC822.PreviewText.from_string(preview)
                    );
                }
            } else {
                warning("No body specifier \"%s\" found",
                        body_specifier.to_string());
                foreach (FetchBodyDataSpecifier specifier in fetched_data.body_data_map.keys)
                    warning(" - has %s", specifier.to_string());
            }
        }

        return email;
    }

    /**
     * Stores a new message in the remote mailbox.
     *
     * Returns a no-message-id ImapDB.EmailIdentifier with the UID
     * stored in it.
     *
     * This method does not take a cancellable; there is currently no
     * way to tell if an email was created or not if {@link
     * exec_commands_async} is cancelled during the append. For
     * atomicity's sake, callers need to remove the returned email ID
     * if a cancel occurred.
    */
    public async Geary.EmailIdentifier? create_email_async(RFC822.Message message,
                                                           Geary.EmailFlags? flags,
                                                           GLib.DateTime? date_received)
        throws GLib.Error {
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

        AppendCommand cmd = new AppendCommand(
            this.mailbox,
            msg_flags,
            internaldate,
            message.get_rfc822_buffer(),
            null
        );

        Gee.Map<Command, StatusResponse> responses = yield exec_commands_async(
            Geary.iterate<AppendCommand>(cmd).to_array_list(), null, null, null
        );

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

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%s, %s, ro: %s, permanent_flags: %s, accepts_user_flags: %s",
            base.to_logging_state().format_message(), // XXX this is cruddy
            this.folder.to_string(),
            this.readonly.to_string(),
            this.permanent_flags != null
                ? this.permanent_flags.to_string() : "(none)",
            this.accepts_user_flags.to_string()
        );
    }

    /**
     * Returns a valid IMAP client session for use by this object.
     *
     * In addition to the checks made by {@link
     * SessionObject.get_session}, this method also ensures that the
     * IMAP session is in the SELECTED state for the correct mailbox.
     */
    protected override ClientSession get_session()
        throws ImapError {
        var session = base.get_session();
        if (session.protocol_state != SELECTED &&
            !this.mailbox.equal_to(session.selected_mailbox)) {
            throw new ImapError.NOT_CONNECTED(
                "IMAP object no longer SELECTED for %s",
                this.mailbox.to_string()
            );
        }
        return session;
    }

    // HACK: See https://bugzilla.gnome.org/show_bug.cgi?id=714902
    //
    // Detect when a server has returned a BAD response to FETCH
    // BODY[HEADER.FIELDS (HEADER-LIST)] due to space between
    // HEADER.FIELDS and (HEADER-LIST)
    private bool retry_bad_header_fields_response(Gee.Collection<FetchCommand> cmds) {
        foreach (FetchCommand fetch in cmds) {
            if (fetch.status.status == BAD) {
                foreach (FetchBodyDataSpecifier specifier in
                         fetch.for_body_data_specifiers) {
                    if (specifier.section_part == HEADER_FIELDS ||
                        specifier.section_part == HEADER_FIELDS_NOT) {
                        // Check the specifier's use of the space, not the
                        // folder's property, as it's possible the
                        // property was enabled after sending command but
                        // before response returned
                        if (specifier.request_header_fields_space) {
                            this.quirks.fetch_header_part_no_space = true;
                            return true;
                        }
                    }
                }
            }
        }

        return false;
     }

    private void throw_on_not_ok(StatusResponse response, string cmd)
        throws ImapError {
        switch (response.status) {
        case Status.OK:
            // All good
            break;

        case Status.NO:
            throw new ImapError.NOT_SUPPORTED(
                "Request %s failed: %s", cmd.to_string(), response.to_string()
            );

        default:
            throw new ImapError.SERVER_ERROR(
                "Unknown response status to %s: %s",
                cmd.to_string(), response.to_string()
            );
        }
    }

    private static bool required_but_not_set(Geary.Email.Field check, Geary.Email.Field users_fields, Geary.Email email) {
        return users_fields.require(check) ? !email.fields.is_all_set(check) : false;
    }

    private RFC822.Date? unflatten_date(string? str) {
        RFC822.Date? date = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                date = new RFC822.Date.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 date \"%s\": %s", str, err.message);
            }
        }
        return date;
    }

    private RFC822.MailboxAddresses? unflatten_addresses(string? str) {
        RFC822.MailboxAddresses? addresses = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                addresses = new RFC822.MailboxAddresses.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 mailbox addresses \"%s\": %s", str, err.message);
            }
        }
        return addresses;
    }

    private RFC822.MessageID? unflatten_message_id(string? str) {
        RFC822.MessageID? id = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                id = new RFC822.MessageID.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 message id \"%s\": %s", str, err.message);
            }
        }
        return id;
    }

    private RFC822.MessageIDList? unflatten_message_id_list(string? str) {
        RFC822.MessageIDList? ids = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                ids = new RFC822.MessageIDList.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 message id \"%s\": %s", str, err.message);
            }
        }
        return ids;
    }

}
