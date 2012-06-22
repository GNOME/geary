/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.SmtpOutboxFolderRoot : Geary.FolderRoot {
    public const string MAGIC_BASENAME = "$GearyOutbox$";
    
    public SmtpOutboxFolderRoot() {
        base(MAGIC_BASENAME, null, false);
    }
}

// Special type of folder that runs an asynchronous send queue.  Messages are
// saved to the database, then queued up for sending.
private class Geary.SmtpOutboxFolder : Geary.AbstractFolder {
    private static FolderRoot? path = null;
    
    private Geary.Sqlite.SmtpOutboxTable local_folder;
    private Imap.Account remote;
    private Sqlite.Database db;
    private bool opened = false;
    private NonblockingMailbox<Geary.Sqlite.SmtpOutboxRow> outbox_queue = 
        new NonblockingMailbox<Geary.Sqlite.SmtpOutboxRow>();
    
    public SmtpOutboxFolder(Imap.Account remote, Geary.Sqlite.SmtpOutboxTable table) {
        this.remote = remote;
        this.local_folder = table;
        db = table.gdb;
        
        do_postman_async.begin();
    }
    
    private string message_subject(RFC822.Message message) {
        return (message.subject != null && !String.is_empty(message.subject.to_string()))
            ? message.subject.to_string() : "(no subject)";
    }
    
    // TODO: Use Cancellable to shut down outbox processor when closing account
    private async void do_postman_async() {
        debug("Starting outbox postman");
        
        // Fill the send queue with existing mail (if any)
        try {
            Gee.List<Geary.Sqlite.SmtpOutboxRow>? row_list = yield local_folder.list_email_async(
               null, new OutboxEmailIdentifier(-1), -1, null);
            if (row_list != null && row_list.size > 0) {
                debug("Priming outbox postman with %d stored messages", row_list.size);
                foreach (Geary.Sqlite.SmtpOutboxRow row in row_list)
                    outbox_queue.send(row);
            }
        } catch (Error prime_err) {
            warning("Error priming outbox: %s", prime_err.message);
        }
        
        // Start the send queue.
        for (;;) {
            // yield until a message is ready
            Geary.Sqlite.SmtpOutboxRow row;
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
                debug("Outbox postman: Sending \"%s\" (ID:%s)...", message_subject(message), row.to_string());
                yield remote.send_email_async(message);
            } catch (Error send_err) {
                debug("Outbox postman send error, retrying: %s", send_err.message);
                
                try {
                    outbox_queue.send(row);
                } catch (Error send_err) {
                    debug("Outbox postman: Unable to re-send row to outbox, dropping on floor: %s", send_err.message);
                }
                
                continue;
            }
            
            // Remove from database
            try {
                debug("Outbox postman: Removing \"%s\" (ID:%s) from database", message_subject(message),
                    row.to_string());
                yield remove_single_email_async(new OutboxEmailIdentifier(row.ordering));
            } catch (Error rm_err) {
                debug("Outbox postman: Unable to remove row from database: %s", rm_err.message);
            }
        }
        
        debug("Exiting outbox postman");
    }
    
    public override Geary.FolderPath get_path() {
        if (path == null)
            path = new SmtpOutboxFolderRoot();
        
        return path;
    }
    
    public override Geary.Trillian has_children() {
        return Geary.Trillian.FALSE;
    }
    
    public override Geary.SpecialFolderType get_special_folder_type() {
        return Geary.SpecialFolderType.OUTBOX;
    }
    
    public override Geary.Folder.OpenState get_open_state() {
        return opened ? Geary.Folder.OpenState.LOCAL : Geary.Folder.OpenState.CLOSED;
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null)
        throws Error {
        if (opened)
            throw new EngineError.ALREADY_OPEN("Folder %s already open", to_string());
        
        opened = true;
        notify_opened(Geary.Folder.OpenState.LOCAL, yield get_email_count_async(cancellable));
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        opened = false;
        notify_closed(Geary.Folder.CloseReason.LOCAL_CLOSE);
        notify_closed(Geary.Folder.CloseReason.FOLDER_CLOSED);
    }
    
    public override async int get_email_count_async(Cancellable? cancellable = null) throws Error {
        return yield internal_get_email_count_async(null, cancellable);
    }
    
    private async int internal_get_email_count_async(Sqlite.Transaction? transaction, Cancellable? cancellable)
        throws Error {
        return yield local_folder.get_email_count_async(transaction, cancellable);
    }
    
    public override async bool create_email_async(Geary.RFC822.Message rfc822,
        Cancellable? cancellable = null) throws Error {
        Sqlite.Transaction transaction = yield db.begin_transaction_async("Outbox.create_email_async",
            cancellable);
        
        Geary.Sqlite.SmtpOutboxRow row = yield local_folder.create_async(transaction,
            rfc822.get_body_rfc822_buffer().to_string(), cancellable);
        
        int count = yield internal_get_email_count_async(transaction, cancellable);
        
        // signal message added before adding for delivery
        Gee.List<OutboxEmailIdentifier> list = new Gee.ArrayList<OutboxEmailIdentifier>();
        list.add(new OutboxEmailIdentifier(row.ordering));
        notify_email_appended(list);
        notify_email_count_changed(count, CountChangeReason.ADDED);
        
        // immediately add to outbox queue for delivery
        outbox_queue.send(row);
        
        return true;
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        return yield list_email_by_id_async(new OutboxEmailIdentifier(low), count,
            required_fields, flags, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(
        Geary.EmailIdentifier initial_id, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        
        OutboxEmailIdentifier? id = initial_id as OutboxEmailIdentifier;
        assert(id != null);
        
        Sqlite.Transaction transaction = yield db.begin_transaction_async("Outbox.list_email_by_id_async",
            cancellable);
        
        Gee.List<Geary.Sqlite.SmtpOutboxRow>? row_list = yield local_folder.list_email_async(
           transaction, id, count, cancellable);
        if (row_list == null || row_list.size == 0)
            return null;
        
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        foreach (Geary.Sqlite.SmtpOutboxRow row in row_list) {
            int position = yield row.get_position_async(transaction, cancellable);
            list.add(outbox_email_for_row(row, position));
        }
        
        return list;
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> _ids, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        Gee.List<OutboxEmailIdentifier> ids = new Gee.ArrayList<OutboxEmailIdentifier>();
        foreach (Geary.EmailIdentifier id in _ids) {
            assert(id is OutboxEmailIdentifier);
            ids.add((OutboxEmailIdentifier) id);
        }
        
        Sqlite.Transaction transaction = yield db.begin_transaction_async("Outbox.list_email_by_sparse_id_async",
            cancellable);
        
        Gee.List<Geary.Sqlite.SmtpOutboxRow>? row_list = yield local_folder.
            list_email_by_sparse_id_async(transaction, ids, cancellable);
        if (row_list == null || row_list.size == 0)
            return null;
        
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        foreach (Geary.Sqlite.SmtpOutboxRow row in row_list) {
            int position = yield row.get_position_async(transaction, cancellable);
            list.add(outbox_email_for_row(row, position));
        }
        
        return list;
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? 
        list_local_email_fields_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable = null) throws Error {
        // Not implemented.
        return null;
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier _id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        OutboxEmailIdentifier? id = _id as OutboxEmailIdentifier;
        assert(id != null);
        
        Sqlite.Transaction transaction = yield db.begin_transaction_async("Outbox.fetch_email_async",
            cancellable);
        
        Geary.Sqlite.SmtpOutboxRow? row = yield local_folder.fetch_email_async(transaction, id);
        if (row == null)
            throw new EngineError.NOT_FOUND("No message with ID %lld found in database", row.ordering);
        
        int position = yield row.get_position_async(transaction, cancellable);
        
        return outbox_email_for_row(row, position);
    }
    
    public override async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids, 
        Cancellable? cancellable = null) throws Error {
        foreach (Geary.EmailIdentifier id in email_ids)
            remove_single_email_async(id, cancellable);
    }
    
    public override async void remove_single_email_async(Geary.EmailIdentifier _id,
        Cancellable? cancellable = null) throws Error {
        OutboxEmailIdentifier? id = _id as OutboxEmailIdentifier;
        assert(id != null);
        
        Sqlite.Transaction transaction = yield db.begin_transaction_async("Outbox.remove_single_email_async",
            cancellable);
        
        yield local_folder.remove_single_email_async(transaction, id, cancellable);
        
        int count = yield internal_get_email_count_async(transaction, cancellable);
        
        Gee.ArrayList<OutboxEmailIdentifier> list = new Gee.ArrayList<OutboxEmailIdentifier>();
        list.add(id);
        notify_email_removed(list);
        notify_email_count_changed(count, CountChangeReason.REMOVED);
    }
    
    public override async void mark_email_async(
        Gee.List<Geary.EmailIdentifier> to_mark, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable = null) throws Error {
        // Not implemented.
    }
    
    // Utility for getting an email object back from an outbox row.
    private Geary.Email outbox_email_for_row(Geary.Sqlite.SmtpOutboxRow row, int position) throws Error {
        RFC822.Message message = new RFC822.Message.from_string(row.message);
        
        Geary.Email email = message.get_email(position, new OutboxEmailIdentifier(row.ordering));
        email.set_email_properties(new OutboxEmailProperties());
        email.set_flags(new Geary.EmailFlags());
        
        return email;
    }
    
    public override async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        // Not implemented.
    }

    public override async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        // Not implemented.
    }
}

