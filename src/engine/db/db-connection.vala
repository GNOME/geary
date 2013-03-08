/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * A Connection represents a connection to an open database.  Because SQLite uses a 
 * synchronous interface, all calls are blocking.  Db.Database offers asynchronous queries by
 * pooling connections and invoking queries from background threads.
 *
 * Connections are associated with a Database.  Use Database.open_connection() to create
 * one.
 *
 * A Connection will close when its last reference is dropped.
 */

public class Geary.Db.Connection : Geary.Db.Context {
    /**
     * Default value is for *no* timeout, that is, the Db unit will retry all BUSY results until
     * the database is not locked.
     */
    public const int DEFAULT_BUSY_TIMEOUT_MSEC = 0;
    
    /**
     * This value gives a generous amount of time for SQLite to finish a big write operation and
     * relinquish the lock to other waiting transactions.
     */
    public const int RECOMMENDED_BUSY_TIMEOUT_MSEC = 60 * 1000;
    
    private const string PRAGMA_FOREIGN_KEYS = "foreign_keys";
    private const string PRAGMA_RECURSIVE_TRIGGERS = "recursive_triggers";
    private const string PRAGMA_USER_VERSION = "user_version";
    private const string PRAGMA_SCHEMA_VERSION = "schema_version";
    private const string PRAGMA_SECURE_DELETE = "secure_delete";
    private const string PRAGMA_SYNCHRONOUS = "synchronous";
    
    // this is used for logging purposes only; connection numbers mean nothing to SQLite
    private static int next_cx_number = 0;
    
    /**
     * See http://www.sqlite.org/c3ref/last_insert_rowid.html
     */
    public int64 last_insert_rowid { get {
        return db.last_insert_rowid();
    } }
    
    /**
     * See http://www.sqlite.org/c3ref/changes.html
     */
    public int last_modified_rows { get {
        return db.changes();
    } }
    
    /**
     * See http://www.sqlite.org/c3ref/total_changes.html
     */
    public int total_modified_rows { get {
        return db.total_changes();
    } }
    
    public weak Database database { get; private set; }
    
    internal Sqlite.Database db;
    
    private int cx_number;
    private int busy_timeout_msec = DEFAULT_BUSY_TIMEOUT_MSEC;
    
    internal Connection(Database database, int sqlite_flags, Cancellable? cancellable) throws Error {
        this.database = database;
        
        lock (next_cx_number) {
            cx_number = next_cx_number++;
        }
        
        check_cancelled("Connection.ctor", cancellable);
        
        try {
            throw_on_error("Connection.ctor", Sqlite.Database.open_v2(database.db_file.get_path(),
                out db, sqlite_flags, null));
        } catch (DatabaseError derr) {
            // don't throw BUSY error for open unless no db object was returned, as it's possible for
            // open_v2() to return an error *and* a valid Database object, see:
            // http://www.sqlite.org/c3ref/open.html
            if (!(derr is DatabaseError.BUSY) || (db == null))
                throw derr;
        }
        
        // clear SQLite's busy timeout; this is done manually in the library with exec_retry_locked()
        db.busy_timeout(0);
    }
    
    /**
     * Execute a plain text SQL statement.  More than one SQL statement may be in the string.  See
     * http://www.sqlite.org/lang.html for more information on SQLite's SQL syntax.
     *
     * There is no way to retrieve a result iterator from this call.
     *
     * This may be called from a TransactionMethod called within exec_transaction() or
     * Db.Database.exec_transaction_async().
     *
     * See http://www.sqlite.org/c3ref/exec.html
     */
    public void exec(string sql, Cancellable? cancellable = null) throws Error {
        check_cancelled("Connection.exec", cancellable);
        
        exec_retry_locked(this, "Connection.exec", () => { return db.exec(sql); }, sql);
        
        // Don't use Context.log(), which is designed for logging Results and Statements
        Logging.debug(Logging.Flag.SQL, "exec:\n\t%s", sql);
    }
    
    /**
     * Loads a text file of SQL commands into memory and executes them at once with exec().
     *
     * There is no way to retrieve a result iterator from this call.
     *
     * This can be called from a TransactionMethod called within exec_transaction() or
     * Db.Database.exec_transaction_async().
     */
    public void exec_file(File file, Cancellable? cancellable = null) throws Error {
        check_cancelled("Connection.exec_file", cancellable);
        
        string sql;
        FileUtils.get_contents(file.get_path(), out sql);
        
        exec(sql, cancellable);
    }
    
    /**
     * Executes a plain text SQL statement and returns a Result object directly.
     * This call creates an intermediate Statement object which may be fetched from Result.statement.
     */
    public Result query(string sql, Cancellable? cancellable = null) throws Error {
        return (new Statement(this, sql)).exec(cancellable);
    }
    
    /**
     * Prepares a Statement which may have values bound to it and executed.  See
     * http://www.sqlite.org/c3ref/prepare.html
     */
    public Statement prepare(string sql) throws DatabaseError {
        return new Statement(this, sql);
    }
    
    /**
     * See set_busy_timeout_msec().
     */
    public int get_busy_timeout_msec() {
        return busy_timeout_msec;
    }
    
    /**
     * Sets busy timeout time in milliseconds.  Zero or a negative value indicates that all
     * operations that SQLite returns BUSY will be retried until they complete with success or error.
     * Otherwise, after said amount of time has transpired, DatabaseError.BUSY will be thrown.
     *
     * This is imperative for exec_transaction() and Db.Database.exec_transaction_async(), because
     * those calls will throw a DatabaseError.BUSY call immediately if another transaction has
     * acquired the reserved or exclusive locks.
     */
    public void set_busy_timeout_msec(int busy_timeout_msec) throws Error {
        this.busy_timeout_msec = busy_timeout_msec;
    }
    
    /**
     * Returns the result of a PRAGMA as a boolean.  See http://www.sqlite.org/pragma.html.
     *
     * Note that if the PRAGMA does not return a boolean, the results are undefined.  A boolean
     * in SQLite, however, includes 1 and 0, so an integer may be mistaken as a boolean.
     */
    public bool get_pragma_bool(string name) throws Error {
        string response = query("PRAGMA %s".printf(name)).string_at(0);
        switch (response.down()) {
            case "1":
            case "yes":
            case "true":
            case "on":
                return true;
            
            case "0":
            case "no":
            case "false":
            case "off":
                return false;
            
            default:
                debug("Db.Connection.get_pragma_bool: unknown PRAGMA boolean response \"%s\"",
                    response);
                
                return false;
        }
    }
    
    /**
     * Sets a boolean PRAGMA value to either "true" or "false".
     */
    public void set_pragma_bool(string name, bool b) throws Error {
        exec("PRAGMA %s=%s".printf(name, b ? "true" : "false"));
    }
    
    /**
     * Returns the result of a PRAGMA as an integer.  See http://www.sqlite.org/pragma.html
     *
     * Note that if the PRAGMA does not return an integer, the results are undefined.  Since a
     * boolean in SQLite includes 1 and 0, it's possible for those values to be converted to an
     * integer.
     */
    public int get_pragma_int(string name) throws Error {
        return query("PRAGMA %s".printf(name)).int_at(0);
    }
    
    /**
     * Sets an integer PRAGMA value.
     */
    public void set_pragma_int(string name, int d) throws Error {
        exec("PRAGMA %s=%d".printf(name, d));
    }
    
    /**
     * Returns the result of a PRAGMA as a string.  See http://www.sqlite.org/pragma.html
     */
    public string get_pragma_string(string name) throws Error {
        return query("PRAGMA %s".printf(name)).string_at(0);
    }
    
    /**
     * Sets a string PRAGMA value.
     */
    public void set_pragma_string(string name, string str) throws Error {
        exec("PRAGMA %s=%s".printf(name, str));
    }
    
    /**
     * See set_user_version_number().
     */
    public int get_user_version_number() throws Error {
        return get_pragma_int(PRAGMA_USER_VERSION);
    }
    
    /**
     * Sets the user version number, which is a private number maintained by the user.
     * VersionedDatabase uses this to maintain the version number of the database.
     *
     * See http://www.sqlite.org/pragma.html#pragma_schema_version
     */
    public void set_user_version_number(int version) throws Error {
        set_pragma_int(PRAGMA_USER_VERSION, version);
    }
    
    /**
     * Gets the schema version number, which is maintained by SQLite. See
     * http://www.sqlite.org/pragma.html#pragma_schema_version
     *
     * Since this number is maintained by SQLite, Geary.Db doesn't offer a way to set it.
     */
    public int get_schema_version_number() throws Error {
        return get_pragma_int(PRAGMA_SCHEMA_VERSION);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_foreign_keys
     */
    public void set_foreign_keys(bool enabled) throws Error {
        set_pragma_bool(PRAGMA_FOREIGN_KEYS, enabled);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_foreign_keys
     */
    public bool get_foreign_keys() throws Error {
        return get_pragma_bool(PRAGMA_FOREIGN_KEYS);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_recursive_triggers
     */
    public void set_recursive_triggers(bool enabled) throws Error {
        set_pragma_bool(PRAGMA_RECURSIVE_TRIGGERS, enabled);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_recursive_triggers
     */
    public bool get_recursive_triggers() throws Error {
        return get_pragma_bool(PRAGMA_RECURSIVE_TRIGGERS);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_secure_delete
     */
    public void set_secure_delete(bool enabled) throws Error {
        set_pragma_bool(PRAGMA_SECURE_DELETE, enabled);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_secure_delete
     */
    public bool get_secure_delete() throws Error {
        return get_pragma_bool(PRAGMA_SECURE_DELETE);
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_synchronous
     */
    public void set_synchronous(SynchronousMode mode) throws Error {
        set_pragma_string(PRAGMA_SYNCHRONOUS, mode.sql());
    }
    
    /**
     * See http://www.sqlite.org/pragma.html#pragma_synchronous
     */
    public SynchronousMode get_synchronous() throws Error {
        return SynchronousMode.parse(get_pragma_string(PRAGMA_SYNCHRONOUS));
    }
    
    /**
     * Executes one or more queries inside an SQLite transaction.  This call will initiate a
     * transaction according to the TransactionType specified (although this is merely an
     * optimization -- no matter the transaction type, SQLite guarantees the subsequent operations
     * to be atomic).  The commands executed inside the TransactionMethod against the
     * supplied Db.Connection will be in the context of the transaction.  If the TransactionMethod
     * returns TransactionOutcome.COMMIT, the transaction will be committed to the database,
     * otherwise it will be rolled back and the database left unchanged.
     *
     * It's inadvisable to call exec_transaction() inside exec_transaction().  SQLite has a notion
     * of savepoints that allow for nested transactions; they are not currently supported.
     *
     * See http://www.sqlite.org/lang_transaction.html
     */
    public TransactionOutcome exec_transaction(TransactionType type, TransactionMethod cb,
        Cancellable? cancellable = null) throws Error {
        // initiate the transaction
        try {
            exec(type.sql(), cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Connection.exec_transaction: unable to %s: %s", type.sql(), err.message);
            
            throw err;
        }
        
        // If transaction throws an Error, must rollback, always
        TransactionOutcome outcome = TransactionOutcome.ROLLBACK;
        Error? caught_err = null;
        try {
            // perform the transaction
            outcome = cb(this, cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Connection.exec_transaction: transaction threw error: %s", err.message);
            
            caught_err = err;
        }
        
        // commit/rollback ... don't use Cancellable for TransactionOutcome because it's SQL *must*
        // execute in order to unlock the database
        try {
            exec(outcome.sql());
        } catch (Error err) {
            debug("Connection.exec_transaction: Unable to %s transaction: %s", outcome.to_string(),
                err.message);
        }
        
        if (caught_err != null)
            throw caught_err;
        
        return outcome;
    }
    
    public override Connection? get_connection() {
        return this;
    }
    
    public string to_string() {
        return "[%d] %s".printf(cx_number, database.db_file.get_basename());
    }
}

