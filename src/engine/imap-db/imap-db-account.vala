/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Account : BaseObject {

    // Storage path names
    private const string DB_FILENAME = "geary.db";
    private const string ATTACHMENTS_DIR = "attachments";


    private class FolderReference : Geary.SmartReference {
        public Geary.FolderPath path;

        public FolderReference(ImapDB.Folder folder, Geary.FolderPath path) {
            base (folder);

            this.path = path;
        }
    }


    /**
     * The root path for all remote IMAP folders.
     *
     * No folder exists for this path locally or on the remote server,
     * it merely exists to provide a common root for the paths of all
     * IMAP folders.
     *
     * @see list_folders_async
     */
    public Imap.FolderRoot imap_folder_root {
        get; private set; default = new Imap.FolderRoot("$geary-imap");
    }

    // Only available when the Account is opened
    public IntervalProgressMonitor search_index_monitor { get; private set;
        default = new IntervalProgressMonitor(ProgressType.SEARCH_INDEX, 0, 0); }
    public SimpleProgressMonitor upgrade_monitor { get; private set; default = new SimpleProgressMonitor(
        ProgressType.DB_UPGRADE); }
    public SimpleProgressMonitor vacuum_monitor { get; private set; default = new SimpleProgressMonitor(
        ProgressType.DB_VACUUM); }

    /** The backing database for the account. */
    public ImapDB.Database db { get; private set; }

    internal AccountInformation account_information { get; private set; }

    private string name;
    private GLib.File db_file;
    private GLib.File attachments_dir;
    private Gee.HashMap<Geary.FolderPath, FolderReference> folder_refs =
        new Gee.HashMap<Geary.FolderPath, FolderReference>();
    private Cancellable? background_cancellable = null;

    public Account(AccountInformation config,
                   GLib.File data_dir,
                   GLib.File schema_dir) {
        this.account_information = config;
        this.name = config.id + ":db";
        this.db_file = data_dir.get_child(DB_FILENAME);
        this.attachments_dir = data_dir.get_child(ATTACHMENTS_DIR);

        this.db = new ImapDB.Database(
            this.db_file,
            schema_dir,
            this.attachments_dir,
            upgrade_monitor,
            vacuum_monitor
        );
    }

    public async void open_async(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.db.is_open) {
            throw new EngineError.ALREADY_OPEN("IMAP database already open");
        }

        try {
            yield db.open(
                Db.DatabaseFlags.CREATE_DIRECTORY | Db.DatabaseFlags.CREATE_FILE | Db.DatabaseFlags.CHECK_CORRUPTION,
                cancellable);
        } catch (Error err) {
            warning("Unable to open database: %s", err.message);

            // close database before exiting
            db.close(null);

            throw err;
        }

        // Have seen cases where multiple "Inbox" folders are created
        // in the root, leading to trouble ... this clears out all
        // Inboxes that don't match our "canonical" name and that
        // appears after the first that does.
        //
        // XXX the proper fix for this is of course to move this code
        // to a migration and add a uniqueness constraint on
        // (parent_id, name).
        try {
            yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, name
                    FROM FolderTable
                    WHERE parent_id IS NULL
                    ORDER BY id
                """);

                Db.Result results = stmt.exec(cancellable);
                bool found = false;
                while (!results.finished) {
                    string name = results.string_for("name");
                    if (Imap.MailboxSpecifier.is_inbox_name(name)) {
                        if (!found &&
                            Imap.MailboxSpecifier.is_canonical_inbox_name(name)) {
                            found = true;
                        } else {
                            warning("%s: Removing duplicate INBOX \"%s\"",
                                    this.name, name);
                            do_delete_folder(
                                cx, results.rowid_for("id"), cancellable
                            );
                        }
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

        background_cancellable = new Cancellable();
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

        this.background_cancellable.cancel();
        this.background_cancellable = null;

        this.folder_refs.clear();
    }

    public async Folder clone_folder_async(Geary.Imap.Folder imap_folder,
                                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open();

        Geary.Imap.FolderProperties properties = imap_folder.properties;
        Geary.FolderPath path = imap_folder.path;

        // XXX this should really be a db table constraint
        Geary.ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null) {
            throw new EngineError.ALREADY_EXISTS(
                "Folder with path already exists: %s", path.to_string()
            );
        }

        if (Imap.MailboxSpecifier.folder_path_is_inbox(path) &&
            !Imap.MailboxSpecifier.is_canonical_inbox_name(path.name)) {
            // Don't add faux inboxes
            throw new ImapError.NOT_SUPPORTED(
                "Inbox has : %s", path.to_string()
            );
        }

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
            stmt.bind_string(0, path.name);
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

        // XXX can't we create this from the INSERT above?
        return yield fetch_folder_async(path, cancellable);
    }

    public async void delete_folder_async(Geary.FolderPath path,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open();
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            int64 folder_id;
            do_fetch_folder_id(cx, path, false, out folder_id, cancellable);
            if (folder_id == Db.INVALID_ROWID) {
                throw new EngineError.NOT_FOUND(
                    "Folder not found: %s", path.to_string()
                );
            }

            if (do_has_children(cx, folder_id, cancellable)) {
                throw new ImapError.NOT_SUPPORTED(
                    "Folder has children: %s", path.to_string()
                );
            }

            do_delete_folder(cx, folder_id, cancellable);
            this.folder_refs.unset(path);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }

    /**
     * Lists all children of a given folder.
     *
     * To list all top-level folders, pass in {@link imap_folder_root}
     * as the parent.
     */
    public async Gee.Collection<Geary.ImapDB.Folder>
        list_folders_async(Geary.FolderPath parent,
                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open();

        // TODO: A better solution here would be to only pull the FolderProperties if the Folder
        // object itself doesn't already exist
        Gee.HashMap<Geary.FolderPath, int64?> id_map = new Gee.HashMap<
            Geary.FolderPath, int64?>();
        Gee.HashMap<Geary.FolderPath, Geary.Imap.FolderProperties> prop_map = new Gee.HashMap<
            Geary.FolderPath, Geary.Imap.FolderProperties>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            int64 parent_id = Db.INVALID_ROWID;
            if (!parent.is_root &&
                !do_fetch_folder_id(
                    cx, parent, false, out parent_id, cancellable
                )) {
                debug("Unable to find folder ID for \"%s\" to list folders", parent.to_string());
                return Db.TransactionOutcome.ROLLBACK;
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
                Geary.FolderPath path = parent.get_child(basename);
                Geary.Imap.FolderProperties properties = new Geary.Imap.FolderProperties.from_imapdb(
                    Geary.Imap.MailboxAttributes.deserialize(result.string_for("attributes")),
                    result.int_for("last_seen_total"),
                    result.int_for("unread_count"),
                    new Imap.UIDValidity(result.int64_for("uid_validity")),
                    new Imap.UID(result.int64_for("uid_next"))
                );
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
            throw new EngineError.NOT_FOUND(
                "No local folders under \"%s\"", parent.to_string()
            );
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
                properties = new Imap.FolderProperties.from_imapdb(
                    Geary.Imap.MailboxAttributes.deserialize(results.string_for("attributes")),
                    results.int_for("last_seen_total"),
                    results.int_for("unread_count"),
                    new Imap.UIDValidity(results.int64_for("uid_validity")),
                    new Imap.UID(results.int64_for("uid_next"))
                );
                // due to legacy code, can't set last_seen_total to -1 to indicate that the folder
                // hasn't been SELECT/EXAMINE'd yet, so the STATUS count should be used as the
                // authoritative when the other is zero ... this is important when first creating a
                // folder, as the STATUS is the count that is known first
                properties.set_status_message_count(
                    results.int_for("last_seen_status_total"),
                    (properties.select_examine_messages == 0)
                );
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

        return folder;
    }

    private Geary.ImapDB.Folder create_local_folder(Geary.FolderPath path, int64 folder_id,
        Imap.FolderProperties properties) throws Error {
        // return current if already created
        ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null) {
            folder.set_properties(properties);
        } else {
            folder = new Geary.ImapDB.Folder(
                db,
                path,
                db.attachments_path,
                account_information.primary_mailbox.address,
                folder_id,
                properties
            );

            // build a reference to it
            FolderReference folder_ref = new FolderReference(folder, path);
            folder_ref.reference_broken.connect(on_folder_reference_broken);

            // add to the references table
            folder_refs.set(folder_ref.path, folder_ref);

            folder.unread_updated.connect(on_unread_updated);
        }
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
        check_open();

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
                    Attachment.add_attachments(
                        cx, this.db.attachments_path, email, id, cancellable
                    );

                    Gee.Set<Geary.FolderPath>? folders = do_find_email_folders(cx, id, true, cancellable);
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

    private void sql_add_query_phrases(StringBuilder sql, Gee.HashMap<string, string> query_phrases,
        string operator, string columns, string condition) {
        bool is_first_field = true;
        foreach (string field in query_phrases.keys) {
            if (!is_first_field)
                sql.append_printf("""
                    %s
                    SELECT %s
                    FROM MessageSearchTable
                    WHERE %s
                    MATCH ?
                    %s
                """, operator, columns, field, condition);
            else
                sql.append_printf(" AND %s MATCH ?", field);
            is_first_field = false;
        }
    }

    private int sql_bind_query_phrases(Db.Statement stmt, int start_index,
        Gee.HashMap<string, string> query_phrases) throws Geary.DatabaseError {
        int i = start_index;
        // This relies on the keys being returned in the same order every time
        // from the same map.  It might not be guaranteed, but I feel pretty
        // confident it'll work unless you change the map in between.
        foreach (string field in query_phrases.keys)
            stmt.bind_string(i++, query_phrases.get(field));
        return i - start_index;
    }

    // Append each id in the collection to the StringBuilder, in a format
    // suitable for use in an SQL statement IN (...) clause.
    private void sql_append_ids(StringBuilder s, Gee.Iterable<int64?> ids) {
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

    public async Gee.Collection<Geary.EmailIdentifier>? search_async(Geary.SearchQuery q,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null)
        throws Error {

        debug("Search terms, offset/limit: %s %d/%d",
              q.to_string(), offset, limit);

        check_open();
        ImapDB.SearchQuery query = check_search_query(q);

        Gee.HashMap<string, string> query_phrases = query.get_query_phrases();
        Gee.Map<Geary.NamedFlag, bool> removal_conditions = query.get_removal_conditions();
        if (query_phrases.size == 0 && removal_conditions.is_empty)
            return null;

        foreach (string? field in query.get_fields()) {
            debug(" - Field \"%s\" terms:", field);
            foreach (SearchTerm? term in query.get_search_terms(field)) {
                if (term != null) {
                    debug("    - \"%s\": %s, %s",
                          term.original,
                          term.parsed,
                          term.stemmed
                    );
                    debug("      SQL terms:");
                    foreach (string sql in term.sql) {
                        debug("       - \"%s\"", sql);
                    }
                }
            }
        }

        // Do this outside of transaction to catch invalid search ids up-front
        string? search_ids_sql = get_search_ids_sql(search_ids);

        bool strip_greedy = query.should_strip_greedy_results();
        Gee.List<EmailIdentifier> matching_ids =
            new Gee.LinkedList<EmailIdentifier>();
        Gee.Map<EmailIdentifier,Gee.Set<string>>? search_matches = null;

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
            StringBuilder sql = new StringBuilder();
            sql.append("""
                SELECT id, internaldate_time_t
                FROM MessageTable
                INDEXED BY MessageTableInternalDateTimeTIndex
            """);
            if (query_phrases.size != 0) {
                sql.append("""
                    WHERE id IN (
                        SELECT docid
                        FROM MessageSearchTable
                        WHERE 1=1
                """);
                sql_add_query_phrases(sql, query_phrases, "INTERSECT", "docid", "");
                sql.append(")");
            } else
                sql.append(" WHERE 1=1");

            if (blacklisted_ids_sql != "")
                sql.append(" AND id NOT IN (%s)".printf(blacklisted_ids_sql));
            if (!Geary.String.is_empty(search_ids_sql))
                sql.append(" AND id IN (%s)".printf(search_ids_sql));
            sql.append(" ORDER BY internaldate_time_t DESC");
            if (limit > 0)
                sql.append(" LIMIT ? OFFSET ?");

            Db.Statement stmt = cx.prepare(sql.str);
            int bind_index = sql_bind_query_phrases(stmt, 0, query_phrases);
            if (limit > 0) {
                stmt.bind_int(bind_index++, limit);
                stmt.bind_int(bind_index++, offset);
            }

            Gee.HashMap<int64?, ImapDB.EmailIdentifier> id_map = new Gee.HashMap<int64?, ImapDB.EmailIdentifier>(
                Collection.int64_hash_func, Collection.int64_equal_func);

            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                int64 message_id = result.int64_at(0);
                int64 internaldate_time_t = result.int64_at(1);
                DateTime? internaldate = (internaldate_time_t == -1
                    ? null : new DateTime.from_unix_local(internaldate_time_t));

                ImapDB.EmailIdentifier id = new ImapDB.SearchEmailIdentifier(message_id, internaldate);
                matching_ids.add(id);
                id_map.set(message_id, id);

                result.next(cancellable);
            }


            if (strip_greedy && !id_map.is_empty) {
                search_matches = do_get_search_matches(
                    cx, query, id_map, cancellable
                );
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        debug("Matching emails found: %d", matching_ids.size);

        if (!removal_conditions.is_empty) {
            yield strip_removal_conditions(
                query, matching_ids, removal_conditions, cancellable
            );
        }

        if (strip_greedy && search_matches != null) {
            strip_greedy_results(query, matching_ids, search_matches);
        }

        debug("Final search matches: %d", matching_ids.size);
        return matching_ids.is_empty ? null : matching_ids;
    }

    // Strip out from the given collection any email that matches the
    // given removal conditions
    private async void strip_removal_conditions(ImapDB.SearchQuery query,
                                                Gee.Collection<EmailIdentifier> matches,
                                                Gee.Map<Geary.NamedFlag,bool> conditions,
                                                GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Email.Field required_fields = Geary.Email.Field.FLAGS;
        Gee.Iterator<EmailIdentifier> iter = matches.iterator();

        yield db.exec_transaction_async(RO, (cx) => {
                while (iter.next()) {
                    ImapDB.EmailIdentifier id = iter.get();
                    MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                        cx, id.message_id, required_fields, null, cancellable
                    );
                    Geary.EmailFlags? flags = row.get_generic_email_flags();
                    if (flags != null) {
                        foreach (Gee.Map.Entry<NamedFlag,bool> condition
                                 in conditions.entries) {
                            if (flags.contains(condition.key) == condition.value) {
                                iter.remove();
                                break;
                            }
                        }
                    } else {
                        iter.remove();
                    }
                }
                return Db.TransactionOutcome.DONE;
            }, cancellable
        );
    }

    // Strip out from the given collection of matching ids and results
    // for any search results that only contain a hit due to "greedy"
    // matching of the stemmed variants on all search terms.
    private void strip_greedy_results(SearchQuery query,
                                      Gee.Collection<EmailIdentifier> matches,
                                      Gee.Map<EmailIdentifier,Gee.Set<string>> results) {
        int prestripped_results = matches.size;
        Gee.Iterator<EmailIdentifier> iter = matches.iterator();
        while (iter.next()) {
            // For each matched string in this message, retain the message in the search results
            // if it prefix-matches any of the straight-up parsed terms or matches a stemmed
            // variant (with only max. difference in their lengths allowed, i.e. not a "greedy"
            // match)
            EmailIdentifier id = iter.get();
            bool good_match_found = false;
            Gee.Set<string>? result = results.get(id);
            if (result != null) {
                foreach (string match in result) {
                    foreach (SearchTerm term in query.get_all_terms()) {
                        // if prefix-matches parsed term, then don't strip
                        if (match.has_prefix(term.parsed)) {
                            good_match_found = true;
                            break;
                        }

                        // if prefix-matches stemmed term w/o doing so
                        // greedily, then don't strip
                        if (term.stemmed != null && match.has_prefix(term.stemmed)) {
                            int diff = match.length - term.stemmed.length;
                            if (diff <= query.max_difference_match_stem_lengths) {
                                good_match_found = true;
                                break;
                            }
                        }
                    }
                }

                if (good_match_found) {
                    break;
                }
            }

            if (!good_match_found) {
                iter.remove();
                matches.remove(id);
            }
        }

        debug("Stripped %d emails from search for [%s] due to greedy stem matching",
              prestripped_results - matches.size, query.raw);
    }

    public async Gee.Set<string>? get_search_matches_async(Geary.SearchQuery q,
        Gee.Collection<ImapDB.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        check_open();
        ImapDB.SearchQuery query = check_search_query(q);

        Gee.Set<string>? search_matches = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Gee.HashMap<int64?, ImapDB.EmailIdentifier> id_map = new Gee.HashMap<
                int64?, ImapDB.EmailIdentifier>(Collection.int64_hash_func, Collection.int64_equal_func);
            foreach (ImapDB.EmailIdentifier id in ids)
                id_map.set(id.message_id, id);

            Gee.Map<ImapDB.EmailIdentifier, Gee.Set<string>>? match_map =
                do_get_search_matches(cx, query, id_map, cancellable);
            if (match_map == null || match_map.size == 0)
                return Db.TransactionOutcome.DONE;

            if (query.should_strip_greedy_results()) {
                strip_greedy_results(query, ids, match_map);
            }

            search_matches = new Gee.HashSet<string>();
            foreach (Gee.Set<string> matches in match_map.values)
                search_matches.add_all(matches);

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return search_matches;
    }

    public async Gee.List<Email>? list_email(Gee.Collection<EmailIdentifier> ids,
                                             Email.Field required_fields,
                                             GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        check_open();

        var results = new Gee.ArrayList<Email>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
                foreach (var id in ids) {
                    // TODO: once we have a way of deleting messages, we won't be able
                    // to assume that a row id will point to the same email outside of
                    // transactions, because SQLite will reuse row ids.
                    Geary.Email.Field db_fields;
                    MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                        cx, id.message_id, required_fields, out db_fields, cancellable
                    );
                    if (!row.fields.fulfills(required_fields)) {
                        throw new EngineError.INCOMPLETE_MESSAGE(
                            "Message %s only fulfills %Xh fields (required: %Xh)",
                            id.to_string(), row.fields, required_fields
                        );
                    }

                    Email email = row.to_email(id);
                    Attachment.add_attachments(
                        cx,
                        this.db.attachments_path,
                        email,
                        id.message_id,
                        cancellable
                    );

                    results.add(email);
                }
                return Db.TransactionOutcome.DONE;
            },
            cancellable
        );

        return results;
    }

    public async Geary.Email fetch_email_async(ImapDB.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        check_open();

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
            Attachment.add_attachments(
                cx, this.db.attachments_path, email, email_id.message_id, cancellable
            );

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        assert(email != null);
        return email;
    }

    /**
     * Return a map of each passed-in email identifier to the set of folders
     * that contain it.  If an email id doesn't appear in the resulting map,
     * it isn't contained in any folders.  Return null if the resulting map
     * would be empty.  Only throw database errors et al., not errors due to
     * the email id not being found.
     */
    public async void
        get_containing_folders_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                     Gee.MultiMap<Geary.EmailIdentifier,FolderPath>? map,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx, cancellable) => {
            foreach (Geary.EmailIdentifier id in ids) {
                ImapDB.EmailIdentifier? imap_db_id = id as ImapDB.EmailIdentifier;
                if (imap_db_id == null)
                    continue;

                Gee.Set<Geary.FolderPath>? folders = do_find_email_folders(
                    cx, imap_db_id.message_id, false, cancellable);
                if (folders != null) {
                    Geary.Collection.multi_map_set_all<Geary.EmailIdentifier,
                        Geary.FolderPath>(map, id, folders);
                }
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);
    }

    public async void populate_search_table(Cancellable? cancellable) {
        debug("%s: Populating search table", account_information.id);
        try {
            while (!yield populate_search_table_batch_async(50, cancellable)) {
                // With multiple accounts, meaning multiple background threads
                // doing such CPU- and disk-heavy work, this process can cause
                // the main thread to slow to a crawl.  This delay means the
                // update takes more time, but leaves the main thread nice and
                // snappy the whole time.
                yield Geary.Scheduler.sleep_ms_async(50);
            }
        } catch (Error e) {
            debug("Error populating %s search table: %s", account_information.id, e.message);
        }

        if (search_index_monitor.is_in_progress)
            search_index_monitor.notify_finish();

        debug("%s: Done populating search table", account_information.id);
    }

    private static Gee.HashSet<int64?> do_build_rowid_set(Db.Result result, Cancellable? cancellable)
        throws Error {
        Gee.HashSet<int64?> rowid_set = new Gee.HashSet<int64?>(Collection.int64_hash_func,
            Collection.int64_equal_func);
        while (!result.finished) {
            rowid_set.add(result.rowid_at(0));
            result.next(cancellable);
        }

        return rowid_set;
    }

    private async bool populate_search_table_batch_async(int limit, Cancellable? cancellable)
        throws Error {
        check_open();
        debug("%s: Searching for up to %d missing indexed messages...", account_information.id,
            limit);

        int count = 0, total_unindexed = 0;
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx, cancellable) => {
            // Embedding a SELECT within a SELECT is painfully slow
            // with SQLite, and a LEFT OUTER JOIN will still take in
            // the order of seconds, so manually perform the operation

            Db.Statement stmt = cx.prepare("""
                SELECT docid FROM MessageSearchTable
            """);
            Gee.HashSet<int64?> search_ids = do_build_rowid_set(stmt.exec(cancellable), cancellable);

            stmt = cx.prepare("""
                SELECT id FROM MessageTable WHERE (fields & ?) = ?
            """);
            stmt.bind_uint(0, Geary.ImapDB.Folder.REQUIRED_FTS_FIELDS);
            stmt.bind_uint(1, Geary.ImapDB.Folder.REQUIRED_FTS_FIELDS);
            Gee.HashSet<int64?> message_ids = do_build_rowid_set(stmt.exec(cancellable), cancellable);

            // This is hard to calculate correctly without doing a
            // join (which we should above, but is currently too
            // slow), and if we do get it wrong the progress monitor
            // will crash and burn, so just something too big to fail
            // for now. See Bug 776383.
            total_unindexed = message_ids.size;

            // chaff out any MessageTable entries not present in the MessageSearchTable ... since
            // we're given a limit, stuff messages req'ing search into separate set and stop when limit
            // reached
            Gee.HashSet<int64?> unindexed_message_ids = new Gee.HashSet<int64?>(Collection.int64_hash_func,
                Collection.int64_equal_func);
            foreach (int64 message_id in message_ids) {
                if (search_ids.contains(message_id))
                    continue;

                unindexed_message_ids.add(message_id);
                if (unindexed_message_ids.size >= limit)
                    break;
            }

            // For all remaining MessageTable rowid's, generate search table entry
            foreach (int64 message_id in unindexed_message_ids) {
                try {
                    Geary.Email.Field search_fields = Geary.Email.REQUIRED_FOR_MESSAGE |
                        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.RECEIVERS |
                        Geary.Email.Field.SUBJECT;

                    Geary.Email.Field db_fields;
                    MessageRow row = Geary.ImapDB.Folder.do_fetch_message_row(
                        cx, message_id, search_fields, out db_fields, cancellable);
                    Geary.Email email = row.to_email(new Geary.ImapDB.EmailIdentifier(message_id, null));
                    Attachment.add_attachments(
                        cx, this.db.attachments_path, email, message_id, cancellable
                    );

                    Geary.ImapDB.Folder.do_add_email_to_search_table(cx, message_id, email, cancellable);
                } catch (Error e) {
                    // This is a somewhat serious issue since we rely on
                    // there always being a row in the search table for
                    // every message.
                    warning("Error adding message %s to the search table: %s", message_id.to_string(),
                        e.message);
                }

                ++count;
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        if (count > 0) {
            debug("%s: Found %d/%d missing indexed messages, %d remaining...",
                account_information.id, count, limit, total_unindexed);

            if (!search_index_monitor.is_in_progress) {
                search_index_monitor.set_interval(0, total_unindexed);
                search_index_monitor.notify_start();
            }

            search_index_monitor.increment(count);
        }

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

    // If the FolderPath has no parent, returns true and folder_id
    // will be set to Db.INVALID_ROWID.  If cannot create path or
    // there is a logical problem traversing it, returns false with
    // folder_id set to Db.INVALID_ROWID.
    internal bool do_fetch_folder_id(Db.Connection cx,
                                     Geary.FolderPath path,
                                     bool create,
                                     out int64 folder_id,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (path.is_root) {
            throw new EngineError.BAD_PARAMETERS(
                "Cannot fetch folder for root path"
            );
        }

        string[] parts = path.as_array();
        int64 parent_id = Db.INVALID_ROWID;
        folder_id = Db.INVALID_ROWID;

        foreach (string basename in parts) {
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

    internal bool do_fetch_parent_id(Db.Connection cx,
                                     FolderPath path,
                                     bool create,
                                     out int64 parent_id,
                                     GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        // See do_fetch_folder_id() for return semantics
        bool ret = true;

        // No folder for the root is saved in the database, so
        // top-levels should not have a parent.
        if (path.is_top_level) {
            parent_id = Db.INVALID_ROWID;
        } else {
            ret = do_fetch_folder_id(
                cx, path.parent, create, out parent_id, cancellable
            );
        }
        return ret;
    }

    private bool do_has_children(Db.Connection cx, int64 folder_id, Cancellable? cancellable) throws Error {
        Db.Statement stmt = cx.prepare("SELECT 1 FROM FolderTable WHERE parent_id = ?");
        stmt.bind_rowid(0, folder_id);
        Db.Result result = stmt.exec(cancellable);
        return !result.finished;
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
        if (blacklisted_ids.size > 0) {
            sql.append("""
                SELECT message_id
                FROM MessageLocationTable
                WHERE remove_marker = 0
                    AND folder_id IN (
            """);
            sql_append_ids(sql, blacklisted_ids);
            sql.append(")");

            if (blacklist_folderless)
                sql.append(" UNION ");
        }
        if (blacklist_folderless) {
            sql.append("""
                SELECT id
                FROM MessageTable
                WHERE id NOT IN (
                    SELECT message_id
                    FROM MessageLocationTable
                    WHERE remove_marker = 0
                )
            """);
        }

        return sql.str;
    }

    // For a message row id, return a set of all folders it's in, or null if
    // it's not in any folders.
    private Gee.Set<Geary.FolderPath>?
        do_find_email_folders(Db.Connection cx,
                              int64 message_id,
                              bool include_removed,
                              GLib.Cancellable? cancellable)
        throws GLib.Error {
        string sql = "SELECT folder_id FROM MessageLocationTable WHERE message_id=?";
        if (!include_removed)
            sql += " AND remove_marker=0";
        Db.Statement stmt = cx.prepare(sql);
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
    private Geary.FolderPath? do_find_folder_path(Db.Connection cx,
                                                  int64 folder_id,
                                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
        Db.Statement stmt = cx.prepare(
            "SELECT parent_id, name FROM FolderTable WHERE id=?"
        );
        stmt.bind_int64(0, folder_id);
        Db.Result result = stmt.exec(cancellable);

        if (result.finished)
            return null;

        int64 parent_id = result.int64_at(0);
        string name = result.nonnull_string_at(1);

        // Here too, one level of loop detection is better than nothing.
        if (folder_id == parent_id) {
            warning("Loop found in database: parent of %s is %s in FolderTable",
                folder_id.to_string(), parent_id.to_string());
            return null;
        }

        Geary.FolderPath? path = null;
        if (parent_id <= 0) {
            path = this.imap_folder_root.get_child(name);
        } else {
            Geary.FolderPath? parent_path = do_find_folder_path(
                cx, parent_id, cancellable
            );
            if (parent_path != null) {
                path = parent_path.get_child(name);
            }
        }
        return path;
    }

    private void on_unread_updated(ImapDB.Folder source, Gee.Map<ImapDB.EmailIdentifier, bool>
        unread_status) {
        update_unread_async.begin(source, unread_status, null);
    }

    // Updates unread count on all folders.
    private async void update_unread_async(ImapDB.Folder source, Gee.Map<ImapDB.EmailIdentifier, bool>
        unread_status, Cancellable? cancellable) throws Error {
        Gee.Map<Geary.FolderPath, int> unread_change = new Gee.HashMap<Geary.FolderPath, int>();

        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            foreach (ImapDB.EmailIdentifier id in unread_status.keys) {
                Gee.Set<Geary.FolderPath>? paths = do_find_email_folders(
                    cx, id.message_id, true, cancellable);
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

    // Not using a MultiMap because when traversing want to process all values at once per iteration,
    // not per key-value
    public Gee.Map<ImapDB.EmailIdentifier, Gee.Set<string>>? do_get_search_matches(Db.Connection cx,
        ImapDB.SearchQuery query, Gee.Map<int64?, ImapDB.EmailIdentifier> id_map, Cancellable? cancellable)
        throws Error {
        if (id_map.size == 0)
            return null;

        Gee.HashMap<string, string> query_phrases = query.get_query_phrases();
        if (query_phrases.size == 0)
            return null;

        StringBuilder sql = new StringBuilder();
        sql.append("""
            SELECT docid, offsets(MessageSearchTable), *
            FROM MessageSearchTable
            WHERE docid IN (
        """);
        sql_append_ids(sql, id_map.keys);
        sql.append(")");

        StringBuilder condition = new StringBuilder("AND docid IN (");
        sql_append_ids(condition, id_map.keys);
        condition.append(")");
        sql_add_query_phrases(sql, query_phrases, "UNION", "docid, offsets(MessageSearchTable), *",
            condition.str);

        Db.Statement stmt = cx.prepare(sql.str);
        sql_bind_query_phrases(stmt, 0, query_phrases);

        Gee.Map<ImapDB.EmailIdentifier, Gee.Set<string>> search_matches = new Gee.HashMap<
            ImapDB.EmailIdentifier, Gee.Set<string>>();

        Db.Result result = stmt.exec(cancellable);
        while (!result.finished) {
            int64 docid = result.rowid_at(0);
            assert(id_map.has_key(docid));
            ImapDB.EmailIdentifier id = id_map.get(docid);

            // XXX Avoid a crash when "database disk image is
            // malformed" error occurs. Remove this when the SQLite
            // bug is fixed. See b.g.o #765515 for more info.
            if (result.string_at(1) == null) {
                debug("Avoiding a crash from 'database disk image is malformed' error");
                result.next(cancellable);
                continue;
            }

            // offsets() function returns a list of 4 strings that are ints indicating position
            // and length of match string in search table corpus
            string[] offset_array = result.nonnull_string_at(1).split(" ");

            Gee.Set<string> matches = new Gee.HashSet<string>();

            int j = 0;
            while (true) {
                unowned string[] offset_string = offset_array[j:j+4];

                int column = int.parse(offset_string[0]);
                int byte_offset = int.parse(offset_string[2]);
                int size = int.parse(offset_string[3]);

                unowned string text = result.nonnull_string_at(column + 2);
                matches.add(text[byte_offset : byte_offset + size].down());

                j += 4;
                if (j >= offset_array.length)
                    break;
            }

            if (search_matches.has_key(id))
                matches.add_all(search_matches.get(id));
            search_matches.set(id, matches);

            result.next(cancellable);
        }

        return search_matches.size > 0 ? search_matches : null;
    }

    /** Removes database file and attachments directory. */
    public async void delete_all_data(GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.db.is_open) {
            throw new EngineError.ALREADY_OPEN(
                "Account cannot be open during rebuild"
            );
        }

        if (yield Files.query_exists_async(this.db_file, cancellable)) {
            message(
                "%s: Deleting database file %s...",
                this.name, this.db_file.get_path()
            );
            yield db_file.delete_async(GLib.Priority.DEFAULT, cancellable);
        }

        if (yield Files.query_exists_async(this.attachments_dir, cancellable)) {
            message(
                "%s: Deleting attachments directory %s...",
                this.name, this.attachments_dir.get_path()
            );
            yield Files.recursive_delete_async(
                this.attachments_dir, GLib.Priority.DEFAULT, cancellable
            );
        }
    }

    private inline void check_open() throws GLib.Error {
        if (!this.db.is_open) {
            throw new EngineError.OPEN_REQUIRED("Database not open");
        }
    }

    private ImapDB.SearchQuery check_search_query(Geary.SearchQuery q) throws Error {
        ImapDB.SearchQuery? query = q as ImapDB.SearchQuery;
        if (query == null || query.account != this)
            throw new EngineError.BAD_PARAMETERS("Geary.SearchQuery not associated with %s", name);

        return query;
    }

}
