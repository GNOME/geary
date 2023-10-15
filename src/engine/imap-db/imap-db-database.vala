/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[CCode (cname = "g_utf8_collate_key")]
extern string utf8_collate_key(string data, ssize_t len);
extern int sqlite3_register_fts5_tokeniser(Sqlite.Database db);
extern int sqlite3_register_fts5_matches(Sqlite.Database db);
extern int sqlite3_register_legacy_tokenizer(Sqlite.Database db);

private class Geary.ImapDB.Database : Geary.Db.VersionedDatabase {


    /** SQLite UTF-8 case-insensitive, transliterating function name. */
    public const string UTF8_CASE_INSENSITIVE_FN = "UTF8FOLD";

    /** SQLite UTF-8 collation name. */
    public const string UTF8_COLLATE = "UTF8COLL";

    /** Options to use when running garbage collection. */
    [Flags]
    public enum GarbageCollectionOptions {

        /** Reaping will not be forced and vacuuming not permitted. */
        NONE,

        /**
         * Reaping will be performed, regardless of recommendation.
         */
        FORCE_REAP,

        /**
         * Whether to permit database vacuum.
         *
         * Vacuuming is performed in the foreground.
         */
        ALLOW_VACUUM;
    }

    public bool want_background_vacuum { get; set; default = false; }


    private static void utf8_transliterate_fold(Sqlite.Context context,
                                                Sqlite.Value[] values) {
        string? text = values[0].to_text();
        if (text != null) {
            context.result_text(Geary.Db.normalise_case_insensitive_query(text));
        } else {
            context.result_value(values[0]);
        }
    }

    private static int utf8_collate(int a_len, void* a_bytes,
                                    int b_len, void* b_bytes) {
        // Don't need to normalise, collate_key() will do it for us
        string? a_str = null;
        if (a_bytes != null) {
            a_str = utf8_collate_key((string) a_bytes, a_len);
        }
        string? b_str = null;
        if (b_bytes != null) {
            b_str = utf8_collate_key((string) b_bytes, b_len);
        }
        return GLib.strcmp(a_str, b_str);
    }


    internal GLib.File attachments_path;

    private const int OPEN_PUMP_EVENT_LOOP_MSEC = 100;

    private ProgressMonitor upgrade_monitor;
    private ProgressMonitor vacuum_monitor;
    private bool new_db = false;
    private bool is_open_in_progress = false;

    private GC? gc = null;
    private Cancellable gc_cancellable = new Cancellable();

    public Database(GLib.File db_file,
                    GLib.File schema_dir,
                    GLib.File attachments_path,
                    ProgressMonitor upgrade_monitor,
                    ProgressMonitor vacuum_monitor) {
        base.persistent(db_file, schema_dir);
        this.attachments_path = attachments_path;
        this.upgrade_monitor = upgrade_monitor;
        this.vacuum_monitor = vacuum_monitor;
    }

    /**
     * Prepares the ImapDB database for use.
     */
    public new async void open(Db.DatabaseFlags flags, Cancellable? cancellable)
        throws Error {
        this.is_open_in_progress = true;
        yield base.open(flags, cancellable);
        this.is_open_in_progress = false;
        yield run_gc(NONE, null, cancellable);
    }

    /**
     * Run garbage collection
     *
     * Reap should only be forced when there is known cleanup to perform and
     * the interval based recommendation should be bypassed.
     */
    public async void run_gc(GarbageCollectionOptions options,
                             Gee.Collection<Geary.ClientService>? to_pause,
                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.gc != null) {
            debug("GC abandoned, possibly already running");
            return;
        }

        // Tie user-supplied Cancellable to internal Cancellable, which is used when close() is
        // called
        if (cancellable != null)
            cancellable.cancelled.connect(cancel_gc);

        // Create new garbage collection object for this database
        this.gc = new GC(this, Priority.LOW);

        // Get recommendations on what GC operations should be executed
        GC.RecommendedOperation recommended = yield this.gc.should_run_async(
            gc_cancellable
        );

        // VACUUM needs to execute in the foreground with the user given a busy prompt (and cannot
        // be run at the same time as REAP)
        if ((recommended & GC.RecommendedOperation.VACUUM) != 0) {
            if (GarbageCollectionOptions.ALLOW_VACUUM in options) {
                this.want_background_vacuum = false;
                if (to_pause != null) {
                    foreach (ClientService service in to_pause) {
                        yield service.stop(gc_cancellable);
                    }
                }

                if (!vacuum_monitor.is_in_progress)
                    vacuum_monitor.notify_start();

                try {
                    yield this.gc.vacuum_async(gc_cancellable);
                } catch (Error err) {
                    message(
                        "Vacuum of IMAP database %s failed: %s", this.path, err.message
                    );
                    throw err;
                } finally {
                    if (vacuum_monitor.is_in_progress)
                        vacuum_monitor.notify_finish();
                }

                if (to_pause != null) {
                    foreach (ClientService service in to_pause) {
                        yield service.start(gc_cancellable);
                    }
                }
            } else {
                // Flag a vacuum to run later when we've been idle in the background
                debug("Flagging desire to GC vacuum");
                this.want_background_vacuum = true;
           }
        }

        // Abandon REAP if cancelled
        if (cancellable != null && cancellable.is_cancelled()) {
            cancellable.cancelled.disconnect(cancel_gc);
            return;
        }

        // REAP can run in the background while the application is executing
        if (GarbageCollectionOptions.FORCE_REAP in options || (recommended & GC.RecommendedOperation.REAP) != 0) {
            // run in the background and allow application to continue running
            this.gc.reap_async.begin(gc_cancellable, on_reap_async_completed);
        } else {
            this.gc = null;
        }

        if (cancellable != null)
            cancellable.cancelled.disconnect(cancel_gc);
    }

    private void on_reap_async_completed(Object? object, AsyncResult result) {
        try {
            this.gc.reap_async.end(result);
        } catch (Error err) {
            message("Garbage collection of IMAP database %s failed: %s",
                    this.path, err.message);
        }

        // Check if after reap we now want to schedule a background vacuum. The idea
        // here is eg. if we've just reduced prefetch period, reap has detached a
        // whole lot of messages and we want to vacuum. This check catches that
        // vacuum recommendation, flagging it to run when in background.
        this.gc.should_run_async.begin(
            gc_cancellable,
            (obj, res) => {
                try {
                    GC.RecommendedOperation recommended = this.gc.should_run_async.end(res);
                    if ((recommended & GC.RecommendedOperation.VACUUM) != 0)
                        this.want_background_vacuum = true;
                } catch (Error err) {
                    debug("Failed to run GC check on %s after REAP: %s",
                          this.path, err.message);
                }
            }
        );

        this.gc = null;
    }

    private void cancel_gc() {
        gc_cancellable.cancel();
        gc_cancellable = new Cancellable();
    }

    public override void close(Cancellable? cancellable) throws Error {
        // Ensure GC shuts down before returning
        cancel_gc();
        while (this.gc != null && this.gc.is_running) {
            GLib.MainContext.default().iteration(false);
        }

        base.close(cancellable);
    }

    protected override void starting_upgrade(int current_version, bool new_db) {
        this.new_db = new_db;

        // don't use upgrade_monitor for new databases, as the upgrade should be near-
        // instantaneous.  Also, there's some issue with GTK when starting the progress
        // monitor while GtkDialog's are in play:
        // https://bugzilla.gnome.org/show_bug.cgi?id=726269
        if (!new_db && !upgrade_monitor.is_in_progress) {
            upgrade_monitor.notify_start();
        }
    }

    protected override void completed_upgrade(int final_version) {
        if (!new_db && upgrade_monitor.is_in_progress) {
            upgrade_monitor.notify_finish();
        }
    }

    protected async override void post_upgrade(int version,
                                               Cancellable? cancellable)
        throws Error {
        switch (version) {
            case 6:
                yield post_upgrade_encode_folder_names(cancellable);
            break;

            case 12:
                yield post_upgrade_populate_internal_date_time_t(cancellable);
            break;

            case 13:
                yield post_upgrade_populate_additional_attachments(cancellable);
            break;

            case 14:
                yield post_upgrade_expand_page_size(cancellable);
            break;

            case 15:
                yield post_upgrade_fix_localized_internaldates(cancellable);
            break;

            case 18:
                yield post_upgrade_populate_internal_date_time_t(cancellable);
            break;

            case 19:
                yield post_upgrade_validate_contacts(cancellable);
            break;

            case 22:
                yield post_upgrade_rebuild_attachments(cancellable);
            break;
        }
    }

    // Version 6.
    private async void post_upgrade_encode_folder_names(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Result select = cx.query("SELECT id, name FROM FolderTable");
                while (!select.finished && !cancellable.is_cancelled()) {
                    int64 id = select.int64_at(0);
                    string encoded_name = select.nonnull_string_at(1);

                    try {
                        string canonical_name = Geary.ImapUtf7.imap_utf7_to_utf8(encoded_name);

                        Db.Statement update = cx.prepare(
                            "UPDATE FolderTable SET name=? WHERE id=?"
                        );
                        update.bind_string(0, canonical_name);
                        update.bind_int64(1, id);
                        update.exec();
                    } catch (Error e) {
                        debug("Error renaming folder %s to its canonical representation: %s", encoded_name, e.message);
                    }

                    select.next();
                }
                return Geary.Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    // Versions 12 and 18.
    private async void
        post_upgrade_populate_internal_date_time_t(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Result select = cx.query(
                    "SELECT id, internaldate FROM MessageTable"
                );
                while (!select.finished) {
                    int64 id = select.rowid_at(0);
                    string? internaldate = select.string_at(1);

                    try {
                        int64 as_time_t = (
                            internaldate != null
                            ? Imap.InternalDate.decode(internaldate).value.to_unix()
                            : -1
                        );

                        Db.Statement update = cx.prepare(
                            "UPDATE MessageTable SET internaldate_time_t=? WHERE id=?");
                        update.bind_int64(0, as_time_t);
                        update.bind_rowid(1, id);
                        update.exec();
                    } catch (Error e) {
                        debug("Error converting internaldate '%s' to time_t: %s",
                            internaldate, e.message);
                    }

                    select.next();
                }

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    // Version 13.
    private async void
        post_upgrade_populate_additional_attachments(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, header, body
                    FROM MessageTable
                    WHERE (fields & ?) = ?
                    """);
                stmt.bind_int(0, Geary.Email.REQUIRED_FOR_MESSAGE);
                stmt.bind_int(1, Geary.Email.REQUIRED_FOR_MESSAGE);
                Db.Result select = stmt.exec();

                while (!select.finished) {
                    int64 id = select.rowid_at(0);
                    Geary.Memory.Buffer header = select.string_buffer_at(1);
                    Geary.Memory.Buffer body = select.string_buffer_at(2);

                    try {
                        Geary.RFC822.Message message = new Geary.RFC822.Message.from_parts(
                            new RFC822.Header(header), new RFC822.Text(body));
                        Mime.DispositionType target_disposition = Mime.DispositionType.UNSPECIFIED;
                        if (message.get_sub_messages().is_empty)
                            target_disposition = Mime.DispositionType.INLINE;
                        Attachment.save_attachments(
                            cx,
                            this.attachments_path,
                            id,
                            message.get_attachments(target_disposition),
                            null
                        );
                    } catch (Error e) {
                        debug("Error fetching inline Mime parts: %s", e.message);
                    }

                    select.next();
                }

                // additionally, because this schema change (and code changes as well) introduces
                // two new types of attachments as well as processing for all MIME text sections
                // of messages (not just the first one), blow away the search table and let the
                // search indexer start afresh
                cx.exec("DELETE FROM MessageSearchTable");

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    // Version 14.
    private async void post_upgrade_expand_page_size(Cancellable? cancellable)
        throws Error {
        // When the MessageSearchTable is first touched,
        // SQLite seems to read the whole table into memory
        // (or an awful lot of data, either way).  This was
        // causing slowness when Geary first started and
        // checked for any messages not yet in the search
        // table.  With the database's page_size set to 4096,
        // the reads seem to happen about 2 orders of
        // magnitude quicker, probably because 4096 matches
        // the default filesystem block size and/or Linux's
        // default memory page size.  With this set, the full
        // read into memory is barely noticeable even on slow
        // machines.

        // NOTE: these can't be in the .sql file itself because
        // they must be back to back, outside of a transaction
        Geary.Db.Connection cx = yield open_connection();
        yield Nonblocking.Concurrent.global.schedule_async(() => {
                cx.exec("""
                    PRAGMA page_size = 4096;
                    VACUUM;
                """);
            }, cancellable);
    }

    // Version 15
    private async void
        post_upgrade_fix_localized_internaldates(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, internaldate, fields
                    FROM MessageTable
                """);

                Gee.HashMap<int64?, Geary.Email.Field> invalid_ids = new Gee.HashMap<
                    int64?, Geary.Email.Field>();

                Db.Result results = stmt.exec();
                while (!results.finished) {
                    string? internaldate = results.string_at(1);

                    try {
                        if (!String.is_empty(internaldate))
                            Imap.InternalDate.decode(internaldate);
                    } catch (Error err) {
                        int64 invalid_id = results.rowid_at(0);

                        debug("Invalid INTERNALDATE \"%s\" found at row %s in %s: %s",
                            internaldate != null ? internaldate : "(null)",
                            invalid_id.to_string(), this.path, err.message);
                        invalid_ids.set(invalid_id, (Geary.Email.Field) results.int_at(2));
                    }

                    results.next();
                }

                // used prepared statement for iterating over list
                stmt = cx.prepare("""
                    UPDATE MessageTable
                    SET fields=?, internaldate=?, internaldate_time_t=?, rfc822_size=?
                    WHERE id=?
                """);
                stmt.bind_null(1);
                stmt.bind_null(2);
                stmt.bind_null(3);

                foreach (int64 invalid_id in invalid_ids.keys) {
                    stmt.bind_int(0, invalid_ids.get(invalid_id).clear(Geary.Email.Field.PROPERTIES));
                    stmt.bind_rowid(4, invalid_id);

                    stmt.exec();

                    // reuse statement, overwrite invalid_id, fields only
                    stmt.reset(Db.ResetScope.SAVE_BINDINGS);
                }

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    // Version 19.
    private async void post_upgrade_validate_contacts(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Result result = cx.query("SELECT id, email FROM ContactTable");
                while (!result.finished) {
                    string email = result.string_at(1);
                    if (!RFC822.MailboxAddress.is_valid_address(email)) {
                        int64 id = result.rowid_at(0);

                        Db.Statement stmt = cx.prepare("DELETE FROM ContactTable WHERE id = ?");
                        stmt.bind_rowid(0, id);
                        stmt.exec();
                    }

                    result.next();
                }

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    // Version 22
    private async void post_upgrade_rebuild_attachments(Cancellable? cancellable)
        throws Error {
        yield exec_transaction_async(Db.TransactionType.RW, (cx) => {
                Db.Statement stmt = cx.prepare("""
                    SELECT id, header, body
                    FROM MessageTable
                    WHERE (fields & ?) = ?
                    """);
                stmt.bind_int(0, Geary.Email.REQUIRED_FOR_MESSAGE);
                stmt.bind_int(1, Geary.Email.REQUIRED_FOR_MESSAGE);

                Db.Result results = stmt.exec();
                if (results.finished)
                    return Db.TransactionOutcome.ROLLBACK;

                do {
                    int64 message_id = results.rowid_at(0);
                    Geary.Memory.Buffer header = results.string_buffer_at(1);
                    Geary.Memory.Buffer body = results.string_buffer_at(2);

                    Geary.RFC822.Message message;
                    try {
                        message = new Geary.RFC822.Message.from_parts(
                            new RFC822.Header(header), new RFC822.Text(body));
                    } catch (Error err) {
                        debug("Error decoding message: %s", err.message);
                        continue;
                    }

                    // build a list of attachments in the message itself
                    Gee.List<RFC822.Part> msg_attachments =
                    message.get_attachments();

                    try {
                        Attachment.delete_attachments(
                            cx, this.attachments_path, message_id
                        );
                    } catch (Error err) {
                        debug("Error deleting existing attachments: %s",
                              err.message);
                        continue;
                    }

                    // rebuild all
                    try {
                        Attachment.save_attachments(
                            cx,
                            this.attachments_path,
                            message_id,
                            msg_attachments,
                            null
                        );
                    } catch (Error err) {
                        debug("Error saving attachments: %s", err.message);

                        // fallthrough
                    }
                } while (results.next());

                // rebuild search table due to potentially new attachments
                cx.exec("DELETE FROM MessageSearchTable");

                return Db.TransactionOutcome.COMMIT;
            }, cancellable);
    }

    /**
     * Determines if the database's FTS table indexes are valid.
     */
    public bool fts_integrity_check() throws Error {
        Db.Statement stmt = prepare("""
            INSERT INTO MessageSearchTable(MessageSearchTable)
                VALUES('integrity-check')
        """);
        bool passed = true;
        try {
            stmt.exec();
        } catch (DatabaseError.CORRUPT err) {
            passed = false;
        }
        return passed;
    }

    /**
     * Rebuilds the database's FTS table index.
     *
     * This can be used to recover from corrupt indexes, as indicated
     * by fts_integrity_check() returning false.
     */
    public void fts_rebuild() throws Error {
        Db.Statement stmt = prepare("""
            INSERT INTO MessageSearchTable(MessageSearchTable)
                VALUES('rebuild')
        """);
        stmt.exec();
    }

    /**
     * Optimises the database's FTS table index.
     *
     * This is an expensive call, as much as performing a VACUUM.
     */
    public void fts_optimize() throws Error {
        Db.Statement stmt = prepare("""
            INSERT INTO MessageSearchTable(MessageSearchTable)
                VALUES('optimize')
        """);
        stmt.exec();
    }

    protected override void prepare_connection(Db.DatabaseConnection cx)
        throws GLib.Error {

        // SQLite might need more disk space than we have in /tmp
        // So use XDG_CACHE_DIR instead
        string tmp_path = "%s/geary/database".printf(
                GLib.Environment.get_user_cache_dir()
        );
        GLib.File tmp_directory = GLib.File.new_for_path(tmp_path);
        try {
            if (tmp_directory.query_exists() || tmp_directory.make_directory()) {
                cx.exec(
                    "PRAGMA temp_store_directory = '%s'".printf(tmp_path)
                );
            }
        } catch (GLib.Error err) {
            // Ignore error, will use /tmp as temp store
            debug("couldn't set db temp dir to $XDG_CACHE_DIR: %s", err.message);
        }

        cx.set_busy_timeout_msec(
            Db.DatabaseConnection.RECOMMENDED_BUSY_TIMEOUT_MSEC
        );
        cx.set_foreign_keys(true);
        cx.set_recursive_triggers(true);
        cx.set_synchronous(Db.SynchronousMode.NORMAL);

        if (this.is_open_in_progress) {
            // Register a tokenizer with old "unicodesn" name so that
            // upgrades for existing databases that still reference it
            // don't fail.
            sqlite3_register_legacy_tokenizer(cx.db);
        }

        // Register custom FTS5 tokeniser that uses ICU to correctly
        // segment at both Latin and on-Latin (e.g. CJK, Thai) word
        // boundaries.
        sqlite3_register_fts5_tokeniser(cx.db);

        // Register custom `geary_matches()` FTS5 function that
        // obtains matching tokens from FTS queries.
        sqlite3_register_fts5_matches(cx.db);

        if (cx.db.create_function(
                UTF8_CASE_INSENSITIVE_FN,
                1, // n args
                Sqlite.UTF8,
                null,
                Database.utf8_transliterate_fold,
                null,
                null
            ) != Sqlite.OK) {
            throw new DatabaseError.GENERAL(
                "Failed to register function %s",
                UTF8_CASE_INSENSITIVE_FN
            );
        }

        if (cx.db.create_collation(
                UTF8_COLLATE,
                Sqlite.UTF8,
                Database.utf8_collate
            ) != Sqlite.OK) {
            throw new DatabaseError.GENERAL(
                "Failed to register collation %s", UTF8_COLLATE
            );
        }
    }

}
