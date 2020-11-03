/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * IMAP database garbage collector.
 *
 * Currently the garbage collector reaps messages unlinked from the MessageLocationTable older than
 * a prescribed date.  It also removes their on-disk attachment files (in a transaction-safe manner)
 * and looks for empty directories in the attachment directory tree (caused by attachment files
 * being removed without deleting their parents).
 *
 * The garbage collector is designed to run in the background and in such a way that it can be
 * closed (even by application shutdown) and re-run later without the database going incoherent.
 *
 * In addition, GC can recommend when to perform a VACUUM on the database and perform that
 * operation for the caller.  Vacuuming locks the database for an extended period of time, and GC
 * attempts to determine when it's best to do that by tracking the number of messages reaped by
 * the garbage collector.  (Vacuuming is really only advantageous when lots of rows have been
 * deleted in the database; without garbage collection, Geary's database tends to merely grow in
 * size.)  Unlike garbage collection, vacuuming is not designed to run in the background and the
 * user should be presented a busy monitor while it's occurring.
 */

private class Geary.ImapDB.GC {
    // Maximum number of days between reaping runs.
    private const int REAP_DAYS_SPAN = 10;

    // Minimum number of days between vacuums.
    private const int VACUUM_DAYS_SPAN = 30;

    // Number of reaped messages since last vacuum indicating another vacuum should occur
    private const int VACUUM_WHEN_REAPED_REACHES = 10000;

    // Amount of disk space that must be saved to start a vacuum (500MB).
    private const long VACUUM_WHEN_FREE_BYTES = 500 * 1024 * 1024;

    // Days old from today an unlinked email message must be to be reaped by the garbage collector
    private const int UNLINKED_DAYS = 30;

    // Amount of time to sleep between various database-bound GC iterations to give other
    // transactions a chance
    private const uint SLEEP_MSEC = 15;

    // Number of database operations to perform before sleeping (obviously this is a rough
    // approximation, as not all operations are the same cost)
    private const int OPS_PER_SLEEP_CYCLE = 10;

    // Number of files to reap from the DeleteAttachmentFileTable per iteration
    private const int REAP_ATTACHMENT_PER = 5;

    // Number of files to enumerate per time when walking a directory's children
    private const int ENUM_DIR_PER = 10;

    /**
     * Operation(s) recommended by {@link should_run_async}.
     */
    [Flags]
    public enum RecommendedOperation {
        /**
         * Indicates no garbage collection is recommended at this time.
         */
        NONE = 0,
        /*
         * Indicates the caller should run {@link reap_async} to potentially clean up unlinked
         * messages and files.
         */
        REAP,
        /**
         * Indicates the caller should run {@link vacuum_async} to consolidate disk space and reduce
         * database fragmentation.
         */
        VACUUM
    }

    /**
     * Indicates the garbage collector is running.
     */
    public bool is_running { get; private set; default = false; }

    private ImapDB.Database db;
    private int priority;

    public GC(ImapDB.Database db, int priority) {
        this.db = db;
        this.priority = priority;
    }

    /**
     * Determines if the GC should be executed.
     *
     * @return a recommendation for the operation client to execute.
     */
    public async RecommendedOperation should_run_async(Cancellable? cancellable) throws Error {
        DateTime? last_reap_time, last_vacuum_time;
        int reaped_messages_since_last_vacuum;
        int64 free_page_bytes;
        yield fetch_gc_info_async(cancellable, out last_reap_time, out last_vacuum_time,
            out reaped_messages_since_last_vacuum, out free_page_bytes);

        debug("[%s] GC state: last_reap_time=%s last_vacuum_time=%s reaped_messages_since=%d free_page_bytes=%s",
            to_string(),
            (last_reap_time != null) ? last_reap_time.to_string() : "never",
            (last_vacuum_time != null) ? last_vacuum_time.to_string() : "never",
            reaped_messages_since_last_vacuum,
            free_page_bytes.to_string());

        RecommendedOperation op = RecommendedOperation.NONE;
        if (!yield has_message_rows(cancellable)) {
            // No message rows exist, so don't bother vacuuming
            return op;
        }

        // Reap every REAP_DAYS_SPAN unless never executed, in which case run now
        DateTime now = new DateTime.now_local();
        int64 days;
        if (last_reap_time == null) {
            // null means reaping has never executed
            debug("[%s] Recommending reaping: never completed", to_string());

            op |= RecommendedOperation.REAP;
        } else if (elapsed_days(now, last_reap_time, out days) >= REAP_DAYS_SPAN) {
            debug("[%s] Recommending reaping: %s days since last run", to_string(),
                days.to_string());

            op |= RecommendedOperation.REAP;
        } else {
            debug("[%s] Reaping last completed on %s (%s days ago)", to_string(),
                last_reap_time.to_string(), days.to_string());
        }

        // VACUUM is not something we do regularly, but rather look for a lot of reaped messages
        // as indicator it's time ... to prevent doing this a lot (which is annoying), still space
        // it out over a minimum amount of time
        days = 0;
        bool vacuum_permitted;
        if (last_vacuum_time == null) {
            debug("[%s] Database never vacuumed (%d messages reaped)", to_string(),
                reaped_messages_since_last_vacuum);

            vacuum_permitted = true;
        } else if (elapsed_days(now, last_vacuum_time, out days) >= VACUUM_DAYS_SPAN) {
            debug("[%s] Database vacuuming permitted (%s days since last run, %d messages reaped since)",
                to_string(), days.to_string(), reaped_messages_since_last_vacuum);

            vacuum_permitted = true;
        } else {
            debug("[%s] Database vacuuming not permitted (%s days since last run, %d messages reaped since)",
                to_string(), days.to_string(), reaped_messages_since_last_vacuum);

            vacuum_permitted = false;
        }

        // VACUUM_DAYS_SPAN must have passed since last vacuum (unless no prior vacuum has occurred)
        // *and* a certain number of messages have been reaped (indicating fragmentation is a
        // possibility) or a certain amount of free space exists in the database (indicating they
        // can be freed back to the filesystem)
        bool fragmentation_exists = reaped_messages_since_last_vacuum >= VACUUM_WHEN_REAPED_REACHES;
        bool too_much_free_space = free_page_bytes >= VACUUM_WHEN_FREE_BYTES;
        if (vacuum_permitted && (fragmentation_exists || too_much_free_space)) {
            debug("[%s] Recommending database vacuum: %d messages reaped since last vacuum %s days ago, %s free bytes in file",
                to_string(), reaped_messages_since_last_vacuum, days.to_string(), free_page_bytes.to_string());

            op |= RecommendedOperation.VACUUM;
        }

        return op;
    }

    private static int64 elapsed_days(DateTime end, DateTime start, out int64 days) {
        days = end.difference(start) / TimeSpan.DAY;

        return days;
    }

    /**
     * Vacuum the database, reducing fragmentation and coalescing free space, to optimize access
     * and reduce disk usage.
     *
     * Should only be called from the foreground thread.
     *
     * Since this will lock the database for an extended period of time, the user should be
     * presented a busy indicator.  Operations against the database should not be expected to run
     * until this completes.  Cancellation will not work once vacuuming has started.
     *
     * @throws Geary.EngineError.ALREADY_OPEN if {@link is_running} is true.
     */
    public async void vacuum_async(Cancellable? cancellable) throws Error {
        if (is_running)
            throw new EngineError.ALREADY_OPEN("Cannot vacuum %s: already running", to_string());

        is_running = true;
        try {
            debug("[%s] Starting vacuum of IMAP database", to_string());
            yield internal_vacuum_async(cancellable);
            debug("[%s] Completed vacuum of IMAP database", to_string());
        } finally {
            is_running = false;
        }
    }

    private async void internal_vacuum_async(Cancellable? cancellable) throws Error {
        DateTime? last_vacuum_time = null;

        // NOTE: VACUUM cannot happen inside a transaction, so to avoid blocking the main thread,
        // run a non-transacted command from a background thread
        Geary.Db.DatabaseConnection cx = yield db.open_connection(cancellable);
        yield Nonblocking.Concurrent.global.schedule_async(() => {
            cx.exec("VACUUM", cancellable);

            // it's a small thing, but take snapshot of time when vacuum completes, as scheduling
            // of the next transaction is not instantaneous
            last_vacuum_time = new DateTime.now_local();
        }, cancellable);

        // could assert here, but these calls really need to be bulletproof
        if (last_vacuum_time == null)
            last_vacuum_time = new DateTime.now_local();

        // update last vacuum time and reset messages reaped since last vacuum ... don't allow this
        // to be cancelled, really want to get this in stone so the user doesn't re-vacuum
        // unnecessarily
        yield cx.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                UPDATE GarbageCollectionTable
                SET last_vacuum_time_t = ?, reaped_messages_since_last_vacuum = ?
                WHERE id = 0
            """);
            stmt.bind_int64(0, last_vacuum_time.to_unix());
            stmt.bind_int(1, 0);

            stmt.exec(cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, null);
    }

    /**
     * Run the garbage collector, which reaps unlinked messages from the database and deletes
     * their on-disk attachments.
     *
     * Should only be called from the foreground thread.  {@link reap_async} is designed to run in
     * the background, so the application may continue while it's executing.  It also is designed
     * to be interrupted (i.e. the application closes) and pick back up where it left off when the
     * application restarts.
     *
     * @throws Geary.EngineError.ALREADY_OPEN if {@link is_running} is true.
     */
    public async void reap_async(Cancellable? cancellable) throws Error {
        if (is_running)
            throw new EngineError.ALREADY_OPEN("Cannot garbage collect %s: already running", to_string());

        is_running = true;
        try {
            debug("[%s] Starting garbage collection of IMAP database", to_string());
            yield internal_reap_async(cancellable);
            debug("[%s] Completed garbage collection of IMAP database", to_string());
        } finally {
            is_running = false;
        }
    }

    private async void internal_reap_async(Cancellable? cancellable) throws Error {
        //
        // Find all messages unlinked from the location table and older than the GC reap date ...
        // this is necessary because we can't be certain at any point in time that the local store
        // is fully synchronized with the server.  For example, it's possible we recvd a message in
        // the Inbox, the user archived it, then closed Geary before the engine could synchronize
        // with All Mail.  In that situation, the email is completely unlinked from the
        // MessageLocationTable but still on the server.  This attempts to give some "breathing
        // room" and not remove that message until we feel more comfortable that it's truly
        // unlinked.
        //
        // If the message is reaped and detected later during folder normalization, the engine will
        // merely re-download it and link the new copy to the MessageLocationTable.  The
        // UNLINKED_DAYS optimization is merely an attempt to avoid re-downloading email.
        //
        // Checking internaldate_time_t is NULL is a way to reap emails that were allocated a row
        // in the MessageTable but never downloaded.  Since internaldate is the first thing
        // downloaded, this is rare, but can happen, and this will reap those rows.
        //

        DateTime reap_date = new DateTime.now_local().add_days(0 - UNLINKED_DAYS);
        debug("[%s] Garbage collector reaping date: %s (%s)", to_string(), reap_date.to_string(),
            reap_date.to_unix().to_string());

        Gee.HashSet<int64?> reap_message_ids = new Gee.HashSet<int64?>(Collection.int64_hash_func,
            Collection.int64_equal_func);

        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                SELECT id
                FROM MessageTable
                WHERE (internaldate_time_t IS NULL OR internaldate_time_t <= ?)
                AND NOT EXISTS (
                    SELECT message_id
                    FROM MessageLocationTable
                    WHERE MessageLocationTable.message_id = MessageTable.id
                )
            """);
            stmt.bind_int64(0, reap_date.to_unix());

            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                reap_message_ids.add(result.rowid_at(0));

                result.next(cancellable);
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        message("[%s] Found %d email messages ready for reaping", to_string(), reap_message_ids.size);

        //
        // To prevent holding the database lock for long periods of time, reap each message one
        // at a time, deleting it from the message table and subsidiary tables.  Although slow, we
        // do want this to be a background task that doesn't interrupt the user.  This approach
        // also means gc can be interrupted at any time (i.e. the user exits the application)
        // without leaving the database in an incoherent state.  gc can be resumed even if'
        // interrupted.
        //

        int count = 0;
        foreach (int64 reap_message_id in reap_message_ids) {
            try {
                yield reap_message_async(reap_message_id, cancellable);
                count++;
            } catch (Error err) {
                if (err is IOError.CANCELLED)
                    throw err;

                message("[%s] Unable to reap message #%s: %s", to_string(), reap_message_id.to_string(),
                    err.message);
            }

            if ((count % OPS_PER_SLEEP_CYCLE) == 0)
                yield Scheduler.sleep_ms_async(SLEEP_MSEC);

            if ((count % 5000) == 0)
                debug("[%s] Reaped %d messages", to_string(), count);
        }

        message("[%s] Reaped completed: %d messages", to_string(), count);

        //
        // Now reap on-disk attachment files marked for deletion.  Since they're added to the
        // DeleteAttachmentFileTable as part of the reap_message_async() transaction, it's assured
        // that they're ready for deletion (and, again, means this process is resumable)
        //

        count = 0;
        for (;;) {
            int reaped = yield reap_attachment_files_async(REAP_ATTACHMENT_PER, cancellable);
            if (reaped == 0)
                break;

            count += reaped;

            if ((count % OPS_PER_SLEEP_CYCLE) == 0)
                yield Scheduler.sleep_ms_async(SLEEP_MSEC);

            if ((count % 1000) == 0)
                debug("[%s] Reaped %d attachment files", to_string(), count);
        }

        message("[%s] Completed: Reaped %d attachment files", to_string(), count);

        //
        // To be sure everything's clean, delete any empty directories in the attachment dir tree,
        // as code (here and elsewhere) only removes files.
        //

        count = yield delete_empty_attachment_directories_async(null, cancellable, null);

        message("[%s] Deleted %d empty attachment directories", to_string(), count);

        //
        // A full reap cycle completed -- store date for next time.  By only storing when the full
        // cycle is completed, even if the user closes the application through the cycle it will
        // start the next time, assuring all reaped messages/attachments are dealt with in a timely
        // manner.
        //

        yield db.exec_transaction_async(Db.TransactionType.WO, (cx) => {
            Db.Statement stmt = cx.prepare("""
                UPDATE GarbageCollectionTable
                SET last_reap_time_t = ?
                WHERE id = 0
            """);
            stmt.bind_int64(0, new DateTime.now_local().to_unix());

            stmt.exec(cancellable);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }

    private async void reap_message_async(int64 message_id, Cancellable? cancellable) throws Error {
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            // Since there's a window of time between locating gc-able messages and removing them,
            // need to double-check in the transaction that it's still not in the MessageLocationTable.
            Db.Statement stmt = cx.prepare("""
                SELECT id
                FROM MessageLocationTable
                WHERE message_id = ?
            """);
            stmt.bind_rowid(0, message_id);

            // If find one, then message is no longer unlinked
            Db.Result result = stmt.exec(cancellable);
            if (!result.finished) {
                debug("[%s] Not reaping message #%s: found linked in MessageLocationTable",
                    to_string(), message_id.to_string());

                return Db.TransactionOutcome.ROLLBACK;
            }

            //
            // Fetch all on-disk attachments for this message
            //

            Gee.List<Attachment> attachments = Attachment.list_attachments(
                cx, this.db.attachments_path, message_id, cancellable
            );

            //
            // Delete from search table
            //

            stmt = cx.prepare("""
                DELETE FROM MessageSearchTable
                WHERE rowid = ?
            """);
            stmt.bind_rowid(0, message_id);

            stmt.exec(cancellable);

            //
            // Delete from attachment table
            //

            stmt = cx.prepare("""
                DELETE FROM MessageAttachmentTable
                WHERE message_id = ?
            """);
            stmt.bind_rowid(0, message_id);

            stmt.exec(cancellable);

            //
            // Delete from message table
            //

            stmt = cx.prepare("""
                DELETE FROM MessageTable
                WHERE id = ?
            """);
            stmt.bind_rowid(0, message_id);

            stmt.exec(cancellable);

            //
            // Mark on-disk attachment files as ready for deletion (handled by
            // reap_attachments_files_async).  This two-step process assures that this transaction
            // commits without error and the attachment files can be deleted without being
            // referenced by the database, in a way that's resumable.
            //

            foreach (Attachment attachment in attachments) {
                stmt = cx.prepare("""
                    INSERT INTO DeleteAttachmentFileTable (filename)
                    VALUES (?)
                """);
                stmt.bind_string(0, attachment.file.get_path());
                stmt.exec(cancellable);
            }

            //
            // Increment the reap count since last vacuum
            //

            cx.exec("""
                UPDATE GarbageCollectionTable
                SET reaped_messages_since_last_vacuum = reaped_messages_since_last_vacuum + 1
                WHERE id = 0
            """);

            //
            // Done; other than on-disk attachment files, message is now garbage collected.
            //

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }

    private async int reap_attachment_files_async(int limit, Cancellable? cancellable) throws Error {
        if (limit <= 0)
            return 0;

        int deleted = 0;
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            Db.Statement stmt = cx.prepare("""
                SELECT id, filename
                FROM DeleteAttachmentFileTable
                LIMIT ?
            """);
            stmt.bind_int(0, limit);

            // build SQL for removing file from table (whether it's deleted or not -- at this point,
            // we're in best-attempt mode)
            StringBuilder sql = new StringBuilder("""
                DELETE FROM DeleteAttachmentFileTable
                WHERE id IN (
            """);

            Db.Result result = stmt.exec(cancellable);
            bool first = true;
            while (!result.finished) {
                int64 id = result.rowid_at(0);
                File file = File.new_for_path(result.string_at(1));

                // if it deletes, great; if not, we tried
                try {
                    file.delete(cancellable);
                } catch (Error err) {
                    if (err is IOError.CANCELLED)
                        throw err;

                    debug("[%s] Unable to delete reaped attachment file \"%s\": %s", to_string(),
                        file.get_path(), err.message);
                }

                if (!first)
                    sql.append(", ");

                sql.append(id.to_string());
                first = false;

                deleted++;

                result.next(cancellable);
            }

            sql.append(")");

            // if any files were deleted, remove them from the table
            if (deleted > 0)
                cx.exec(sql.str);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        return deleted;
    }

    private async int delete_empty_attachment_directories_async(File? current, Cancellable? cancellable,
        out bool empty) throws Error {
        File current_dir = current ?? db.attachments_path;

        // directory is considered empty until file or non-deleted child directory is found
        empty = true;

        int deleted = 0;
        FileEnumerator file_enum = yield current_dir.enumerate_children_async("*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, priority, cancellable);
        for (;;) {
            List<FileInfo> infos = yield file_enum.next_files_async(ENUM_DIR_PER, priority, cancellable);
            if (infos.length() == 0)
                break;

            foreach (FileInfo info in infos) {
                if (info.get_file_type() != FileType.DIRECTORY) {
                    empty = false;

                    continue;
                }

                File child = current_dir.get_child(info.get_name());

                bool child_empty;
                deleted += yield delete_empty_attachment_directories_async(child, cancellable,
                    out child_empty);
                if (!child_empty) {
                    empty = false;

                    continue;
                }

                string? failure = null;
                try {
                    if (!yield child.delete_async(priority, cancellable))
                        failure = "delete indicates not empty";
                } catch (Error err) {
                    if (err is IOError.CANCELLED)
                        throw err;

                    failure = err.message;
                }

                if (failure == null) {
                    deleted++;
                } else {
                    message("[%s] Unable to delete empty attachment directory \"%s\": %s",
                        to_string(), child.get_path(), failure);

                    // since it remains, directory not empty
                    empty = false;
                }
            }
        }

        yield file_enum.close_async(priority, cancellable);

        return deleted;
    }

    private async bool has_message_rows(GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool ret = false;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
                Db.Result result = cx.query(
                    "SELECT count(*) FROM MessageTable LIMIT 1"
                );

                Db.TransactionOutcome txn_ret = FAILURE;
                if (!result.finished) {
                    txn_ret = SUCCESS;
                    ret = result.int64_at(0) > 0;
                }
                return txn_ret;
            }, cancellable);
        return ret;
    }

    private async void fetch_gc_info_async(Cancellable? cancellable, out DateTime? last_reap_time,
        out DateTime? last_vacuum_time, out int reaped_messages_since_last_vacuum, out int64 free_page_bytes)
        throws Error {
        // dealing with out arguments for an async method inside a closure is asking for trouble
        int64 last_reap_time_t = -1, last_vacuum_time_t = -1, free_page_count = 0;
        int reaped_count = -1, page_size = 0;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            Db.Result result = cx.query("""
                SELECT last_reap_time_t, last_vacuum_time_t, reaped_messages_since_last_vacuum
                FROM GarbageCollectionTable
                WHERE id = 0
            """);

            if (result.finished)
                return Db.TransactionOutcome.FAILURE;

            // NULL indicates reaping/vacuum has not run
            last_reap_time_t = !result.is_null_at(0) ? result.int64_at(0) : -1;
            last_vacuum_time_t = !result.is_null_at(1) ? result.int64_at(1) : -1;
            reaped_count = result.int_at(2);

            free_page_count = cx.get_free_page_count();
            page_size = cx.get_page_size();

            return Db.TransactionOutcome.SUCCESS;
        }, cancellable);

        last_reap_time = (last_reap_time_t >= 0) ? new DateTime.from_unix_local(last_reap_time_t) : null;
        last_vacuum_time = (last_vacuum_time_t >= 0) ? new DateTime.from_unix_local(last_vacuum_time_t) : null;
        reaped_messages_since_last_vacuum = reaped_count;
        free_page_bytes = free_page_count * page_size;
    }

    public string to_string() {
        return "GC:%s".printf(db.path);
    }
}
