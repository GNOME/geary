/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents a single SQLite database.
 *
 * This class provides convenience methods to execute queries for
 * applications that do not require concurrent access to the database,
 * and it supports executing and asynchronous transaction using a
 * thread pool, as well as allowing multiple connections to be opened
 * for fully concurrent access.
 */
public class Geary.Db.Database : Context {


    /** The path passed to SQLite to open a transient database. */
    public const string MEMORY_PATH = "file::memory:?cache=shared";

    /** The default number of threaded connections opened. */
    public const int DEFAULT_MAX_CONCURRENCY = 4;

    /**
     * The database's location on the filesystem.
     *
     * If null, this is a transient, in-memory database.
     */
    public File? file { get; private set; }

    /**
     * The path passed to Sqlite when opening the database.
     *
     * This will be the path to the database file on disk for
     * persistent databases, else {@link MEMORY_PATH} for transient
     * databases.
     */
    public string path { get; private set; }

    public DatabaseFlags flags { get; private set; }

    private bool _is_open = false;
    public bool is_open {
        get {
            lock (_is_open) {
                return _is_open;
            }
        }

        private set {
            lock (_is_open) {
                _is_open = value;
            }
        }
    }

    /** {@inheritDoc} */
    public override Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

    private DatabaseConnection? primary = null;
    private int outstanding_async_jobs = 0;
    private ThreadPool<TransactionAsyncJob>? thread_pool = null;

    /**
     * Constructs a new database that is persisted on disk.
     */
    public Database.persistent(File db_file) {
        this.file = db_file;
        this.path = db_file.get_path();
    }

    /**
     * Constructs a new database that is stored in memory only.
     */
    public Database.transient() {
        this.file = null;
        this.path = MEMORY_PATH;
    }

    ~Database() {
        // Not thrilled about long-running tasks in a dtor
        if (this.thread_pool != null) {
            GLib.ThreadPool.free((owned) this.thread_pool, true, true);
        }
    }

    /**
     * Prepares the database for use.
     *
     * This will create any needed files and directories, check the
     * database's integrity, and so on, depending on the flags passed
     * to this method.
     *
     * NOTE: A Database may be closed, but the Connections it creates
     * will always be valid as they hold a reference to their source
     * Database. To release a Database's resources, drop all
     * references to it and its associated Connections, Statements,
     * and Results.
     */
    public virtual async void open(DatabaseFlags flags,
                                   Cancellable? cancellable = null)
        throws Error {
        if (is_open)
            return;

        this.flags = flags;

        if (this.file != null && (flags & DatabaseFlags.CREATE_DIRECTORY) != 0) {
            yield Geary.Files.make_directory_with_parents(this.file.get_parent());
        }

        if (threadsafe()) {
            if (thread_pool == null) {
                thread_pool = new ThreadPool<TransactionAsyncJob>.with_owned_data(on_async_job,
                    DEFAULT_MAX_CONCURRENCY, true);
            }
        } else {
            warning("SQLite not thread-safe: asynchronous queries will not be available");
        }

        if ((flags & DatabaseFlags.CHECK_CORRUPTION) != 0 &&
            this.file != null &&
            yield Geary.Files.query_exists_async(this.file, cancellable)) {
            yield Nonblocking.Concurrent.global.schedule_async(() => {
                    check_for_corruption(flags, cancellable);
                }, cancellable);
        }

        is_open = true;
    }

    private void check_for_corruption(DatabaseFlags flags, Cancellable? cancellable) throws Error {
        // Open a connection and test for corruption by creating a dummy table,
        // adding a row, selecting the row, then dropping the table ... can only do this for
        // read-write databases, however
        //
        // TODO: "PRAGMA integrity_check" would be useful here, but it can take a while to execute.
        // Also can be performed on read-only databases.
        //
        // TODO: Allow the caller to specify the name of the test table, so we're not clobbering
        // theirs (however improbable it is to name a table "CorruptionCheckTable")
        if ((flags & DatabaseFlags.READ_ONLY) == 0) {
            var cx = new DatabaseConnection(
                this, Sqlite.OPEN_READWRITE, cancellable
            );

            try {
                // drop existing test table (in case created in prior failed open)
                cx.exec("DROP TABLE IF EXISTS CorruptionCheckTable");

                // create dummy table with a "subtantial" column
                cx.exec("CREATE TABLE CorruptionCheckTable (text_col TEXT)");

                // insert row
                cx.exec("INSERT INTO CorruptionCheckTable (text_col) VALUES ('xyzzy')");

                // select row
                cx.exec("SELECT * FROM CorruptionCheckTable");

                // drop table
                cx.exec("DROP TABLE CorruptionCheckTable");
            } catch (Error err) {
                throw new DatabaseError.CORRUPT(
                    "Possible integrity problem discovered in %s: %s",
                    this.path,
                    err.message
                );
            }
        }
    }

    /**
     * Closes the database, releasing any resources it may hold.
     *
     * Note that closing a Database does not close or invalidate
     * Connections it has spawned nor does it cancel any scheduled
     * asynchronous jobs pending or in execution.  All Connections,
     * Statements, and Results will be able to communicate with the
     * database.  Only when they are destroyed is the Database object
     * finally destroyed.
     */
    public virtual void close(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;

        // drop the primary connection, which holds a ref back to this object
        this.primary = null;

        // As per the contract above, can't simply drop the thread and connection pools; that would
        // be bad.

        is_open = false;
    }

    private void check_open() throws Error {
        if (!is_open) {
            throw new DatabaseError.OPEN_REQUIRED(
                "Database %s not open", this.path
            );
        }
    }

    /**
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public async DatabaseConnection
        open_connection(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        DatabaseConnection? cx = null;
        yield Nonblocking.Concurrent.global.schedule_async(() => {
                cx = internal_open_connection(false, cancellable);
            }, cancellable);
        return cx;
    }

    private DatabaseConnection internal_open_connection(bool is_primary,
                                                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open();

        int sqlite_flags = (flags & DatabaseFlags.READ_ONLY) != 0
            ? Sqlite.OPEN_READONLY
            : Sqlite.OPEN_READWRITE;

        if ((flags & DatabaseFlags.CREATE_FILE) != 0)
            sqlite_flags |= Sqlite.OPEN_CREATE;

        if (this.file == null) {
            sqlite_flags |= SQLITE_OPEN_URI;
        }

        DatabaseConnection cx = new DatabaseConnection(
            this, sqlite_flags, cancellable
        );
        prepare_connection(cx);
        return cx;
    }

    /**
     * Returns the primary connection for the database.
     *
     * The primary connection is a general-use connection many of the
     * calls in Database (including exec(), exec_file(), query(),
     * prepare(), and exec_transaction()) use to perform their work.
     * It can also be used by the caller if a dedicated Connection is
     * not required.
     *
     * Throws {@link DatabaseError.OPEN_REQUIRED} if not open.
     */
    public DatabaseConnection get_primary_connection() throws GLib.Error {
        if (this.primary == null)
            this.primary = internal_open_connection(true, null);

        return this.primary;
    }

    /**
     * Executes a statement from a string using the primary connection.
     *
     * This is a convenience method for calling {@link
     * Connection.exec} on the connection returned by {@link
     * get_primary_connection}. Throws {@link
     * DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see Connection.exec
     */
    public void exec(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        get_primary_connection().exec(sql, cancellable);
    }

    /**
     * Executes a statement from a file using the primary connection.
     *
     * This is a convenience method for calling {@link
     * Connection.exec_file} on the connection returned by {@link
     * get_primary_connection}. Throws {@link
     * DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see Connection.exec_file
     */
    public void exec_file(File file, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        get_primary_connection().exec_file(file, cancellable);
    }

    /**
     * Prepares a statement from a string using the primary connection.
     *
     * This is a convenience method for calling {@link
     * Connection.prepare} on the connection returned by {@link
     * get_primary_connection}. Throws {@link
     * DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see Connection.prepare
     */
    public Statement prepare(string sql) throws GLib.Error {
        return get_primary_connection().prepare(sql);
    }

    /**
     * Executes a query using the primary connection.
     *
     * This is a convenience method for calling {@link
     * Connection.query} on the connection returned by {@link
     * get_primary_connection}. Throws {@link
     * DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see Connection.query
     */
    public Result query(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return get_primary_connection().query(sql, cancellable);
    }

    /**
     * Executes a transaction using the primary connection.
     *
     * This is a convenience method for calling {@link
     * DatabaseConnection.exec_transaction} on the connection returned
     * by {@link get_primary_connection}. Throws {@link
     * DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see DatabaseConnection.exec_transaction
     */
    public TransactionOutcome exec_transaction(TransactionType type,
                                               TransactionMethod cb,
                                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return get_primary_connection().exec_transaction(type, cb, cancellable);
    }

    /**
     * Starts a new asynchronous transaction using a new connection.
     *
     * Asynchronous transactions are handled via background
     * threads. The background thread opens a new connection, and
     * calls {@link DatabaseConnection.exec_transaction}; see that
     * method for more information about coding a transaction. The
     * only caveat is that the {@link TransactionMethod} passed to it
     * must be thread-safe.
     *
     * Throws {@link DatabaseError.OPEN_REQUIRED} if not open.
     *
     * @see DatabaseConnection.exec_transaction
     */
    public async TransactionOutcome exec_transaction_async(TransactionType type,
                                                           TransactionMethod cb,
                                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        TransactionAsyncJob job = new TransactionAsyncJob(
            null, type, cb, cancellable
        );
        add_async_job(job);
        return yield job.wait_for_completion_async();
    }

    /** Sets the logging parent context object for this database. */
    public void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(
            this, "%s, is_open: %s", this.path, this.is_open.to_string()
        );
    }

    /** Adds the given job to the thread pool. */
    internal void add_async_job(TransactionAsyncJob new_job) throws Error {
        check_open();

        if (this.thread_pool == null) {
            throw new DatabaseError.GENERAL(
                "SQLite thread safety disabled, async operations unallowed"
            );
        }

        lock (this.outstanding_async_jobs) {
            this.outstanding_async_jobs++;
        }

        this.thread_pool.add(new_job);
    }

    internal override Database? get_database() {
        return this;
    }

    /**
     * Hook for subclasses to modify a new SQLite connection before use.
     *
     * This allows sub-classes to configure SQLite on a newly
     * established connections before being used, such as setting
     * pragmas, custom collation functions, and so on,
     */
    protected virtual void prepare_connection(DatabaseConnection cx)
        throws GLib.Error {
        // No-op by default;
    }

    // This method must be thread-safe.
    private void on_async_job(owned TransactionAsyncJob job) {
        // *never* use primary connection for threaded operations
        var cx = job.default_cx;
        GLib.Error? open_err = null;
        if (cx == null) {
            try {
                cx = internal_open_connection(false, job.cancellable);
            } catch (Error err) {
                open_err = err;
                debug("Warning: unable to open database connection to %s, cancelling AsyncJob: %s",
                      this.path, err.message);
            }
        }

        if (cx != null) {
            job.execute(cx);
        } else {
            job.failed(open_err);
        }

        lock (outstanding_async_jobs) {
            assert(outstanding_async_jobs > 0);
            --outstanding_async_jobs;
        }
    }

}
