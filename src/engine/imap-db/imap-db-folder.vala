/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * ImapDB.Folder provides an interface for retreiving messages from the local store in methods
 * that are synonymous with Geary.Folder's interface, but with some differences that deal with
 * how IMAP addresses and organizes email.
 *
 * One important note about ImapDB.Folder: if an EmailIdentifier is returned (either by itself
 * or attached to a Geary.Email), it will always be an ImapDB.EmailIdentifier and it will always
 * have a valid Imap.UID present.  This is not the case for EmailIdentifiers returned from
 * ImapDB.Account, as those EmailIdentifiers aren't associated with a Folder, which UIDs require.
 */

private class Geary.ImapDB.Folder : BaseObject, Geary.ReferenceSemantics {
    public const Geary.Email.Field REQUIRED_FIELDS = Geary.Email.Field.PROPERTIES;
    
    private const int LIST_EMAIL_CHUNK_COUNT = 5;
    private const int LIST_EMAIL_FIELDS_CHUNK_COUNT = 500;
    
    [Flags]
    public enum ListFlags {
        NONE = 0,
        PARTIAL_OK,
        INCLUDE_MARKED_FOR_REMOVE,
        INCLUDING_ID,
        OLDEST_TO_NEWEST,
        ONLY_INCOMPLETE;
        
        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }
        
        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool include_marked_for_remove() {
            return is_all_set(INCLUDE_MARKED_FOR_REMOVE);
        }
        
        public static ListFlags from_folder_flags(Geary.Folder.ListFlags flags) {
            ListFlags result = NONE;
            
            if (flags.is_all_set(Geary.Folder.ListFlags.INCLUDING_ID))
                result |= INCLUDING_ID;
            
            if (flags.is_all_set(Geary.Folder.ListFlags.OLDEST_TO_NEWEST))
                result |= OLDEST_TO_NEWEST;
            
            return result;
        }
    }
    
    private class LocationIdentifier {
        public int64 message_id;
        public Imap.UID uid;
        public ImapDB.EmailIdentifier email_id;
        public bool marked_removed;
        
        public LocationIdentifier(int64 message_id, Imap.UID uid, bool marked_removed) {
            this.message_id = message_id;
            this.uid = uid;
            email_id = new ImapDB.EmailIdentifier(message_id, uid);
            this.marked_removed = marked_removed;
        }
    }
    
    protected int manual_ref_count { get; protected set; }
    
    private ImapDB.Database db;
    private Geary.FolderPath path;
    private ContactStore contact_store;
    private string account_owner_email;
    private int64 folder_id;
    private Geary.Imap.FolderProperties properties;
    
    /**
     * Fired after one or more emails have been fetched with all Fields, and
     * saved locally.
     */
    public signal void email_complete(Gee.Collection<Geary.EmailIdentifier> email_ids);
    
    /**
     * Fired when an email's unread (aka seen) status has changed.  This allows the account to
     * change the unread count for other folders that contain the email.
     */
    public signal void unread_updated(Gee.Map<ImapDB.EmailIdentifier, bool> unread_status);
    
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
    
    public unowned Geary.FolderPath get_path() {
        return path;
    }
    
    // Use with caution; ImapDB.Account uses this to "improve" the path with one from the server,
    // which has a usable path delimiter.
    internal void set_path(FolderPath path) {
        this.path = path;
    }
    
    public Geary.Imap.FolderProperties get_properties() {
        return properties;
    }
    
    internal void set_properties(Geary.Imap.FolderProperties properties) {
        this.properties = properties;
    }
    
    public async int get_email_count_async(ListFlags flags, Cancellable? cancellable) throws Error {
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_email_count(cx, flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        return count;
    }
    
    // Updates both the FolderProperties and the value in the local store.
    public async void update_remote_status_message_count(int count, Cancellable? cancellable) throws Error {
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
    
    // Returns a Map with the created or merged email as the key and the result of the operation
    // (true if created, false if merged) as the value.  Note that every email
    // object passed in's EmailIdentifier will be fully filled out by this
    // function (see ImapDB.EmailIdentifier.promote_with_message_id).  This
    // means if you've hashed the collection of EmailIdentifiers prior, you may
    // not be able to find them after this function.  Be warned.
    public async Gee.Map<Geary.Email, bool> create_or_merge_email_async(Gee.Collection<Geary.Email> emails,
        Cancellable? cancellable) throws Error {
        Gee.HashMap<Geary.Email, bool> results = new Gee.HashMap<Geary.Email, bool>();
        Gee.ArrayList<Geary.EmailIdentifier> complete_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Collection<Contact> updated_contacts = new Gee.ArrayList<Contact>();
        int total_unread_change = 0;
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            foreach (Geary.Email email in emails) {
                Gee.Collection<Contact>? contacts_this_email = null;
                Geary.Email.Field pre_fields;
                Geary.Email.Field post_fields;
                int unread_change = 0;
                bool created = do_create_or_merge_email(cx, email, out pre_fields,
                    out post_fields, out contacts_this_email, ref unread_change, cancellable);
                
                if (contacts_this_email != null)
                    updated_contacts.add_all(contacts_this_email);
                
                results.set(email, created);
                
                // in essence, only fire the "email-completed" signal if the local version didn't
                // have all the fields but after the create/merge now does
                if (post_fields.is_all_set(Geary.Email.Field.ALL) && !pre_fields.is_all_set(Geary.Email.Field.ALL))
                    complete_ids.add(email.id);
                
                // Update unread count in DB.
                do_add_to_unread_count(cx, unread_change, cancellable);
                
                total_unread_change += unread_change;
            }
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        if (updated_contacts.size > 0)
            contact_store.update_contacts(updated_contacts);
        
        // Update the email_unread properties.
        properties.set_status_unseen((properties.email_unread + total_unread_change).clamp(0, int.MAX));
        
        if (complete_ids.size > 0)
            email_complete(complete_ids);
        
        return results;
    }
    
    public async Gee.List<Geary.Email>? list_email_by_id_async(ImapDB.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable)
        throws Error {
        if (count <= 0)
            return null;
        
        bool including_id = flags.is_all_set(ListFlags.INCLUDING_ID);
        bool oldest_to_newest = flags.is_all_set(ListFlags.OLDEST_TO_NEWEST);
        bool only_incomplete = flags.is_all_set(ListFlags.ONLY_INCOMPLETE);
        
        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier>? locations = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            // convert initial_id into UID to start walking the list
            Imap.UID? start_uid = null;
            if (initial_id != null) {
                // use INCLUDE_MARKED_FOR_REMOVE because this is a ranged list ...
                // do_results_to_location() will deal with removing EmailIdentifiers if necessary
                LocationIdentifier? location = do_get_location_for_id(cx, initial_id,
                    ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
                if (location == null)
                    return Db.TransactionOutcome.DONE;
                
                start_uid = location.uid;
                
                // deal with exclusive searches
                if (!including_id) {
                    if (oldest_to_newest)
                        start_uid = start_uid.next();
                    else
                        start_uid = start_uid.previous();
                }
            } else if (oldest_to_newest) {
                start_uid = new Imap.UID(Imap.UID.MIN);
            } else {
                start_uid = new Imap.UID(Imap.UID.MAX);
            }
            
            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
            """);
            if (only_incomplete) {
                sql.append("""
                    INNER JOIN MessageTable
                    ON MessageTable.id = MessageLocationTable.message_id
                """);
            }
            
            sql.append("WHERE folder_id = ? ");
            
            if (oldest_to_newest)
                sql.append("AND ordering >= ? ");
            else
                sql.append("AND ordering <= ? ");
            
            if (only_incomplete)
                sql.append_printf("AND fields != %d ", Geary.Email.Field.ALL);
            
            if (oldest_to_newest)
                sql.append("ORDER BY ordering ASC ");
            else
                sql.append("ORDER BY ordering DESC ");
            
            sql.append("LIMIT ?");
            
            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            stmt.bind_int(2, count);
            
            locations = do_results_to_locations(stmt.exec(cancellable), flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, read in email in chunks
        return yield list_email_in_chunks_async(locations, required_fields, flags, cancellable);
    }
    
    // ListFlags.OLDEST_TO_NEWEST is ignored.  INCLUDING_ID means including *both* identifiers.
    // Without this flag, neither are considered as part of the range.
    public async Gee.List<Geary.Email>? list_email_by_range_async(ImapDB.EmailIdentifier start_id,
        ImapDB.EmailIdentifier end_id, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable)
        throws Error {
        bool including_id = flags.is_all_set(ListFlags.INCLUDING_ID);
        
        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier>? locations = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            // use INCLUDE_MARKED_FOR_REMOVE because this is a ranged list ...
            // do_results_to_location() will deal with removing EmailIdentifiers if necessary
            LocationIdentifier? start_location = do_get_location_for_id(cx, start_id,
                ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
            if (start_location == null)
                return Db.TransactionOutcome.DONE;
            
            Imap.UID start_uid = start_location.uid;
            
            // see note above about INCLUDE_MARKED_FOR_REMOVE
            LocationIdentifier? end_location = do_get_location_for_id(cx, end_id,
                ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
            if (end_location == null)
                return Db.TransactionOutcome.DONE;
            
            Imap.UID end_uid = end_location.uid;
            
            if (!including_id) {
                start_uid = start_uid.next();
                end_uid = end_uid.previous();
            }
            
            if (start_uid.compare_to(end_uid) > 0)
                return Db.TransactionOutcome.DONE;
            
            Db.Statement stmt = cx.prepare("""
                SELECT message_id, ordering, remove_marker
                FROM MessageLocationTable
                WHERE folder_id = ? AND ordering >= ? AND ordering <= ?
            """);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            stmt.bind_int64(2, end_uid.value);
            
            locations = do_results_to_locations(stmt.exec(cancellable), flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, read in email in chunks
        return yield list_email_in_chunks_async(locations, required_fields, flags, cancellable);
    }
    
    // ListFlags.OLDEST_TO_NEWEST is ignored.  INCLUDING_ID means including *both* identifiers.
    // Without this flag, neither are considered as part of the range.
    public async Gee.List<Geary.Email>? list_email_by_uid_range_async(Imap.UID start,
        Imap.UID end, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable)
        throws Error {
        bool including_id = flags.is_all_set(ListFlags.INCLUDING_ID);
        bool only_incomplete = flags.is_all_set(ListFlags.ONLY_INCOMPLETE);
        
        Imap.UID start_uid = start;
        Imap.UID end_uid = end;
        
        if (!including_id) {
            start_uid = start_uid.next();
            end_uid = end_uid.previous();
        }
        
        if (start_uid.compare_to(end_uid) > 0)
            return null;
            
        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier>? locations = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
            """);
            
            if (only_incomplete) {
                sql.append("""
                    INNER JOIN MessageTable
                    ON MessageTable.id = MessageLocationTable.message_id
                """);
            }
            
            sql.append("WHERE folder_id = ? AND ordering >= ? AND ordering <= ? ");
            if (only_incomplete)
                sql.append_printf(" AND fields != %d ", Geary.Email.Field.ALL);
            
            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            stmt.bind_int64(2, end_uid.value);
            
            locations = do_results_to_locations(stmt.exec(cancellable), flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, read in email in chunks
        return yield list_email_in_chunks_async(locations, required_fields, flags, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_by_sparse_id_async(Gee.Collection<ImapDB.EmailIdentifier> ids,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        if (ids.size == 0)
            return null;
        
        bool only_incomplete = flags.is_all_set(ListFlags.ONLY_INCOMPLETE);
        
        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier> locations = new Gee.ArrayList<LocationIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
            """);
            
            if (only_incomplete) {
                sql.append("""
                    INNER JOIN MessageTable
                    ON MessageTable.id = MessageLocationTable.message_id
                """);
            }
            
            sql.append("WHERE folder_id = ? ");
            if (only_incomplete)
                sql.append_printf(" AND fields != %d ", Geary.Email.Field.ALL);
            
            sql.append("AND ordering IN (");
            bool first = true;
            foreach (ImapDB.EmailIdentifier id in ids) {
                LocationIdentifier? location = do_get_location_for_id(cx, id, flags, cancellable);
                if (location == null)
                    continue;
                
                if (!first)
                    sql.append(", ");
                
                sql.append(location.uid.to_string());
                first = false;
            }
            sql.append(")");
            
            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            
            locations = do_results_to_locations(stmt.exec(cancellable), flags, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        // Next, read in email in chunks
        return yield list_email_in_chunks_async(locations, required_fields, flags, cancellable);
    }
    
    private async Gee.List<Geary.Email>? list_email_in_chunks_async(Gee.List<LocationIdentifier>? ids,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        if (ids == null || ids.size == 0)
            return null;
        
        int length_rounded_up = Numeric.int_round_up(ids.size, LIST_EMAIL_CHUNK_COUNT);
        
        Gee.List<Geary.Email> results = new Gee.ArrayList<Geary.Email>();
        for (int start = 0; start < length_rounded_up; start += LIST_EMAIL_CHUNK_COUNT) {
            // stop is the index *after* the end of the slice
            int stop = Numeric.int_ceiling((start + LIST_EMAIL_CHUNK_COUNT), ids.size);
            
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
        
        if (results.size != ids.size)
            debug("list_email_in_chunks_async: Requested %d email, returned %d", ids.size, results.size);
        
        return (results.size > 0) ? results : null;
    }
    
    public async Geary.Email fetch_email_async(ImapDB.EmailIdentifier id,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        Geary.Email? email = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            LocationIdentifier? location = do_get_location_for_id(cx, id, flags, cancellable);
            if (location == null)
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
    
    // Note that this does INCLUDES messages marked for removal
    // TODO: Let the user request a SortedSet, or have them provide the Set to add to
    public async Gee.Set<Imap.UID>? list_uids_by_range_async(Imap.UID first_uid, Imap.UID last_uid,
        bool include_marked_for_removal, Cancellable? cancellable) throws Error {
        // order correctly
        Imap.UID start, end;
        if (first_uid.compare_to(last_uid) < 0) {
            start = first_uid;
            end = last_uid;
        } else {
            start = last_uid;
            end = first_uid;
        }
        
        Gee.Set<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                SELECT ordering, remove_marker
                FROM MessageLocationTable
                WHERE folder_id = ? AND ordering >= ? AND ordering <= ?
            """);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start.value);
            stmt.bind_int64(2, end.value);
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                if (include_marked_for_removal || !result.bool_at(1))
                    uids.add(new Imap.UID(result.int64_at(0)));
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (uids.size > 0) ? uids : null;
    }
    
    // pos is 1-based.  This method does not respect messages marked for removal.
    public async ImapDB.EmailIdentifier? get_id_at_async(int pos, Cancellable? cancellable) throws Error {
        assert(pos >= 1);
        
        ImapDB.EmailIdentifier? id = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                SELECT message_id, ordering
                FROM MessageLocationTable
                WHERE folder_id=?
                ORDER BY ordering
                LIMIT 1
                OFFSET ?
            """);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int(1, pos - 1);
            
            Db.Result results = stmt.exec(cancellable);
            if (!results.finished)
                id = new ImapDB.EmailIdentifier(results.rowid_at(0), new Imap.UID(results.int64_at(1)));
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return id;
    }
    
    public async Imap.UID? get_uid_async(ImapDB.EmailIdentifier id, ListFlags flags,
        Cancellable? cancellable) throws Error {
        // Always look up the UID rather than pull the one from the EmailIdentifier; it could be
        // for another Folder
        Imap.UID? uid = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            LocationIdentifier? location = do_get_location_for_id(cx, id, flags, cancellable);
            if (location != null)
                uid = location.uid;
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return uid;
    }
    
    public async Gee.Set<Imap.UID>? get_uids_async(Gee.Collection<ImapDB.EmailIdentifier> ids,
        ListFlags flags, Cancellable? cancellable) throws Error {
        // Always look up the UID rather than pull the one from the EmailIdentifier; it could be
        // for another Folder
        Gee.Set<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            foreach (ImapDB.EmailIdentifier id in ids) {
                LocationIdentifier? location = do_get_location_for_id(cx, id, flags, cancellable);
                if (location != null)
                    uids.add(location.uid);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (uids.size > 0) ? uids : null;
    }
    
    // Returns null if the UID is not found in this Folder.
    public async ImapDB.EmailIdentifier? get_id_async(Imap.UID uid, ListFlags flags,
        Cancellable? cancellable) throws Error {
        ImapDB.EmailIdentifier? id = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            LocationIdentifier? location = do_get_location_for_uid(cx, uid, flags,
                cancellable);
            if (location != null)
                id = location.email_id;
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return id;
    }
    
    public async Gee.Set<ImapDB.EmailIdentifier>? get_ids_async(Gee.Collection<Imap.UID> uids,
        ListFlags flags, Cancellable? cancellable) throws Error {
        Gee.Set<ImapDB.EmailIdentifier> ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            foreach (Imap.UID uid in uids) {
                LocationIdentifier? location = do_get_location_for_uid(cx, uid, flags,
                    cancellable);
                if (location != null)
                    ids.add(location.email_id);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return (ids.size > 0) ? ids : null;
    }
    
    // This does not respect messages marked for removal.
    public async ImapDB.EmailIdentifier? get_earliest_id_async(Cancellable? cancellable) throws Error {
        return yield get_id_extremes_async(true, cancellable);
    }
    
    // This does not respect messages marked for removal.
    public async ImapDB.EmailIdentifier? get_latest_id_async(Cancellable? cancellable) throws Error {
        return yield get_id_extremes_async(false, cancellable);
    }
    
    private async ImapDB.EmailIdentifier? get_id_extremes_async(bool earliest, Cancellable? cancellable)
        throws Error {
        ImapDB.EmailIdentifier? id = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt;
            if (earliest)
                stmt = cx.prepare("SELECT MIN(ordering), message_id FROM MessageLocationTable WHERE folder_id=?");
            else
                stmt = cx.prepare("SELECT MAX(ordering), message_id FROM MessageLocationTable WHERE folder_id=?");
            stmt.bind_rowid(0, folder_id);
            
            Db.Result results = stmt.exec(cancellable);
            // MIN and MAX return NULL if the result set being examined is zero-length
            if (!results.finished && !results.is_null_at(0))
                id = new ImapDB.EmailIdentifier(results.rowid_at(1), new Imap.UID(results.int64_at(0)));
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return id;
    }
    
    public async void detach_multiple_emails_async(Gee.Collection<ImapDB.EmailIdentifier> ids,
        Cancellable? cancellable) throws Error {
        int unread_count = 0;
        // TODO: Right now, deleting an email is merely detaching its association with a folder
        // (since it may be located in multiple folders).  This means at some point in the future
        // a vacuum will be required to remove emails that are completely unassociated with the
        // account.
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            unread_count = do_get_unread_count_for_ids(cx, ids, cancellable);
            do_add_to_unread_count(cx, -unread_count, cancellable);
            
            // prepare DELETE Statement and invariants
            Db.Statement delete_stmt = cx.prepare(
                "DELETE FROM MessageLocationTable WHERE folder_id=? AND message_id=?");
            delete_stmt.bind_rowid(0, folder_id);
            
            // remove one at a time, gather UIDs
            Gee.HashSet<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
            foreach (ImapDB.EmailIdentifier id in ids) {
                LocationIdentifier? location = do_get_location_for_id(cx, id,
                    ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
                if (location == null)
                    continue;
                
                delete_stmt.reset(Db.ResetScope.SAVE_BINDINGS);
                delete_stmt.bind_rowid(1, location.message_id);
                
                delete_stmt.exec(cancellable);
                
                uids.add(location.uid);
            }
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        if (unread_count > 0)
            properties.set_status_unseen(properties.email_unread - unread_count);
    }
    
    public async void detach_all_emails_async(Cancellable? cancellable) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            Db.Statement stmt = cx.prepare(
                "DELETE FROM MessageLocationTable WHERE folder_id=?");
            stmt.bind_rowid(0, folder_id);
            
            Db.Statement update_stmt = cx.prepare(
                "UPDATE FolderTable SET unread_count = 0 WHERE id=?");
            update_stmt.bind_rowid(0, folder_id);
            update_stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async void mark_email_async(Gee.Collection<ImapDB.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, Cancellable? cancellable)
        throws Error {
        int unread_change = 0; // Negative means messages are read, positive means unread.
        Gee.Map<ImapDB.EmailIdentifier, bool> unread_status = new Gee.HashMap<ImapDB.EmailIdentifier, bool>();
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            // fetch flags for each email
            Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? map = do_get_email_flags(cx,
                to_mark, cancellable);
            if (map == null)
                return Db.TransactionOutcome.COMMIT;
            
            // update flags according to arguments
            foreach (ImapDB.EmailIdentifier id in map.keys) {
                Geary.Imap.EmailFlags flags = ((Geary.Imap.EmailFlags) map.get(id));
                
                if (flags_to_add != null) {
                    foreach (Geary.NamedFlag flag in flags_to_add.get_all()) {
                        if (flags.contains(flag))
                            continue;
                        
                        flags.add(flag);
                        
                        if (flag.equal_to(Geary.EmailFlags.UNREAD)) {
                            unread_change++;
                            unread_status.set(id, true);
                        }
                    }
                }
                
                if (flags_to_remove != null) {
                    foreach (Geary.NamedFlag flag in flags_to_remove.get_all()) {
                        if (!flags.contains(flag))
                            continue;
                        
                        flags.remove(flag);
                        
                        if (flag.equal_to(Geary.EmailFlags.UNREAD)) {
                            unread_change--;
                            unread_status.set(id, false);
                        }
                    }
                }
            }
            
            // write them all back out
            do_set_email_flags(cx, map, cancellable);
            
            // Update unread count.
            do_add_to_unread_count(cx, unread_change, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        // Update the email_unread properties.
        properties.set_status_unseen((properties.email_unread + unread_change).clamp(0, int.MAX));
        
        // Signal changes so other folders can be updated.
        if (unread_status.size > 0)
            unread_updated(unread_status);
    }
    
    public async Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? get_email_flags_async(
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? map = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            map = do_get_email_flags(cx, ids, cancellable);
            
            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);
        
        return map;
    }
    
    public async void set_email_flags_async(Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map,
        Cancellable? cancellable) throws Error {
        Error? error = null;
        int unread_change = 0; // Negative means messages are read, positive means unread.
        
        try {
            yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
                // TODO get current flags, compare to ones being set
                Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? existing_map =
                    do_get_email_flags(cx, map.keys, cancellable);
                
                if (existing_map != null) {
                    foreach(ImapDB.EmailIdentifier id in map.keys) {
                        Geary.EmailFlags? existing_flags = existing_map.get(id);
                        if (existing_flags == null)
                            continue;
                        
                        Geary.EmailFlags new_flags = map.get(id);
                        if (!existing_flags.contains(Geary.EmailFlags.UNREAD) &&
                            new_flags.contains(Geary.EmailFlags.UNREAD))
                            unread_change++;
                        else if (existing_flags.contains(Geary.EmailFlags.UNREAD) &&
                            !new_flags.contains(Geary.EmailFlags.UNREAD))
                            unread_change--;
                    }
                }
                
                do_set_email_flags(cx, map, cancellable);
                
                // Update unread count.
                do_add_to_unread_count(cx, unread_change, cancellable);
                
                // TODO set db unread count
                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
        } catch (Error e) {
            error = e;
        }
        
        // Update the email_unread properties.
        if (error == null) {
            properties.set_status_unseen((properties.email_unread + unread_change).clamp(0, int.MAX));
        } else {
            throw error;
        }
    }
    
    public async void detach_single_email_async(ImapDB.EmailIdentifier id, out bool is_marked,
        Cancellable? cancellable) throws Error {
        bool internal_is_marked = false;
        bool was_unread = false;
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            LocationIdentifier? location = do_get_location_for_id(cx, id, ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                cancellable);
            if (location == null) {
                throw new EngineError.NOT_FOUND("Message %s cannot be removed from %s: not found",
                    id.to_string(), to_string());
            }
            
            // Check to see if message is unread (this only affects non-marked emails.)
            if (do_get_unread_count_for_ids(cx, new Geary.Collection.SingleItem
                <ImapDB.EmailIdentifier>(id), cancellable) > 0) {
                do_add_to_unread_count(cx, -1, cancellable);
                was_unread = true;
            }
            
            internal_is_marked = location.marked_removed;
            
            do_remove_association_with_folder(cx, location, cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        is_marked = internal_is_marked;
        
        if (was_unread)
            properties.set_status_unseen(properties.email_unread - 1);
    }
    
    // Mark messages as removed (but not expunged) from the folder.  Marked messages are skipped
    // on most operations unless ListFlags.INCLUDE_MARKED_REMOVED is true.  Use detach_email_async()
    // to formally remove the messages from the folder.
    //
    // Returns a collection of ImapDB.EmailIdentifiers *with the UIDs set* for this folder.
    // Supplied EmailIdentifiers not in this Folder will not be included.
    public async Gee.Set<ImapDB.EmailIdentifier>? mark_removed_async(
        Gee.Collection<ImapDB.EmailIdentifier> ids, bool mark_removed, Cancellable? cancellable)
        throws Error {
        int unread_count = 0;
        Gee.Set<ImapDB.EmailIdentifier> removed_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            unread_count = do_get_unread_count_for_ids(cx, ids, cancellable);
            
            Gee.HashSet<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
            foreach (ImapDB.EmailIdentifier id in ids) {
                LocationIdentifier? location = do_get_location_for_id(cx, id,
                    ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
                if (location != null) {
                    uids.add(location.uid);
                    removed_ids.add(location.email_id);
                }
            }
            
            if (uids.size > 0)
                do_mark_unmark_removed(cx, uids, mark_removed, cancellable);
            
            do_add_to_unread_count(cx, -unread_count, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (unread_count > 0)
            properties.set_status_unseen(properties.email_unread - unread_count);
        
        return (removed_ids.size > 0) ? removed_ids : null;
    }
    
    // Returns the number of messages marked for removal in this folder
    public async int get_marked_for_remove_count_async(Cancellable? cancellable) throws Error {
        int count = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            count = do_get_marked_removed_count(cx, cancellable);
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return count;
    }
    
    // Clears all remove markers from the folder
    public async void clear_remove_markers_async(Cancellable? cancellable) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                UPDATE MessageLocationTable
                SET remove_marker=?
                WHERE folder_id=? AND remove_marker <> ?
            """);
            stmt.bind_bool(0, false);
            stmt.bind_rowid(1, folder_id);
            stmt.bind_bool(2, false);
            
            stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async Gee.Map<ImapDB.EmailIdentifier, Geary.Email.Field>? list_email_fields_by_id_async(
        Gee.Collection<ImapDB.EmailIdentifier> ids, ListFlags flags, Cancellable? cancellable)
        throws Error {
        if (ids.size == 0)
            return null;
        
        Gee.HashMap<Geary.EmailIdentifier, Geary.Email.Field> map = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email.Field>();
        
        // Break up the work
        Gee.List<ImapDB.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Iterator<ImapDB.EmailIdentifier> iter = ids.iterator();
        while (iter.next()) {
            list.add(iter.get());
            if (list.size < LIST_EMAIL_FIELDS_CHUNK_COUNT && iter.has_next())
                continue;
            
            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                Db.Statement fetch_stmt = cx.prepare(
                    "SELECT fields FROM MessageTable WHERE id = ?");
                
                foreach (ImapDB.EmailIdentifier id in list) {
                    LocationIdentifier? location_id = do_get_location_for_id(cx, id, flags,
                        cancellable);
                    if (location_id == null)
                        continue;
                    
                    fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
                    fetch_stmt.bind_rowid(0, location_id.message_id);
                    
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
        
        int marked = !flags.include_marked_for_remove() ? do_get_marked_removed_count(cx, cancellable) : 0;
        
        return Numeric.int_floor(results.int_at(0) - marked, 0);
    }
    
    private int do_get_marked_removed_count(Db.Connection cx, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*) FROM MessageLocationTable WHERE folder_id=? AND remove_marker <> ?");
        stmt.bind_rowid(0, folder_id);
        stmt.bind_bool(1, false);
        
        Db.Result results = stmt.exec(cancellable);
        
        return !results.finished ? results.int_at(0) : 0;
    }
    
    private void do_mark_unmark_removed(Db.Connection cx, Gee.Collection<Imap.UID> uids,
        bool mark_removed, Cancellable? cancellable) throws Error {
        // prepare Statement for reuse
        Db.Statement stmt = cx.prepare(
            "UPDATE MessageLocationTable SET remove_marker=? WHERE folder_id=? AND ordering=?");
        stmt.bind_bool(0, mark_removed);
        stmt.bind_rowid(1, folder_id);
        
        foreach (Imap.UID uid in uids) {
            stmt.bind_int64(2, uid.value);
            
            stmt.exec(cancellable);
            
            // keep folder_id and mark_removed, replace UID each iteration
            stmt.reset(Db.ResetScope.SAVE_BINDINGS);
        }
    }
    
    // Returns message_id if duplicate found, associated set to true if message is already associated
    // with this folder.  Only call this on emails that came from the IMAP Folder.
    private LocationIdentifier? do_search_for_duplicates(Db.Connection cx, Geary.Email email,
        out bool associated, Cancellable? cancellable) throws Error {
        associated = false;
        
        ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
        
        // This should only ever get invoked for messages that came from the
        // IMAP layer, which don't have a message id, but should have a UID.
        assert(email_id.message_id == Db.INVALID_ROWID);
        
        LocationIdentifier? location = null;
        // See if it already exists; first by UID (which is only guaranteed to
        // be unique in a folder, not account-wide)
        if (email_id.uid != null)
            location = do_get_location_for_uid(cx, email_id.uid, ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                cancellable);
        
        if (location != null) {
            associated = true;
            
            return location;
        }
        
        // if fields not present, then no duplicate can reliably be found
        if (!email.fields.is_all_set(REQUIRED_FIELDS)) {
            debug("Unable to detect duplicates for %s (%s available)", email.id.to_string(),
                email.fields.to_list_string());
            
            return null;
        }
        
        // what's more, actually need all those fields to be available, not merely attempted,
        // to err on the side of safety
        Imap.EmailProperties? imap_properties = (Imap.EmailProperties) email.properties;
        string? internaldate = (imap_properties != null && imap_properties.internaldate != null)
            ? imap_properties.internaldate.serialize() : null;
        long rfc822_size = (imap_properties != null) ? imap_properties.rfc822_size.value : -1;
        
        if (String.is_empty(internaldate) || rfc822_size < 0) {
            debug("Unable to detect duplicates for %s (%s available but invalid)", email.id.to_string(),
                email.fields.to_list_string());
            
            return null;
        }
        
        // look for duplicate in IMAP message properties
        Db.Statement stmt = cx.prepare(
            "SELECT id FROM MessageTable WHERE internaldate=? AND rfc822_size=?");
        stmt.bind_string(0, internaldate);
        stmt.bind_int64(1, rfc822_size);
        
        Db.Result results = stmt.exec(cancellable);
        // no duplicates found
        if (results.finished)
            return null;
        
        int64 message_id = results.rowid_at(0);
        if (results.next(cancellable)) {
            debug("Warning: multiple messages with the same internaldate (%s) and size (%lu) in %s",
                internaldate, rfc822_size, to_string());
        }
        
        Db.Statement search_stmt = cx.prepare(
            "SELECT ordering, remove_marker FROM MessageLocationTable WHERE message_id=? AND folder_id=?");
        search_stmt.bind_rowid(0, message_id);
        search_stmt.bind_rowid(1, folder_id);
        
        Db.Result search_results = search_stmt.exec(cancellable);
        if (!search_results.finished) {
            associated = true;
            location = new LocationIdentifier(message_id, new Imap.UID(search_results.int64_at(0)),
                search_results.bool_at(1));
        } else {
            assert(email_id.uid != null);
            location = new LocationIdentifier(message_id, email_id.uid, false);
        }
        
        return location;
    }
    
    // Note: does NOT check if message is already associated with thie folder
    private void do_associate_with_folder(Db.Connection cx, int64 message_id, Imap.UID uid,
        Cancellable? cancellable) throws Error {
        assert(message_id != Db.INVALID_ROWID);
        
        // insert email at supplied position
        Db.Statement stmt = cx.prepare(
            "INSERT INTO MessageLocationTable (message_id, folder_id, ordering) VALUES (?, ?, ?)");
        stmt.bind_rowid(0, message_id);
        stmt.bind_rowid(1, folder_id);
        stmt.bind_int64(2, uid.value);
        
        stmt.exec(cancellable);
    }
    
    private void do_remove_association_with_folder(Db.Connection cx, LocationIdentifier location,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "DELETE FROM MessageLocationTable WHERE folder_id=? AND message_id=?");
        stmt.bind_rowid(0, folder_id);
        stmt.bind_int64(1, location.message_id);
        
        stmt.exec(cancellable);
    }
    
    private bool do_create_or_merge_email(Db.Connection cx, Geary.Email email,
        out Geary.Email.Field pre_fields, out Geary.Email.Field post_fields,
        out Gee.Collection<Contact> updated_contacts, ref int unread_count_change,
        Cancellable? cancellable) throws Error {
        // see if message already present in current folder, if not, search for duplicate throughout
        // mailbox
        bool associated;
        LocationIdentifier? location = do_search_for_duplicates(cx, email, out associated, cancellable);
        
        // if found, merge, and associate if necessary
        if (location != null) {
            if (!associated)
                do_associate_with_folder(cx, location.message_id, location.uid, cancellable);
            
            // If the email came from the Imap layer, we need to fill in the id.
            ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
            if (email_id.message_id == Db.INVALID_ROWID)
                email_id.promote_with_message_id(location.message_id);
            
            // special-case updating flags, which happens often and should only write to the DB
            // if necessary
            if (email.fields != Geary.Email.Field.FLAGS) {
                do_merge_email(cx, location, email, out pre_fields, out post_fields,
                    out updated_contacts, ref unread_count_change, cancellable);
                
                // Already associated with folder and flags were known.
                if (associated && pre_fields.is_all_set(Geary.Email.Field.FLAGS))
                    unread_count_change = 0;
            } else {
                do_merge_email_flags(cx, location, email, out pre_fields, out post_fields,
                    out updated_contacts, ref unread_count_change, cancellable);
            }
            
            // return false to indicate a merge
            return false;
        }
        
        // not found, so create and associate with this folder
        MessageRow row = new MessageRow.from_email(email);
        
        ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
        
        // the create case *requires* a UID be present (originating from Imap.Folder)
        Imap.UID? uid = email_id.uid;
        assert(uid != null);
        
        pre_fields = Geary.Email.Field.NONE;
        post_fields = email.fields;
        
        Db.Statement stmt = cx.prepare(
            "INSERT INTO MessageTable "
            + "(fields, date_field, date_time_t, from_field, sender, reply_to, to_field, cc, bcc, "
            + "message_id, in_reply_to, reference_ids, subject, header, body, preview, flags, "
            + "internaldate, internaldate_time_t, rfc822_size) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
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
        stmt.bind_string_buffer(13, row.header);
        stmt.bind_string_buffer(14, row.body);
        stmt.bind_string(15, row.preview);
        stmt.bind_string(16, row.email_flags);
        stmt.bind_string(17, row.internaldate);
        stmt.bind_int64(18, row.internaldate_time_t);
        stmt.bind_long(19, row.rfc822_size);
        
        int64 message_id = stmt.exec_insert(cancellable);
        
        // Make sure the id is filled in even if it came from the Imap layer.
        if (email_id.message_id == Db.INVALID_ROWID)
            email_id.promote_with_message_id(message_id);
        
        do_associate_with_folder(cx, message_id, uid, cancellable);
        
        // write out attachments, if any
        // TODO: Because this involves saving files, it potentially means holding up access to the
        // database while they're being written; may want to do this outside of transaction.
        if (email.fields.fulfills(Attachment.REQUIRED_FIELDS))
            do_save_attachments(cx, message_id, email.get_message().get_attachments(), cancellable);
        
        do_add_email_to_search_table(cx, message_id, email, cancellable);
        
        MessageAddresses message_addresses =
            new MessageAddresses.from_email(account_owner_email, email);
        foreach (Contact contact in message_addresses.contacts)
            do_update_contact(cx, contact, cancellable);
        updated_contacts = message_addresses.contacts;
        
        // Update unread count if our new email is unread.
        if (email.email_flags != null && email.email_flags.is_unread())
            unread_count_change++;
        
        return true;
    }
    
    internal static void do_add_email_to_search_table(Db.Connection cx, int64 message_id,
        Geary.Email email, Cancellable? cancellable) throws Error {
        string? body = null;
        try {
            body = email.get_message().get_searchable_body();
        } catch (Error e) {
            // Ignore.
        }
        string? recipients = null;
        try {
            recipients = email.get_message().get_searchable_recipients();
        } catch (Error e) {
            // Ignore.
        }
        
        Db.Statement stmt = cx.prepare("""
            INSERT INTO MessageSearchTable
                (id, body, attachment, subject, from_field, receivers, cc, bcc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """);
        stmt.bind_rowid(0, message_id);
        stmt.bind_string(1, body);
        stmt.bind_string(2, email.get_searchable_attachment_list());
        stmt.bind_string(3, (email.subject != null ? email.subject.to_searchable_string() : null));
        stmt.bind_string(4, (email.from != null ? email.from.to_searchable_string() : null));
        stmt.bind_string(5, recipients);
        stmt.bind_string(6, (email.cc != null ? email.cc.to_searchable_string() : null));
        stmt.bind_string(7, (email.bcc != null ? email.bcc.to_searchable_string() : null));
        
        stmt.exec_insert(cancellable);
    }
    
    private static bool do_check_for_message_search_row(Db.Connection cx, int64 message_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT 'TRUE' FROM MessageSearchTable WHERE id=?");
        stmt.bind_rowid(0, message_id);
        
        Db.Result result = stmt.exec(cancellable);
        return !result.finished;
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
        Geary.Email.Field requested_fields, out Geary.Email.Field db_fields,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT %s FROM MessageTable WHERE id=?".printf(fields_to_columns(requested_fields)));
        stmt.bind_rowid(0, message_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            throw new EngineError.NOT_FOUND("No message ID %s found in database", message_id.to_string());
        
        db_fields = (Geary.Email.Field) results.int_for("fields");
        return new MessageRow.from_result(requested_fields, results);
    }
    
    private Geary.Email do_location_to_email(Db.Connection cx, LocationIdentifier location,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        if (!flags.include_marked_for_remove() && location.marked_removed) {
            throw new EngineError.NOT_FOUND("Message %s marked as removed in %s",
                location.email_id.to_string(), to_string());
        }
        
        // look for perverse case
        if (required_fields == Geary.Email.Field.NONE)
            return new Geary.Email(location.email_id);
        
        Geary.Email.Field db_fields;
        MessageRow row = do_fetch_message_row(cx, location.message_id, required_fields,
            out db_fields, cancellable);
        if (!flags.is_all_set(ListFlags.PARTIAL_OK) && !row.fields.fulfills(required_fields)) {
            throw new EngineError.INCOMPLETE_MESSAGE(
                "Message %s in folder %s only fulfills %Xh fields (required: %Xh)",
                location.email_id.to_string(), to_string(), row.fields, required_fields);
        }
        
        Geary.Email email = row.to_email(location.email_id);
        
        return do_add_attachments(cx, email, location.message_id, cancellable);
    }
    
    internal static Geary.Email do_add_attachments(Db.Connection cx, Geary.Email email,
        int64 message_id, Cancellable? cancellable = null) throws Error {
        // Add attachments if available
        if (email.fields.fulfills(ImapDB.Attachment.REQUIRED_FIELDS)) {
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
                        append = "internaldate, internaldate_time_t, rfc822_size";
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
    
    private Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? do_get_email_flags(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        // prepare Statement for reuse
        Db.Statement fetch_stmt = cx.prepare("SELECT flags FROM MessageTable WHERE id=?");
        
        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.EmailFlags>();
        foreach (ImapDB.EmailIdentifier id in ids) {
            LocationIdentifier? location = do_get_location_for_id(cx, id, ListFlags.NONE, cancellable);
            if (location == null)
                continue;
            
            fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
            fetch_stmt.bind_rowid(0, location.message_id);
            
            Db.Result results = fetch_stmt.exec(cancellable);
            if (results.finished)
                continue;
            
            map.set(location.email_id,
                new Geary.Imap.EmailFlags(Geary.Imap.MessageFlags.deserialize(results.string_at(0))));
        }
        
        return (map.size > 0) ? map : null;
    }
    
    private Geary.EmailFlags? do_get_email_flags_single(Db.Connection cx, int64 message_id, 
        Cancellable? cancellable) throws Error {
        Db.Statement fetch_stmt = cx.prepare("SELECT flags FROM MessageTable WHERE id=?");
        fetch_stmt.bind_rowid(0, message_id);
        
        Db.Result results = fetch_stmt.exec(cancellable);
        
        if (results.finished)
            return null;
        
        return new Geary.Imap.EmailFlags(Geary.Imap.MessageFlags.deserialize(results.string_at(0)));
    }
    
    private void do_set_email_flags(Db.Connection cx, Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map,
        Cancellable? cancellable) throws Error {
        Db.Statement update_stmt = cx.prepare(
            "UPDATE MessageTable SET flags=?, fields = fields | ? WHERE id=?");
        
        foreach (ImapDB.EmailIdentifier id in map.keys) {
            LocationIdentifier? location = do_get_location_for_id(cx, id, ListFlags.NONE,
                cancellable);
            if (location == null)
                continue;
            
            Geary.Imap.MessageFlags flags = ((Geary.Imap.EmailFlags) map.get(id)).message_flags;
            
            update_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
            update_stmt.bind_string(0, flags.serialize());
            update_stmt.bind_int(1, Geary.Email.Field.FLAGS);
            update_stmt.bind_rowid(2, id.message_id);
            
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
        out Geary.Email.Field new_fields, out Gee.Collection<Contact> updated_contacts,
        ref int unread_count_change, Cancellable? cancellable) throws Error {
        
        // Initialize to an empty list, in case we return early.
        updated_contacts = new Gee.LinkedList<Contact>();
        
        Geary.Email.Field available_fields;
        if (!do_fetch_email_fields(cx, row.id, out available_fields, cancellable))
            throw new EngineError.NOT_FOUND("No message with ID %s found in database", row.id.to_string());
        
        // This calculates the fields in the row that are not in the database already and then adds
        // any available mutable fields provided by the caller
        new_fields = (row.fields ^ available_fields) & row.fields;
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
            stmt.bind_string_buffer(0, row.header);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.BODY)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET body=? WHERE id=?");
            stmt.bind_string_buffer(0, row.body);
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
            // Fetch existing flags to update unread count
            Geary.EmailFlags? old_flags = do_get_email_flags_single(cx, row.id, cancellable);
            Geary.EmailFlags new_flags = new Geary.Imap.EmailFlags(
                    Geary.Imap.MessageFlags.deserialize(row.email_flags));
            
            if (old_flags != null && (old_flags.is_unread() != new_flags.is_unread()))
                unread_count_change += new_flags.is_unread() ? 1 : -1;
            else if (new_flags.is_unread())
                unread_count_change++;
            
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET flags=? WHERE id=?");
            stmt.bind_string(0, row.email_flags);
            stmt.bind_rowid(1, row.id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.PROPERTIES)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageTable SET internaldate=?, internaldate_time_t=?, rfc822_size=? WHERE id=?");
            stmt.bind_string(0, row.internaldate);
            stmt.bind_int64(1, row.internaldate_time_t);
            stmt.bind_long(2, row.rfc822_size);
            stmt.bind_rowid(3, row.id);
            
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
            do_update_contact(cx, contact, cancellable);
        updated_contacts = message_addresses.contacts;
    }
    
    private void do_merge_email_in_search_table(Db.Connection cx, int64 message_id,
        Geary.Email.Field new_fields, Geary.Email email, Cancellable? cancellable) throws Error {
        if (new_fields.is_any_set(Geary.Email.REQUIRED_FOR_MESSAGE) &&
            email.fields.is_all_set(Geary.Email.REQUIRED_FOR_MESSAGE)) {
            string? body = null;
            try {
                body = email.get_message().get_searchable_body();
            } catch (Error e) {
                // Ignore.
            }
            string? recipients = null;
            try {
                recipients = email.get_message().get_searchable_recipients();
            } catch (Error e) {
                // Ignore.
            }
            
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageSearchTable SET body=?, attachment=?, receivers=? WHERE id=?");
            stmt.bind_string(0, body);
            stmt.bind_string(1, email.get_searchable_attachment_list());
            stmt.bind_string(2, recipients);
            stmt.bind_rowid(3, message_id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.SUBJECT)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageSearchTable SET subject=? WHERE id=?");
            stmt.bind_string(0, (email.subject != null ? email.subject.to_searchable_string() : null));
            stmt.bind_rowid(1, message_id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.ORIGINATORS)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageSearchTable SET from_field=? WHERE id=?");
            stmt.bind_string(0, (email.from != null ? email.from.to_searchable_string() : null));
            stmt.bind_rowid(1, message_id);
            
            stmt.exec(cancellable);
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.RECEIVERS)) {
            Db.Statement stmt = cx.prepare(
                "UPDATE MessageSearchTable SET cc=?, bcc=? WHERE id=?");
            stmt.bind_string(0, (email.cc != null ? email.cc.to_searchable_string() : null));
            stmt.bind_string(1, (email.bcc != null ? email.bcc.to_searchable_string() : null));
            stmt.bind_rowid(2, message_id);
            
            stmt.exec(cancellable);
        }
    }
    
    // This *replaces* the stored flags, it does not OR them ... this is simply a fast-path over
    // do_merge_email(), as updating FLAGS happens often and doesn't require a lot of extra work
    private void do_merge_email_flags(Db.Connection cx, LocationIdentifier location, Geary.Email email,
        out Geary.Email.Field pre_fields, out Geary.Email.Field post_fields,
        out Gee.Collection<Contact> updated_contacts, ref int unread_count_change,
        Cancellable? cancellable) throws Error {
        assert(email.fields == Geary.Email.Field.FLAGS);
        
        // no contacts were harmed in the production of this email
        updated_contacts = new Gee.ArrayList<Contact>();
        
        // fetch MessageRow and its fields, note that the fields now include FLAGS if they didn't
        // already
        MessageRow row = do_fetch_message_row(cx, location.message_id, Geary.Email.Field.FLAGS,
            out pre_fields, cancellable);
        post_fields = pre_fields;
        
        // compare flags for (a) any change at all and (b) unread changes
        Geary.Email row_email = row.to_email(location.email_id);
        
        if (row_email.email_flags != null && row_email.email_flags.equal_to(email.email_flags))
            return;
        
        if (row_email.email_flags.is_unread() != email.email_flags.is_unread())
            unread_count_change += email.email_flags.is_unread() ? 1 : -1;
        
        // write them out to the message row
        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map = new Gee.HashMap<ImapDB.EmailIdentifier,
            Geary.EmailFlags>();
        map.set((ImapDB.EmailIdentifier) email.id, email.email_flags);
        
        do_set_email_flags(cx, map, cancellable);
        post_fields |= Geary.Email.Field.FLAGS;
    }
    
    private void do_merge_email(Db.Connection cx, LocationIdentifier location, Geary.Email email,
        out Geary.Email.Field pre_fields, out Geary.Email.Field post_fields,
        out Gee.Collection<Contact> updated_contacts, ref int unread_count_change,
        Cancellable? cancellable) throws Error {
        // Default to an empty list, in case we never call do_merge_message_row.
        updated_contacts = new Gee.LinkedList<Contact>();
        
        // fetch message from database and merge in this email
        MessageRow row = do_fetch_message_row(cx, location.message_id,
            email.fields | Email.REQUIRED_FOR_MESSAGE | Attachment.REQUIRED_FIELDS,
            out pre_fields, cancellable);
        Geary.Email.Field fetched_fields = row.fields;
        post_fields = pre_fields | email.fields;
        row.merge_from_remote(email);
        
        if (email.fields == Geary.Email.Field.NONE)
            return;
        
        // Build the combined email from the merge, which will be used to save the attachments
        Geary.Email combined_email = row.to_email(location.email_id);
        do_add_attachments(cx, combined_email, location.message_id, cancellable);
        
        // Merge in any fields in the submitted email that aren't already in the database or are mutable
        int new_unread_count = 0;
        if (((fetched_fields & email.fields) != email.fields) ||
            email.fields.is_any_set(Geary.Email.MUTABLE_FIELDS)) {
            Geary.Email.Field new_fields;
            do_merge_message_row(cx, row, out new_fields, out updated_contacts,
                ref new_unread_count, cancellable);
            
            // Update attachments if not already in the database
            if (!fetched_fields.fulfills(Attachment.REQUIRED_FIELDS)
                && combined_email.fields.fulfills(Attachment.REQUIRED_FIELDS)) {
                do_save_attachments(cx, location.message_id, combined_email.get_message().get_attachments(),
                    cancellable);
            }
            
            if (do_check_for_message_search_row(cx, location.message_id, cancellable))
                do_merge_email_in_search_table(cx, location.message_id, new_fields, combined_email, cancellable);
            else
                do_add_email_to_search_table(cx, location.message_id, combined_email, cancellable);
        } else {
            // If the email is ready to go, we still may need to update the unread count.
            Geary.EmailFlags? combined_flags = do_get_email_flags_single(cx, location.message_id,
                cancellable);
            if (combined_flags != null && combined_flags.is_unread())
                new_unread_count = 1;
        }
        
        unread_count_change += new_unread_count;
    }
    
    private static Gee.List<Geary.Attachment>? do_list_attachments(Db.Connection cx, int64 message_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT id, filename, mime_type, filesize, disposition
            FROM MessageAttachmentTable
            WHERE message_id = ?
            ORDER BY id
            """);
        stmt.bind_rowid(0, message_id);
        
        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<Geary.Attachment> list = new Gee.ArrayList<Geary.Attachment>();
        do {
            list.add(new ImapDB.Attachment(cx.database.db_file.get_parent(), results.string_at(1),
                results.string_at(2), results.int64_at(3), message_id, results.rowid_at(0),
                Geary.Attachment.Disposition.from_int(results.int_at(4))));
        } while (results.next(cancellable));
        
        return list;
    }

    private void do_save_attachments(Db.Connection cx, int64 message_id,
        Gee.List<GMime.Part>? attachments, Cancellable? cancellable) throws Error {
        do_save_attachments_db(cx, message_id, attachments, db, cancellable);
    }
    
    public static void do_save_attachments_db(Db.Connection cx, int64 message_id,
        Gee.List<GMime.Part>? attachments, ImapDB.Database db, Cancellable? cancellable) throws Error {
        // nothing to do if no attachments
        if (attachments == null || attachments.size == 0)
            return;
        
        foreach (GMime.Part attachment in attachments) {
            string mime_type = attachment.get_content_type().to_string();
            string disposition = attachment.get_disposition();
            string filename = RFC822.Utils.get_attachment_filename(attachment);
            
            // Convert the attachment content into a usable ByteArray.
            GMime.DataWrapper attachment_data = attachment.get_content_object();
            ByteArray byte_array = new ByteArray();
            GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
            stream.set_owner(false);
            if (attachment_data != null)
                attachment_data.write_to_stream(stream); // data is null if it's 0 bytes
            uint filesize = byte_array.len;
            
            // Insert it into the database.
            Db.Statement stmt = cx.prepare("""
                INSERT INTO MessageAttachmentTable (message_id, filename, mime_type, filesize, disposition)
                VALUES (?, ?, ?, ?, ?)
                """);
            stmt.bind_rowid(0, message_id);
            stmt.bind_string(1, filename);
            stmt.bind_string(2, mime_type);
            stmt.bind_uint(3, filesize);
            stmt.bind_int(4, Geary.Attachment.Disposition.from_string(disposition));
            
            int64 attachment_id = stmt.exec_insert(cancellable);
            
            File saved_file = ImapDB.Attachment.generate_file(db.db_file.get_parent(), message_id,
                attachment_id, filename);
            
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
    
    /**
     * Adds a value to the unread count.  If this makes the unread count negative, it will be
     * set to zero.
     */
    internal void do_add_to_unread_count(Db.Connection cx, int to_add, Cancellable? cancellable)
        throws Error {
        if (to_add == 0)
            return; // Nothing to do.
        
        Db.Statement update_stmt = cx.prepare(
            "UPDATE FolderTable SET unread_count = CASE WHEN unread_count + ? < 0 THEN 0 ELSE " +
            "unread_count + ? END WHERE id=?");
        
        update_stmt.bind_int(0, to_add);
        update_stmt.bind_int(1, to_add);
        update_stmt.bind_rowid(2, folder_id);
            
        update_stmt.exec(cancellable);
    }
    
    // Db.Result must include columns for "message_id", "ordering", and "remove_marker" from the
    // MessageLocationTable
    private Gee.List<LocationIdentifier> do_results_to_locations(Db.Result results,
        ListFlags flags, Cancellable? cancellable) throws Error {
        Gee.List<LocationIdentifier> locations = new Gee.ArrayList<LocationIdentifier>();
        
        if (results.finished)
            return locations;
        
        do {
            LocationIdentifier location = new LocationIdentifier(results.rowid_for("message_id"),
                new Imap.UID(results.int64_for("ordering")), results.bool_for("remove_marker"));
            if (!flags.include_marked_for_remove() && location.marked_removed)
                continue;
            
            locations.add(location);
        } while (results.next(cancellable));
        
        return locations;
    }
    
    private LocationIdentifier? do_get_location_for_id(Db.Connection cx, ImapDB.EmailIdentifier id,
        ListFlags flags, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT ordering, remove_marker
            FROM MessageLocationTable
            WHERE folder_id = ? AND message_id = ?
        """);
        stmt.bind_rowid(0, folder_id);
        stmt.bind_rowid(1, id.message_id);
        
        Db.Result result = stmt.exec(cancellable);
        if (result.finished)
            return null;
        
        LocationIdentifier location = new LocationIdentifier(id.message_id,
            new Imap.UID(result.int64_at(0)), result.bool_at(1));
        
        return (!flags.include_marked_for_remove() && location.marked_removed) ? null : location;
    }
    
    private LocationIdentifier? do_get_location_for_uid(Db.Connection cx, Imap.UID uid,
        ListFlags flags, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT message_id, remove_marker
            FROM MessageLocationTable
            WHERE folder_id = ? AND ordering = ?
        """);
        stmt.bind_rowid(0, folder_id);
        stmt.bind_int64(1, uid.value);
        
        Db.Result result = stmt.exec(cancellable);
        if (result.finished)
            return null;
        
        LocationIdentifier location = new LocationIdentifier(result.rowid_at(0), uid, result.bool_at(1));
        
        return (!flags.include_marked_for_remove() && location.marked_removed) ? null : location;
    }
    
    private int do_get_unread_count_for_ids(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        int unread_count = 0;
        
        // Fetch flags for each email and update this folder's unread count.
        // (Note that this only flags for emails which have NOT been marked for removal
        // are included.)
        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? flag_map = do_get_email_flags(cx,
            ids, cancellable);
        if (flag_map != null) {
            foreach (Geary.EmailFlags flags in flag_map.values)
                unread_count += flags.is_unread() ? 1 : 0;
        }
        
        return unread_count;
    }
}

