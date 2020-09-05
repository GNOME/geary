/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A SQLite database with a versioned, upgradeable schema.
 *
 * This class uses the SQLite user version pragma to track the current
 * version of a database, and a set of SQL scripts (one per version)
 * to manage updating from one version to another. When the database
 * is first opened by a call to {@link open}, its current version is
 * checked against the set of available scripts, and each available
 * version script above the current version is applied in
 * order. Derived classes may override the {@link pre_upgrade} and
 * {@link post_upgrade} methods to perform additional work before and
 * after an upgrade script is executed, and {@link starting_upgrade}
 * and {@link completed_upgrade} to be notified of the upgrade process
 * starting and finishing.
 */
public class Geary.Db.VersionedDatabase : Geary.Db.Database {


    private static Geary.Nonblocking.Mutex upgrade_mutex =
        new Geary.Nonblocking.Mutex();


    public File schema_dir { get; private set; }

    /** {@inheritDoc} */
    public VersionedDatabase.persistent(File db_file, File schema_dir) {
        base.persistent(db_file);
        this.schema_dir = schema_dir;
    }

    /** {@inheritDoc} */
    public VersionedDatabase.transient(File schema_dir) {
        base.transient();
        this.schema_dir = schema_dir;
    }

    /** Returns the current schema version number of this database. */
    public int get_schema_version()
        throws GLib.Error {
        return get_primary_connection().get_user_version_number();
    }

    /**
     * Called by {@link open} if a schema upgrade is required and beginning.
     *
     * If new_db is set to true, the database is being created from scratch.
     */
    protected virtual void starting_upgrade(int current_version, bool new_db) {
    }

    /**
     * Called by {@link open} just before performing a schema upgrade step.
     */
    protected virtual async void pre_upgrade(int version, Cancellable? cancellable)
        throws Error {
    }

    /**
     * Called by {@link open} just after performing a schema upgrade step.
     */
    protected virtual async void post_upgrade(int version, Cancellable? cancellable)
        throws Error {
    }

    /**
     * Called by {@link open} if a schema upgrade was required and has now completed.
     */
    protected virtual void completed_upgrade(int final_version) {
    }

    /**
     * Prepares the database for use, initializing and upgrading the schema.
     *
     * If it's detected that the database has a schema version that's
     * unavailable in the schema directory, throws {@link
     * DatabaseError.SCHEMA_VERSION}.  Generally this indicates the
     * user attempted to load the database with an older version of
     * the application.
     */
    public override async void open(DatabaseFlags flags,
                                    GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield base.open(flags, cancellable);

        // get Connection for upgrade activity
        DatabaseConnection cx = yield open_connection(cancellable);

        int db_version = cx.get_user_version_number();
        debug("VersionedDatabase.upgrade: current database schema for %s: %d",
              this.path, db_version);

        // If the DB doesn't exist yet, the version number will be zero, but also treat negative
        // values as new
        bool new_db = db_version <= 0;

        // Initialize new database to version 1 (note the preincrement in the loop below)
        if (db_version < 0)
            db_version = 0;

        if (db_version > 0) {
            // Check for database schemas newer than what's available
            // in the schema directory; this happens some times in
            // development or if a user attempts to roll back their
            // version of the app without restoring a backup of the
            // database ... since schema is so important to database
            // coherency, need to protect against both
            //
            // Note that this is checking for a schema file for the
            // current version of the database (assuming it's version
            // 1 or better); the next check autoincrements to look for
            // the *next* version of the database
            if (!yield exists(get_schema_file(db_version), cancellable)) {
                throw new DatabaseError.SCHEMA_VERSION(
                    "%s schema %d unknown to current schema plan",
                    this.path, db_version
                );
            }
        }

        // Go through all the version scripts in the schema directory and apply each of them.
        bool started = false;
        for (;;) {
            File upgrade_script = get_schema_file(++db_version);
            if (!yield exists(upgrade_script, cancellable)) {
                break;
            }

            if (!started) {
                starting_upgrade(db_version, new_db);
                started = true;
            }

            // Since these upgrades run in a background thread,
            // there's a possibility they can run in parallel.  That
            // leads to Geary absolutely taking over the machine, with
            // potentially several threads all doing heavy database
            // manipulation at once.  So, we wrap this bit in a mutex
            // lock so that only one database is updating at once.  It
            // means overall it might take a bit longer, but it keeps
            // things usable in the meantime.  See
            // <https://bugzilla.gnome.org/show_bug.cgi?id=724475>.
            int token = yield VersionedDatabase.upgrade_mutex.claim_async(
                cancellable
            );

            Error? locked_err = null;
            try {
                yield execute_upgrade(
                    cx, db_version, upgrade_script, cancellable
                );
            } catch (Error err) {
                locked_err = err;
            }

            VersionedDatabase.upgrade_mutex.release(ref token);

            if (locked_err != null) {
                throw locked_err;
            }
        }

        if (started)
            completed_upgrade(db_version);
    }

    private async void execute_upgrade(DatabaseConnection cx,
                                       int db_version,
                                       GLib.File upgrade_script,
                                       Cancellable? cancellable)
        throws Error {
        debug("Upgrading database to version %d with %s",
              db_version, upgrade_script.get_path());

        check_cancelled("VersionedDatabase.open", cancellable);
        try {
            yield pre_upgrade(db_version, cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                warning("Error executing pre-upgrade for version %d: %s",
                        db_version, err.message);
            }
            throw err;
        }

        check_cancelled("VersionedDatabase.open", cancellable);
        try {
            yield cx.exec_transaction_async(TransactionType.EXCLUSIVE, (cx) => {
                    cx.exec_file(upgrade_script, cancellable);
                    cx.set_user_version_number(db_version);

                    return TransactionOutcome.COMMIT;
                }, cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                warning("Error upgrading database to version %d: %s",
                        db_version, err.message);
            }
            throw err;
        }

        check_cancelled("VersionedDatabase.open", cancellable);
        try {
            yield post_upgrade(db_version, cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                warning("Error executing post-upgrade for version %d: %s",
                        db_version, err.message);
            }
            throw err;
        }
    }

    private File get_schema_file(int db_version) {
        return schema_dir.get_child("version-%03d.sql".printf(db_version));
    }

    private async bool exists(GLib.File target, Cancellable? cancellable) {
        bool ret = true;
        try {
            yield target.query_info_async(
                GLib.FileAttribute.STANDARD_TYPE,
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    cancellable
                );
        } catch (Error err) {
            ret = false;
        }
        return ret;
    }

}
