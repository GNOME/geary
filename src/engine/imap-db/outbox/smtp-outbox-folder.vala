/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Special type of folder that runs an asynchronous send queue.  Messages are
// saved to the database, then queued up for sending.
//
// The Outbox table is not currently maintained in its own database, so it must piggy-back
// on the ImapDB.Database.  SmtpOutboxFolder assumes the database is opened before it's passed in
// to the constructor -- it does not open or close the database itself and will start using it
// immediately.
private class Geary.SmtpOutboxFolder :
    Geary.AbstractLocalFolder, Geary.FolderSupport.Remove, Geary.FolderSupport.Create {


    // Min and max times between attempting to re-send after a connection failure.
    private const uint MIN_SEND_RETRY_INTERVAL_SEC = 4;
    private const uint MAX_SEND_RETRY_INTERVAL_SEC = 64;

    // Time to wait before starting the postman for accounts to be
    // loaded, connections to settle, pigs to fly, etc.
    private const uint START_TIMEOUT = 4;


    private class OutboxRow {
        public int64 id;
        public int position;
        public int64 ordering;
        public bool sent;
        public Memory.Buffer? message;
        public SmtpOutboxEmailIdentifier outbox_id;

        public OutboxRow(int64 id, int position, int64 ordering, bool sent, Memory.Buffer? message) {
            assert(position >= 1);

            this.id = id;
            this.position = position;
            this.ordering = ordering;
            this.sent = sent;
            this.message = message;

            outbox_id = new SmtpOutboxEmailIdentifier(id, ordering);
        }
    }


    // Used solely for debugging, hence "(no subject)" not marked for translation
    private static string message_subject(RFC822.Message message) {
        return (message.subject != null && !String.is_empty(message.subject.to_string()))
            ? message.subject.to_string() : "(no subject)";
    }


    public override Account account { get { return this._account; } }

    public override FolderProperties properties { get { return _properties; } }

    private SmtpOutboxFolderRoot _path = new SmtpOutboxFolderRoot();
    public override FolderPath path {
        get {
            return _path;
        }
    }

    public override SpecialFolderType special_folder_type {
        get {
            return Geary.SpecialFolderType.OUTBOX;
        }
    }

    private Endpoint smtp_endpoint {
        get { return this._account.information.smtp.endpoint; }
    }

    private weak Account _account;
    private ImapDB.Database db;

    private Cancellable? queue_cancellable = null;
    private Nonblocking.Queue<OutboxRow> outbox_queue = new Nonblocking.Queue<OutboxRow>.fifo();
    private Geary.ProgressMonitor sending_monitor;
    private SmtpOutboxFolderProperties _properties = new SmtpOutboxFolderProperties(0, 0);
    private int64 next_ordering = 0;

    private TimeoutManager start_timer;

    /** Fired when an email has successfully been sent. */
    public signal void email_sent(Geary.RFC822.Message rfc822);

    /** Fired if a user-notifiable problem occurs. */
    public signal void report_problem(ProblemReport report);


    // Requires the Database from the get-go because it runs a background task that access it
    // whether open or not
    public SmtpOutboxFolder(ImapDB.Database db, Account account, Geary.ProgressMonitor sending_monitor) {
        base();
        this._account = account;
        this._account.opened.connect(on_account_opened);
        this._account.closed.connect(on_account_closed);
        this.db = db;
        this.sending_monitor = sending_monitor;
        this.start_timer = new TimeoutManager.seconds(
            START_TIMEOUT,
            () => { this.start_postman_async.begin(); }
        );
    }

    /**
     * Starts delivery of messages in the outbox.
     */
    public async void start_postman_async() {
        debug("Starting outbox postman with %u messages queued", this.outbox_queue.size);
        if (this.queue_cancellable != null) {
            debug("Postman already started, not starting another");
            return;
        }

        Cancellable cancellable = this.queue_cancellable = new Cancellable();
        uint send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;

        // Start the send queue.
        while (!cancellable.is_cancelled()) {
            // yield until a message is ready
            OutboxRow? row = null;
            bool row_handled = false;
            try {
                row = yield this.outbox_queue.receive(cancellable);
                row_handled = yield postman_send(row, cancellable);
            } catch (SmtpError err) {
                ProblemType problem = ProblemType.GENERIC_ERROR;
                if (err is SmtpError.AUTHENTICATION_FAILED) {
                    problem = ProblemType.LOGIN_FAILED;
                } else if (err is SmtpError.STARTTLS_FAILED) {
                    problem = ProblemType.CONNECTION_ERROR;
                } else if (err is SmtpError.NOT_CONNECTED) {
                    problem = ProblemType.NETWORK_ERROR;
                } else if (err is SmtpError.PARSE_ERROR ||
                           err is SmtpError.SERVER_ERROR ||
                           err is SmtpError.NOT_SUPPORTED) {
                    problem = ProblemType.SERVER_ERROR;
                }
                notify_report_problem(problem, err);
                cancellable.cancel();
            } catch (IOError.CANCELLED err) {
                // Nothing to do here — we're already cancelled. In
                // particular we don't want to report the cancelled
                // error as a problem since this is the normal
                // shutdown method.
            } catch (IOError err) {
                notify_report_problem(ProblemType.for_ioerror(err), err);
                cancellable.cancel();
            } catch (Error err) {
                notify_report_problem(ProblemType.GENERIC_ERROR, err);
                cancellable.cancel();
            }

            if (row_handled) {
                // send was good, reset nap length
                send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;
            } else {
                // send was bad, try sending again later
                if (row != null) {
                    this.outbox_queue.send(row);
                }

                if (!cancellable.is_cancelled()) {
                    debug("Outbox napping for %u seconds...", send_retry_seconds);
                    // Take a brief nap before continuing to allow
                    // connection problems to resolve.
                    yield Geary.Scheduler.sleep_async(send_retry_seconds);
                    send_retry_seconds = Geary.Numeric.uint_ceiling(
                        send_retry_seconds * 2,
                        MAX_SEND_RETRY_INTERVAL_SEC
                    );
                }
            }
        }

        this.queue_cancellable = null;
        debug("Exiting outbox postman");
    }

    /**
     * Queues a message in the outbox for delivery.
     *
     * This should be used instead of {@link create_email_async},
     * since that requires the Outbox be open according to contract,
     * but enqueuing emails for background delivery can happen at any
     * time, so this is the mechanism to do so.
     */
    public async SmtpOutboxEmailIdentifier enqueue_email_async(Geary.RFC822.Message rfc822,
        Cancellable? cancellable) throws Error {
        debug("Queuing message for sending: %s",
              (rfc822.subject != null) ? rfc822.subject.to_string() : "(no subject)");

        int email_count = 0;
        OutboxRow? row = null;
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            int64 ordering = do_get_next_ordering(cx, cancellable);

            // save in database ready for SMTP, but without dot-stuffing
            Db.Statement stmt = cx.prepare(
                "INSERT INTO SmtpOutboxTable (message, ordering) VALUES (?, ?)");
            stmt.bind_string_buffer(0, rfc822.get_network_buffer(false));
            stmt.bind_int64(1, ordering);

            int64 id = stmt.exec_insert(cancellable);

            stmt = cx.prepare("SELECT message FROM SmtpOutboxTable WHERE id=?");
            stmt.bind_rowid(0, id);

            // This has got to work; Db should throw an exception if the INSERT failed
            Db.Result results = stmt.exec(cancellable);
            assert(!results.finished);

            Memory.Buffer message = results.string_buffer_at(0);

            int position = do_get_position_by_ordering(cx, ordering, cancellable);

            row = new OutboxRow(id, position, ordering, false, message);
            email_count = do_get_email_count(cx, cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        // should have thrown an error if this failed
        assert(row != null);

        // update properties
        _properties.set_total(yield get_email_count_async(cancellable));

        // immediately add to outbox queue for delivery
        outbox_queue.send(row);

        Gee.List<SmtpOutboxEmailIdentifier> list = new Gee.ArrayList<SmtpOutboxEmailIdentifier>();
        list.add(row.outbox_id);

        notify_email_appended(list);
        notify_email_locally_appended(list);
        notify_email_count_changed(email_count, CountChangeReason.APPENDED);

        return row.outbox_id;
    }

    public async void add_to_containing_folders_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath> map, Cancellable? cancellable) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            foreach (Geary.EmailIdentifier id in ids) {
                SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
                if (outbox_id == null)
                    continue;

                OutboxRow? row = do_fetch_row_by_ordering(cx, outbox_id.ordering, cancellable);
                if (row == null)
                    continue;

                map.set(id, path);
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);
    }

    public virtual async Geary.EmailIdentifier? create_email_async(Geary.RFC822.Message rfc822, EmailFlags? flags,
        DateTime? date_received, Geary.EmailIdentifier? id = null, Cancellable? cancellable = null) throws Error {
        check_open();

        return yield enqueue_email_async(rfc822, cancellable);
    }

    public virtual async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        check_open();

        yield internal_remove_email_async(email_ids, cancellable);
    }

    public override Geary.Folder.OpenState get_open_state() {
        return is_open() ? Geary.Folder.OpenState.LOCAL : Geary.Folder.OpenState.CLOSED;
    }

    public override async Gee.List<Geary.Email>? list_email_by_id_async(
        Geary.EmailIdentifier? _initial_id, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        check_open();

        SmtpOutboxEmailIdentifier? initial_id = _initial_id as SmtpOutboxEmailIdentifier;
        if (_initial_id != null && initial_id == null) {
            throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not for Outbox",
                initial_id.to_string());
        }

        if (count <= 0)
            return null;

        Gee.List<Geary.Email>? list = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            string dir = flags.is_newest_to_oldest() ? "DESC" : "ASC";

            Db.Statement stmt;
            if (initial_id != null) {
                stmt = cx.prepare("""
                    SELECT id, ordering, message, sent
                    FROM SmtpOutboxTable
                    WHERE ordering >= ?
                    ORDER BY ordering %s
                    LIMIT ?
                """.printf(dir));
                stmt.bind_int64(0,
                    flags.is_including_id() ? initial_id.ordering : initial_id.ordering + 1);
                stmt.bind_int(1, count);
            } else {
                stmt = cx.prepare("""
                    SELECT id, ordering, message, sent
                    FROM SmtpOutboxTable
                    ORDER BY ordering %s
                    LIMIT ?
                """.printf(dir));
                stmt.bind_int(0, count);
            }

            Db.Result results = stmt.exec(cancellable);
            if (results.finished)
                return Db.TransactionOutcome.DONE;

            list = new Gee.ArrayList<Geary.Email>();
            int position = -1;
            do {
                int64 ordering = results.int64_at(1);
                if (position == -1) {
                    position = do_get_position_by_ordering(cx, ordering, cancellable);
                    assert(position >= 1);
                }

                list.add(row_to_email(new OutboxRow(results.rowid_at(0), position, ordering,
                    results.bool_at(3), results.string_buffer_at(2))));
                position += flags.is_newest_to_oldest() ? -1 : 1;
                assert(position >= 1);
            } while (results.next());

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return list;
    }

    public override async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        check_open();

        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            foreach (Geary.EmailIdentifier id in ids) {
                SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
                if (outbox_id == null)
                    throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());

                OutboxRow? row = do_fetch_row_by_ordering(cx, outbox_id.ordering, cancellable);
                if (row == null)
                    continue;

                list.add(row_to_email(row));
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return (list.size > 0) ? list : null;
    }

    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>?
        list_local_email_fields_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable = null) throws Error {
        check_open();

        Gee.Map<Geary.EmailIdentifier, Geary.Email.Field> map = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email.Field>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare(
                "SELECT id FROM SmtpOutboxTable WHERE ordering=?");
            foreach (Geary.EmailIdentifier id in ids) {
                SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
                if (outbox_id == null)
                    throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());

                stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
                stmt.bind_int64(0, outbox_id.ordering);

                // merely checking for presence, all emails in outbox have same fields
                Db.Result results = stmt.exec(cancellable);
                if (!results.finished)
                    map.set(outbox_id, Geary.Email.Field.ALL);
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return (map.size > 0) ? map : null;
    }

    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        check_open();

        SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
        if (outbox_id == null)
            throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());

        OutboxRow? row = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            row = do_fetch_row_by_ordering(cx, outbox_id.ordering, cancellable);

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        if (row == null)
            throw new EngineError.NOT_FOUND("No message with ID %s in outbox", id.to_string());

        return row_to_email(row);
    }

    // Returns true if row was successfully processed, else false
    private async bool postman_send(OutboxRow row, Cancellable cancellable)
        throws Error {
        AccountInformation account = this.account.information;
        bool mail_sent = !yield is_unsent_async(row.ordering, cancellable);

        // Convert row into RFC822 message suitable for sending or framing
        RFC822.Message message;
        try {
            message = new RFC822.Message.from_buffer(row.message);
        } catch (RFC822Error msg_err) {
            // TODO: This needs to be reported to the user
            debug("Outbox postman message error: %s", msg_err.message);
            return false;
        }

        if (!mail_sent) {
            // Get SMTP password if we haven't loaded it yet and the account needs credentials.
            // If the account needs a password but it's not set or incorrect in the keyring, we'll
            // prompt below after getting an AUTHENTICATION_FAILED error.
            yield this.account.information.load_smtp_credentials(cancellable);

            // only try sending if (a) no TLS issues or (b) user has
            // acknowledged them and says to continue
            if (!this.smtp_endpoint.is_trusted_or_never_connected) {
                return false;
            }

            // We immediately retry auth errors after the prompting
            // the user, but if they get it wrong enough times or
            // cancel we have no choice other than to stop the postman
            uint attempts = 0;
            while (!mail_sent && ++attempts <= Geary.Account.AUTH_ATTEMPTS_MAX) {
                try {
                    debug("Outbox postman: Sending \"%s\" (ID:%s)...",
                          message_subject(message), row.outbox_id.to_string());
                    yield send_email_async(message, cancellable);
                    mail_sent = true;
                } catch (Error send_err) {
                    debug("Outbox postman send error: %s", send_err.message);
                    if (send_err is SmtpError.AUTHENTICATION_FAILED) {
                        if (attempts == Geary.Account.AUTH_ATTEMPTS_MAX) {
                            throw send_err;
                        }

                        // At this point we may already have a
                        // password in memory -- but it's incorrect.
                        if (!yield account.prompt_smtp_credentials(cancellable)) {
                            // The user cancelled and hence they don't
                            // want to be prompted again, so bail out.
                            throw send_err;
                        }
                    } else if (send_err is TlsError) {
                        // up to application to be aware of problem
                        // via Geary.Engine, but do nap and try later
                        debug("TLS connection warnings connecting to %s, user must confirm connection to continue",
                              this.smtp_endpoint.to_string());
                        break;
                    } else {
                        // not much else we can do - just bail out
                        throw send_err;
                    }
                }
            }

            // Mark as sent, so if there's a problem pushing up to
            // Sent, we don't retry sending. Don't observe the
            // cancellable here - if it's been sent we want to try to
            // update the sent flag anyway
            if (mail_sent) {
                debug("Outbox postman: Marking %s as sent", row.outbox_id.to_string());
                yield mark_email_as_sent_async(row.outbox_id, null);
            }

            if (!mail_sent || cancellable.is_cancelled()) {
                // try again later
                return false;
            }
        }

        // If we get to this point, the message has either been just
        // sent, or previously sent but not saved. So now try saving
        // if needed.
        if (account.allow_save_sent_mail() &&
            account.save_sent_mail) {
            try {
                debug("Outbox postman: Saving %s to sent mail", row.outbox_id.to_string());
                yield save_sent_mail_async(message, cancellable);
            } catch (Error err) {
                debug("Outbox postman: Error saving sent mail: %s", err.message);
                notify_report_problem(ProblemType.SEND_EMAIL_SAVE_FAILED, err);
                return false;
            }
        }

        // Remove from database ... can't use remove_email_async()
        // because this runs even if the outbox is closed as a
        // Geary.Folder. Again, don't observe the cancellable here -
        // if it's been send and saved we want to try to remove it
        // anyway.
        debug("Outbox postman: Deleting row %s", row.outbox_id.to_string());
        Gee.ArrayList<SmtpOutboxEmailIdentifier> list = new Gee.ArrayList<SmtpOutboxEmailIdentifier>();
        list.add(row.outbox_id);
        yield internal_remove_email_async(list, null);

        return true;
    }

    private void stop_postman() {
        debug("Stopping outbox postman");
        Cancellable? old_cancellable = this.queue_cancellable;
        if (old_cancellable != null) {
            old_cancellable.cancel();
        }
    }

    // Fill the send queue with existing mail (if any)
    private async void fill_outbox_queue() {
        debug("Filling outbox queue");
        try {
            Gee.ArrayList<OutboxRow> list = new Gee.ArrayList<OutboxRow>();
            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, ordering, message
                    FROM SmtpOutboxTable
                    ORDER BY ordering
                """);

                Db.Result results = stmt.exec(cancellable);
                int position = 1;
                while (!results.finished) {
                    list.add(new OutboxRow(results.rowid_at(0), position++, results.int64_at(1),
                        false, results.string_buffer_at(2)));
                    results.next(cancellable);
                }

                return Db.TransactionOutcome.DONE;
            }, null);

            if (list.size > 0) {
                // set properties now (can't do yield in ctor)
                _properties.set_total(list.size);

                debug("Priming outbox postman with %d stored messages", list.size);
                foreach (OutboxRow row in list)
                    outbox_queue.send(row);
            }
        } catch (Error prime_err) {
            warning("Error priming outbox: %s", prime_err.message);
        }
    }

    // Utility for getting an email object back from an outbox row.
    private Geary.Email row_to_email(OutboxRow row) throws Error {
        RFC822.Message message = new RFC822.Message.from_buffer(row.message);

        Geary.Email email = message.get_email(row.outbox_id);
        // TODO: Determine message's total size (header + body) to store in Properties.
        email.set_email_properties(new SmtpOutboxEmailProperties(new DateTime.now_local(), -1));
        Geary.EmailFlags flags = new Geary.EmailFlags();
        if (row.sent)
            flags.add(Geary.EmailFlags.OUTBOX_SENT);
        email.set_flags(flags);

        return email;
    }

    private async bool is_unsent_async(int64 ordering, Cancellable? cancellable) throws Error {
        bool exists = false;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare(
                "SELECT 1 FROM SmtpOutboxTable WHERE ordering=? AND sent = 0");
            stmt.bind_int64(0, ordering);

            exists = !stmt.exec(cancellable).finished;

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return exists;
    }

    private async void send_email_async(Geary.RFC822.Message rfc822, Cancellable? cancellable)
        throws Error {
        AccountInformation account = this._account.information;
        Smtp.ClientSession smtp = new Geary.Smtp.ClientSession(this.smtp_endpoint);

        sending_monitor.notify_start();

        Error? smtp_err = null;
        try {
            yield smtp.login_async(account.get_smtp_credentials(), cancellable);
        } catch (Error login_err) {
            debug("SMTP login error: %s", login_err.message);
            smtp_err = login_err;
        }

        if (smtp_err == null) {
            try {
                yield smtp.send_email_async(
                    account.primary_mailbox,
                    rfc822,
                    cancellable
                );
            } catch (Error send_err) {
                debug("SMTP send mail error: %s", send_err.message);
                smtp_err = send_err;
            }
        }

        try {
            // always logout
            yield smtp.logout_async(false, null);
        } catch (Error err) {
            debug("Unable to disconnect from SMTP server %s: %s", smtp.to_string(), err.message);
        }

        sending_monitor.notify_finish();

        if (smtp_err != null)
            throw smtp_err;

        email_sent(rfc822);
    }

    private async void mark_email_as_sent_async(SmtpOutboxEmailIdentifier outbox_id,
        Cancellable? cancellable = null) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            do_mark_email_as_sent(cx, outbox_id, cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.OUTBOX_SENT);

        Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> changed_map
            = new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>();
        changed_map.set(outbox_id, flags);
        notify_email_flags_changed(changed_map);
    }

    private async void save_sent_mail_async(Geary.RFC822.Message rfc822, Cancellable? cancellable)
        throws Error {
        Geary.FolderSupport.Create? create = (yield _account.get_required_special_folder_async(
            Geary.SpecialFolderType.SENT, cancellable)) as Geary.FolderSupport.Create;
        if (create == null)
            throw new EngineError.NOT_FOUND("Save sent mail enabled, but no writable sent mail folder");

        bool open = false;
        try {
            yield create.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
            open = true;
            yield create.create_email_async(rfc822, null, null, null, cancellable);
        } finally {
            if (open) {
                try {
                    yield create.close_async();
                } catch (Error e) {
                    debug("Error closing folder %s: %s", create.to_string(), e.message);
                }
            }
        }
    }

    private async int get_email_count_async(Cancellable? cancellable) throws Error {
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_email_count(cx, cancellable);

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return count;
    }

    // Like remove_email_async(), but can be called even when the folder isn't open
    private async bool internal_remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable) throws Error {
        Gee.List<Geary.EmailIdentifier> removed = new Gee.ArrayList<Geary.EmailIdentifier>();
        int final_count = 0;
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            foreach (Geary.EmailIdentifier id in email_ids) {
                // ignore anything not belonging to the outbox, but also don't report it as removed
                // either
                SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
                if (outbox_id == null)
                    continue;

                // Even though we discard the new value here, this check must
                // occur before any insert/delete on the table, to ensure we
                // never reuse an ordering value while Geary is running.
                do_get_next_ordering(cx, cancellable);

                if (do_remove_email(cx, outbox_id, cancellable))
                    removed.add(outbox_id);
            }

            final_count = do_get_email_count(cx, cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        if (removed.size == 0)
            return false;

        _properties.set_total(final_count);

        notify_email_removed(removed);
        notify_email_count_changed(final_count, CountChangeReason.REMOVED);

        return true;
    }

    //
    // Transaction helper methods
    //

    private int64 do_get_next_ordering(Db.Connection cx, Cancellable? cancellable) throws Error {
        lock (next_ordering) {
            if (next_ordering == 0) {
                Db.Statement stmt = cx.prepare("SELECT COALESCE(MAX(ordering), 0) + 1 FROM SmtpOutboxTable");

                Db.Result result = stmt.exec(cancellable);
                if (!result.finished)
                    next_ordering = result.int64_at(0);

                assert(next_ordering > 0);
            }

            return next_ordering++;
        }
    }

    private int do_get_email_count(Db.Connection cx, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT COUNT(*) FROM SmtpOutboxTable");

        Db.Result results = stmt.exec(cancellable);

        return (!results.finished) ? results.int_at(0) : 0;
    }

    private int do_get_position_by_ordering(Db.Connection cx, int64 ordering, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*), MAX(ordering) FROM SmtpOutboxTable WHERE ordering <= ? ORDER BY ordering ASC");
        stmt.bind_int64(0, ordering);

        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return -1;

        // without the MAX it's possible to overshoot, so the MAX(ordering) *must* match the argument
        if (results.int64_at(1) != ordering)
            return -1;

        return results.int_at(0) + 1;
    }

    private OutboxRow? do_fetch_row_by_ordering(Db.Connection cx, int64 ordering, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT id, message, sent
            FROM SmtpOutboxTable
            WHERE ordering=?
        """);
        stmt.bind_int64(0, ordering);

        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;

        int position = do_get_position_by_ordering(cx, ordering, cancellable);
        if (position < 1)
            return null;

        return new OutboxRow(results.rowid_at(0), position, ordering, results.bool_at(2),
            results.string_buffer_at(1));
    }

    private void do_mark_email_as_sent(Db.Connection cx, SmtpOutboxEmailIdentifier id, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("UPDATE SmtpOutboxTable SET sent = 1 WHERE ordering = ?");
        stmt.bind_int64(0, id.ordering);

        stmt.exec(cancellable);
    }

    private bool do_remove_email(Db.Connection cx, SmtpOutboxEmailIdentifier id, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("DELETE FROM SmtpOutboxTable WHERE ordering=?");
        stmt.bind_int64(0, id.ordering);

        return stmt.exec_get_modified(cancellable) > 0;
    }

    private void notify_report_problem(ProblemType problem, Error? err) {
        report_problem(
            new ServiceProblemReport(
                problem,
                this._account.information,
                this.account.information.smtp,
                err
            )
        );
    }

    private void on_account_opened() {
        this.fill_outbox_queue.begin();
        this.smtp_endpoint.connectivity.notify["is-reachable"].connect(on_reachable_changed);
        this.smtp_endpoint.connectivity.address_error_reported.connect(on_connectivity_error);
        if (this.smtp_endpoint.connectivity.is_reachable.is_certain()) {
            this.start_timer.start();
        } else {
            this.smtp_endpoint.connectivity.check_reachable.begin();
        }
    }

    private void on_account_closed() {
        this.start_timer.reset();
        this.stop_postman();
        this.smtp_endpoint.connectivity.notify["is-reachable"].disconnect(on_reachable_changed);
        this.smtp_endpoint.connectivity.address_error_reported.disconnect(on_connectivity_error);
    }

    private void on_reachable_changed() {
        if (this.smtp_endpoint.connectivity.is_reachable.is_certain()) {
            if (this.queue_cancellable == null) {
                this.start_timer.start();
            }
        } else {
            this.start_timer.reset();
            stop_postman();
        }
    }

    private void on_connectivity_error(Error error) {
        stop_postman();
        notify_report_problem(ProblemType.CONNECTION_ERROR, error);
    }

}
