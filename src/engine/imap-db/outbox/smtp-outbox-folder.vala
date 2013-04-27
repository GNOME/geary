/* Copyright 2011-2013 Yorba Foundation
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
private class Geary.SmtpOutboxFolder : Geary.AbstractFolder, Geary.FolderSupport.Remove,
    Geary.FolderSupport.Create {
    private class OutboxRow {
        public int64 id;
        public int position;
        public int64 ordering;
        public string? message;
        public SmtpOutboxEmailIdentifier outbox_id;
        
        public OutboxRow(int64 id, int position, int64 ordering, string? message) {
            assert(position >= 1);
            
            this.id = id;
            this.position = position;
            this.ordering = ordering;
            this.message = message;
            
            outbox_id = new SmtpOutboxEmailIdentifier(ordering);
        }
    }
    
    public signal void report_problem(Geary.Account.Problem problem, Error? err);
    
    // Min and max times between attempting to re-send after a connection failure.
    private const uint MIN_SEND_RETRY_INTERVAL_SEC = 4;
    private const uint MAX_SEND_RETRY_INTERVAL_SEC = 64;

    private static FolderRoot? path = null;
    
    private ImapDB.Database db;
    private weak Account _account;
    private Geary.Smtp.ClientSession smtp;
    private int open_count = 0;
    private Nonblocking.Mailbox<OutboxRow> outbox_queue = new Nonblocking.Mailbox<OutboxRow>();
    private SmtpOutboxFolderProperties properties = new SmtpOutboxFolderProperties(0, 0);
    
    public override Account account { get { return _account; } }
    
    // Requires the Database from the get-go because it runs a background task that access it
    // whether open or not
    public SmtpOutboxFolder(ImapDB.Database db, Account account) {
        this.db = db;
        _account = account;
        
        smtp = new Geary.Smtp.ClientSession(_account.information.get_smtp_endpoint());
        
        do_postman_async.begin();
    }
    
    // Used solely for debugging, hence "(no subject)" not marked for translation
    private static string message_subject(RFC822.Message message) {
        return (message.subject != null && !String.is_empty(message.subject.to_string()))
            ? message.subject.to_string() : "(no subject)";
    }
    
    // TODO: Use Cancellable to shut down outbox processor when closing account
    private async void do_postman_async() {
        debug("Starting outbox postman");
        uint send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;
        
        // Fill the send queue with existing mail (if any)
        try {
            Gee.ArrayList<OutboxRow> list = new Gee.ArrayList<OutboxRow>();
            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                Db.Statement stmt = cx.prepare(
                    "SELECT id, ordering, message FROM SmtpOutboxTable ORDER BY ordering");
                
                Db.Result results = stmt.exec(cancellable);
                int position = 1;
                while (!results.finished) {
                    list.add(new OutboxRow(results.rowid_at(0), position++, results.int64_at(1),
                        results.string_at(2)));
                    results.next(cancellable);
                }
                
                return Db.TransactionOutcome.DONE;
            }, null);
            
            if (list.size > 0) {
                // set properties now (can't do yield in ctor)
                properties.set_total(list.size);
                
                debug("Priming outbox postman with %d stored messages", list.size);
                foreach (OutboxRow row in list)
                    outbox_queue.send(row);
            }
        } catch (Error prime_err) {
            warning("Error priming outbox: %s", prime_err.message);
        }
        
        // Start the send queue.
        for (;;) {
            // yield until a message is ready
            OutboxRow row;
            try {
                row = yield outbox_queue.recv_async();
            } catch (Error wait_err) {
                debug("Outbox postman queue error: %s", wait_err.message);
                
                break;
            }
            
            // Convert row into RFC822 message suitable for sending or framing
            RFC822.Message message;
            try {
                message = new RFC822.Message.from_string(row.message);
            } catch (RFC822Error msg_err) {
                // TODO: This needs to be reported to the user
                debug("Outbox postman message error: %s", msg_err.message);
                
                continue;
            }
            
            // Send the message, but only remove from database once sent
            try {
                debug("Outbox postman: Sending \"%s\" (ID:%s)...", message_subject(message),
                    row.outbox_id.to_string());
                yield send_email_async(message, null);
            } catch (Error send_err) {
                debug("Outbox postman send error, retrying: %s", send_err.message);
                
                outbox_queue.send(row);
                
                if (send_err is SmtpError.AUTHENTICATION_FAILED) {
                    bool report = true;
                    try {
                        if (yield _account.information.fetch_passwords_async(
                            CredentialsMediator.ServiceFlag.SMTP))
                            report = false;
                    } catch (Error e) {
                        debug("Error prompting for IMAP password: %s", e.message);
                    }
                    
                    if (report)
                        report_problem(Geary.Account.Problem.SEND_EMAIL_LOGIN_FAILED, send_err);
                }
                
                // Take a brief nap before continuing to allow connection problems to resolve.
                yield Geary.Scheduler.sleep_async(send_retry_seconds);
                send_retry_seconds *= 2;
                send_retry_seconds = Geary.Numeric.uint_ceiling(send_retry_seconds, MAX_SEND_RETRY_INTERVAL_SEC);

                continue;
            }
            
            // Remove from database ... can't use remove_email_async() because this runs even if
            // the outbox is closed as a Geary.Folder.
            try {
                debug("Outbox postman: Removing \"%s\" (ID:%s) from database", message_subject(message),
                    row.outbox_id.to_string());
                Gee.ArrayList<SmtpOutboxEmailIdentifier> list = new Gee.ArrayList<SmtpOutboxEmailIdentifier>();
                list.add(row.outbox_id);
                yield internal_remove_email_async(list, null);
            } catch (Error rm_err) {
                debug("Outbox postman: Unable to remove row from database: %s", rm_err.message);
            }
            
            // update properties
            try {
                properties.set_total(yield get_email_count_async(null));
            } catch (Error err) {
                debug("Outbox postman: Unable to fetch updated email count for properties: %s",
                    err.message);
            }
            
            // If we got this far the send was successful, so reset the send retry interval.
            send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;
        }
        
        debug("Exiting outbox postman");
    }
    
    public override Geary.FolderPath get_path() {
        if (path == null)
            path = new SmtpOutboxFolderRoot();
        
        return path;
    }
    
    public override Geary.FolderProperties get_properties() {
        return properties;
    }
    
    public override Geary.SpecialFolderType get_special_folder_type() {
        return Geary.SpecialFolderType.OUTBOX;
    }
    
    public override Geary.Folder.OpenState get_open_state() {
        return open_count > 0 ? Geary.Folder.OpenState.LOCAL : Geary.Folder.OpenState.CLOSED;
    }
    
    private void check_open() throws EngineError {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("%s not open", to_string());
    }
    
    public override async void wait_for_open_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("Outbox not open");
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0)
            return;
        
        notify_opened(Geary.Folder.OpenState.LOCAL, properties.email_total);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || --open_count > 0)
            return;
        
        notify_closed(Geary.Folder.CloseReason.LOCAL_CLOSE);
        notify_closed(Geary.Folder.CloseReason.FOLDER_CLOSED);
    }
    
    private async int get_email_count_async(Cancellable? cancellable) throws Error {
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_email_count(cx, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return count;
    }
    
    // create_email_async() requires the Outbox be open according to contract, but enqueuing emails
    // for background delivery can happen at any time, so this is the mechanism to do so.
    // email_count is the number of emails in the Outbox after enqueueing the message.
    public async SmtpOutboxEmailIdentifier enqueue_email_async(Geary.RFC822.Message rfc822,
        Cancellable? cancellable) throws Error {
        int email_count = 0;
        OutboxRow? row = null;
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            Db.Statement stmt = cx.prepare(
                "INSERT INTO SmtpOutboxTable (message, ordering)"
                + "VALUES (?, (SELECT COALESCE(MAX(ordering), 0) + 1 FROM SmtpOutboxTable))");
            stmt.bind_string(0, rfc822.get_body_rfc822_buffer().to_string());
            
            int64 id = stmt.exec_insert(cancellable);
            
            stmt = cx.prepare("SELECT ordering, message FROM SmtpOutboxTable WHERE id=?");
            stmt.bind_rowid(0, id);
            
            // This has got to work; Db should throw an exception if the INSERT failed
            Db.Result results = stmt.exec(cancellable);
            assert(!results.finished);
            
            int64 ordering = results.int64_at(0);
            string message = results.string_at(1);
            
            int position = do_get_position_by_ordering(cx, ordering, cancellable);
            
            row = new OutboxRow(id, position, ordering, message);
            email_count = do_get_email_count(cx, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        // should have thrown an error if this failed
        assert(row != null);
        
        // update properties
        properties.set_total(yield get_email_count_async(cancellable));
        
        // immediately add to outbox queue for delivery
        outbox_queue.send(row);
        
        // notify only if opened
        if (open_count > 0) {
            Gee.List<SmtpOutboxEmailIdentifier> list = new Gee.ArrayList<SmtpOutboxEmailIdentifier>();
            list.add(row.outbox_id);
            
            notify_email_appended(list);
            notify_email_count_changed(email_count, CountChangeReason.ADDED);
        }
        
        return row.outbox_id;
    }
    
    public virtual async Geary.FolderSupport.Create.Result create_email_async(Geary.RFC822.Message rfc822,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        yield enqueue_email_async(rfc822, cancellable);
        
        return FolderSupport.Create.Result.CREATED;
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Gee.List<Geary.Email>? list = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Geary.Folder.normalize_span_specifiers(ref low, ref count,
                do_get_email_count(cx, cancellable));
            
            if (count == 0)
                return Db.TransactionOutcome.DONE;
            
            Db.Statement stmt = cx.prepare(
                "SELECT id, ordering, message FROM SmtpOutboxTable ORDER BY ordering LIMIT ? OFFSET ?");
            stmt.bind_int(0, count);
            stmt.bind_int(1, low - 1);
            
            Db.Result results = stmt.exec(cancellable);
            if (results.finished)
                return Db.TransactionOutcome.DONE;
            
            list = new Gee.ArrayList<Geary.Email>();
            int position = low;
            do {
                list.add(row_to_email(new OutboxRow(results.rowid_at(0), position++, results.int64_at(1),
                    results.string_at(2))));
            } while (results.next());
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return list;
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(
        Geary.EmailIdentifier initial_id, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        check_open();
        
        SmtpOutboxEmailIdentifier? id = initial_id as SmtpOutboxEmailIdentifier;
        if (id == null) {
            throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not for Outbox",
                initial_id.to_string());
        }
        
        Gee.List<Geary.Email>? list = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = int.min(count, do_get_email_count(cx, cancellable));
            
            Db.Statement stmt = cx.prepare(
                "SELECT id, ordering, message FROM SmtpOutboxTable WHERE ordering >= ? "
                + "ORDER BY ordering LIMIT ?");
            stmt.bind_int64(0,
                flags.is_all_set(Folder.ListFlags.EXCLUDING_ID) ? id.ordering + 1 : id.ordering);
            stmt.bind_int(1, count);
            
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
                
                list.add(row_to_email(new OutboxRow(results.rowid_at(0), position++, ordering,
                    results.string_at(2))));
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
    
    public virtual async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids, 
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        yield internal_remove_email_async(email_ids, cancellable);
    }
    
    // Like remove_email_async(), but can be called even when the folder isn't open
    private async bool internal_remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable) throws Error {
        Gee.List<Geary.EmailIdentifier> removed = new Gee.ArrayList<Geary.EmailIdentifier>();
        int final_count = 0;
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            foreach (Geary.EmailIdentifier id in email_ids) {
                SmtpOutboxEmailIdentifier? outbox_id = id as SmtpOutboxEmailIdentifier;
                if (outbox_id == null)
                    throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());
                
                if (do_remove_email(cx, outbox_id, cancellable))
                    removed.add(outbox_id);
            }
            
            final_count = do_get_email_count(cx, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        if (removed.size == 0)
            return false;
        
        // notify only if opened
        if (open_count > 0) {
            notify_email_removed(removed);
            notify_email_count_changed(final_count, CountChangeReason.REMOVED);
        }
        
        return true;
    }
    
    public virtual async void remove_single_email_async(Geary.EmailIdentifier id,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        list.add(id);
        
        yield remove_email_async(list, cancellable);
    }
    
    // Utility for getting an email object back from an outbox row.
    private Geary.Email row_to_email(OutboxRow row) throws Error {
        RFC822.Message message = new RFC822.Message.from_string(row.message);
        
        Geary.Email email = message.get_email(row.position, row.outbox_id);
        // TODO: Determine message's total size (header + body) to store in Properties.
        email.set_email_properties(new SmtpOutboxEmailProperties(new DateTime.now_local(), -1));
        email.set_flags(new Geary.EmailFlags());
        
        return email;
    }
    
    private async void send_email_async(Geary.RFC822.Message rfc822, Cancellable? cancellable)
        throws Error {
        Error? smtp_err = null;
        
        try {
            yield smtp.login_async(_account.information.smtp_credentials, cancellable);
        } catch (Error login_err) {
            debug("SMTP login error: %s", login_err.message);
            smtp_err = login_err;
        }
        
        if (smtp_err == null) {
            try {
                yield smtp.send_email_async(_account.information.get_mailbox_address(),
                    rfc822, cancellable);
            } catch (Error send_err) {
                debug("SMTP send mail error: %s", send_err.message);
                smtp_err = send_err;
            }
        }
        
        // always logout
        try {
            yield smtp.logout_async(cancellable);
        } catch (Error err) {
            debug("Unable to disconnect from SMTP server %s: %s", smtp.to_string(), err.message);
        }
        
        if (smtp_err != null)
            throw smtp_err;
    }
    
    //
    // Transaction helper methods
    //
    
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
        Db.Statement stmt = cx.prepare(
            "SELECT id, message FROM SmtpOutboxTable WHERE ordering=?");
        stmt.bind_int64(0, ordering);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;
        
        int position = do_get_position_by_ordering(cx, ordering, cancellable);
        if (position < 1)
            return null;
        
        return new OutboxRow(results.rowid_at(0), position, ordering, results.string_at(1));
    }
    
    private bool do_remove_email(Db.Connection cx, SmtpOutboxEmailIdentifier id, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("DELETE FROM SmtpOutboxTable WHERE ordering=?");
        stmt.bind_int64(0, id.ordering);
        
        return stmt.exec_get_modified(cancellable) > 0;
    }
}

