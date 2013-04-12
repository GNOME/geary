/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Folder : BaseObject, Geary.ReferenceSemantics {
    public const Geary.Email.Field REQUIRED_FOR_DUPLICATE_DETECTION = Geary.Email.Field.PROPERTIES;
    
    private const int LIST_EMAIL_CHUNK_COUNT = 5;
    private const int LIST_EMAIL_FIELDS_CHUNK_COUNT = 500;
    
    [Flags]
    public enum ListFlags {
        NONE = 0,
        PARTIAL_OK,
        INCLUDE_MARKED_FOR_REMOVE,
        EXCLUDING_ID;
        
        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }
        
        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool include_marked_for_remove() {
            return is_all_set(INCLUDE_MARKED_FOR_REMOVE);
        }
    }
    
    private class LocationIdentifier {
        public int64 message_id;
        public int position;
        public int64 ordering;
        public Geary.EmailIdentifier email_id;
        
        // If EmailIdentifier has already been built, it can be supplied rather then auto-created
        // by LocationIdentifier
        public LocationIdentifier(int64 message_id, int position, int64 ordering,
            Geary.FolderPath path, Geary.EmailIdentifier? email_id) {
            assert(position >= 1);
            
            this.message_id = message_id;
            this.position = position;
            this.ordering = ordering;
            this.email_id = email_id ?? new Imap.EmailIdentifier(new Imap.UID(ordering), path);
            
            // verify that the EmailIdentifier and ordering are pointing to the same thing
            assert(this.email_id.ordering == this.ordering);
        }
    }
    
    public bool opened { get; private set; default = false; }
    
    protected int manual_ref_count { get; protected set; }
    
    private ImapDB.Database db;
    private Geary.FolderPath path;
    private ContactStore contact_store;
    private string account_owner_email;
    private int64 folder_id;
    private Geary.Imap.FolderProperties properties;
    private Gee.HashSet<Geary.EmailIdentifier> marked_removed = new Gee.HashSet<Geary.EmailIdentifier>(
        Hashable.hash_func, Equalable.equal_func);
    
    internal Folder(ImapDB.Database db, Geary.FolderPath path, ContactStore contact_store,
        string account_owner_email, int64 folder_id, Geary.Imap.FolderProperties properties) {
        assert(folder_id != Db.INVALID_ROWID);
        
        this.db = db;
        this.path = path;
        this.contact_store = contact_store;
        this.account_owner_email = account_owner_email;
        this.folder_id = folder_id;
        this.properties = properties;
    }
    
    private void check_open() throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s not open", to_string());
    }
    
    public Geary.FolderPath get_path() {
        return path;
    }
    
    public Geary.Imap.FolderProperties get_properties() {
        return properties;
    }
    
    internal void set_properties(Geary.Imap.FolderProperties properties) {
        this.properties = properties;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (opened)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        opened = true;
        
        lock (marked_removed)
            marked_removed.clear();
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        opened = false;
        
        // anything marked as removed is dropped rather than actually deleted from the database;
        // folder synchronization the next time the folder is opened will take care of anything
        // not properly sync'd
        lock (marked_removed) {
            marked_removed.clear();
        }
        
        // TODO: Wait for all I/O to complete before exiting
    }
    
    // Returns true if the EmailIdentifier was marked before being removed
    private bool unmark_removed(Geary.EmailIdentifier id) {
        lock (marked_removed) {
            return marked_removed.remove(id);
        }
    }
    
    private void mark_unmark_removed(Gee.Collection<Geary.EmailIdentifier> ids, bool mark) {
        lock (marked_removed) {
            if (mark)
                marked_removed.add_all(ids);
            else
                marked_removed.remove_all(ids);
        }
    }
    
    private bool is_marked_removed(Geary.EmailIdentifier id) {
        lock (marked_removed) {
            return marked_removed.contains(id);
        }
    }
    
    private int get_marked_removed_count() {
        lock (marked_removed) {
            return marked_removed.size;
        }
    }
    
    private int get_marked_removed_count_lte(Geary.EmailIdentifier id) {
        int count = 0;
        lock (marked_removed) {
            foreach (Geary.EmailIdentifier marked in marked_removed) {
                if (marked.ordering <= id.ordering)
                    count++;
            }
        }
        
        return count;
    }
    
    public async int get_email_count_async(ListFlags flags, Cancellable? cancellable) throws Error {
        check_open();
        
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_email_count(cx, flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        return count;
    }
    
    // Updates both the FolderProperties and the value in the local store.  Must be called while
    // open.
    public async void update_remote_status_message_count(int count, Cancellable? cancellable) throws Error {
        check_open();
        
        if (count < 0)
            return;
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            Db.Statement stmt = cx.prepare(
                "UPDATE FolderTable SET last_seen_status_total=? WHERE id=?");
            stmt.bind_int(0, Numeric.int_floor(count, 0));
            stmt.bind_rowid(1, folder_id);
            
            stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        properties.set_status_message_count(count, false);
    }
    
    // Updates both the FolderProperties and the value in the local store.  Must be called while
    // open.
    public async void update_remote_selected_message_count(int count, Cancellable? cancellable) throws Error {
        check_open();
        
        if (count < 0)
            return;
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            Db.Statement stmt = cx.prepare(
                "UPDATE FolderTable SET last_seen_total=? WHERE id=?");
            stmt.bind_int(0, Numeric.int_floor(count, 0));
            stmt.bind_rowid(1, folder_id);
            
            stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        properties.set_select_examine_message_count(count);
    }
    
    public async int get_id_position_async(Geary.EmailIdentifier id, ListFlags flags,
        Cancellable? cancellable) throws Error {
        check_open();
        
        int position = -1;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            position = do_get_message_position(cx, id, flags, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return position;
    }
    
    // Returns a Map with the created or merged email as the key and the result of the operation
    // (true if created, false if merged) as the value
    public async Gee.Map<Geary.Email, bool> create_or_merge_email_async(Gee.Collection<Geary.Email> emails,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        Gee.HashMap<Geary.Email, bool> results = new Gee.HashMap<Geary.Email, bool>();
        Gee.Collection<Contact> updated_contacts = new Gee.ArrayList<Contact>();
        foreach (Geary.Email email in emails) {
            Db.TransactionOutcome outcome = yield db.exec_transaction_async(Db.TransactionType.RW,
                (cx) => {
                Gee.Collection<Contact>? contacts_this_email = null;
                bool created = do_create_or_merge_email(cx, email, out contacts_this_email, cancellable);
                
                if (contacts_this_email != null)
                    updated_contacts.add_all(contacts_this_email);
                
                results.set(email, created);
                
                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
            
            if (outcome == Db.TransactionOutcome.COMMIT && updated_contacts.size > 0)
                contact_store.update_contacts(updated_contacts);
            
            // clear each iteration
            updated_contacts.clear();
        }
        
        return results;
    }
    
    // NOTE: This can be used to check local messages without opening the folder, useful since
    // opening a Geary.Folder implies remote connection ... this skips check_open() (and, by
    // implication, means the ImapDB.Folder can be in an odd state), so USE CAREFULLY.
    public async Gee.List<Geary.Email>? local_list_email_async(int low, int count,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        return yield internal_list_email_async(low, count, required_fields, flags, true, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        return yield internal_list_email_async(low, count, required_fields, flags, false, cancellable);
    }
    
    private async Gee.List<Geary.Email>? internal_list_email_async(int low, int count,
        Geary.Email.Field required_fields, ListFlags flags, bool skip_open_check,
        Cancellable? cancellable) throws Error {
        if (!skip_open_check)
            check_open();
        
        // Break up this work a bit so the database is not held on one long continuous transaction
        // First, pull in all the message locations that correspond to the list criteria
        //
        // TODO: A more efficient way to do this would be to pull in all the columns at once in
        // a single SELECT operation ... this might be less efficient than current practice if
        // a lot of messages are marked for removal, but that's an edge case
        Gee.List<LocationIdentifier> ids = new Gee.ArrayList<LocationIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            Geary.Folder.normalize_span_specifiers(ref low, ref count,
                do_get_email_count(cx, flags, cancellable));
            if (count == 0)
                return Db.TransactionOutcome.SUCCESS;
            
            Db.Statement stmt = cx.prepare(
                "SELECT message_id, ordering FROM MessageLocationTable WHERE folder_id=? "
                + "ORDER BY ordering LIMIT ? OFFSET ?");
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int(1, count);
            stmt.bind_int(2, low - 1);
            
            Db.Result results = stmt.exec(cancellable);
            if (results.finished)
                return Db.TransactionOutcome.SUCCESS;
            
            int position = low;
            do {
                LocationIdentifier location = new LocationIdentifier(results.rowid_at(0), position++,
                    results.int64_at(1), path, null);
                if (!flags.include_marked_for_remove() && is_marked_removed(location.email_id))
                    continue;
                
                ids.add(location);
            } while (results.next(cancellable));
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, pull in email from locations in chunks (rather than all in one transaction)
        return yield list_email_in_chunks_async(ids, required_fields, flags, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        if (count == 0 || count == 1) {
            try {
                Geary.Email email = yield fetch_email_async(initial_id, required_fields, flags,
                    cancellable);
                
                Gee.List<Geary.Email> singleton = new Gee.ArrayList<Geary.Email>();
                singleton.add(email);
                
                return singleton;
            } catch (EngineError engine_err) {
                // list_email variants don't return NOT_FOUND or INCOMPLETE_MESSAGE
                if ((engine_err is EngineError.NOT_FOUND) || (engine_err is EngineError.INCOMPLETE_MESSAGE))
                    return null;
                
                throw engine_err;
            }
        }
        
        Geary.Imap.UID uid = ((Geary.Imap.EmailIdentifier) initial_id).uid;
        bool excluding_id = flags.is_all_set(ListFlags.EXCLUDING_ID);
        
        int64 low, high;
        if (count < 0) {
            high = excluding_id ? uid.value - 1 : uid.value;
            low = (count != int.MIN) ? (high + count).clamp(1, uint32.MAX) : -1;
        } else {
            // count > 1
            low = excluding_id ? uid.value + 1 : uid.value;
            high = (count != int.MAX) ? (low + count).clamp(1, uint32.MAX) : -1;
        }
        
        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier> ids = new Gee.ArrayList<LocationIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt;
            if (high != -1 && low != -1) {
                stmt = cx.prepare(
                    "SELECT message_id, ordering FROM MessageLocationTable WHERE folder_id=? "
                    + "AND ordering >= ? AND ordering <= ? ORDER BY ordering ASC");
                stmt.bind_rowid(0, folder_id);
                stmt.bind_int64(1, low);
                stmt.bind_int64(2, high);
            } else if (high == -1) {
                stmt = cx.prepare(
                    "SELECT message_id, ordering FROM MessageLocationTable WHERE folder_id=? "
                    + "AND ordering >= ? ORDER BY ordering ASC");
                stmt.bind_rowid(0, folder_id);
                stmt.bind_int64(1, low);
            } else {
                assert(low == -1);
                
                stmt = cx.prepare(
                    "SELECT message_id, ordering FROM MessageLocationTable WHERE folder_id=? "
                    + "AND ordering <= ? ORDER BY ordering ASC");
                stmt.bind_rowid(0, folder_id);
                stmt.bind_int64(1, high);
            }
            
            Db.Result results = stmt.exec(cancellable);
            if (results.finished)
                return Db.TransactionOutcome.SUCCESS;
            
            int position = -1;
            do {
                int64 ordering = results.int64_at(1);
                Geary.EmailIdentifier email_id = new Imap.EmailIdentifier(new Imap.UID(ordering), path);
                
                // get position of first message and roll from there
                if (position == -1) {
                    position = do_get_message_position(cx, email_id, flags, cancellable);
                    assert(position >= 1);
                }
                
                LocationIdentifier location = new LocationIdentifier(results.rowid_at(0), position++,
                    ordering, path, email_id);
                if (!flags.include_marked_for_remove() && is_marked_removed(location.email_id)) {
                    // don't count this in the positional addressing
                    position--;
                    
                    continue;
                }
                
                ids.add(location);
            } while (results.next(cancellable));
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, read in email in chunks
        return yield list_email_in_chunks_async(ids, required_fields, flags, cancellable);
    }
    
    private async Gee.List<Geary.Email>? list_email_in_chunks_async(Gee.List<LocationIdentifier> ids,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        int length = ids.size;
        if (length == 0)
            return null;
        
        int length_rounded_up = Numeric.int_round_up(length, LIST_EMAIL_CHUNK_COUNT);
        
        Gee.List<Geary.Email> results = new Gee.ArrayList<Geary.Email>();
        for (int start = 0; start < length_rounded_up; start += LIST_EMAIL_CHUNK_COUNT) {
            // stop is the index *after* the end of the slice
            int stop = Numeric.int_ceiling((start + LIST_EMAIL_CHUNK_COUNT), length);
            
            Gee.List<LocationIdentifier>? slice = ids.slice(start, stop);
            assert(slice != null && slice.size > 0);
            
            Gee.List<Geary.Email>? list = null;
            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                list = do_list_email(cx, slice, required_fields, flags, cancellable);
                
                return Db.TransactionOutcome.SUCCESS;
            }, cancellable);
            
            if (list != null)
                results.add_all(list);
        }
        
        if (results.size != length)
            debug("list_email_in_chunks_async: Requested %d email, returned %d", length, results.size);
        
        return (results.size > 0) ? results : null;
    }
    
    public async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        check_open();
        
        Geary.Email? email = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            // get the message and its position
            int64 message_id = do_find_message(cx, id, flags, cancellable);
            if (message_id == Db.INVALID_ROWID)
                return Db.TransactionOutcome.DONE;
            
            int position = do_get_message_position(cx, id, flags, cancellable);
            if (position < 1)
                return Db.TransactionOutcome.DONE;
            
            LocationIdentifier location = new LocationIdentifier(message_id, position, id.ordering,
                path, null);
            if (!flags.include_marked_for_remove() && is_marked_removed(location.email_id))
                return Db.TransactionOutcome.DONE;
            
            email = do_location_to_email(cx, location, required_fields, flags, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (email == null) {
            throw new EngineError.NOT_FOUND("No message ID %s in folder %s", id.to_string(),
                to_string());
        }
        
        return email;
    }
    
    public async Geary.Imap.UID? get_earliest_uid_async(Cancellable? cancellable = null) throws Error {
        return yield get_uid_extremes_async(true, cancellable);
    }
    
    public async Geary.Imap.UID? get_latest_uid_async(Cancellable? cancellable = null) throws Error {
        return yield get_uid_extremes_async(false, cancellable);
    }
    
    private async Geary.Imap.UID? get_uid_extremes_async(bool earliest, Cancellable? cancellable)
        throws Error {
        check_open();
        
        int64 ordering = Imap.UID.INVALID;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt;
            if (earliest)
                stmt = cx.prepare("SELECT MIN(ordering) FROM MessageLocationTable WHERE folder_id=?");
            else
                stmt = cx.prepare("SELECT MAX(ordering) FROM MessageLocationTable WHERE folder_id=?");
            stmt.bind_rowid(0, folder_id);
            
            Db.Result results = stmt.exec(cancellable);
            if (!results.finished)
                ordering = results.int64_at(0);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return Imap.UID.is_value_valid(ordering) ? new Imap.UID(ordering) : null;
    }
    
    public async void remove_email_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO: Right now, deleting an email is merely detaching its association with a folder
        // (since it may be located in multiple folders).  This means at some point in the future
        // a vacuum will be required to remove emails that are completely unassociated with the
        // account.
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            // prepare Statement and invariants
            Db.Statement stmt = cx.prepare(
                "DELETE FROM MessageLocationTable WHERE folder_id=? AND ordering=?");
            stmt.bind_rowid(0, folder_id);
            
            foreach (Geary.EmailIdentifier id in ids) {
                stmt.reset(Db.ResetScope.SAVE_BINDINGS);
                stmt.bind_int64(1, id.ordering);
                
                stmt.exec(cancellable);
            }
            
            // Remove any that may have been marked removed
            mark_unmark_removed(ids, false);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async void mark_email_async(Gee.Collection<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, Cancellable? cancellable)
        throws Error {
        check_open();
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            // fetch flags for each email
            Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? map = do_get_email_flags(cx, to_mark,
                cancellable);
            if (map == null)
                return Db.TransactionOutcome.COMMIT;
            
            // update flags according to arguments
            foreach (Geary.EmailIdentifier id in map.keys) {
                Geary.Imap.EmailFlags flags = ((Geary.Imap.EmailFlags) map.get(id));
                
                if (flags_to_add != null) {
                    foreach (Geary.EmailFlag flag in flags_to_add.get_all())
                        flags.add(flag);
                }
                
                if (flags_to_remove != null) {
                    foreach (Geary.EmailFlag flag in flags_to_remove.get_all())
                        flags.remove(flag);
                }
            }
            
            // write them all back out
            do_set_email_flags(cx, map, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? get_email_flags_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? map = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            map = do_get_email_flags(cx, ids, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        return map;
    }
    
    public async void set_email_flags_async(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map,
        Cancellable? cancellable) throws Error {
        check_open();
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            do_set_email_flags(cx, map, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async bool is_email_present_async(Geary.EmailIdentifier id, out Geary.Email.Field available_fields,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        Geary.Email.Field internal_available_fields = Geary.Email.Field.NONE;
        bool is_present = false;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            int64 message_id = do_find_message(cx, id, ListFlags.NONE, cancellable);
            if (message_id == Db.INVALID_ROWID)
                return Db.TransactionOutcome.DONE;
            
            is_present = do_fetch_email_fields(cx, message_id, out internal_available_fields,
                cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        available_fields = internal_available_fields;
        
        return is_present;
    }
    
    public async void remove_marked_email_async(Geary.EmailIdentifier id, out bool is_marked,
        Cancellable? cancellable) throws Error {
        check_open();
        
        bool internal_is_marked = false;
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            internal_is_marked = unmark_removed(id);
            
            do_remove_association_with_folder(cx, id, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        is_marked = internal_is_marked;
    }
    
    // Mark messages as removed (but not expunged) from the folder.  Marked messages are skipped
    // on most operations unless ListFlags.INCLUDE_MARKED_REMOVED is true.  Use remove_marked_email_async()
    // to formally remove the messages from the folder.
    //
    // TODO: Need to verify each EmailIdentifier before adding to marked_removed collection.
    public async void mark_removed_async(Gee.Collection<Geary.EmailIdentifier> ids, bool mark_removed, 
        Cancellable? cancellable) throws Error {
        check_open();
        
        mark_unmark_removed(ids, mark_removed);
    }
    
    public async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_email_fields_by_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        check_open();
        
        if (ids.size == 0)
            return null;
        
        Gee.HashMap<Geary.EmailIdentifier, Geary.Email.Field> map = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email.Field>(Hashable.hash_func, Equalable.equal_func);
        
        // Break up the work
        Gee.List<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Iterator<Geary.EmailIdentifier> iter = ids.iterator();
        while (iter.next()) {
            list.add(iter.get());
            if (list.size < LIST_EMAIL_FIELDS_CHUNK_COUNT && iter.has_next())
                continue;
            
            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                Db.Statement fetch_stmt = cx.prepare(
                    "SELECT fields FROM MessageTable WHERE id=?");
                
                foreach (Geary.EmailIdentifier id in list) {
                    int64 message_id = do_find_message(cx, id, ListFlags.NONE, cancellable);
                    if (message_id == Db.INVALID_ROWID)
                        continue;
                    
                    fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
                    fetch_stmt.bind_rowid(0, message_id);
                    
                    Db.Result results = fetch_stmt.exec(cancellable);
                    if (!results.finished)
                        map.set(id, (Geary.Email.Field) results.int_at(0));
                }
                
                return Db.TransactionOutcome.SUCCESS;
            }, cancellable);
            
            list.clear();
        }
        assert(list.size == 0);
        
        return (map.size > 0) ? map : null;
    }
    
    public string to_string() {
        return path.to_string();
    }
    
    //
    // Database transaction helper methods
    // These should only be called from within a TransactionMethod.
    //
    
    private int do_get_email_count(Db.Connection cx, ListFlags flags, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*) FROM MessageLocationTable WHERE folder_id=?");
        stmt.bind_rowid(0, folder_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return 0;
        
        int marked = !flags.include_marked_for_remove() ? get_marked_removed_count() : 0;
        
        return Numeric.int_floor(results.int_at(0) - marked, 0);
    }
    
    private int64 do_find_message(Db.Connection cx, Geary.EmailIdentifier id, ListFlags flags,
        Cancellable? cancellable) throws Error {
        if (!flags.include_marked_for_remove() && is_marked_removed(id))
            return Db.INVALID_ROWID;
        
        Db.Statement stmt = cx.prepare(
            "SELECT message_id FROM MessageLocationTable WHERE folder_id=? AND ordering=?");
        stmt.bind_rowid(0, folder_id);
        stmt.bind_int64(1, id.ordering);
        
        Db.Result results = stmt.exec(cancellable);
        
        return (!results.finished) ? results.rowid_at(0) : Db.INVALID_ROWID;
    }
    
    // Returns -1 if not found
    private int do_get_message_position(Db.Connection cx, Geary.EmailIdentifier id, ListFlags flags,
        Cancellable? cancellable) throws Error {
        if (!flags.include_marked_for_remove() && is_marked_removed(id))
            return -1;
        
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*), MAX(ordering) FROM MessageLocationTable WHERE folder_id=? "
            + "AND ordering <= ? ORDER BY ordering ASC");
        stmt.bind_rowid(0, folder_id);
        stmt.bind_int64(1, id.ordering);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return -1;
        
        // without the MAX it's possible to overshoot, so the MAX(ordering) *must* match the argument
        if (results.int64_at(1) != id.ordering)
            return -1;
        
        // the COUNT represents the 1-based number of rows from the first ordering to this one
        if (!flags.include_marked_for_remove())
            return results.int_at(0);
        
        int adjusted = results.int_at(0) - get_marked_removed_count_lte(id);
        
        return (adjusted >= 1) ? adjusted : -1;
    }
    
    // Returns message_id if duplicate found, associated set to true if message is already associated
    // with this folder
    private int64 do_search_for_duplicates(Db.Connection cx, Geary.Email email, out bool associated,
        Cancellable? cancellable) throws Error {
        associated = false;
        
        // See if it already exists; first by UID (which is only guaranteed to be unique in a folder,
        // not account-wide)
        int64 message_id = do_find_message(cx, email.id, ListFlags.NONE, cancellable);
        if (message_id != Db.INVALID_ROWID) {
            associated = true;
            
            return message_id;
        }
        
        // if fields not present, then no duplicate can reliably be found
        if (!email.fields.is_all_set(REQUIRED_FOR_DUPLICATE_DETECTION)) {
            debug("Unable to detect duplicates for %s (%s available)", email.id.to_string(),
                email.fields.to_list_string());
            return Db.INVALID_ROWID;
        }
        
        // what's more, actually need all those fields to be available, not merely attempted,
        // to err on the side of safety
        Imap.EmailProperties? imap_properties = (Imap.EmailProperties) email.properties;
        string? internaldate = (imap_properties != null && imap_properties.internaldate != null)
            ? imap_properties.internaldate.original : null;
        long rfc822_size = (imap_properties != null) ? imap_properties.rfc822_size.value : -1;
        
        if (String.is_empty(internaldate) || rfc822_size < 0) {
            debug("Unable to detect duplicates for %s (%s available but invalid)", email.id.to_string(),
                email.fields.to_list_string());
            return Db.INVALID_ROWID;
        }
        
        // look for duplicate in IMAP message properties
        Db.Statement stmt = cx.prepare(
            "SELECT id FROM MessageTable WHERE internaldate=? AND rfc822_size=?");
        stmt.bind_string(0, internaldate);
        stmt.bind_int64(1, rfc822_size);
        
        Db.Result results = stmt.exec(cancellable);
        if (!results.finished) {
            message_id = results.rowid_at(0);
            if (results.next(cancellable)) {
                debug("Warning: multiple messages with the same internaldate (%s) and size (%lu) in %s",
                    internaldate, rfc822_size, to_string());
            }
            
            Db.Statement search_stmt = cx.prepare(
                "SELECT id FROM MessageLocationTable WHERE message_id=? AND folder_id=?");
            search_stmt.bind_rowid(0, message_id);
            search_stmt.bind_rowid(1, folder_id);
            
            Db.Result search_results = search_stmt.exec(cancellable);
            associated = !search_results.finished;
            
            return message_id;
        }
        
        // no duplicates found
        return Db.INVALID_ROWID;
    }
    
    // Note: does NOT check if message is already associated with thie folder
    private void do_associate_with_folder(Db.Connection cx, int64 message_id, Geary.Email email,
        Cancellable? cancellable) throws Error {
        assert(message_id != Db.INVALID_ROWID);
        
        // insert email at supplied position
        Db.Statement stmt = cx.prepare(
            "INSERT INTO MessageLocationTable (message_id, folder_id, ordering) VALUES (?, ?, ?)");
        stmt.bind_rowid(0, message_id);
        stmt.bind_rowid(1, folder_id);
        stmt.bind_int64(2, email.id.ordering);
        
        stmt.exec(cancellable);
    }
    
    private void do_remove_association_with_folder(Db.Connection cx, Geary.EmailIdentifier id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "DELETE FROM MessageLocationTable WHERE folder_id=? AND ordering=?");
        stmt.bind_rowid(0, folder_id);
        stmt.bind_int64(1, id.ordering);
        
        stmt.exec(cancellable);
    }
    
    private bool do_create_or_merge_email(Db.Connection cx, Geary.Email email,
        out Gee.Collection<Contact> updated_contacts, Cancellable? cancellable) throws Error {
        // see if message already present in current folder, if not, search for duplicate throughout
        // mailbox
        bool associated;
        int64 message_id = do_search_for_duplicates(cx, email, out associated, cancellable);
        
        // if found, merge, and associate if necessary
        if (message_id != Db.INVALID_ROWID) {
            if (!associated)
                do_associate_with_folder(cx, message_id, email, cancellable);
            
            do_merge_email(cx, message_id, email, out updated_contacts, cancellable);
            
            // return false to indicate a merge
            return false;
        }
        
        // not found, so create and associate with this folder
        MessageRow row = new MessageRow.from_email(email);
        
        Db.Statement stmt = cx.prepare(
            "INSERT INTO MessageTable "
            + "(fields, date_field, date_time_t, from_field, sender, reply_to, to_field, cc, bcc, "
            + "message_id, in_reply_to, reference_ids, subject, header, body, preview, flags, "
            + "internaldate, rfc822_size) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        stmt.bind_int(0, row.fields);
        stmt.bind_string(1, row.date);
        stmt.bind_int64(2, row.date_time_t);
        stmt.bind_string(3, row.from);
        stmt.bind_string(4, row.sender);
        stmt.bind_string(5, row.reply_to);
        stmt.bind_string(6, row.to);
        stmt.bind_string(7, row.cc);
        stmt.bind_string(8, row.bcc);
        stmt.bind_string(9, row.message_id);
        stmt.bind_string(10, row.in_reply_to);
        stmt.bind_string(11, row.references);
        stmt.bind_string(12, row.subject);
        stmt.bind_string(13, row.header);
        stmt.bind_string(14, row.body);
        stmt.bind_string(15, row.preview);
        stmt.bind_string(16, row.email_flags);
        stmt.bind_string(17, row.internaldate);
        stmt.bind_long(18, row.rfc822_size);
        
        message_id = stmt.exec_insert(cancellable);
        do_associate_with_folder(cx, message_id, email, cancellable);
        
        // write out attachments, if any
        // TODO: Because this involves saving files, it potentially means holding up access to the
        // database while they're being written; may want to do this outside of transaction.
        if (email.fields.fulfills(Attachment.REQUIRED_FIELDS))
            do_save_attachments(cx, message_id, email.get_message().get_attachments(), cancellable);
        
        MessageAddresses message_addresses =
            new MessageAddresses.from_email(account_owner_email, email);
        foreach (Contact contact in message_addresses.contacts)
            do_update_contact_importance(cx, contact, cancellable);
        updated_contacts = message_addresses.contacts;
        
        return true;
    }
    
    private Gee.List<Geary.Email>? do_list_email(Db.Connection cx, Gee.List<LocationIdentifier> locations,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        Gee.List<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        foreach (LocationIdentifier location in locations) {
            try {
                emails.add(do_location_to_email(cx, location, required_fields, flags, cancellable));
            } catch (EngineError err) {
                if (err is EngineError.NOT_FOUND) {
                    debug("Warning: Message not found, dropping: %s", err.message);
                } else if (!(err is EngineError.INCOMPLETE_MESSAGE)) {
                    // if not all required_fields available, simply drop with no comment; it's up to
                    // the caller to detect and fulfill from the network
                    throw err;
                }
            }
        }
        
        return (emails.size > 0) ? emails : null;
    }
    
    // Throws EngineError.NOT_FOUND if message_id is invalid.  Note that this does not verify that
    // the message is indeed in this folder.
    internal static MessageRow do_fetch_message_row(Db.Connection cx, int64 message_id,
        Geary.Email.Field requested_fields, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT %s FROM MessageTable WHERE id=?".printf(fields_to_columns(requested_fields)));
        stmt.bind_rowid(0, message_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            throw new EngineError.NOT_FOUND("No message ID %s found in database", message_id.to_string());
        
        return new MessageRow.from_result(requested_fields, results);
    }
    
    private Geary.Email do_location_to_email(Db.Connection cx, LocationIdentifier location,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        if (!flags.include_marked_for_remove() && is_marked_removed(location.email_id)) {
            throw new EngineError.NOT_FOUND("Message %s marked as removed in %s",
                location.email_id.to_string(), to_string());
        }
        
        // look for perverse case
        if (required_fields == Geary.Email.Field.NONE)
            return new Geary.Email(location.position, location.email_id);
        
        MessageRow row = do_fetch_message_row(cx, location.message_id, required_fields, cancellable);
        if (!flags.is_all_set(ListFlags.PARTIAL_OK) && !row.fields.fulfills(required_fields)) {
            throw new EngineError.INCOMPLETE_MESSAGE(
                "Message %s in folder %s only fulfills %Xh fields (required: %Xh)",
                location.email_id.to_string(), to_string(), row.fields, required_fields);
        }
        
        Geary.Email email = row.to_email(location.position, location.email_id);
        
        return do_add_attachments(cx, email, location.message_id, cancellable);
    }
    
    internal static Geary.Email do_add_attachments(Db.Connection cx, Geary.Email email,
        int64 message_id, Cancellable? cancellable = null) throws Error {
        // Add attachments if available
        if (email.fields.fulfills(Geary.Attachment.REQUIRED_FIELDS)) {
            Gee.List<Geary.Attachment>? attachments = do_list_attachments(cx, message_id,
                cancellable);
            if (attachments != null)
                email.add_attachments(attachments);
        }
        
        return email;
    }
    
    private static string fields_to_columns(Geary.Email.Field fields) {
        // always pull the rowid and fields of the message
        StringBuilder builder = new StringBuilder("id, fields");
        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            unowned string? append = null;
            if (fields.is_all_set(fields)) {
                switch (field) {
                    case Geary.Email.Field.DATE:
                        append = "date_field, date_time_t";
                    break;
                    
                    case Geary.Email.Field.ORIGINATORS:
                        append = "from_field, sender, reply_to";
                    break;
                    
                    case Geary.Email.Field.RECEIVERS:
                        append = "to_field, cc, bcc";
                    break;
                    
                    case Geary.Email.Field.REFERENCES:
                        append = "message_id, in_reply_to, reference_ids";
                    break;
                    
                    case Geary.Email.Field.SUBJECT:
                        append = "subject";
                    break;
                    
                    case Geary.Email.Field.HEADER:
                        append = "header";
                    break;
                    
                    case Geary.Email.Field.BODY:
                        append = "body";
                    break;
                    
                    case Geary.Email.Field.PREVIEW:
                        append = "preview";
                    break;
                    
                    case Geary.Email.Field.FLAGS:
                        append = "flags";
                    break;
                    
                    case Geary.Email.Field.PROPERTIES:
                        append = "internaldate, rfc822_size";
                    break;
                }
            }
            
            if (append != null) {
                builder.append(", ");
                builder.append(append);
            }
        }
        
        return builder.str;
    }
    
    private Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? do_get_email_flags(Db.Connection cx,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        // prepare Statement for reuse
        Db.Statement fetch_stmt = cx.prepare("SELECT flags FROM MessageTable WHERE id=?");
        
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.EmailFlags>(Hashable.hash_func, Equalable.equal_func);
        
        foreach (Geary.EmailIdentifier id in ids) {
            int64 message_id = do_find_message(cx, id, ListFlags.NONE, cancellable);
            if (message_id == Db.INVALID_ROWID)
                continue;
            
            fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
            fetch_stmt.bind_rowid(0, message_id);
            
            Db.Result results = fetch_stmt.exec(cancellable);
            if (results.finished)
                continue;
            
            map.set(id, new Geary.Imap.EmailFlags(Geary.Imap.MessageFlags.deserialize(results.string_at(0))));
        }
        
        return (map.size > 0) ? map : null;
    }
    
    private void do_set_email_flags(Db.Connection cx, Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map,
        Cancellable? cancellable) throws Error {
        Db.Statement update_stmt = cx.prepare(
            "UPDATE MessageTable SET flags=? WHERE id=?");
        
        foreach (Geary.EmailIdentifier id in map.keys) {
            int64 message_id = do_find_message(cx, id, ListFlags.NONE, cancellable);
            if (message_id == Db.INVALID_ROWID)
                continue;
            
            Geary.Imap.MessageFlags flags = ((Geary.Imap.EmailFlags) map.get(id)).message_flags;
            
            update_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
            update_stmt.bind_string(0, flags.serialize());
            update_stmt.bind_rowid(1, message_id);
            
            update_stmt.exec(cancellable);
        }
    }
    
    private bool do_fetch_email_fields(Db.Connection cx, int64 message_id, out Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT fields FROM MessageTable WHERE id=?");
        stmt.bind_rowid(0, message_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished) {
            fields = Geary.Email.Field.NONE;
            
            return false;
        }
        
        fields = (Geary.Email.Field) results.int_at(0);
        
        return true;
    }
    
    private void do_merge_message_row(Db.Connection cx, MessageRow row,
        out Gee.Collection<Contact> updated_contacts, Cancellable? cancellable) throws Error {
        // Initialize to an empty list, in case we return early.
        updated_contacts = new Gee.LinkedList<Contact>();
        
        Geary.Email.Field available_fields;
        if (!do_fetch_email_fields(cx, row.id, out available_fields, cancellable))
            throw new EngineError.NOT_FOUND("No message with ID %s found in database", row.id.to_string());
        
        // This calculates the fields in the row that are not in the database already and then adds
        // any available mutable fields provided by the caller
        Geary.Email.Field new_fields = (row.fields ^ available_fields) & row.fields;
        new_fields |= (row.fields & Geary.Email.MUTABLE_FIELDS);
        if (new_fields == Geary.Email.Field.NONE) {
            // nothing to add
            return;
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.DATE)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET date_field=?, date_time_t=? WHERE id=?");
            stmt.bind_string(0, row.date);
            stmt.bind_int64(1, row.date_time_t);
            stmt.bind_rowid(2, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.ORIGINATORS)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET from_field=?, sender=?, reply_to=? WHERE id=?");
            stmt.bind_string(0, row.from);
            stmt.bind_string(1, row.sender);
            stmt.bind_string(2, row.reply_to);
            stmt.bind_rowid(3, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.RECEIVERS)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET to_field=?, cc=?, bcc=? WHERE id=?");
            stmt.bind_string(0, row.to);
            stmt.bind_string(1, row.cc);
            stmt.bind_string(2, row.bcc);
            stmt.bind_rowid(3, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.REFERENCES)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET message_id=?, in_reply_to=?, reference_ids=? WHERE id=?");
            stmt.bind_string(0, row.message_id);
            stmt.bind_string(1, row.in_reply_to);
            stmt.bind_string(2, row.references);
            stmt.bind_rowid(3, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.SUBJECT)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET subject=? WHERE id=?");
            stmt.bind_string(0, row.subject);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.HEADER)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET header=? WHERE id=?");
            stmt.bind_string(0, row.header);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.BODY)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET body=? WHERE id=?");
            stmt.bind_string(0, row.body);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.PREVIEW)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET preview=? WHERE id=?");
            stmt.bind_string(0, row.preview);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.FLAGS)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET flags=? WHERE id=?");
            stmt.bind_string(0, row.email_flags);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.PROPERTIES)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET internaldate=?, rfc822_size=? WHERE id=?");
            stmt.bind_string(0, row.internaldate);
            stmt.bind_long(1, row.rfc822_size);
            stmt.bind_rowid(2, row.id);
            
            stmt.exec(cancellable);
        }
        
        // now merge the new fields in the row
        Db.Statement stmt = cx.prepare(
            "UPDATE MessageTable SET fields = fields | ? WHERE id=?");
        stmt.bind_int(0, new_fields);
        stmt.bind_rowid(1, row.id);
        
        stmt.exec(cancellable);
        
        // Update the autocompletion table.
        MessageAddresses message_addresses =
            new MessageAddresses.from_row(account_owner_email, row);
        foreach (Geary.Contact contact in message_addresses.contacts)
            do_update_contact_importance(cx, contact, cancellable);
        updated_contacts = message_addresses.contacts;
    }
    
    private void do_merge_email(Db.Connection cx, int64 message_id, Geary.Email email,
        out Gee.Collection<Contact> updated_contacts, Cancellable? cancellable) throws Error {
        assert(message_id != Db.INVALID_ROWID);
        
        // Default to an empty list, in case we never call do_merge_message_row.
        updated_contacts = new Gee.LinkedList<Contact>();
        
        if (email.fields == Geary.Email.Field.NONE)
            return;
        
        // fetch message from database and merge in this email
        MessageRow row = do_fetch_message_row(cx, message_id, email.fields | Attachment.REQUIRED_FIELDS,
            cancellable);
        Geary.Email.Field db_fields = row.fields;
        row.merge_from_remote(email);
        
        // Build the combined email from the merge, which will be used to save the attachments
        Geary.Email combined_email = row.to_email(email.position, email.id);
        
        // Merge in any fields in the submitted email that aren't already in the database or are mutable
        if (((db_fields & email.fields) != email.fields) || email.fields.is_any_set(Geary.Email.MUTABLE_FIELDS)) {
            do_merge_message_row(cx, row, out updated_contacts, cancellable);
            
            // Update attachments if not already in the database
            if (!db_fields.fulfills(Attachment.REQUIRED_FIELDS)
                && combined_email.fields.fulfills(Attachment.REQUIRED_FIELDS)) {
                do_save_attachments(cx, message_id, combined_email.get_message().get_attachments(),
                    cancellable);
            }
        }
    }
    
    private static Gee.List<Geary.Attachment>? do_list_attachments(Db.Connection cx, int64 message_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT id, filename, mime_type, filesize FROM MessageAttachmentTable WHERE message_id=? "
            + "ORDER BY id");
        stmt.bind_rowid(0, message_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<Geary.Attachment> list = new Gee.ArrayList<Geary.Attachment>();
        do {
            list.add(new Geary.Attachment(cx.database.db_file.get_parent(), results.string_at(1),
                results.string_at(2), results.int64_at(3), message_id, results.rowid_at(0)));
        } while (results.next(cancellable));
        
        return list;
    }
    
    private void do_save_attachments(Db.Connection cx, int64 message_id,
        Gee.List<GMime.Part>? attachments, Cancellable? cancellable) throws Error {
        // nothing to do if no attachments
        if (attachments == null || attachments.size == 0)
            return;
        
        foreach (GMime.Part attachment in attachments) {
            string mime_type = attachment.get_content_type().to_string();
            string? filename = attachment.get_filename();
            if (String.is_empty(filename)) {
                /// Placeholder filename for attachments with no filename.
                filename = _("none");
            }
            
            // Convert the attachment content into a usable ByteArray.
            GMime.DataWrapper attachment_data = attachment.get_content_object();
            ByteArray byte_array = new ByteArray();
            GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
            stream.set_owner(false);
            if (attachment_data != null)
                attachment_data.write_to_stream(stream); // data is null if it's 0 bytes
            uint filesize = byte_array.len;
            
            // Insert it into the database.
            Db.Statement stmt = cx.prepare(
                "INSERT INTO MessageAttachmentTable (message_id, filename, mime_type, filesize) " +
                "VALUES (?, ?, ?, ?)");
            stmt.bind_rowid(0, message_id);
            stmt.bind_string(1, filename);
            stmt.bind_string(2, mime_type);
            stmt.bind_uint(3, filesize);
            
            int64 attachment_id = stmt.exec_insert(cancellable);
            
            File saved_file = File.new_for_path(Attachment.get_path(db.db_file.get_parent(), message_id,
                attachment_id, filename));
            
            debug("Saving attachment to %s", saved_file.get_path());
            
            try {
                // create directory, but don't throw exception if already exists
                try {
                    saved_file.get_parent().make_directory_with_parents(cancellable);
                } catch (IOError ioe) {
                    // fall through if already exists
                    if (!(ioe is IOError.EXISTS))
                        throw ioe;
                }
                
                // REPLACE_DESTINATION doesn't seem to work as advertised all the time ... just
                // play it safe here
                if (saved_file.query_exists(cancellable))
                    saved_file.delete(cancellable);
                
                // Create the file where the attachment will be saved and get the output stream.
                FileOutputStream saved_stream = saved_file.create(FileCreateFlags.REPLACE_DESTINATION,
                    cancellable);
                
                // Save the data to disk and flush it.
                size_t written;
                if (filesize != 0)
                    saved_stream.write_all(byte_array.data[0:filesize], out written, cancellable);
                
                saved_stream.flush(cancellable);
            } catch (Error error) {
                // An error occurred while saving the attachment, so lets remove the attachment from
                // the database and delete the file (in case it's partially written)
                debug("Failed to save attachment %s: %s", saved_file.get_path(), error.message);
                
                try {
                    saved_file.delete();
                } catch (Error delete_error) {
                    debug("Error attempting to delete partial attachment %s: %s", saved_file.get_path(),
                        delete_error.message);
                }
                
                try {
                    Db.Statement remove_stmt = cx.prepare(
                        "DELETE FROM MessageAttachmentTable WHERE id=?");
                    remove_stmt.bind_rowid(0, attachment_id);
                    
                    remove_stmt.exec();
                } catch (Error remove_error) {
                    debug("Error attempting to remove added attachment row for %s: %s",
                        saved_file.get_path(), remove_error.message);
                }
                
                throw error;
            }
        }
    }
    
}

