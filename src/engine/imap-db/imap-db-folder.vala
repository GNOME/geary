/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * ImapDB.Folder provides an interface for retrieving messages from the local store in methods
 * that are synonymous with Geary.Folder's interface, but with some differences that deal with
 * how IMAP addresses and organizes email.
 *
 * One important note about ImapDB.Folder: if an EmailIdentifier is returned (either by itself
 * or attached to a Geary.Email), it will always be an ImapDB.EmailIdentifier and it will always
 * have a valid Imap.UID present.  This is not the case for EmailIdentifiers returned from
 * ImapDB.Account, as those EmailIdentifiers aren't associated with a Folder, which UIDs require.
 */

private class Geary.ImapDB.Folder : BaseObject, Geary.ReferenceSemantics {

    /**
     * Fields required for a message to be stored in the database.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        // Required for primary duplicate detection done with properties
        Email.Field.PROPERTIES |
        // Required for secondary duplicate detection via UID
        Email.Field.REFERENCES |
        // Required to ensure the unread count is up to date and so
        // that when moving a message, the new copy turns back up as
        // being not deleted.
        Email.Field.FLAGS
    );

    /**
     * Fields required for a message to be considered for full-text indexing.
     */
    public const Geary.Email.Field REQUIRED_FTS_FIELDS = Geary.Email.REQUIRED_FOR_MESSAGE;

    private const int LIST_EMAIL_WITH_MESSAGE_CHUNK_COUNT = 10;
    private const int LIST_EMAIL_METADATA_COUNT = 100;
    private const int LIST_EMAIL_FIELDS_CHUNK_COUNT = 500;
    private const int REMOVE_COMPLETE_LOCATIONS_CHUNK_COUNT = 500;
    private const int CREATE_MERGE_EMAIL_CHUNK_COUNT = 10;
    private const int OLD_MSG_DETACH_BATCH_SIZE = 1000;

    // When old messages beyond the period set in the account preferences are removed this number 
    // are retained even if they are beyond the threshold.
    private const int MINIMUM_MESSAGES_TO_RETAIN_DURING_GC = 100;

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
            this.email_id = new ImapDB.EmailIdentifier(message_id, uid);
            this.marked_removed = marked_removed;
        }
    }

    protected int manual_ref_count { get; protected set; }

    private Geary.Db.Database db;
    private Geary.FolderPath path;
    private GLib.File attachments_path;
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

    internal Folder(Geary.Db.Database db,
                    Geary.FolderPath path,
                    GLib.File attachments_path,
                    string account_owner_email,
                    int64 folder_id,
                    Geary.Imap.FolderProperties properties) {
        this.db = db;
        this.path = path;
        this.attachments_path = attachments_path;
        // Update to use all addresses on the account. Bug 768779
        this.account_owner_email = account_owner_email;
        this.folder_id = folder_id;
        this.properties = properties;
    }

    public unowned Geary.FolderPath get_path() {
        return path;
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

    /**
     * Updates folder's STATUS message count, attributes, recent, and unseen.
     *
     * UIDVALIDITY and UIDNEXT updated when the folder is
     * SELECT/EXAMINED (see update_folder_select_examine_async())
     * unless update_uid_info is true.
     */
    public async void update_folder_status(Geary.Imap.FolderProperties remote_properties,
                                           bool respect_marked_for_remove,
                                           Cancellable? cancellable)
        throws Error {
        // adjust for marked remove, but don't write these adjustments to the database -- they're
        // only reflected in memory via the properties
        int adjust_unseen = 0;
        int adjust_total = 0;

        yield this.db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            if (respect_marked_for_remove) {
                Db.Statement stmt = cx.prepare("""
                    SELECT flags
                    FROM MessageTable
                    WHERE id IN (
                        SELECT message_id
                        FROM MessageLocationTable
                        WHERE folder_id = ? AND remove_marker = ?
                    )
                """);
                stmt.bind_rowid(0, folder_id);
                stmt.bind_bool(1, true);

                Db.Result results = stmt.exec(cancellable);
                while (!results.finished) {
                    adjust_total++;

                    Imap.EmailFlags flags = new Imap.EmailFlags(Imap.MessageFlags.deserialize(
                        results.string_at(0)));
                    if (flags.contains(EmailFlags.UNREAD))
                        adjust_unseen++;

                    results.next(cancellable);
                }
            }

            Db.Statement stmt = cx.prepare(
                "UPDATE FolderTable SET attributes=?, unread_count=? WHERE id=?");
            stmt.bind_string(0, remote_properties.attrs.serialize());
            stmt.bind_int(1, remote_properties.email_unread);
            stmt.bind_rowid(2, this.folder_id);
            stmt.exec(cancellable);

            if (remote_properties.status_messages >= 0) {
                do_update_last_seen_status_total(
                    cx, remote_properties.status_messages, cancellable
                );
            }

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        // update appropriate local properties
        this.properties.set_status_unseen(
            Numeric.int_floor(remote_properties.unseen - adjust_unseen, 0)
        );
        this.properties.recent = remote_properties.recent;
        this.properties.attrs = remote_properties.attrs;

        // only update STATUS MESSAGES count if previously set, but use this count as the
        // "authoritative" value until another SELECT/EXAMINE or MESSAGES response
        if (remote_properties.status_messages >= 0) {
            this.properties.set_status_message_count(
                Numeric.int_floor(remote_properties.status_messages - adjust_total, 0),
                true
            );
        }
    }

    /**
     * Updates folder's SELECT/EXAMINE message count, UIDVALIDITY, UIDNEXT, unseen, and recent.
     * See also update_folder_status_async().
     */
    public async void update_folder_select_examine(Geary.Imap.FolderProperties remote_properties,
                                                   Cancellable? cancellable)
        throws Error {
        yield this.db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            do_update_uid_info(cx, remote_properties, cancellable);

            if (remote_properties.select_examine_messages >= 0) {
                do_update_last_seen_select_examine_total(
                    cx, remote_properties.select_examine_messages, cancellable
                );
            }

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        // update appropriate local properties
        this.properties.set_status_unseen(remote_properties.unseen);
        this.properties.recent = remote_properties.recent;
        this.properties.uid_validity = remote_properties.uid_validity;
        this.properties.uid_next = remote_properties.uid_next;

        if (remote_properties.select_examine_messages >= 0) {
            this.properties.set_select_examine_message_count(
                remote_properties.select_examine_messages
            );
        }
    }

    // Updates both the FolderProperties and the value in the local store.  Must be called while
    // open.
    public async void update_remote_selected_message_count(int count, Cancellable? cancellable) throws Error {
        if (count < 0)
            return;

        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
                do_update_last_seen_select_examine_total(cx, count, cancellable);
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
    public async Gee.Map<Email, bool>
        create_or_merge_email_async(Gee.Collection<Email> emails,
                                    bool update_totals,
                                    ContactHarvester harvester,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        Gee.HashMap<Geary.Email, bool> results = new Gee.HashMap<Geary.Email, bool>();

        Gee.ArrayList<Geary.Email> list = traverse<Geary.Email>(emails).to_array_list();
        int index = 0;
        while (index < list.size) {
            int stop = Numeric.int_ceiling(index + CREATE_MERGE_EMAIL_CHUNK_COUNT, list.size);
            Gee.List<Geary.Email> slice = list.slice(index, stop);

            Gee.ArrayList<Geary.EmailIdentifier> complete_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
            int total_unread_change = 0;
            yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
                foreach (Geary.Email email in slice) {
                    Geary.Email.Field pre_fields;
                    Geary.Email.Field post_fields;
                    int unread_change = 0;
                    bool created = do_create_or_merge_email(
                        cx, email,
                        out pre_fields, out post_fields,
                        ref unread_change,
                        cancellable
                    );

                    results.set(email, created);

                    // in essence, only fire the "email-completed" signal if the local version didn't
                    // have all the fields but after the create/merge now does
                    if (post_fields.is_all_set(Geary.Email.Field.ALL) && !pre_fields.is_all_set(Geary.Email.Field.ALL))
                        complete_ids.add(email.id);

                    if (update_totals) {
                        // Update unread count in DB.
                        do_add_to_unread_count(cx, unread_change, cancellable);
                        total_unread_change += unread_change;
                    }
                }

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);

            if (update_totals) {
                // Update the email_unread properties.
                properties.set_status_unseen(
                    (properties.email_unread + total_unread_change).clamp(0, int.MAX)
                );
            }

            if (complete_ids.size > 0)
                email_complete(complete_ids);

            index = stop;
            if (index < list.size)
                yield Scheduler.sleep_ms_async(100);
        }

        yield harvester.harvest_from_email(
            results.keys, cancellable
        );

        return results;
    }

    /** Returns a subset of the given ids that are in this folder. */
    public async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        var contained_ids = new Gee.HashMap<int64?,EmailIdentifier>(
            Collection.int64_hash_func,
            Collection.int64_equal_func
        );
        if (!ids.is_empty) {
            var valid_ids = new Gee.HashMap<int64?,EmailIdentifier>(
                Collection.int64_hash_func,
                Collection.int64_equal_func
            );
            yield db.exec_transaction_async(
                RO,
                (cx, cancellable) => {
                    var sql = new StringBuilder("""
                        SELECT message_id
                        FROM MessageLocationTable
                        WHERE message_id IN (
                    """);
                    foreach (var id in ids) {
                        var id_impl = id as EmailIdentifier;
                        if (id_impl != null) {
                            sql.append(id_impl.message_id.to_string());
                            valid_ids.set(id_impl.message_id, id_impl);
                        }
                    }
                    sql.append(") AND folder_id=? AND remove_marker<>?");

                    Db.Statement stmt = cx.prepare(sql.str);
                    stmt.bind_rowid(0, this.folder_id);
                    stmt.bind_bool(0, false);

                    Db.Result results = stmt.exec(cancellable);
                    while (!results.finished) {
                        var message_id = results.int64_at(0);
                        contained_ids.set(message_id, valid_ids.get(message_id));
                        results.next(cancellable);
                    }
                    return COMMIT;
                },
                cancellable
            );
        }
        return contained_ids.values;
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
                        start_uid = start_uid.next(false);
                    else
                        start_uid = start_uid.previous(false);
                }
            } else if (oldest_to_newest) {
                start_uid = new Imap.UID(Imap.UID.MIN);
            } else {
                start_uid = new Imap.UID(Imap.UID.MAX);
            }

            if (!start_uid.is_valid())
                return Db.TransactionOutcome.DONE;

            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
                WHERE folder_id = ?
            """);

            if (oldest_to_newest)
                sql.append("AND ordering >= ? ");
            else
                sql.append("AND ordering <= ? ");

            if (oldest_to_newest)
                sql.append("ORDER BY ordering ASC ");
            else
                sql.append("ORDER BY ordering DESC ");

            if (count != int.MAX)
                sql.append("LIMIT ? ");

            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            if (count != int.MAX)
                stmt.bind_int(2, count);

            locations = do_results_to_locations(stmt.exec(cancellable), count, flags, cancellable);

            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);

        // remove complete locations (emails with all fields downloaded)
        if (only_incomplete)
            locations = yield remove_complete_locations_in_chunks_async(locations, cancellable);

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
                start_uid = start_uid.next(false);
                end_uid = end_uid.previous(false);
            }

            if (!start_uid.is_valid() || !end_uid.is_valid() || start_uid.compare_to(end_uid) > 0)
                return Db.TransactionOutcome.DONE;

            Db.Statement stmt = cx.prepare("""
                SELECT message_id, ordering, remove_marker
                FROM MessageLocationTable
                WHERE folder_id = ? AND ordering >= ? AND ordering <= ?
            """);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            stmt.bind_int64(2, end_uid.value);

            locations = do_results_to_locations(stmt.exec(cancellable), int.MAX, flags, cancellable);

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
            start_uid = start_uid.next(false);
            end_uid = end_uid.previous(false);
        }

        if (!start_uid.is_valid() || !end_uid.is_valid() || start_uid.compare_to(end_uid) > 0)
            return null;

        // Break up work so all reading isn't done in single transaction that locks up the
        // database ... first, gather locations of all emails in database
        Gee.List<LocationIdentifier>? locations = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
            """);

            sql.append("WHERE folder_id = ? AND ordering >= ? AND ordering <= ? ");

            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, start_uid.value);
            stmt.bind_int64(2, end_uid.value);

            locations = do_results_to_locations(stmt.exec(cancellable), int.MAX, flags, cancellable);

            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);

        // remove complete locations (emails with all fields downloaded)
        if (only_incomplete)
            locations = yield remove_complete_locations_in_chunks_async(locations, cancellable);

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
            // convert ids into LocationIdentifiers
            Gee.List<LocationIdentifier>? locs = do_get_locations_for_ids(cx, ids, flags,
                cancellable);
            if (locs == null || locs.size == 0)
                return Db.TransactionOutcome.DONE;

            StringBuilder sql = new StringBuilder("""
                SELECT MessageLocationTable.message_id, ordering, remove_marker
                FROM MessageLocationTable
            """);

            if (locs.size != 1) {
                sql.append("WHERE ordering IN (");
                bool first = true;
                foreach (LocationIdentifier location in locs) {
                    if (!first)
                        sql.append(",");

                    sql.append(location.uid.to_string());
                    first = false;
                }
                sql.append(")");
            } else {
                sql.append_printf("WHERE ordering = '%s' ", locs[0].uid.to_string());
            }

            sql.append("AND folder_id = ? ");

            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);

            locations = do_results_to_locations(stmt.exec(cancellable), int.MAX, flags, cancellable);

            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);

        // remove complete locations (emails with all fields downloaded)
        if (only_incomplete)
            locations = yield remove_complete_locations_in_chunks_async(locations, cancellable);

        // Next, read in email in chunks
        return yield list_email_in_chunks_async(locations, required_fields, flags, cancellable);
    }

    private async Gee.List<LocationIdentifier>? remove_complete_locations_in_chunks_async(
        Gee.List<LocationIdentifier>? locations, Cancellable? cancellable) throws Error {
        if (locations == null || locations.size == 0)
            return locations;

        Gee.List<LocationIdentifier> incomplete_locations = new Gee.ArrayList<LocationIdentifier>();

        // remove complete locations in chunks to avoid locking the database for long periods of
        // time
        int start = 0;
        for (;;) {
            if (start >= locations.size)
                break;

            int end = (start + REMOVE_COMPLETE_LOCATIONS_CHUNK_COUNT).clamp(0, locations.size);
            Gee.List<LocationIdentifier> slice = locations.slice(start, end);

            yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
                do_remove_complete_locations(cx, slice, cancellable);

                return Db.TransactionOutcome.SUCCESS;
            }, cancellable);

            incomplete_locations.add_all(slice);

            start = end;
        }

        return (incomplete_locations.size > 0) ? incomplete_locations : null;
    }

    private async Gee.List<Geary.Email>? list_email_in_chunks_async(Gee.List<LocationIdentifier>? ids,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable) throws Error {
        if (ids == null || ids.size == 0)
            return null;

        // chunk count depends on whether or not the message -- body + headers -- is being fetched
        int chunk_count = required_fields.requires_any(Email.Field.BODY | Email.Field.HEADER)
            ? LIST_EMAIL_WITH_MESSAGE_CHUNK_COUNT : LIST_EMAIL_METADATA_COUNT;

        int length_rounded_up = Numeric.int_round_up(ids.size, chunk_count);

        Gee.List<Geary.Email> results = new Gee.ArrayList<Geary.Email>();
        for (int start = 0; start < length_rounded_up; start += chunk_count) {
            // stop is the index *after* the end of the slice
            int stop = Numeric.int_ceiling((start + chunk_count), ids.size);

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
    public async ImapDB.EmailIdentifier? get_id_at_async(int64 pos, Cancellable? cancellable) throws Error {
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
            stmt.bind_int64(1, pos - 1);

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
            Gee.List<LocationIdentifier>? locs = do_get_locations_for_ids(cx, ids, flags,
                cancellable);
            if (locs != null) {
                foreach (LocationIdentifier location in locs)
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
            Gee.List<LocationIdentifier>? locs = do_get_locations_for_uids(cx, uids, flags,
                cancellable);
            if (locs != null) {
                foreach (LocationIdentifier location in locs)
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
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            Gee.List<LocationIdentifier>? locs = do_get_locations_for_ids(cx, ids,
                ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
            if (locs == null || locs.size == 0)
                return Db.TransactionOutcome.DONE;

            unread_count = do_get_unread_count_for_ids(cx, ids, cancellable);
            do_add_to_unread_count(cx, -unread_count, cancellable);

            StringBuilder sql = new StringBuilder("""
                DELETE FROM MessageLocationTable WHERE message_id IN (
            """);
            Gee.Iterator<LocationIdentifier> iter = locs.iterator();
            while (iter.next()) {
                sql.append_printf("%s", iter.get().message_id.to_string());
                if (iter.has_next())
                    sql.append(", ");
            }
            sql.append(") AND folder_id=?");

            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);

            stmt.exec(cancellable);

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

            stmt.exec(cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }

    public async Gee.Collection<Geary.EmailIdentifier>? detach_emails_before_timestamp(DateTime cutoff,
        GLib.Cancellable? cancellable) throws Error {
        debug("Detaching emails before %s for folder ID %s", cutoff.to_string(), this.folder_id.to_string());
        Gee.ArrayList<ImapDB.EmailIdentifier>? deleted_email_ids = null;
        Gee.ArrayList<string> deleted_primary_keys = null;

        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            // MessageLocationTable.ordering isn't relied on throughout due 
            // to IMAP folder UIDs not guaranteed to be in order. Make sure to 
            // performance test any changes to the select queries below.
            StringBuilder sql = new StringBuilder();
            sql.append("""
                SELECT COUNT(*)
                FROM MessageLocationTable
                WHERE folder_id = ?
                AND message_id IN (
                    SELECT id
                    FROM MessageTable
                    INDEXED BY MessageTableInternalDateTimeTIndex
                    WHERE internaldate_time_t >= ?
                )
            """);

            Db.Statement stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, cutoff.to_unix());
            Db.Result results = stmt.exec(cancellable);
            int64 found_within_threshold = results.int64_at(0);
            int64 extra_to_retain = 
                (MINIMUM_MESSAGES_TO_RETAIN_DURING_GC - found_within_threshold).clamp(0, int64.MAX);

            sql = new StringBuilder();
            sql.append("""
                SELECT ml.id, ml.message_id, ml.ordering
                FROM MessageLocationTable ml
                INNER JOIN MessageTable m
                INDEXED BY MessageTableInternalDateTimeTIndex
                    ON ml.message_id = m.id
                WHERE ml.folder_id = ?
                AND m.internaldate_time_t < ?
                ORDER BY m.internaldate_time_t DESC
                LIMIT -1 OFFSET ?;
            """);

            stmt = cx.prepare(sql.str);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_int64(1, cutoff.to_unix());
            stmt.bind_int64(2, extra_to_retain);

            results = stmt.exec(cancellable);

            while (!results.finished) {
                if (deleted_email_ids == null) {
                    deleted_email_ids = new Gee.ArrayList<ImapDB.EmailIdentifier>();
                    deleted_primary_keys = new Gee.ArrayList<string>();
                }

                deleted_email_ids.add(
                    new ImapDB.EmailIdentifier(results.int64_at(1),
                                               new Imap.UID(results.int64_at(2)))
                );
                deleted_primary_keys.add(results.rowid_at(0).to_string());

                results.next(cancellable);
            }
            return Db.TransactionOutcome.DONE;
        }, cancellable);

        if (deleted_email_ids != null) {
            // Delete in batches to avoid hiting SQLite maximum query
            // length (although quite unlikely)
            int delete_index = 0;
            while (delete_index < deleted_primary_keys.size) {
                int batch_counter = 0;

                StringBuilder message_location_ids_sql_sublist = new StringBuilder();
                StringBuilder message_ids_sql_sublist = new StringBuilder();
                while (delete_index < deleted_primary_keys.size
                       && batch_counter < OLD_MSG_DETACH_BATCH_SIZE) {
                    if (batch_counter > 0) {
                        message_location_ids_sql_sublist.append(",");
                        message_ids_sql_sublist.append(",");
                    }
                    message_location_ids_sql_sublist.append(
                        deleted_primary_keys.get(delete_index)
                    );
                    message_ids_sql_sublist.append(
                        deleted_email_ids.get(delete_index).message_id.to_string()
                    );
                    delete_index++;
                    batch_counter++;
                }

                yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
                    StringBuilder sql = new StringBuilder();
                    sql.append("""
                        DELETE FROM MessageLocationTable
                        WHERE id IN (
                    """);
                    sql.append(message_location_ids_sql_sublist.str);
                    sql.append(")");
                    Db.Statement stmt = cx.prepare(sql.str);

                    stmt.exec(cancellable);

                    sql = new StringBuilder();
                    sql.append("""
                        DELETE FROM MessageSearchTable
                        WHERE rowid IN (
                    """);
                    sql.append(message_ids_sql_sublist.str);
                    sql.append(")");
                    stmt = cx.prepare(sql.str);

                    stmt.exec(cancellable);

                    return Db.TransactionOutcome.COMMIT;
                }, cancellable);
            }
        }

        return deleted_email_ids;
    }

    public async int mark_email_async(Gee.Collection<ImapDB.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, Cancellable? cancellable)
        throws Error {
        int unread_change = 0; // Negative means messages are read, positive means unread.
        Gee.Map<ImapDB.EmailIdentifier, bool> unread_status = new Gee.HashMap<ImapDB.EmailIdentifier, bool>();
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            // fetch flags for each email
            Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? map = do_get_email_flags(cx,
                to_mark, ListFlags.NONE, cancellable);
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

        return unread_change;
    }

    internal async Gee.List<Imap.UID>? get_email_uids_async(
        Gee.Collection<EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.List<Imap.UID> uids = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            uids = do_get_email_uids(cx, ids, cancellable);

            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);

        return uids;
    }

    internal async Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? get_email_flags_async(
        Gee.Collection<EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.Map<EmailIdentifier, Geary.EmailFlags>? map = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            map = do_get_email_flags(cx, ids, ListFlags.NONE, cancellable);

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
                    do_get_email_flags(cx, map.keys, ListFlags.NONE, cancellable);

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

    public async void detach_single_email_async(ImapDB.EmailIdentifier id, Cancellable? cancellable,
        out bool is_marked) throws Error {
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
            if (do_get_unread_count_for_ids(cx,
                Geary.iterate<ImapDB.EmailIdentifier>(id).to_array_list(), cancellable) > 0) {
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
    // If ids is null, all messages are marked for removal.
    //
    // Returns a collection of ImapDB.EmailIdentifiers *with the UIDs set* for this folder.
    // Supplied EmailIdentifiers not in this Folder will not be included.
    public async Gee.Set<ImapDB.EmailIdentifier>? mark_removed_async(
        Gee.Collection<ImapDB.EmailIdentifier>? ids, bool mark_removed, Cancellable? cancellable)
        throws Error {
        int total_changed = 0;
        int unread_count = 0;
        Gee.Set<ImapDB.EmailIdentifier> removed_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            Gee.List<LocationIdentifier?> locs;
            if (ids == null || ids.size == 0)
                locs = do_get_all_locations(cx, ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
            else
                locs = do_get_locations_for_ids(cx, ids, ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);

            if (locs == null || locs.size == 0)
                return Db.TransactionOutcome.DONE;

            total_changed = locs.size;
            unread_count = do_get_unread_count_for_ids(cx, ids, cancellable);

            Gee.HashSet<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
            foreach (LocationIdentifier location in locs) {
                uids.add(location.uid);
                removed_ids.add(location.email_id);
            }

            do_mark_unmark_removed(cx, uids, mark_removed, cancellable);
            do_add_to_unread_count(cx, -unread_count, cancellable);

            return Db.TransactionOutcome.DONE;
        }, cancellable);


        // Update the folder properties so client sees the changes
        // right away

        // Email total
        if (mark_removed) {
            total_changed = -total_changed;
        }
        int total = this.properties.select_examine_messages + total_changed;
        if (total >= 0) {
            this.properties.set_select_examine_message_count(total);
        }

        // Unread total
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

    public async Gee.Set<ImapDB.EmailIdentifier>? get_marked_ids_async(Cancellable? cancellable)
        throws Error {
        Gee.Set<ImapDB.EmailIdentifier> ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                SELECT message_id, ordering
                FROM MessageLocationTable
                WHERE folder_id=? AND remove_marker<>?
            """);
            stmt.bind_rowid(0, folder_id);
            stmt.bind_bool(1, false);

            Db.Result results = stmt.exec(cancellable);
            while (!results.finished) {
                ids.add(new ImapDB.EmailIdentifier(results.rowid_at(0), new Imap.UID(results.int64_at(1))));

                results.next(cancellable);
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return ids.size > 0 ? ids : null;
    }

    // Clears all remove markers from the folder except those in the exceptions Collection
    public async void clear_remove_markers_async(Gee.Collection<ImapDB.EmailIdentifier>? exceptions,
        Cancellable? cancellable) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            StringBuilder sql = new StringBuilder();
            sql.append("""
                UPDATE MessageLocationTable
                SET remove_marker=?
                WHERE folder_id=? AND remove_marker <> ?
            """);

            if (exceptions != null && exceptions.size > 0) {
                sql.append("""
                    AND message_id NOT IN (
                """);
                Gee.Iterator<ImapDB.EmailIdentifier> iter = exceptions.iterator();
                while (iter.next()) {
                    sql.append(iter.get().message_id.to_string());
                    if (iter.has_next())
                        sql.append(", ");
                }
                sql.append(")");
            }

            Db.Statement stmt = cx.prepare(sql.str);
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

        Gee.HashMap<ImapDB.EmailIdentifier,Geary.Email.Field> map = new Gee.HashMap<
            ImapDB.EmailIdentifier,Geary.Email.Field>();

        // Break up the work
        Gee.List<ImapDB.EmailIdentifier> list = new Gee.ArrayList<ImapDB.EmailIdentifier>();
        Gee.Iterator<ImapDB.EmailIdentifier> iter = ids.iterator();
        while (iter.next()) {
            list.add(iter.get());
            if (list.size < LIST_EMAIL_FIELDS_CHUNK_COUNT && iter.has_next())
                continue;

            yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
                Gee.List<LocationIdentifier>? locs = do_get_locations_for_ids(cx, ids, flags,
                    cancellable);
                if (locs == null || locs.size == 0)
                    return Db.TransactionOutcome.DONE;

                Db.Statement fetch_stmt = cx.prepare(
                    "SELECT fields FROM MessageTable WHERE id = ?");

                // TODO: Unroll loop
                foreach (LocationIdentifier location in locs) {
                    fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
                    fetch_stmt.bind_rowid(0, location.message_id);

                    Db.Result results = fetch_stmt.exec(cancellable);
                    if (!results.finished)
                        map.set(location.email_id, (Geary.Email.Field) results.int_at(0));
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

    // TODO: Unroll loop
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

    /**
     * Returns the id of any existing message matching the given.
     *
     * Searches for an existing message that matches `email`, based on
     * its message attributes. Currently, since ImapDB only requests
     * the IMAP internal date and RFC822 message size, these are the
     * only attributes used.
     *
     * The unique, internal message ID of the first matching message
     * is returned, else `-1` if no matching message was found.
     *
     * This should only be called on messages obtained via the IMAP
     * stack.
     */
    private int64 do_search_for_duplicates(Db.Connection cx,
                                           Geary.Email email,
                                           ImapDB.EmailIdentifier email_id,
                                           Cancellable? cancellable)
        throws Error {
        int64 id = -1;
        // if fields not present, then no duplicate can reliably be found
        if (!email.fields.is_all_set(REQUIRED_FIELDS)) {
            debug(
                "%s: Unable to detect duplicates for %s, fields available: %s",
                this.to_string(),
                email.id.to_string(),
                email.fields.to_string()
            );
            return id;
        }

        // what's more, actually need all those fields to be available, not merely attempted,
        // to err on the side of safety
        Imap.EmailProperties? imap_properties = (Imap.EmailProperties) email.properties;
        string? internaldate = (imap_properties != null && imap_properties.internaldate != null)
            ? imap_properties.internaldate.serialize() : null;
        int64 rfc822_size = (imap_properties != null) ? imap_properties.rfc822_size.value : -1;

        if (String.is_empty(internaldate) || rfc822_size < 0) {
            debug(
                "Unable to detect duplicates for %s (%s available but invalid)",
                email.id.to_string(),
                email.fields.to_string()
            );
            return id;
        }

        // look for duplicate in IMAP message properties
        Db.Statement stmt;
        if (email.message_id != null)
            stmt = cx.prepare("SELECT id FROM MessageTable WHERE internaldate=? AND rfc822_size=? AND message_id=?");
         else
            stmt = cx.prepare("SELECT id FROM MessageTable WHERE internaldate=? AND rfc822_size=?");

        stmt.bind_string(0, internaldate);
        stmt.bind_int64(1, rfc822_size);
        if (email.message_id != null) {
            stmt.bind_string(2, email.message_id.to_rfc822_string());
        }

        Db.Result results = stmt.exec(cancellable);
        if (!results.finished) {
            id = results.int64_at(0);
        }
        return id;
    }

    /**
     * Adds a message to the folder.
     *
     * Note: does NOT check if message is already associated with this
     * folder.
     */
    private void do_associate_with_folder(Db.Connection cx,
                                          int64 message_id,
                                          Imap.UID uid,
                                          Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "INSERT INTO MessageLocationTable (message_id, folder_id, ordering) VALUES (?, ?, ?)");
        stmt.bind_rowid(0, message_id);
        stmt.bind_rowid(1, this.folder_id);
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

    /**
     * Adds a single message to the folder, creating or merging it.
     *
     * This creates the message and appends it to the folder if the
     * message does not already exist, else appends and merges if the
     * message exists but not in the given position in this folder,
     * else it exists in the given position, so simply merges it.
     *
     * Returns `true` if created, else was merged and returns `false`.
     */
    private bool do_create_or_merge_email(Db.Connection cx,
                                          Geary.Email email,
                                          out Geary.Email.Field pre_fields,
                                          out Geary.Email.Field post_fields,
                                          ref int unread_count_change,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error {

        // This should only ever get invoked for messages that came
        // from the IMAP layer, which should not have a message id,
        // but should have a UID.
        ImapDB.EmailIdentifier? email_id = email.id as ImapDB.EmailIdentifier;
        if (email_id == null ||
            email_id.message_id != Db.INVALID_ROWID ||
            email_id.uid == null) {
            throw new EngineError.BAD_PARAMETERS(
                "IMAP message with UID required"
            );
        }

        int64 message_id = -1;
        bool is_associated = false;

        // First, look for the same message at the same location
        LocationIdentifier? location = do_get_location_for_uid(
            cx,
            email_id.uid,
            ListFlags.INCLUDE_MARKED_FOR_REMOVE,
            cancellable
        );
        if (location != null) {
            // Already at the specified location, so no need to create
            // or associate with this folder — just merge it
            message_id = location.message_id;
            is_associated = true;
        } else {
            // Not already at the specified location, so look for the
            // same message in other locations or other folders
            message_id = do_search_for_duplicates(
                cx, email, email_id, cancellable
            );
            if (message_id >= 0) {
                location = new LocationIdentifier(
                    message_id, email_id.uid, false
                );
            }
        }

        bool was_created = false;
        if (location != null) {
            // Found the same or a duplicate message, so merge it. We
            // special-case flag-only updates, which happens often and
            // will only write to the DB if necessary.
            if (email.fields != Geary.Email.Field.FLAGS) {
                do_merge_email(
                    cx, location, email,
                    out pre_fields, out post_fields,
                    ref unread_count_change,
                    cancellable
                );

                // Already associated with folder and flags were known.
                if (is_associated && pre_fields.is_all_set(Geary.Email.Field.FLAGS))
                    unread_count_change = 0;
            } else {
                do_merge_email_flags(
                    cx, location, email,
                    out pre_fields, out post_fields,
                    ref unread_count_change, cancellable
                );
            }
        } else {
            // Message was not found, so create a new message for it
            was_created = true;
            MessageRow row = new MessageRow.from_email(email);
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
            stmt.bind_int64(19, row.rfc822_size);

            message_id = stmt.exec_insert(cancellable);

            // write out attachments, if any
            // TODO: Because this involves saving files, it potentially means holding up access to the
            // database while they're being written; may want to do this outside of transaction.
            if (email.fields.fulfills(Attachment.REQUIRED_FIELDS)) {
                Attachment.save_attachments(
                    cx,
                    this.attachments_path,
                    message_id,
                    email.get_message().get_attachments(),
                    cancellable
                );
            }

            do_add_email_to_search_table(cx, message_id, email, cancellable);

            // Update unread count if our new email is unread.
            if (email.email_flags != null && email.email_flags.is_unread())
                unread_count_change++;
        }

        // Finally, update the email's message id and add it to the
        // folder, if needed
        email_id.promote_with_message_id(message_id);
        if (!is_associated) {
            do_associate_with_folder(cx, message_id, email_id.uid, cancellable);
        }

        return was_created;
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

        // Often when Geary first adds a message to the FTS table
        // these fields will all be null or empty strings. Check that
        // this isn't the case beforehand to avoid the IO overhead.

        string? attachments = email.get_searchable_attachment_list();
        string? subject = email.subject != null ? email.subject.to_searchable_string() : null;
        string? from = email.from != null ? email.from.to_searchable_string() : null;
        string? cc = email.cc != null ? email.cc.to_searchable_string() : null;
        string? bcc = email.bcc != null ? email.bcc.to_searchable_string() : null;
        string? flags = email.email_flags != null ? email.email_flags.serialise() : null;

        if (!Geary.String.is_empty(body) ||
            !Geary.String.is_empty(attachments) ||
            !Geary.String.is_empty(subject) ||
            !Geary.String.is_empty(from) ||
            !Geary.String.is_empty(recipients) ||
            !Geary.String.is_empty(cc) ||
            !Geary.String.is_empty(bcc) ||
            !Geary.String.is_empty(flags)) {

            Db.Statement stmt = cx.prepare("""
                INSERT INTO MessageSearchTable
                    (rowid, body, attachments, subject, "from", receivers, cc, bcc, flags)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """);
            stmt.bind_rowid(0, message_id);
            stmt.bind_string(1, body);
            stmt.bind_string(2, attachments);
            stmt.bind_string(3, subject);
            stmt.bind_string(4, from);
            stmt.bind_string(5, recipients);
            stmt.bind_string(6, cc);
            stmt.bind_string(7, bcc);
            stmt.bind_string(8, flags);

            stmt.exec_insert(cancellable);
        }
    }

    private static bool do_check_for_message_search_row(Db.Connection cx, int64 message_id,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT 'TRUE' FROM MessageSearchTable WHERE rowid=?");
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
        Attachment.add_attachments(
            cx, this.attachments_path, email, location.message_id, cancellable
        );
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

                    case NONE:
                        // no-op
                        break;

                    case ENVELOPE:
                    case ALL:
                        // XXX hmm
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

    private Gee.List<Imap.UID>? do_get_email_uids(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.List<LocationIdentifier>? locs = do_get_locations_for_ids(cx, ids, ListFlags.NONE,
            cancellable);
        if (locs == null)
            return null;

        Gee.List<Imap.UID> uids = new Gee.ArrayList<Imap.UID>();
        foreach (LocationIdentifier location in locs) {
            uids.insert(0, location.uid);
        }

        return (uids.size > 0) ? uids : null;
    }

    private Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? do_get_email_flags(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier>? ids, ListFlags flags,
        Cancellable? cancellable) throws Error {
        Gee.List<LocationIdentifier>? locs;

        if (ids == null || ids.size == 0)
            locs = do_get_all_locations(cx, flags, cancellable);
        else
            locs = do_get_locations_for_ids(cx, ids, flags, cancellable);

        if (locs == null || locs.size == 0)
            return null;

        // prepare Statement for reuse
        Db.Statement fetch_stmt = cx.prepare("SELECT flags FROM MessageTable WHERE id=?");

        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map = new Gee.HashMap<
            ImapDB.EmailIdentifier, Geary.EmailFlags>();
        // TODO: Unroll this loop
        foreach (LocationIdentifier location in locs) {
            fetch_stmt.reset(Db.ResetScope.CLEAR_BINDINGS);
            fetch_stmt.bind_rowid(0, location.message_id);

            Db.Result results = fetch_stmt.exec(cancellable);
            if (results.finished || results.is_null_at(0))
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

        if (results.finished || results.is_null_at(0))
            return null;

        return new Geary.Imap.EmailFlags(Geary.Imap.MessageFlags.deserialize(results.string_at(0)));
    }

    // TODO: Unroll loop
    private void do_set_email_flags(Db.Connection cx, Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags> map,
        Cancellable? cancellable) throws Error {
        Db.Statement update_message = cx.prepare(
            "UPDATE MessageTable SET flags = ?, fields = fields | ? WHERE id = ?"
        );
        Db.Statement update_search = cx.prepare("""
            UPDATE MessageSearchTable SET flags = ? WHERE rowid = ?
            """
        );

        foreach (ImapDB.EmailIdentifier id in map.keys) {
            // Find the email location

            LocationIdentifier? location = do_get_location_for_id(
                cx,
                id,
                // Could be setting a flag on a deleted message
                ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                cancellable
            );
            if (location == null) {
                throw new EngineError.NOT_FOUND(
                    "Email not found: %s", id.to_string()
                );
            }

            // Update MessageTable

            Geary.Imap.EmailFlags? flags = map.get(id) as Geary.Imap.EmailFlags;
            if (flags == null) {
                throw new EngineError.BAD_PARAMETERS(
                    "Email with Geary.Imap.EmailFlags required"
                );
            }

            update_message.reset(Db.ResetScope.CLEAR_BINDINGS);
            update_message.bind_string(0, flags.message_flags.serialize());
            update_message.bind_int(1, Geary.Email.Field.FLAGS);
            update_message.bind_rowid(2, id.message_id);
            update_message.exec(cancellable);

            // Update MessageSearchTable

            update_search.reset(Db.ResetScope.CLEAR_BINDINGS);
            update_search.bind_string(0, flags.serialise());
            update_search.bind_rowid(1, id.message_id);
            update_search.exec_insert(cancellable);
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

    private void do_merge_message_row(Db.Connection cx,
                                      MessageRow row,
                                      out Geary.Email.Field new_fields,
                                      ref int unread_count_change,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
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
            stmt.bind_int64(2, row.rfc822_size);
            stmt.bind_rowid(3, row.id);

            stmt.exec(cancellable);
        }

        // now merge the new fields in the row
        Db.Statement stmt = cx.prepare(
            "UPDATE MessageTable SET fields = fields | ? WHERE id=?");
        stmt.bind_int(0, new_fields);
        stmt.bind_rowid(1, row.id);

        stmt.exec(cancellable);
    }

    private void do_merge_email_in_search_table(Db.Connection cx, int64 message_id,
        Geary.Email.Field new_fields, Geary.Email email, Cancellable? cancellable) throws Error {

        // We can't simply issue an UPDATE here for the changed
        // fields, since it will likely corrupt the
        // MessageSearchTable. So instead do a SELECT to get the
        // existing data, then do a DELETE and INSERT. See Bug 772522.

        Db.Statement select = cx.prepare("""
            SELECT body, attachments, subject, "from", receivers, cc, bcc, flags
            FROM MessageSearchTable
            WHERE rowid=?
        """);
        select.bind_rowid(0, message_id);
        Db.Result row = select.exec(cancellable);

        string? body = row.string_at(0);
        string? attachments = row.string_at(1);
        string? subject = row.string_at(2);
        string? from = row.string_at(3);
        string? recipients = row.string_at(4);
        string? cc = row.string_at(5);
        string? bcc = row.string_at(6);
        string? flags = row.string_at(7);

        if (new_fields.is_any_set(Geary.Email.REQUIRED_FOR_MESSAGE) &&
            email.fields.is_all_set(Geary.Email.REQUIRED_FOR_MESSAGE)) {
            try {
                body = email.get_message().get_searchable_body();
            } catch (Error e) {
                // Ignore.
            }
            try {
                recipients = email.get_message().get_searchable_recipients();
            } catch (Error e) {
                // Ignore.
            }
        }

        if (new_fields.is_any_set(Geary.Email.Field.SUBJECT)) {
            if (email.subject != null)
                email.subject.to_searchable_string();
        }

        if (new_fields.is_any_set(Geary.Email.Field.ORIGINATORS)) {
            if (email.from != null)
                from = email.from.to_searchable_string();
        }

        if (new_fields.is_any_set(Geary.Email.Field.RECEIVERS)) {
            if (email.cc != null)
                cc =  email.cc.to_searchable_string();
            if (email.bcc != null)
                bcc = email.bcc.to_searchable_string();
        }

        if (new_fields.is_any_set(Geary.Email.Field.FLAGS)) {
            if (email.email_flags != null) {
                flags = email.email_flags.serialise();
            }
        }

        Db.Statement del = cx.prepare(
            "DELETE FROM MessageSearchTable WHERE rowid=?"
        );
        del.bind_rowid(0, message_id);
        del.exec(cancellable);

        Db.Statement insert = cx.prepare("""
            INSERT INTO MessageSearchTable
                (rowid, body, attachments, subject, "from", receivers, cc, bcc, flags)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """);
        insert.bind_rowid(0, message_id);
        insert.bind_string(1, body);
        insert.bind_string(2, attachments);
        insert.bind_string(3, subject);
        insert.bind_string(4, from);
        insert.bind_string(5, recipients);
        insert.bind_string(6, cc);
        insert.bind_string(7, bcc);
        insert.bind_string(8, flags);

        insert.exec_insert(cancellable);
    }

    // This *replaces* the stored flags, it does not OR them ... this is simply a fast-path over
    // do_merge_email(), as updating FLAGS happens often and doesn't require a lot of extra work
    private void do_merge_email_flags(Db.Connection cx,
                                      LocationIdentifier location,
                                      Geary.Email email,
                                      out Geary.Email.Field pre_fields,
                                      out Geary.Email.Field post_fields,
                                      ref int unread_count_change,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        assert(email.fields == Geary.Email.Field.FLAGS);

        // fetch MessageRow and its fields, note that the fields now include FLAGS if they didn't
        // already
        MessageRow row = do_fetch_message_row(cx, location.message_id, Geary.Email.Field.FLAGS,
            out pre_fields, cancellable);
        post_fields = pre_fields;

        // Only update if changed
        Geary.Email row_email = row.to_email(location.email_id);
        if (row_email.email_flags == null ||
            !row_email.email_flags.equal_to(email.email_flags)) {

            // Check for unread count changes
            if (row_email.email_flags != null &&
                row_email.email_flags.is_unread() != email.email_flags.is_unread()) {
                unread_count_change += email.email_flags.is_unread() ? 1 : -1;
            }

            // do_set_email_flags requires a valid message location,
            // but doesn't accept one as an arg, so despite knowing
            // the location here, make sure we pass an id with a
            // message_id in so it can look the location back up.
            do_set_email_flags(
                cx,
                Collection.single_map<ImapDB.EmailIdentifier,Geary.EmailFlags>(
                    (ImapDB.EmailIdentifier) row_email.id, email.email_flags
                ),
                cancellable
            );

            post_fields |= Geary.Email.Field.FLAGS;
        }
    }

    private void do_merge_email(Db.Connection cx,
                                LocationIdentifier location,
                                Geary.Email email,
                                out Geary.Email.Field pre_fields,
                                out Geary.Email.Field post_fields,
                                ref int unread_count_change,
                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        // fetch message from database and merge in this email
        MessageRow row = do_fetch_message_row(cx, location.message_id,
            email.fields | Email.REQUIRED_FOR_MESSAGE | Attachment.REQUIRED_FIELDS,
            out pre_fields, cancellable);
        Geary.Email.Field fetched_fields = row.fields;
        post_fields = pre_fields | email.fields;
        row.merge_from_remote(email);

        if (email.fields == Geary.Email.Field.NONE)
            return;

        // Merge in any fields in the submitted email that aren't already in the database or are mutable
        int new_unread_count = 0;
        if (((fetched_fields & email.fields) != email.fields) ||
            email.fields.is_any_set(Geary.Email.MUTABLE_FIELDS)) {
            // Build the combined email from the merge, which will be used to save the attachments
            Geary.Email combined_email = row.to_email(location.email_id);

            // Update attachments if not already in the database
            if (!fetched_fields.fulfills(Attachment.REQUIRED_FIELDS)
                && combined_email.fields.fulfills(Attachment.REQUIRED_FIELDS)) {
                combined_email.add_attachments(
                    Attachment.save_attachments(
                        cx,
                        this.attachments_path,
                        location.message_id,
                        combined_email.get_message().get_attachments(),
                        cancellable
                    )
                );
            }

            Geary.Email.Field new_fields;
            do_merge_message_row(
                cx, row,
                out new_fields,
                ref new_unread_count,
                cancellable
            );

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
    private Gee.List<LocationIdentifier> do_results_to_locations(Db.Result results, int count,
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
            if (locations.size >= count)
                break;
        } while (results.next(cancellable));

        return locations;
    }

    // Use a separate step to strip out complete emails because original implementation (using an
    // INNER JOIN) was horribly slow under load
    private void do_remove_complete_locations(Db.Connection cx, Gee.List<LocationIdentifier>? locations,
        Cancellable? cancellable) throws Error {
        if (locations == null || locations.size == 0)
            return;

        StringBuilder sql = new StringBuilder("""
            SELECT id FROM MessageTable WHERE id IN (
        """);
        bool first = true;
        foreach (LocationIdentifier location_id in locations) {
            if (!first)
                sql.append(",");

            sql.append(location_id.message_id.to_string());
            first = false;
        }
        sql.append(") AND fields <> ?");

        Db.Statement stmt = cx.prepare(sql.str);
        stmt.bind_int(0, Geary.Email.Field.ALL);

        Db.Result results = stmt.exec(cancellable);

        Gee.HashSet<int64?> incomplete_locations = new Gee.HashSet<int64?>(Collection.int64_hash_func,
            Collection.int64_equal_func);
        while (!results.finished) {
            incomplete_locations.add(results.int64_at(0));
            results.next(cancellable);
        }

        if (incomplete_locations.size == 0) {
            locations.clear();

            return;
        }

        Gee.Iterator<LocationIdentifier> iter = locations.iterator();
        while (iter.next()) {
            if (!incomplete_locations.contains(iter.get().message_id))
                iter.remove();
        }
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

    private Gee.List<LocationIdentifier>? do_get_locations_for_ids(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier>? ids, ListFlags flags, Cancellable? cancellable)
        throws Error {
        if (ids == null || ids.size == 0)
            return null;

        StringBuilder sql = new StringBuilder("""
            SELECT message_id, ordering, remove_marker
            FROM MessageLocationTable
            WHERE message_id IN (
        """);
        bool first = true;
        foreach (ImapDB.EmailIdentifier id in ids) {
            if (!first)
                sql.append(",");
            sql.append_printf(id.message_id.to_string());

            first = false;
        }
        sql.append(") AND folder_id = ?");

        Db.Statement stmt = cx.prepare(sql.str);
        stmt.bind_rowid(0, folder_id);

        Gee.List<LocationIdentifier> locs = do_results_to_locations(stmt.exec(cancellable), int.MAX,
            flags, cancellable);

        return (locs.size > 0) ? locs : null;
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

    private Gee.List<LocationIdentifier>? do_get_locations_for_uids(Db.Connection cx,
        Gee.Collection<Imap.UID>? uids, ListFlags flags, Cancellable? cancellable)
        throws Error {
        if (uids == null || uids.size == 0)
            return null;

        StringBuilder sql = new StringBuilder("""
            SELECT message_id, ordering, remove_marker
            FROM MessageLocationTable
            WHERE ordering IN (
        """);
        bool first = true;
        foreach (Imap.UID uid in uids) {
            if (!first)
                sql.append(",");
            sql.append(uid.value.to_string());

            first = false;
        }
        sql.append(") AND folder_id = ?");

        Db.Statement stmt = cx.prepare(sql.str);
        stmt.bind_rowid(0, folder_id);

        Gee.List<LocationIdentifier> locs = do_results_to_locations(stmt.exec(cancellable), int.MAX,
            flags, cancellable);

        return (locs.size > 0) ? locs : null;
    }

    private Gee.List<LocationIdentifier>? do_get_all_locations(Db.Connection cx, ListFlags flags,
        Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT message_id, ordering, remove_marker
            FROM MessageLocationTable
            WHERE folder_id = ?
        """);
        stmt.bind_rowid(0, folder_id);

        Gee.List<LocationIdentifier> locs = do_results_to_locations(stmt.exec(cancellable), int.MAX,
            flags, cancellable);

        return (locs.size > 0) ? locs : null;
    }

    private int do_get_unread_count_for_ids(Db.Connection cx,
        Gee.Collection<ImapDB.EmailIdentifier>? ids, Cancellable? cancellable) throws Error {

        // Fetch flags for each email and update this folder's unread count.
        // (Note that this only flags for emails which have NOT been marked for removal
        // are included.)
        Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? flag_map = do_get_email_flags(cx,
            ids, ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
        if (flag_map != null)
            return Geary.traverse<Geary.EmailFlags>(flag_map.values).count_matching(f => f.is_unread());

        return 0;
    }

    // For SELECT/EXAMINE responses, not STATUS responses
    private void do_update_last_seen_select_examine_total(Db.Connection cx,
                                                          int total,
                                                          Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "UPDATE FolderTable SET last_seen_total=? WHERE id=?"
        );
        stmt.bind_int(0, Numeric.int_floor(total, 0));
        stmt.bind_rowid(1, this.folder_id);
        stmt.exec(cancellable);
    }

    // For STATUS responses, not SELECT/EXAMINE responses
    private void do_update_last_seen_status_total(Db.Connection cx,
                                                  int total,
                                                  Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "UPDATE FolderTable SET last_seen_status_total=? WHERE id=?");
        stmt.bind_int(0, Numeric.int_floor(total, 0));
        stmt.bind_rowid(1, this.folder_id);
        stmt.exec(cancellable);
    }

    private void do_update_uid_info(Db.Connection cx,
                                    Imap.FolderProperties remote_properties,
                                    Cancellable? cancellable)
        throws Error {
        int64 uid_validity = (remote_properties.uid_validity != null)
            ? remote_properties.uid_validity.value
            : Imap.UIDValidity.INVALID;
        int64 uid_next = (remote_properties.uid_next != null)
            ? remote_properties.uid_next.value
            : Imap.UID.INVALID;

        Db.Statement stmt = cx.prepare(
            "UPDATE FolderTable SET uid_validity=?, uid_next=? WHERE id=?");
        stmt.bind_int64(0, uid_validity);
        stmt.bind_int64(1, uid_next);
        stmt.bind_rowid(2, this.folder_id);
        stmt.exec(cancellable);
    }

}

