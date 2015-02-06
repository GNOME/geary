/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Db.VersionedDatabase : Geary.Db.Database {
    public delegate void WorkCallback();
    
    private static Mutex upgrade_mutex = new Mutex();
    
    public File schema_dir { get; private set; }
    
    public VersionedDatabase(File db_file, File schema_dir) {
        base (db_file);
        
        this.schema_dir = schema_dir;
    }
    
    /**
     * Called by {@link open} if a schema upgrade is required and beginning.
     *
     * If called by {@link open_background}, this will be called in the context of a background
     * thread.
     *
     * If new_db is set to true, the database is being created from scratch.
     */
    protected virtual void starting_upgrade(int current_version, bool new_db) {
    }
    
    /**
     * Called by {@link open} just before performing a schema upgrade step.
     *
     * If called by {@link open_background}, this will be called in the context of a background
     * thread.
     */
    protected virtual void pre_upgrade(int version) {
    }
    
    /**
     * Called by {@link open} just after performing a schema upgrade step.
     *
     * If called by {@link open_background}, this will be called in the context of a background
     * thread.
     */
    protected virtual void post_upgrade(int version) {
    }
    
    /**
     * Called by {@link open} if a schema upgrade was required and has now completed.
     *
     * If called by {@link open_background}, this will be called in the context of a background
     * thread.
     */
    protected virtual void completed_upgrade(int final_version) {
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
        
        // If the DB doesn't exist yet, the version number will be zero, but also treat negative
        // values as new
        bool new_db = db_version <= 0;
        
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
        bool started = false;
        for (;;) {
            File upgrade_script = get_schema_file(++db_version);
            if (!upgrade_script.query_exists(cancellable))
                break;
            
            if (!started) {
                starting_upgrade(db_version, new_db);
                started = true;
            }
            
            // Since these upgrades run in a background thread, there's a possibility they
            // can run in parallel.  That leads to Geary absolutely taking over the machine,
            // with potentially several threads all doing heavy database manipulation at
            // once.  So, we wrap this bit in a mutex lock so that only one database is
            // updating at once.  It means overall it might take a bit longer, but it keeps
            // things usable in the meantime.  See <https://bugzilla.gnome.org/show_bug.cgi?id=724475>.
            upgrade_mutex.@lock();
            
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
                upgrade_mutex.unlock();
                
                throw err;
            }
            
            post_upgrade(db_version);
            
            upgrade_mutex.unlock();
        }
        
        if (started)
            completed_upgrade(db_version);
    }
    
    /**
     * Opens the database in a background thread so foreground work can be performed while updating.
     *
     * Since {@link open} may take a considerable amount of time for a {@link VersionedDatabase},
     * background_open() can be used to perform that work in a thread while the calling thread
     * "pumps" a {@link WorkCallback} every work_cb_msec milliseconds.  In general, this is
     * designed for allowing an event queue to execute tasks or update a progress monitor of some
     * kind.
     *
     * Note that the database is not opened while the callback is executing and so it should not
     * call into the database (unless it's a call safe to use prior to open).
     *
     * If work_cb_sec is zero or less, WorkCallback is called continuously, which may or may not be
     * desired.
     *
     * @see open
     */
    public void open_background(DatabaseFlags flags, PrepareConnection? prepare_cb,
        WorkCallback work_cb, int work_cb_msec, Cancellable? cancellable = null) throws Error {
        // use a SpinWaiter to safely wait for the thread to exit while occassionally calling the
        // WorkCallback (which can not abort in current impl.) to do foreground work.
        Synchronization.SpinWaiter waiter = new Synchronization.SpinWaiter(work_cb_msec, () => {
            work_cb();
            
            // continue (never abort)
            return true;
        });
        
        // do the open in a background thread
        Error? thread_err = null;
        Thread<bool> thread = new Thread<bool>.try("Geary.Db.VersionedDatabase.open()", () => {
            try {
                open(flags, prepare_cb, cancellable);
            } catch (Error err) {
                thread_err = err;
            }
            
            // notify the foreground waiter we're done
            waiter.notify();
            
            return true;
        });
        
        // wait until thread is completed and then dispose of it
        waiter.wait();
        thread = null;
        
        if (thread_err != null)
            throw thread_err;
    }
}

