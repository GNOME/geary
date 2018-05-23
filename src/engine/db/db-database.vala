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
 * Each database supports multiple {@link Connection}s that allow SQL
 * queries to be executed, however if a single connection is required
 * by an app, this class also provides convenience methods to execute
 * queries against a common ''master'' connection.
 *
 * This class offers a number of asynchronous methods, however since
 * SQLite only supports a synchronous API, these are implemented using
 * a pool of background threads. Asynchronous transactions are
 * available via {@link exec_transaction_async}.
 */

public class Geary.Db.Database : Geary.Db.Context {


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

    private Connection? master_connection = null;
    private int outstanding_async_jobs = 0;
    private ThreadPool<TransactionAsyncJob>? thread_pool = null;
    private unowned PrepareConnection? prepare_cb = null;

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
        // Not thrilled about using lock in a dtor
        lock (outstanding_async_jobs) {
            assert(outstanding_async_jobs == 0);
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
                                   PrepareConnection? prepare_cb,
                                   Cancellable? cancellable = null)
        throws Error {
        if (is_open)
            return;

        this.flags = flags;
        this.prepare_cb = prepare_cb;

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
            Connection cx = new Connection(this, Sqlite.OPEN_READWRITE, cancellable);
            
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
     * Closes the Database, releasing any resources it may hold, including the master connection.
     *
     * Note that closing a Database does not close or invalidate Connections it has spawned nor does
     * it cancel any scheduled asynchronous jobs pending or in execution.  All Connections,
     * Statements, and Results will be able to communicate with the database.  Only when they are
     * destroyed is the Database object finally destroyed.
     */
    public virtual void close(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;
        
        // drop the master connection, which holds a ref back to this object
        master_connection = null;
        
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
    public async Connection open_connection(Cancellable? cancellable = null)
        throws Error {
        Connection? cx = null;
        yield Nonblocking.Concurrent.global.schedule_async(() => {
                cx = internal_open_connection(false, cancellable);
            }, cancellable);
        return cx;
    }

    private Connection internal_open_connection(bool master, Cancellable? cancellable) throws Error {
        check_open();

        int sqlite_flags = (flags & DatabaseFlags.READ_ONLY) != 0
            ? Sqlite.OPEN_READONLY
            : Sqlite.OPEN_READWRITE;

        if ((flags & DatabaseFlags.CREATE_FILE) != 0)
            sqlite_flags |= Sqlite.OPEN_CREATE;

        if (this.file == null) {
            sqlite_flags |= SQLITE_OPEN_URI;
        }

        Connection cx = new Connection(this, sqlite_flags, cancellable);
        if (prepare_cb != null)
            prepare_cb(cx, master);
        
        return cx;
    }
    
    /**
     * The master connection is a general-use connection many of the calls in Database (including
     * exec(), exec_file(), query(), prepare(), and exec_trnasaction()) use to perform their work.
     * It can also be used by the caller if a dedicated Connection is not required.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public Connection get_master_connection() throws Error {
        if (master_connection == null)
            master_connection = internal_open_connection(true, null);
        
        return master_connection;
    }
    
    /**
     * Calls Connection.exec() on the master connection.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public void exec(string sql, Cancellable? cancellable = null) throws Error {
        get_master_connection().exec(sql, cancellable);
    }
    
    /**
     * Calls Connection.exec_file() on the master connection.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public void exec_file(File file, Cancellable? cancellable = null) throws Error {
        get_master_connection().exec_file(file, cancellable);
    }
    
    /**
     * Calls Connection.prepare() on the master connection.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public Statement prepare(string sql) throws Error {
        return get_master_connection().prepare(sql);
    }
    
    /**
     * Calls Connection.query() on the master connection.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public Result query(string sql, Cancellable? cancellable = null) throws Error {
        return get_master_connection().query(sql, cancellable);
    }
    
    /**
     * Calls Connection.exec_transaction() on the master connection.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public TransactionOutcome exec_transaction(TransactionType type, TransactionMethod cb,
        Cancellable? cancellable = null) throws Error {
        return get_master_connection().exec_transaction(type, cb, cancellable);
    }

    /**
     * Starts a new asynchronous transaction using a new connection.
     *
     * Asynchronous transactions are handled via background
     * threads. The background thread opens a new connection, and
     * calls {@link Connection.exec_transaction}; see that method for
     * more information about coding a transaction. The only caveat is
     * that the {@link TransactionMethod} passed to it must be
     * thread-safe.
     *
     * Throws {@link DatabaseError.OPEN_REQUIRED} if not open.
     */
    public async TransactionOutcome exec_transaction_async(TransactionType type,
                                                           TransactionMethod cb,
                                                           Cancellable? cancellable)
        throws Error {
        TransactionAsyncJob job = new TransactionAsyncJob(
            null, type, cb, cancellable
        );
        add_async_job(job);
        return yield job.wait_for_completion_async();
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

    // This method must be thread-safe.
    private void on_async_job(owned TransactionAsyncJob job) {
        // *never* use master connection for threaded operations
        Connection? cx = job.cx;
        Error? open_err = null;
        if (cx == null) {
            try {
                cx = internal_open_connection(false, job.cancellable);
            } catch (Error err) {
                open_err = err;
                debug("Warning: unable to open database connection to %s, cancelling AsyncJob: %s",
                      this.path, err.message);
            }
        }

        if (cx != null)
            job.execute(cx);
        else
            job.failed(open_err);
        
        lock (outstanding_async_jobs) {
            assert(outstanding_async_jobs > 0);
            --outstanding_async_jobs;
        }
    }
    
    public override Database? get_database() {
        return this;
    }
}

