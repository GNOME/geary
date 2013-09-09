/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Db.VersionedDatabase : Geary.Db.Database {
    public File schema_dir { get; private set; }
    public ProgressMonitor upgrade_monitor { get; private set; }
    
    public VersionedDatabase(File db_file, File schema_dir, ProgressMonitor upgrade_monitor) {
        base (db_file);
        
        this.schema_dir = schema_dir;
        this.upgrade_monitor = upgrade_monitor;
    }
    
    protected virtual void pre_upgrade(int version) {
    }

    protected virtual void post_upgrade(int version) {
    }
    
    private File get_schema_file(int db_version) {
        return schema_dir.get_child("version-%03d.sql".printf(db_version));
    }
    
    /**
     * Creates or opens the database, initializing and upgrading the schema.
     *
     * If it's detected that the database has a schema version that's unavailable in the schema
     * directory, throws {@link DatabaseError.SCHEMA_VERSION}.  Generally this indicates the
     * user attempted to load the database with an older version of the application.
     */
    public override void open(DatabaseFlags flags, PrepareConnection? prepare_cb,
        Cancellable? cancellable = null) throws Error {
        base.open(flags, prepare_cb, cancellable);
        
        // get Connection for upgrade activity
        Connection cx = open_connection(cancellable);
        
        int db_version = cx.get_user_version_number();
        debug("VersionedDatabase.upgrade: current database schema for %s: %d", db_file.get_path(),
            db_version);
        
        // Initialize new database to version 1 (note the preincrement in the loop below)
        if (db_version < 0)
            db_version = 0;
        
        // Check for database schemas newer than what's available in the schema directory; this
        // happens some times in development or if a user attempts to roll back their version
        // of the app without restoring a backup of the database ... since schema is so important
        // to database coherency, need to protect against both
        //
        // Note that this is checking for a schema file for the current version of the database
        // (assuming it's version 1 or better); the next check autoincrements to look for the
        // *next* version of the database
        if (db_version > 0 && !get_schema_file(db_version).query_exists(cancellable)) {
            throw new DatabaseError.SCHEMA_VERSION("%s schema %d unknown to current schema plan",
                db_file.get_path(), db_version);
        }
        
        // Go through all the version scripts in the schema directory and apply each of them.
        for (;;) {
            File upgrade_script = get_schema_file(++db_version);
            if (!upgrade_script.query_exists(cancellable))
                break;
            
            if (!upgrade_monitor.is_in_progress)
                upgrade_monitor.notify_start();
            
            pump_event_loop();
            
            pre_upgrade(db_version);
            
            check_cancelled("VersionedDatabase.open", cancellable);
            
            try {
                debug("Upgrading database to version %d with %s", db_version, upgrade_script.get_path());
                cx.exec_transaction(TransactionType.EXCLUSIVE, (cx) => {
                    cx.exec_file(upgrade_script, cancellable);
                    cx.set_user_version_number(db_version);
                    
                    return TransactionOutcome.COMMIT;
                }, cancellable);
            } catch (Error err) {
                warning("Error upgrading database to version %d: %s", db_version, err.message);
                
                throw err;
            }
            
            pump_event_loop();
            
            post_upgrade(db_version);
        }
        
        if (upgrade_monitor.is_in_progress)
            upgrade_monitor.notify_finish();
    }
    
    protected void pump_event_loop() {
        while (Gtk.events_pending())
            Gtk.main_iteration();
    }
}

