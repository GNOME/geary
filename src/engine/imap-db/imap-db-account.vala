/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Account : BaseObject {
    private class FolderReference : Geary.SmartReference {
        public Geary.FolderPath path;
        
        public FolderReference(ImapDB.Folder folder, Geary.FolderPath path) {
            base (folder);
            
            this.path = path;
        }
    }
    
    private class SearchOffset {
        public int column;      // Column in search table
        public int byte_offset; // Offset (in bytes) of search term in string
        public int size;        // Size (in bytes) of the search term in string
        
        public SearchOffset(string[] offset_string) {
            column = int.parse(offset_string[0]);
            byte_offset = int.parse(offset_string[2]);
            size = int.parse(offset_string[3]);
        }
    }
    
    public signal void email_sent(Geary.RFC822.Message rfc822);
    
    // Only available when the Account is opened
    public SmtpOutboxFolder? outbox { get; private set; default = null; }
    public SearchFolder? search_folder { get; private set; default = null; }
    public ImapEngine.ContactStore contact_store { get; private set; }
    public IntervalProgressMonitor search_index_monitor { get; private set; 
        default = new IntervalProgressMonitor(ProgressType.SEARCH_INDEX, 0, 0); }
    public SimpleProgressMonitor upgrade_monitor { get; private set; default = new SimpleProgressMonitor(
        ProgressType.DB_UPGRADE); }
    public SimpleProgressMonitor sending_monitor { get; private set;
        default = new SimpleProgressMonitor(ProgressType.ACTIVITY); }
    
    private string name;
    private AccountInformation account_information;
    private ImapDB.Database? db = null;
    private Gee.HashMap<Geary.FolderPath, FolderReference> folder_refs =
        new Gee.HashMap<Geary.FolderPath, FolderReference>();
    private Cancellable? background_cancellable = null;
    
    public Account(Geary.AccountInformation account_information) {
        this.account_information = account_information;
        contact_store = new ImapEngine.ContactStore(this);
        
        name = "IMAP database account for %s".printf(account_information.imap_credentials.user);
    }
    
    private void check_open() throws Error {
        if (db == null)
            throw new EngineError.OPEN_REQUIRED("Database not open");
    }
    
    public static void get_imap_db_storage_locations(File user_data_dir, out File db_file,
        out File attachments_dir) {
        db_file = ImapDB.Database.get_db_file(user_data_dir);
        attachments_dir = ImapDB.Attachment.get_attachments_dir(user_data_dir);
    }
    
    public async void open_async(File user_data_dir, File schema_dir, Cancellable? cancellable)
        throws Error {
        if (db != null)
            throw new EngineError.ALREADY_OPEN("IMAP database already open");
        
        db = new ImapDB.Database(user_data_dir, schema_dir, upgrade_monitor, account_information.email);
        
        try {
            db.open(
                Db.DatabaseFlags.CREATE_DIRECTORY | Db.DatabaseFlags.CREATE_FILE | Db.DatabaseFlags.CHECK_CORRUPTION,
                null, cancellable);
        } catch (Error err) {
            warning("Unable to open database: %s", err.message);
            
            // close database before exiting
            db = null;
            
            throw err;
        }
        
        // have seen cases where multiple "Inbox" folders are created in the root with different
        // case names, leading to trouble ... this clears out all Inboxes that don't match our
        // "canonical" name
        try {
            yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, name
                    FROM FolderTable
                    WHERE parent_id IS NULL
                """);
                
                Db.Result results = stmt.exec(cancellable);
                while (!results.finished) {
                    string name = results.string_for("name");
                    if (Imap.MailboxSpecifier.is_inbox_name(name)
                        && !Imap.MailboxSpecifier.is_canonical_inbox_name(name)) {
                        debug("%s: Removing duplicate INBOX \"%s\"", this.name, name);
                        do_delete_folder(cx, results.rowid_for("id"), cancellable);
                    }
                    
                    results.next(cancellable);
                }
                
                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
        } catch (Error err) {
            debug("Error trimming duplicate INBOX from database: %s", err.message);
            
            // drop database to indicate closed
            db = null;
            
            throw err;
        }
        
        Geary.Account account;
        try {
            account = Geary.Engine.instance.get_account_instance(account_information);
        } catch (Error e) {
            // If they're opening an account, the engine should already be
            // open, and there should be no reason for this to fail.  Thus, if
            // we get here, it's a programmer error.
            
            error("Error finding account from its information: %s", e.message);
        }
        
        background_cancellable = new Cancellable();
        
        // Kick off a background update of the search table.
        populate_search_table_async.begin(background_cancellable);
        
        initialize_contacts(cancellable);
        
        // ImapDB.Account holds the Outbox, which is tied to the database it maintains
        outbox = new SmtpOutboxFolder(db, account, sending_monitor);
        outbox.email_sent.connect(on_outbox_email_sent);
        
        // Search folder
        search_folder = ((ImapEngine.GenericAccount) account).new_search_folder();
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (db == null)
            return;
        
        // close and always drop reference
        try {
            db.close(cancellable);
        } finally {
            db = null;
        }
        
        background_cancellable.cancel();
        background_cancellable = null;
        
        outbox.email_sent.disconnect(on_outbox_email_sent);
        outbox = null;
        search_folder = null;
    }
    
    private void on_outbox_email_sent(Geary.RFC822.Message rfc822) {
        email_sent(rfc822);
    }
    
    public async void clone_folder_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties properties = imap_folder.properties;
        Geary.FolderPath path = imap_folder.path;
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            // get the parent of this folder, creating parents if necessary ... ok if this fails,
            // that just means the folder has no parents
            int64 parent_id = Db.INVALID_ROWID;
            if (!do_fetch_parent_id(cx, path, true, out parent_id, cancellable)) {
                debug("Unable to find parent ID to %s clone folder", path.to_string());
                
                return Db.TransactionOutcome.ROLLBACK;
            }
            
            // create the folder object
            Db.Statement stmt = cx.prepare(
                "INSERT INTO FolderTable (name, parent_id, last_seen_total, last_seen_status_total, "
                + "uid_validity, uid_next, attributes, unread_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
            stmt.bind_string(0, path.basename);
            stmt.bind_rowid(1, parent_id);
            stmt.bind_int(2, Numeric.int_floor(properties.select_examine_messages, 0));
            stmt.bind_int(3, Numeric.int_floor(properties.status_messages, 0));
            stmt.bind_int64(4, (properties.uid_validity != null) ? properties.uid_validity.value
                : Imap.UIDValidity.INVALID);
            stmt.bind_int64(5, (properties.uid_next != null) ? properties.uid_next.value
                : Imap.UID.INVALID);
            stmt.bind_string(6, properties.attrs.serialize());
            stmt.bind_int(7, properties.email_unread);
            
            stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    /**
     * Only updates folder's STATUS message count, attributes, recent, and unseen; UIDVALIDITY and UIDNEXT
     * updated when the folder is SELECT/EXAMINED (see update_folder_select_examine_async()) unless
     * update_uid_info is true.
     */
    public async void update_folder_status_async(Geary.Imap.Folder imap_folder, bool update_uid_info,
        Cancellable? cancellable) throws Error {
        check_open();
        
        Geary.Imap.FolderProperties properties = imap_folder.properties;
        Geary.FolderPath path = imap_folder.path;
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            int64 parent_id;
            if (!do_fetch_parent_id(cx, path, true, out parent_id, cancellable)) {
                debug("Unable to find parent ID of %s to update properties", path.to_string());
                
                return Db.TransactionOutcome.ROLLBACK;
            }
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare(
                    "UPDATE FolderTable SET attributes=?, unread_count=? WHERE parent_id=? AND name=?");
                stmt.bind_string(0, properties.attrs.serialize());
                stmt.bind_int(1, properties.email_unread);
                stmt.bind_rowid(2, parent_id);
                stmt.bind_string(3, path.basename);
            } else {
                stmt = cx.prepare(
                    "UPDATE FolderTable SET attributes=?, unread_count=? WHERE parent_id IS NULL AND name=?");
                stmt.bind_string(0, properties.attrs.serialize());
                stmt.bind_int(1, properties.email_unread);
                stmt.bind_string(2, path.basename);
            }
            
            stmt.exec(cancellable);
            
            if (update_uid_info)
                do_update_uid_info(cx, properties, parent_id, path, cancellable);
            
            if (properties.status_messages >= 0) {
                do_update_last_seen_status_total(cx, parent_id, path.basename, properties.status_messages,
                    cancellable);
            }
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        // update appropriate properties in the local folder
        ImapDB.Folder? db_folder = get_local_folder(path);
        if (db_folder != null) {
            Imap.FolderProperties local_properties = db_folder.get_properties();
            
            local_properties.set_status_unseen(properties.unseen);
            local_properties.recent = properties.recent;
            local_properties.attrs = properties.attrs;
            
            if (update_uid_info) {
                local_properties.uid_validity = properties.uid_validity;
                local_properties.uid_next = properties.uid_next;
            }
            
            if (properties.status_messages >= 0)
                local_properties.set_status_message_count(properties.status_messages, false);
        }
    }
    
    /**
     * Updates folder's SELECT/EXAMINE message count, UIDVALIDITY, UIDNEXT, unseen, and recent.
     * See also update_folder_status_async().
     */
    public async void update_folder_select_examine_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties properties = imap_folder.properties;
        Geary.FolderPath path = imap_folder.path;
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            int64 parent_id;
            if (!do_fetch_parent_id(cx, path, true, out parent_id, cancellable)) {
                debug("Unable to find parent ID of %s to update properties", path.to_string());
                
                return Db.TransactionOutcome.ROLLBACK;
            }
            
            do_update_uid_info(cx, properties, parent_id, path, cancellable);
            
            if (properties.select_examine_messages >= 0) {
                do_update_last_seen_select_examine_total(cx, parent_id, path.basename,
                    properties.select_examine_messages, cancellable);
            }
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        // update appropriate properties in the local folder
        ImapDB.Folder? db_folder = get_local_folder(path);
        if (db_folder != null) {
            Imap.FolderProperties local_properties = db_folder.get_properties();
            
            local_properties.set_status_unseen(properties.unseen);
            local_properties.recent = properties.recent;
            local_properties.uid_validity = properties.uid_validity;
            local_properties.uid_next = properties.uid_next;
            
            if (properties.select_examine_messages >= 0)
                local_properties.set_select_examine_message_count(properties.select_examine_messages);
        }
    }
    
    private void initialize_contacts(Cancellable? cancellable = null) throws Error {
        check_open();
        
        Gee.Collection<Contact> contacts = new Gee.LinkedList<Contact>();
        Db.TransactionOutcome outcome = db.exec_transaction(Db.TransactionType.RO,
            (context) => {
            Db.Statement statement = context.prepare(
                "SELECT email, real_name, highest_importance, normalized_email, flags " +
                "FROM ContactTable");
            
            Db.Result result = statement.exec(cancellable);
            while (!result.finished) {
                try {
                    Contact contact = new Contact(result.string_at(0), result.string_at(1),
                        result.int_at(2), result.string_at(3), ContactFlags.deserialize(result.string_at(4)));
                    contacts.add(contact);
                } catch (Geary.DatabaseError err) {
                    // We don't want to abandon loading all contacts just because there was a
                    // problem with one.
                    debug("Problem loading contact: %s", err.message);
                }
                
                result.next();
            }
                
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (outcome == Db.TransactionOutcome.DONE)
            contact_store.update_contacts(contacts);
    }
    
    public async Gee.Collection<Geary.ImapDB.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO: A better solution here would be to only pull the FolderProperties if the Folder
        // object itself doesn't already exist
        Gee.HashMap<Geary.FolderPath, int64?> id_map = new Gee.HashMap<
            Geary.FolderPath, int64?>();
        Gee.HashMap<Geary.FolderPath, Geary.Imap.FolderProperties> prop_map = new Gee.HashMap<
            Geary.FolderPath, Geary.Imap.FolderProperties>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            int64 parent_id = Db.INVALID_ROWID;
            if (parent != null) {
                if (!do_fetch_folder_id(cx, parent, false, out parent_id, cancellable)) {
                    debug("Unable to find folder ID for %s to list folders", parent.to_string());
                    
                    return Db.TransactionOutcome.ROLLBACK;
                }
                
                if (parent_id == Db.INVALID_ROWID)
                    throw new EngineError.NOT_FOUND("Folder %s not found", parent.to_string());
            }
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare(
                    "SELECT id, name, last_seen_total, unread_count, last_seen_status_total, "
                    + "uid_validity, uid_next, attributes FROM FolderTable WHERE parent_id=?");
                stmt.bind_rowid(0, parent_id);
            } else {
                stmt = cx.prepare(
                    "SELECT id, name, last_seen_total, unread_count, last_seen_status_total, "
                    + "uid_validity, uid_next, attributes FROM FolderTable WHERE parent_id IS NULL");
            }
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                string basename = result.string_for("name");
                
                // ignore anything that's not canonical Inbox
                if (parent == null
                    && Imap.MailboxSpecifier.is_inbox_name(basename)
                    && !Imap.MailboxSpecifier.is_canonical_inbox_name(basename)) {
                    result.next(cancellable);
                    
                    continue;
                }
                
                Geary.FolderPath path = (parent != null)
                    ? parent.get_child(basename)
                    : new Imap.FolderRoot(basename, "/");
                
                Geary.Imap.FolderProperties properties = new Geary.Imap.FolderProperties(
                    result.int_for("last_seen_total"), result.int_for("unread_count"), 0,
                    new Imap.UIDValidity(result.int64_for("uid_validity")),
                    new Imap.UID(result.int64_for("uid_next")),
                    Geary.Imap.MailboxAttributes.deserialize(result.string_for("attributes")));
                // due to legacy code, can't set last_seen_total to -1 to indicate that the folder
                // hasn't been SELECT/EXAMINE'd yet, so the STATUS count should be used as the
                // authoritative when the other is zero ... this is important when first creating a
                // folder, as the STATUS is the count that is known first
                properties.set_status_message_count(result.int_for("last_seen_status_total"),
                    (properties.select_examine_messages == 0));
                
                id_map.set(path, result.rowid_for("id"));
                prop_map.set(path, properties);
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        assert(id_map.size == prop_map.size);
        
        if (id_map.size == 0) {
            throw new EngineError.NOT_FOUND("No local folders in %s",
                (parent != null) ? parent.to_string() : "root");
        }
        
        Gee.Collection<Geary.ImapDB.Folder> folders = new Gee.ArrayList<Geary.ImapDB.Folder>();
        foreach (Geary.FolderPath path in id_map.keys) {
            Geary.ImapDB.Folder? folder = get_local_folder(path);
            if (folder == null && id_map.has_key(path) && prop_map.has_key(path))
                folder = create_local_folder(path, id_map.get(path), prop_map.get(path));
            
            folders.add(folder);
        }
        
        return folders;
    }
    
    public async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        bool exists = false;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            try {
                int64 folder_id;
                do_fetch_folder_id(cx, path, false, out folder_id, cancellable);
                
                exists = (folder_id != Db.INVALID_ROWID);
            } catch (EngineError err) {
                // treat NOT_FOUND as non-exceptional situation
                if (!(err is EngineError.NOT_FOUND))
                    throw err;
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return exists;
    }
    
    public async Geary.ImapDB.Folder fetch_folder_async(Geary.FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();
        
        // check references table first
        Geary.ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null)
            return folder;
        
        int64 folder_id = Db.INVALID_ROWID;
        Imap.FolderProperties? properties = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            if (!do_fetch_folder_id(cx, path, false, out folder_id, cancellable))
                return Db.TransactionOutcome.DONE;
            
            if (folder_id == Db.INVALID_ROWID)
                return Db.TransactionOutcome.DONE;
            
            Db.Statement stmt = cx.prepare(
                "SELECT last_seen_total, unread_count, last_seen_status_total, uid_validity, uid_next, "
                + "attributes FROM FolderTable WHERE id=?");
            stmt.bind_rowid(0, folder_id);
            
            Db.Result results = stmt.exec(cancellable);
            if (!results.finished) {
                properties = new Imap.FolderProperties(results.int_for("last_seen_total"),
                    results.int_for("unread_count"), 0,
                    new Imap.UIDValidity(results.int64_for("uid_validity")),
                    new Imap.UID(results.int64_for("uid_next")),
                    Geary.Imap.MailboxAttributes.deserialize(results.string_for("attributes")));
                // due to legacy code, can't set last_seen_total to -1 to indicate that the folder
                // hasn't been SELECT/EXAMINE'd yet, so the STATUS count should be used as the
                // authoritative when the other is zero ... this is important when first creating a
                // folder, as the STATUS is the count that is known first
                properties.set_status_message_count(results.int_for("last_seen_status_total"),
                    (properties.select_examine_messages == 0));
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (folder_id == Db.INVALID_ROWID || properties == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", path.to_string());
        
        return create_local_folder(path, folder_id, properties);
    }
    
    private Geary.ImapDB.Folder? get_local_folder(Geary.FolderPath path) {
        FolderReference? folder_ref = folder_refs.get(path);
        if (folder_ref == null)
            return null;
        
        ImapDB.Folder? folder = (Geary.ImapDB.Folder?) folder_ref.get_reference();
        if (folder == null)
            return null;
        
        // use supplied FolderPath rather than one here; if it came from the server, it has
        // a usable separator
        if (path.get_root().default_separator != null)
            folder.set_path(path);
        
        return folder;
    }
    
    private Geary.ImapDB.Folder create_local_folder(Geary.FolderPath path, int64 folder_id,
        Imap.FolderProperties properties) throws Error {
        // return current if already created
        ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null) {
            // update properties
            folder.set_properties(properties);
            
            return folder;
        }
        
        // create folder
        folder = new Geary.ImapDB.Folder(db, path, contact_store, account_information.email, folder_id,
            properties);
        
        // build a reference to it
        FolderReference folder_ref = new FolderReference(folder, path);
        folder_ref.reference_broken.connect(on_folder_reference_broken);
        
        // add to the references table
        folder_refs.set(folder_ref.path, folder_ref);
        
        folder.unread_updated.connect(on_unread_updated);
        
        return folder;
    }
    
    private void on_folder_reference_broken(Geary.SmartReference reference) {
        FolderReference folder_ref = (FolderReference) reference;
        
        // drop from folder references table, all cleaned up
        folder_refs.unset(folder_ref.path);
    }
    
    public async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Geary.EmailFlags? flag_blacklist,
        Cancellable? cancellable = null) throws Error {
        Gee.HashMultiMap<Geary.Email, Geary.FolderPath?> messages
            = new Gee.HashMultiMap<Geary.Email, Geary.FolderPath?>();
        
        if (flag_blacklist != null)
            requested_fields = requested_fields | Geary.Email.Field.FLAGS;
        
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("SELECT id FROM MessageTable WHERE message_id = ? OR in_reply_to = ?");
            stmt.bind_string(0, message_id.value);
            stmt.bind_string(1, message_id.value);
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                int64 id = result.int64_at(0);
                Geary.Email.Field db_fields;
                MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                    cx, id, requested_fields, out db_fields, cancellable);
                
                // Ignore any messages that don't have the required fields.
                if (partial_ok || row.fields.fulfills(requested_fields)) {
                    Geary.Email email = row.to_email(new Geary.ImapDB.EmailIdentifier(id, null));
                    Geary.ImapDB.Folder.do_add_attachments(cx, email, id, cancellable);
                    
                    Gee.Set<Geary.FolderPath>? folders = do_find_email_folders(cx, id, cancellable);
                    if (folders == null) {
                        if (folder_blacklist == null || !folder_blacklist.contains(null))
                            messages.set(email, null);
                    } else {
                        foreach (Geary.FolderPath path in folders) {
                            // If it's in a blacklisted folder, we don't report
                            // it at all.
                            if (folder_blacklist != null && folder_blacklist.contains(path)) {
                                messages.remove_all(email);
                                break;
                            } else {
                                messages.set(email, path);
                            }
                        }
                    }
                    
                    // Check for blacklisted flags.
                    if (flag_blacklist != null && email.email_flags != null &&
                        email.email_flags.contains_any(flag_blacklist))
                        messages.remove_all(email);
                }
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (messages.size == 0 ? null : messages);
    }
    
    public string prepare_search_query(string raw_query) {
        // Two goals here:
        //   1) append an * after every term so it becomes a prefix search
        //      (see <https://www.sqlite.org/fts3.html#section_3>), and
        //   2) strip out common words/operators that might get interpreted as
        //      search operators.
        // We ignore everything inside quotes to give the user a way to
        // override our algorithm here.  The idea is to offer one search query
        // syntax for Geary that we can use locally and via IMAP, etc.
        string[] words = raw_query.split_set(" \t\r\n:()%*\\");
        bool in_quote = false;
        StringBuilder prepared_query = new StringBuilder();
        foreach (string s in words) {
            s = s.strip();
            
            int quotes = Geary.String.count_char(s, '"');
            if (!in_quote && quotes > 0) {
                in_quote = true;
                --quotes;
            }
            
            if (!in_quote) {
                string lower = s.down();
                if (lower == "" || lower == "and" || lower == "or" || lower == "not" || lower == "near"
                    || lower.has_prefix("near/"))
                    continue;
                
                if (s.has_prefix("-"))
                    s = s.substring(1);
                
                if (s == "")
                    continue;
                
                s = "\"" + s + "*\"";
            }
            
            if (in_quote && quotes % 2 != 0)
                in_quote = false;
            
            prepared_query.append(s);
            prepared_query.append(" ");
        }
        
        string prepared = prepared_query.str.strip();
        if (in_quote)
            prepared += "\"";
        return prepared;
    }
    
    // Append each id in the collection to the StringBuilder, in a format
    // suitable for use in an SQL statement IN (...) clause.
    private void sql_append_ids(StringBuilder s, Gee.Collection<int64?> ids) {
        bool first = true;
        foreach (int64? id in ids) {
            assert(id != null);
            
            if (!first)
                s.append(", ");
            s.append(id.to_string());
            first = false;
        }
    }
    
    private string? get_search_ids_sql(Gee.Collection<Geary.EmailIdentifier>? search_ids) throws Error {
        if (search_ids == null)
            return null;
        
        Gee.ArrayList<int64?> ids = new Gee.ArrayList<int64?>();
        foreach (Geary.EmailIdentifier id in search_ids) {
            ImapDB.EmailIdentifier? imapdb_id = id as ImapDB.EmailIdentifier;
            if (imapdb_id == null) {
                throw new EngineError.BAD_PARAMETERS(
                    "search_ids must contain only Geary.ImapDB.EmailIdentifiers");
            }
            
            ids.add(imapdb_id.message_id);
        }
        
        StringBuilder sql = new StringBuilder();
        sql_append_ids(sql, ids);
        return sql.str;
    }
    
    public async Gee.Collection<Geary.EmailIdentifier>? search_async(string prepared_query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<ImapDB.SearchEmailIdentifier> search_results
            = new Gee.ArrayList<ImapDB.SearchEmailIdentifier>();
        
        string? search_ids_sql = get_search_ids_sql(search_ids);
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            string blacklisted_ids_sql = do_get_blacklisted_message_ids_sql(
                folder_blacklist, cx, cancellable);
            
            // Every mutation of this query we could think of has been tried,
            // and this version was found to minimize running time.  We
            // discovered that just doing a JOIN between the MessageTable and
            // MessageSearchTable was causing a full table scan to order the
            // results.  When it's written this way, and we force SQLite to use
            // the correct index (not sure why it can't figure it out on its
            // own), it cuts the running time roughly in half of how it was
            // before.  The short version is: modify with extreme caution.  See
            // <http://redmine.yorba.org/issues/7372>.
            string sql = """
                SELECT id, internaldate_time_t
                FROM MessageTable
                INDEXED BY MessageTableInternalDateTimeTIndex
                WHERE id IN (
                    SELECT id
                    FROM MessageSearchTable
                    WHERE MessageSearchTable MATCH ?
                )
            """;
            if (blacklisted_ids_sql != "")
                sql += " AND id NOT IN (%s)".printf(blacklisted_ids_sql);
            if (!Geary.String.is_empty(search_ids_sql))
                sql += " AND id IN (%s)".printf(search_ids_sql);
            sql += " ORDER BY internaldate_time_t DESC";
            if (limit > 0)
                sql += " LIMIT ? OFFSET ?";
            Db.Statement stmt = cx.prepare(sql);
            stmt.bind_string(0, prepared_query);
            if (limit > 0) {
                stmt.bind_int(1, limit);
                stmt.bind_int(2, offset);
            }
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                int64 id = result.int64_at(0);
                int64 internaldate_time_t = result.int64_at(1);
                DateTime? internaldate = (internaldate_time_t == -1
                    ? null : new DateTime.from_unix_local(internaldate_time_t));
                search_results.add(new ImapDB.SearchEmailIdentifier(id, internaldate));
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (search_results.size == 0 ? null : search_results);
    }
    
    public async Gee.Collection<string>? get_search_matches_async(string prepared_query,
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        Gee.Set<string> search_matches = new Gee.HashSet<string>();
        
        // Create a question mark for each ID.
        string id_string = "";
        for(int i = 0; i < ids.size; i++) {
            id_string += "?";
            if (i != ids.size - 1)
                id_string += ", ";
        }
        
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("SELECT offsets(MessageSearchTable), * FROM MessageSearchTable " +
                "WHERE MessageSearchTable MATCH ? AND id IN (%s)".printf(id_string));
            
            // Bind query and IDs.
            int i = 0;
            stmt.bind_string(i++, prepared_query);
            foreach(ImapDB.EmailIdentifier id in ids)
                stmt.bind_rowid(i++, id.message_id);
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                // Build a list of search offsets.
                string[] offset_array = result.string_at(0).split(" ");
                Gee.ArrayList<SearchOffset> all_offsets = new Gee.ArrayList<SearchOffset>();
                int j = 0;
                while (true) {
                    all_offsets.add(new SearchOffset(offset_array[j:j+4]));
                    
                    j += 4;
                    if (j >= offset_array.length)
                        break;
                }
                
                // Iterate over the offset list, scrape strings from the database, and push
                // the results into our return set.
                foreach(SearchOffset offset in all_offsets) {
                    string text = result.string_at(offset.column + 1);
                    search_matches.add(text[offset.byte_offset : offset.byte_offset + offset.size].down());
                }
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (search_matches.size == 0 ? null : search_matches);
    }
    
    public async Geary.Email fetch_email_async(ImapDB.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        Geary.Email? email = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            // TODO: once we have a way of deleting messages, we won't be able
            // to assume that a row id will point to the same email outside of
            // transactions, because SQLite will reuse row ids.
            Geary.Email.Field db_fields;
            MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                cx, email_id.message_id, required_fields, out db_fields, cancellable);
            
            if (!row.fields.fulfills(required_fields))
                throw new EngineError.INCOMPLETE_MESSAGE(
                    "Message %s only fulfills %Xh fields (required: %Xh)",
                    email_id.to_string(), row.fields, required_fields);
            
            email = row.to_email(email_id);
            Geary.ImapDB.Folder.do_add_attachments(cx, email, email_id.message_id, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        assert(email != null);
        return email;
    }
    
    public async void update_contact_flags_async(Geary.Contact contact, Cancellable? cancellable)
        throws Error{
        check_open();
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            Db.Statement update_stmt =
                cx.prepare("UPDATE ContactTable SET flags=? WHERE email=?");
            update_stmt.bind_string(0, contact.contact_flags.serialize());
            update_stmt.bind_string(1, contact.email);
            update_stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async int get_email_count_async(Cancellable? cancellable) throws Error {
        check_open();
        
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_email_count(cx, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        return count;
    }
    
    /**
     * Return a map of each passed-in email identifier to the set of folders
     * that contain it.  If an email id doesn't appear in the resulting map,
     * it isn't contained in any folders.  Return null if the resulting map
     * would be empty.  Only throw database errors et al., not errors due to
     * the email id not being found.
     */
    public async Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? get_containing_folders_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath> map
            = new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            foreach (Geary.EmailIdentifier id in ids) {
                ImapDB.EmailIdentifier? imap_db_id = id as ImapDB.EmailIdentifier;
                if (imap_db_id == null)
                    continue;
                
                Gee.Set<Geary.FolderPath>? folders = do_find_email_folders(
                    cx, imap_db_id.message_id, cancellable);
                if (folders != null) {
                    Geary.Collection.multi_map_set_all<Geary.EmailIdentifier,
                        Geary.FolderPath>(map, id, folders);
                }
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        yield outbox.add_to_containing_folders_async(ids, map, cancellable);
        
        return (map.size == 0 ? null : map);
    }
    
    private async void populate_search_table_async(Cancellable? cancellable) {
        debug("%s: Populating search table", account_information.email);
        try {
            int total = yield get_email_count_async(cancellable);
            search_index_monitor.set_interval(0, total);
            search_index_monitor.notify_start();
            
            while (!yield populate_search_table_batch_async(100, cancellable)) {
                // With multiple accounts, meaning multiple background threads
                // doing such CPU- and disk-heavy work, this process can cause
                // the main thread to slow to a crawl.  This delay means the
                // update takes more time, but leaves the main thread nice and
                // snappy the whole time.
                yield Geary.Scheduler.sleep_ms_async(50);
            }
        } catch (Error e) {
            debug("Error populating %s search table: %s", account_information.email, e.message);
        }
        
        if (search_index_monitor.is_in_progress)
            search_index_monitor.notify_finish();
        
        debug("%s: Done populating search table", account_information.email);
    }
    
    private async bool populate_search_table_batch_async(int limit = 100,
        Cancellable? cancellable) throws Error {
        debug("%s: Searching for missing indexed messages...", account_information.email);
        
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            Db.Statement stmt = cx.prepare("""
                SELECT id
                FROM MessageTable
                WHERE id NOT IN (
                    SELECT id
                    FROM MessageSearchTable
                )
                LIMIT ?
            """);
            stmt.bind_int(0, limit);
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                int64 id = result.rowid_at(0);
                
                try {
                    Geary.Email.Field search_fields = Geary.Email.REQUIRED_FOR_MESSAGE |
                        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.RECEIVERS |
                        Geary.Email.Field.SUBJECT;
                    
                    Geary.Email.Field db_fields;
                    MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                        cx, id, search_fields, out db_fields, cancellable);
                    Geary.Email email = row.to_email(new Geary.ImapDB.EmailIdentifier(id, null));
                    Geary.ImapDB.Folder.do_add_attachments(cx, email, id, cancellable);
                    
                    Geary.ImapDB.Folder.do_add_email_to_search_table(cx, id, email, cancellable);
                } catch (Error e) {
                    // This is a somewhat serious issue since we rely on
                    // there always being a row in the search table for
                    // every message.
                    warning("Error adding message %lld to the search table: %s", id, e.message);
                }
                
                ++count;
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        search_index_monitor.increment(count);
        
        if (count > 0)
            debug("%s: Found %d/%d missing indexed messages...", account_information.email, count, limit);
        
        return (count < limit);
    }
    
    //
    // Transaction helper methods
    //
    
    private void do_delete_folder(Db.Connection cx, int64 folder_id, Cancellable? cancellable)
        throws Error {
        Db.Statement msg_loc_stmt = cx.prepare("""
            DELETE FROM MessageLocationTable
            WHERE folder_id = ?
        """);
        msg_loc_stmt.bind_rowid(0, folder_id);
        
        msg_loc_stmt.exec(cancellable);
        
        Db.Statement folder_stmt = cx.prepare("""
            DELETE FROM FolderTable
            WHERE id = ?
        """);
        folder_stmt.bind_rowid(0, folder_id);
        
        folder_stmt.exec(cancellable);
    }
    
    // If the FolderPath has no parent, returns true and folder_id will be set to Db.INVALID_ROWID.
    // If cannot create path or there is a logical problem traversing it, returns false with folder_id
    // set to Db.INVALID_ROWID.
    private bool do_fetch_folder_id(Db.Connection cx, Geary.FolderPath path, bool create, out int64 folder_id,
        Cancellable? cancellable) throws Error {
        int length = path.get_path_length();
        if (length < 0)
            throw new EngineError.BAD_PARAMETERS("Invalid path %s", path.to_string());
        
        folder_id = Db.INVALID_ROWID;
        int64 parent_id = Db.INVALID_ROWID;
        
        // walk the folder tree to the final node (which is at length - 1 - 1)
        for (int ctr = 0; ctr < length; ctr++) {
            string basename = path.get_folder_at(ctr).basename;
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare("SELECT id FROM FolderTable WHERE parent_id=? AND name=?");
                stmt.bind_rowid(0, parent_id);
                stmt.bind_string(1, basename);
            } else {
                stmt = cx.prepare("SELECT id FROM FolderTable WHERE parent_id IS NULL AND name=?");
                stmt.bind_string(0, basename);
            }
            
            int64 id = Db.INVALID_ROWID;
            
            Db.Result result = stmt.exec(cancellable);
            if (!result.finished) {
                id = result.rowid_at(0);
            } else if (!create) {
                return false;
            } else {
                // not found, create it
                Db.Statement create_stmt = cx.prepare(
                    "INSERT INTO FolderTable (name, parent_id) VALUES (?, ?)");
                create_stmt.bind_string(0, basename);
                create_stmt.bind_rowid(1, parent_id);
                
                id = create_stmt.exec_insert(cancellable);
            }
            
            // watch for path loops, real bad if it happens ... could be more thorough here, but at
            // least one level of checking is better than none
            if (id == parent_id) {
                warning("Loop found in database: parent of %s is %s in FolderTable",
                    parent_id.to_string(), id.to_string());
                
                return false;
            }
            
            parent_id = id;
        }
        
        // parent_id is now the folder being searched for
        folder_id = parent_id;
        
        return true;
    }
    
    // See do_fetch_folder_id() for return semantics.
    private bool do_fetch_parent_id(Db.Connection cx, Geary.FolderPath path, bool create, out int64 parent_id,
        Cancellable? cancellable = null) throws Error {
        if (path.is_root()) {
            parent_id = Db.INVALID_ROWID;
            
            return true;
        }
        
        return do_fetch_folder_id(cx, path.get_parent(), create, out parent_id, cancellable);
    }
    
    // Turn the collection of folder paths into actual folder ids.  As a
    // special case, if "folderless" or orphan emails are to be blacklisted,
    // set the out bool to true.
    private Gee.Collection<int64?> do_get_blacklisted_folder_ids(Gee.Collection<Geary.FolderPath?>? folder_blacklist,
        Db.Connection cx, out bool blacklist_folderless, Cancellable? cancellable) throws Error {
        blacklist_folderless = false;
        Gee.ArrayList<int64?> ids = new Gee.ArrayList<int64?>();
        
        if (folder_blacklist != null) {
            foreach (Geary.FolderPath? folder_path in folder_blacklist) {
                if (folder_path == null) {
                    blacklist_folderless = true;
                } else {
                    int64 id;
                    do_fetch_folder_id(cx, folder_path, true, out id, cancellable);
                    if (id != Db.INVALID_ROWID)
                        ids.add(id);
                }
            }
        }
        
        return ids;
    }
    
    // Return a parameterless SQL statement that selects any message ids that
    // are in a blacklisted folder.  This is used as a sub-select for the
    // search query to omit results from blacklisted folders.
    private string do_get_blacklisted_message_ids_sql(Gee.Collection<Geary.FolderPath?>? folder_blacklist,
        Db.Connection cx, Cancellable? cancellable) throws Error {
        bool blacklist_folderless;
        Gee.Collection<int64?> blacklisted_ids = do_get_blacklisted_folder_ids(
            folder_blacklist, cx, out blacklist_folderless, cancellable);
        
        StringBuilder sql = new StringBuilder();
        if (blacklisted_ids.size > 0 || blacklist_folderless) {
            if (blacklist_folderless) {
                // We select out of the MessageTable and join on the location
                // table so we can recognize emails that aren't in any folders.
                // This is slightly more complicated than the case below, where
                // we can just select directly out of the location table.
                sql.append("""
                    SELECT m.id
                    FROM MessageTable m
                    LEFT JOIN MessageLocationTable l ON l.message_id = m.id
                    WHERE folder_id IS NULL
                """);
                if (blacklisted_ids.size > 0) {
                    sql.append(" OR folder_id IN (");
                    sql_append_ids(sql, blacklisted_ids);
                    sql.append(")");
                }
            } else {
                sql.append("""
                    SELECT message_id
                    FROM MessageLocationTable
                    WHERE folder_id IN (
                """);
                sql_append_ids(sql, blacklisted_ids);
                sql.append(")");
            }
        }
        
        return sql.str;
    }
    
    // For a message row id, return a set of all folders it's in, or null if
    // it's not in any folders.
    private static Gee.Set<Geary.FolderPath>? do_find_email_folders(Db.Connection cx, int64 message_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT folder_id FROM MessageLocationTable WHERE message_id=?");
        stmt.bind_int64(0, message_id);
        Db.Result result = stmt.exec(cancellable);
        
        if (result.finished)
            return null;
        
        Gee.HashSet<Geary.FolderPath> folder_paths = new Gee.HashSet<Geary.FolderPath>();
        while (!result.finished) {
            int64 folder_id = result.int64_at(0);
            Geary.FolderPath? path = do_find_folder_path(cx, folder_id, cancellable);
            if (path != null)
                folder_paths.add(path);
            
            result.next(cancellable);
        }
        
        return (folder_paths.size == 0 ? null : folder_paths);
    }
    
    // For a folder row id, return the folder path (constructed with default
    // separator and case sensitivity) of that folder, or null in the event
    // it's not found.
    private static Geary.FolderPath? do_find_folder_path(Db.Connection cx, int64 folder_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT parent_id, name FROM FolderTable WHERE id=?");
        stmt.bind_int64(0, folder_id);
        Db.Result result = stmt.exec(cancellable);
        
        if (result.finished)
            return null;
        
        int64 parent_id = result.int64_at(0);
        string name = result.string_at(1);
        
        // Here too, one level of loop detection is better than nothing.
        if (folder_id == parent_id) {
            warning("Loop found in database: parent of %s is %s in FolderTable",
                folder_id.to_string(), parent_id.to_string());
            return null;
        }
        
        if (parent_id <= 0)
            return new Imap.FolderRoot(name, null);
        
        Geary.FolderPath? parent_path = do_find_folder_path(cx, parent_id, cancellable);
        return (parent_path == null ? null : parent_path.get_child(name));
    }
    
    // For SELECT/EXAMINE responses, not STATUS responses
    private void do_update_last_seen_select_examine_total(Db.Connection cx, int64 parent_id, string name, int total,
        Cancellable? cancellable) throws Error {
        do_update_total(cx, parent_id, name, "last_seen_total", total, cancellable);
    }
    
    // For STATUS responses, not SELECT/EXAMINE responses
    private void do_update_last_seen_status_total(Db.Connection cx, int64 parent_id, string name,
        int total, Cancellable? cancellable) throws Error {
        do_update_total(cx, parent_id, name, "last_seen_status_total", total, cancellable);
    }
    
    private void do_update_total(Db.Connection cx, int64 parent_id, string name, string colname,
        int total, Cancellable? cancellable) throws Error {
        Db.Statement stmt;
        if (parent_id != Db.INVALID_ROWID) {
            stmt = cx.prepare(
                "UPDATE FolderTable SET %s=? WHERE parent_id=? AND name=?".printf(colname));
            stmt.bind_int(0, Numeric.int_floor(total, 0));
            stmt.bind_rowid(1, parent_id);
            stmt.bind_string(2, name);
        } else {
            stmt = cx.prepare(
                "UPDATE FolderTable SET %s=? WHERE parent_id IS NULL AND name=?".printf(colname));
            stmt.bind_int(0, Numeric.int_floor(total, 0));
            stmt.bind_string(1, name);
        }
        
        stmt.exec(cancellable);
    }
    
    private void do_update_uid_info(Db.Connection cx, Imap.FolderProperties properties,
        int64 parent_id, FolderPath path, Cancellable? cancellable) throws Error {
        int64 uid_validity = (properties.uid_validity != null) ? properties.uid_validity.value
                : Imap.UIDValidity.INVALID;
        int64 uid_next = (properties.uid_next != null) ? properties.uid_next.value
            : Imap.UID.INVALID;
        
        Db.Statement stmt;
        if (parent_id != Db.INVALID_ROWID) {
            stmt = cx.prepare(
                "UPDATE FolderTable SET uid_validity=?, uid_next=? WHERE parent_id=? AND name=?");
            stmt.bind_int64(0, uid_validity);
            stmt.bind_int64(1, uid_next);
            stmt.bind_rowid(2, parent_id);
            stmt.bind_string(3, path.basename);
        } else {
            stmt = cx.prepare(
                "UPDATE FolderTable SET uid_validity=?, uid_next=? WHERE parent_id IS NULL AND name=?");
            stmt.bind_int64(0, uid_validity);
            stmt.bind_int64(1, uid_next);
            stmt.bind_string(2, path.basename);
        }
        
        stmt.exec(cancellable);
    }
    
    private int do_get_email_count(Db.Connection cx, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*) FROM MessageTable");
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return 0;
        
        return results.int_at(0);
    }
    
    private void on_unread_updated(ImapDB.Folder source, Gee.Map<ImapDB.EmailIdentifier, bool>
        unread_status) {
        update_unread_async.begin(source, unread_status, null);
    }
    
    // Updates unread count on all folders.
    private async void update_unread_async(ImapDB.Folder source, Gee.Map<ImapDB.EmailIdentifier, bool>
        unread_status, Cancellable? cancellable) throws Error {
        Gee.Map<Geary.FolderPath, int> unread_change = new Gee.HashMap<Geary.FolderPath, int>();
        
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            foreach (ImapDB.EmailIdentifier id in unread_status.keys) {
                Gee.Set<Geary.FolderPath>? paths = do_find_email_folders(cx, id.message_id, cancellable);
                if (paths == null)
                    continue;
                
                // Remove the folder that triggered this event.
                paths.remove(source.get_path());
                if (paths.size == 0)
                    continue;
                
                foreach (Geary.FolderPath path in paths) {
                    int current_unread = unread_change.has_key(path) ? unread_change.get(path) : 0;
                    current_unread += unread_status.get(id) ? 1 : -1;
                    unread_change.set(path, current_unread);
                }
            }
            
            // Update each folder's unread count in the database.
            foreach (Geary.FolderPath path in unread_change.keys) {
                Geary.ImapDB.Folder? folder = get_local_folder(path);
                if (folder == null)
                    continue;
                
                folder.do_add_to_unread_count(cx, unread_change.get(path), cancellable);
            }
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Update each folder's unread count property.
        foreach (Geary.FolderPath path in unread_change.keys) {
            Geary.ImapDB.Folder? folder = get_local_folder(path);
            if (folder == null)
                continue;
            
            folder.get_properties().set_status_unseen(folder.get_properties().email_unread +
                unread_change.get(path));
        }
    }
}

