/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern int sqlite3_unicodesn_register_tokenizer(Sqlite.Database db);

private class Geary.ImapDB.Database : Geary.Db.VersionedDatabase {
    private const string DB_FILENAME = "geary.db";
    private const int OPEN_PUMP_EVENT_LOOP_MSEC = 100;
    
    private ProgressMonitor upgrade_monitor;
    private ProgressMonitor vacuum_monitor;
    private string account_owner_email;
    private bool new_db = false;
    private Cancellable gc_cancellable = new Cancellable();
    
    public Database(File db_dir, File schema_dir, ProgressMonitor upgrade_monitor,
        ProgressMonitor vacuum_monitor, string account_owner_email) {
        base (get_db_file(db_dir), schema_dir);
        
        this.upgrade_monitor = upgrade_monitor;
        this.vacuum_monitor = vacuum_monitor;
        this.account_owner_email = account_owner_email;
    }
    
    public static File get_db_file(File db_dir) {
        return db_dir.get_child(DB_FILENAME);
    }
    
    /**
     * Opens the ImapDB database.
     *
     * This should only be done from the main thread, as it is designed to pump the event loop
     * while the database is being opened and updated.
     */
    public async void open_async(Db.DatabaseFlags flags, Cancellable? cancellable) throws Error {
        open_background(flags, on_prepare_database_connection, pump_event_loop,
            OPEN_PUMP_EVENT_LOOP_MSEC, cancellable);
        
        // Tie user-supplied Cancellable to internal Cancellable, which is used when close() is
        // called
        if (cancellable != null)
            cancellable.cancelled.connect(cancel_gc);
        
        // Create new garbage collection object for this database
        GC gc = new GC(this, Priority.LOW);
        
        // Get recommendations on what GC operations should be executed
        GC.RecommendedOperation recommended = yield gc.should_run_async(gc_cancellable);
        
        // VACUUM needs to execute in the foreground with the user given a busy prompt (and cannot
        // be run at the same time as REAP)
        if ((recommended & GC.RecommendedOperation.VACUUM) != 0) {
            if (!vacuum_monitor.is_in_progress)
                vacuum_monitor.notify_start();
            
            try {
                yield gc.vacuum_async(gc_cancellable);
            } catch (Error err) {
                message("Vacuum of IMAP database %s failed: %s", db_file.get_path(), err.message);
                
                throw err;
            } finally {
                if (vacuum_monitor.is_in_progress)
                    vacuum_monitor.notify_finish();
            }
        }
        
        // REAP can run in the background while the application is executing
        if ((recommended & GC.RecommendedOperation.REAP) != 0) {
            // run in the background and allow application to continue running
            gc.reap_async.begin(gc_cancellable, on_reap_async_completed);
        }
        
        if (cancellable != null)
            cancellable.cancelled.disconnect(cancel_gc);
    }
    
    private void on_reap_async_completed(Object? object, AsyncResult result) {
        GC gc = (GC) object;
        try {
            gc.reap_async.end(result);
        } catch (Error err) {
            message("Garbage collection of IMAP database %s failed: %s", db_file.get_path(), err.message);
        }
    }
    
    private void cancel_gc() {
        gc_cancellable.cancel();
        gc_cancellable = new Cancellable();
    }
    
    public override void close(Cancellable? cancellable) throws Error {
        cancel_gc();
        
        base.close(cancellable);
    }
    
    private void pump_event_loop() {
        while (MainContext.default().pending())
            MainContext.default().iteration(true);
    }
    
    protected override void starting_upgrade(int current_version, bool new_db) {
        this.new_db = new_db;
        // can't call the ProgressMonitor directly, as it's hooked up to signals that expect to be
        // called in the foreground thread, so use the Idle loop for this
        Idle.add(() => {
            // don't use upgrade_monitor for new databases, as the upgrade should be near-
            // instantaneous.  Also, there's some issue with GTK when starting the progress
            // monitor while GtkDialog's are in play:
            // https://bugzilla.gnome.org/show_bug.cgi?id=726269
            if (!new_db && !upgrade_monitor.is_in_progress)
                upgrade_monitor.notify_start();
            
            return false;
        });
    }
    
    protected override void completed_upgrade(int final_version) {
        // see starting_upgrade() for explanation why this is done in Idle loop
        Idle.add(() => {
            if (!new_db && upgrade_monitor.is_in_progress)
                upgrade_monitor.notify_finish();
            
            return false;
        });
    }
    
    protected override void post_upgrade(int version) {
        switch (version) {
            case 5:
                post_upgrade_populate_autocomplete();
            break;
            
            case 6:
                post_upgrade_encode_folder_names();
            break;
            
            case 11:
                post_upgrade_add_search_table();
            break;
            
            case 12:
                post_upgrade_populate_internal_date_time_t();
            break;
            
            case 13:
                post_upgrade_populate_additional_attachments();
            break;
            
            case 14:
                post_upgrade_expand_page_size();
            break;
            
            case 15:
                post_upgrade_fix_localized_internaldates();
            break;
            
            case 18:
                post_upgrade_populate_internal_date_time_t();
            break;
            
            case 19:
                post_upgrade_validate_contacts();
            break;
            
            case 22:
                post_upgrade_rebuild_attachments();
            break;
            
            case 23:
                post_upgrade_add_tokenizer_table();
            break;
        }
    }
    
    // Version 5.
    private void post_upgrade_populate_autocomplete() {
        try {
            Db.Result result = query("SELECT sender, from_field, to_field, cc, bcc FROM MessageTable");
            while (!result.finished) {
                MessageAddresses message_addresses =
                    new MessageAddresses.from_result(account_owner_email, result);
                foreach (Contact contact in message_addresses.contacts) {
                    do_update_contact(get_master_connection(), contact, null);
                }
                
                result.next();
            }
        } catch (Error err) {
            debug("Error populating autocompletion table during upgrade to database schema 5");
        }
    }
    
    // Version 6.
    private void post_upgrade_encode_folder_names() {
        try {
            Db.Result select = query("SELECT id, name FROM FolderTable");
            while (!select.finished) {
                int64 id = select.int64_at(0);
                string encoded_name = select.nonnull_string_at(1);
                
                try {
                    string canonical_name = Geary.ImapUtf7.imap_utf7_to_utf8(encoded_name);
                    
                    Db.Statement update = prepare("UPDATE FolderTable SET name=? WHERE id=?");
                    update.bind_string(0, canonical_name);
                    update.bind_int64(1, id);
                    update.exec();
                } catch (Error e) {
                    debug("Error renaming folder %s to its canonical representation: %s", encoded_name, e.message);
                }
                
                select.next();
            }
        } catch (Error e) {
            debug("Error decoding folder names during upgrade to database schema 6: %s", e.message);
        }
    }
    
    // Version 11.
    private void post_upgrade_add_search_table() {
        try {
            string stemmer = find_appropriate_search_stemmer();
            debug("Creating search table using %s stemmer", stemmer);
            
            // This can't go in the .sql file because its schema (the stemmer
            // algorithm) is determined at runtime.
            exec("""
                CREATE VIRTUAL TABLE MessageSearchTable USING fts4(
                    body,
                    attachment,
                    subject,
                    from_field,
                    receivers,
                    cc,
                    bcc,
                    
                    tokenize=unicodesn "stemmer=%s",
                    prefix="2,4,6,8,10",
                );
            """.printf(stemmer));
        } catch (Error e) {
            error("Error creating search table: %s", e.message);
        }
    }
    
    private string find_appropriate_search_stemmer() {
        // Unfortunately, the stemmer library only accepts the full language
        // name for the stemming algorithm.  This translates between the user's
        // preferred language ISO 639-1 code and our available stemmers.
        // FIXME: the available list here is determined by what's included in
        // src/sqlite3-unicodesn/CMakeLists.txt.  We should pass that list in
        // instead of hardcoding it here.
        foreach (string l in Intl.get_language_names()) {
            switch (l) {
                case "da": return "danish";
                case "nl": return "dutch";
                case "en": return "english";
                case "fi": return "finnish";
                case "fr": return "french";
                case "de": return "german";
                case "hu": return "hungarian";
                case "it": return "italian";
                case "no": return "norwegian";
                case "pt": return "portuguese";
                case "ro": return "romanian";
                case "ru": return "russian";
                case "es": return "spanish";
                case "sv": return "swedish";
                case "tr": return "turkish";
            }
        }
        
        // Default to English because it seems to be on average the language
        // most likely to be present in emails, regardless of the user's
        // language setting.  This is not an exact science, and search results
        // should be ok either way in most cases.
        return "english";
    }
    
    // Versions 12 and 18.
    private void post_upgrade_populate_internal_date_time_t() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
                Db.Result select = cx.query("SELECT id, internaldate FROM MessageTable");
                while (!select.finished) {
                    int64 id = select.rowid_at(0);
                    string? internaldate = select.string_at(1);
                    
                    try {
                        time_t as_time_t = (internaldate != null ?
                            Geary.Imap.InternalDate.decode(internaldate).as_time_t : -1);
                        
                        Db.Statement update = cx.prepare(
                            "UPDATE MessageTable SET internaldate_time_t=? WHERE id=?");
                        update.bind_int64(0, (int64) as_time_t);
                        update.bind_rowid(1, id);
                        update.exec();
                    } catch (Error e) {
                        debug("Error converting internaldate '%s' to time_t: %s",
                            internaldate, e.message);
                    }
                    
                    select.next();
                }
                
                return Db.TransactionOutcome.COMMIT;
            });
        } catch (Error e) {
            debug("Error populating internaldate_time_t column during upgrade to database schema 12: %s",
                e.message);
        }
    }
    
    // Version 13.
    private void post_upgrade_populate_additional_attachments() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
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
                        Geary.ImapDB.Folder.do_save_attachments_db(cx, id,
                            message.get_attachments(target_disposition), this, null);
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
            });
        } catch (Error e) {
            debug("Error populating old inline attachments during upgrade to database schema 13: %s",
                e.message);
        }
    }
    
    // Version 14.
    private void post_upgrade_expand_page_size() {
        try {
            // When the MessageSearchTable is first touched, SQLite seems to
            // read the whole table into memory (or an awful lot of data,
            // either way).  This was causing slowness when Geary first started
            // and checked for any messages not yet in the search table.  With
            // the database's page_size set to 4096, the reads seem to happen
            // about 2 orders of magnitude quicker, probably because 4096
            // matches the default filesystem block size and/or Linux's default
            // memory page size.  With this set, the full read into memory is
            // barely noticeable even on slow machines.
            
            // NOTE: these can't be in the .sql file itself because they must
            // be back to back, outside of a transaction.
            exec("""
                PRAGMA page_size = 4096;
                VACUUM;
            """);
        } catch (Error e) {
            debug("Error bumping page_size or vacuuming database; performance may be degraded: %s",
                e.message);
        }
    }
    
    // Version 15
    private void post_upgrade_fix_localized_internaldates() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
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
                            invalid_id.to_string(), db_file.get_path(), err.message);
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
                    
                    // reuse statment, overwrite invalid_id, fields only
                    stmt.reset(Db.ResetScope.SAVE_BINDINGS);
                }
                
                return Db.TransactionOutcome.COMMIT;
            });
        } catch (Error err) {
            debug("Error fixing INTERNALDATES during upgrade to schema 15 for %s: %s",
                db_file.get_path(), err.message);
        }
    }
    
    // Version 19.
    private void post_upgrade_validate_contacts() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
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
            });
        } catch (Error e) {
            debug("Error fixing up contacts table: %s", e.message);
        }
    }
    
    // Version 22
    private void post_upgrade_rebuild_attachments() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
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
                    Gee.List<GMime.Part> msg_attachments = message.get_attachments();
                    
                    // delete all attachments for this message
                    try {
                        Geary.ImapDB.Folder.do_delete_attachments(cx, message_id);
                    } catch (Error err) {
                        debug("Error deleting existing attachments: %s", err.message);
                        
                        continue;
                    }
                    
                    // rebuild all
                    try {
                        Geary.ImapDB.Folder.do_save_attachments_db(cx, message_id, msg_attachments,
                            this, null);
                    } catch (Error err) {
                        debug("Error saving attachments: %s", err.message);
                        
                        // fallthrough
                    }
                } while (results.next());
                
                // rebuild search table due to potentially new attachments
                cx.exec("DELETE FROM MessageSearchTable");
                
                return Db.TransactionOutcome.COMMIT;
            });
        } catch (Error e) {
            debug("Error populating old inline attachments during upgrade to database schema 13: %s",
                e.message);
        }
    }
    
    // Version 23
    private void post_upgrade_add_tokenizer_table() {
        try {
            string stemmer = find_appropriate_search_stemmer();
            debug("Creating tokenizer table using %s stemmer", stemmer);
            
            // These can't go in the .sql file because its schema (the stemmer
            // algorithm) is determined at runtime.
            exec("""
                CREATE VIRTUAL TABLE TokenizerTable USING fts3tokenize(
                    unicodesn,
                    "stemmer=%s"
                );
            """.printf(stemmer));
        } catch (Error e) {
            error("Error creating tokenizer table: %s", e.message);
        }
    }
    
    private void on_prepare_database_connection(Db.Connection cx) throws Error {
        cx.set_busy_timeout_msec(Db.Connection.RECOMMENDED_BUSY_TIMEOUT_MSEC);
        cx.set_foreign_keys(true);
        cx.set_recursive_triggers(true);
        cx.set_synchronous(Db.SynchronousMode.NORMAL);
        sqlite3_unicodesn_register_tokenizer(cx.db);
    }
}

