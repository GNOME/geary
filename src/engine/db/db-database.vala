/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Database represents an SQLite file.  Multiple Connections may be opened to against the
 * Database.
 *
 * Since it's often just more bookkeeping to maintain a single global connection, Database also
 * offers a master connection which may be used to perform queries and transactions.
 *
 * Database also offers asynchronous transactions which work via connection and thread pools.
 *
 * NOTE: In-memory databases are currently unsupported.
 */

public class Geary.Db.Database : Geary.Db.Context {
    // Dealing with BUSY signal is a bear, and so for now concurrency is turned off
    // http://redmine.yorba.org/issues/6460
    public const int DEFAULT_MAX_CONCURRENCY = 1;
    
    public File db_file { get; private set; }
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
    private Gee.LinkedList<Connection>? cx_pool = null;
    private unowned PrepareConnection? prepare_cb = null;
    
    public Database(File db_file) {
        this.db_file = db_file;
    }
    
    ~Database() {
        // Not thrilled about using lock in a dtor
        lock (outstanding_async_jobs) {
            assert(outstanding_async_jobs == 0);
        }
    }
    
    /**
     * Opens the Database, creating any files and directories it may need in the process depending
     * on the DatabaseFlags.
     *
     * NOTE: A Database may be closed, but the Connections it creates will always be valid as
     * they hold a reference to their source Database.  To release a Database's resources, drop all
     * references to it and its associated Connections, Statements, and Results.
     */
    public virtual void open(DatabaseFlags flags, PrepareConnection? prepare_cb,
        Cancellable? cancellable = null) throws Error {
        if (is_open)
            return;
        
        this.flags = flags;
        this.prepare_cb = prepare_cb;
        
        if ((flags & DatabaseFlags.CREATE_DIRECTORY) != 0) {
            File db_dir = db_file.get_parent();
            if (!db_dir.query_exists(cancellable))
                db_dir.make_directory_with_parents(cancellable);
        }
        
        if (threadsafe()) {
            if (thread_pool == null) {
                thread_pool = new ThreadPool<TransactionAsyncJob>.with_owned_data(on_async_job,
                    DEFAULT_MAX_CONCURRENCY, true);
            }
            
            if (cx_pool == null)
                cx_pool = new Gee.LinkedList<Connection>();
        } else {
            warning("SQLite not thread-safe: asynchronous queries will not be available");
        }
        
        if ((flags & DatabaseFlags.CHECK_CORRUPTION) != 0)
            check_for_corruption(flags, cancellable);
        
        is_open = true;
    }
    
    private void check_for_corruption(DatabaseFlags flags, Cancellable? cancellable) throws Error {
        // if the file exists, open a connection and test for corruption by creating a dummy table,
        // adding a row, selecting the row, then dropping the table ... can only do this for
        // read-write databases, however
        //
        // TODO: "PRAGMA integrity_check" would be useful here, but it can take a while to execute.
        // Also can be performed on read-only databases.
        //
        // TODO: Allow the caller to specify the name of the test table, so we're not clobbering
        // theirs (however improbable it is to name a table "CorruptionCheckTable")
        bool exists = db_file.query_exists(cancellable);
        if (exists && (flags & DatabaseFlags.READ_ONLY) == 0) {
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
                throw new DatabaseError.CORRUPT("Possible integrity problem discovered in %s: %s",
                    db_file.get_path(), err.message);
            }
        } else if (!exists && (flags & DatabaseFlags.CREATE_FILE) == 0) {
            // file doesn't exist and no flag to create it ... that's bad too, might as well
            // let them know now
            throw new DatabaseError.CORRUPT("Database file %s not found and no CREATE_FILE flag",
                db_file.get_path());
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
        if (!is_open)
            throw new DatabaseError.OPEN_REQUIRED("Database %s not open", db_file.get_path());
    }
    
    /**
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public Connection open_connection(Cancellable? cancellable = null) throws Error {
        return internal_open_connection(false, cancellable);
    }
    
    private Connection internal_open_connection(bool master, Cancellable? cancellable) throws Error {
        check_open();
        
        int sqlite_flags = (flags & DatabaseFlags.READ_ONLY) != 0 ? Sqlite.OPEN_READONLY
            : Sqlite.OPEN_READWRITE;
        if ((flags & DatabaseFlags.CREATE_FILE) != 0)
            sqlite_flags |= Sqlite.OPEN_CREATE;
        
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
     * Asynchronous transactions are handled via background threads using a pool of Connections.
     * The background thread calls Connection.exec_transaction(); see that method for more
     * information about coding a transaction.  The only caveat is that the TransactionMethod
     * must be thread-safe.
     *
     * Throws DatabaseError.OPEN_REQUIRED if not open.
     */
    public async TransactionOutcome exec_transaction_async(TransactionType type, TransactionMethod cb,
        Cancellable? cancellable) throws Error {
        check_open();
        
        if (thread_pool == null)
            throw new DatabaseError.GENERAL("SQLite thread safety disabled, async operations unallowed");
        
        // create job to execute in background thread
        TransactionAsyncJob job = new TransactionAsyncJob(type, cb, cancellable);
        
        lock (outstanding_async_jobs) {
            outstanding_async_jobs++;
        }
        
        thread_pool.add(job);
        
        return yield job.wait_for_completion_async();
    }
    
    // This method must be thread-safe.
    private void on_async_job(owned TransactionAsyncJob job) {
        // go to connection pool before creating a connection -- *never* use master connection for
        // threaded operations
        Connection? cx = null;
        lock (cx_pool) {
            cx = cx_pool.poll();
        }
        
        Error? open_err = null;
        if (cx == null) {
            try {
                cx = open_connection();
            } catch (Error err) {
                open_err = err;
                debug("Warning: unable to open database connection to %s, cancelling AsyncJob: %s",
                    db_file.get_path(), err.message);
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
        
        lock (cx_pool) {
            cx_pool.offer(cx);
        }
    }
    
    public override Database? get_database() {
        return this;
    }
}

