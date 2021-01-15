/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A primary connection to the database.
 */
public class Geary.Db.DatabaseConnection : Context, Connection {


    /**
     * Default value is for the connection's busy timeout.
     *
     * By default, SQLite will not retry BUSY results.
     *
     * @see busy_timeout
     */
    public const int DEFAULT_BUSY_TIMEOUT_MSEC = 0;

    /**
     * Recommended value is for the connection's busy timeout.
     *
     * This value gives a generous amount of time for SQLite to finish
     * a big write operation and relinquish the lock to other waiting
     * transactions.
     *
     * @see busy_timeout
     */
    public const int RECOMMENDED_BUSY_TIMEOUT_MSEC = 60 * 1000;


    // This is used for logging purposes only; connection numbers mean
    // nothing to SQLite
    private static uint next_cx_number = 0;


    /**
     * The busy timeout for this connection.
     *
     * A non-zero, positive value indicates that all operations that
     * SQLite returns BUSY will be retried until they complete with
     * success or error. Only after the given amount of time has
     * transpired will a {@link DatabaseError.BUSY} will be thrown. If
     * zero or negative, a {@link DatabaseError.BUSY} will be
     * immediately if the database is already locked when a new lock
     * is required.
     *
     * Setting a positive value imperative for transactions, otherwise
     * those calls will throw a {@link DatabaseError.BUSY} error
     * immediately if another transaction has acquired the reserved or
     * exclusive locks.
     *
     * @see DEFAULT_BUSY_TIMEOUT_MSEC
     * @see RECOMMENDED_BUSY_TIMEOUT_MSEC
     * @see set_busy_timeout_msec
     */
    public int busy_timeout {
        get; private set; default = DEFAULT_BUSY_TIMEOUT_MSEC;
    }

    /** {@inheritDoc} */
    public Database database { get { return this._database; } }
    private weak Database _database;

    /** {@inheritDoc} */
    public override Logging.Source? logging_parent {
        get { return this._database; }
    }

    /** {@inheritDoc} */
    internal Sqlite.Database db { get { return this._db; } }
    private Sqlite.Database _db;

    private uint cx_number;


    internal DatabaseConnection(Database database,
                                int sqlite_flags,
                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        this._database = database;

        lock (next_cx_number) {
            this.cx_number = next_cx_number++;
        }

        check_cancelled("Connection.ctor", cancellable);

        try {
            throw_on_error(
                "Connection.ctor",
                Sqlite.Database.open_v2(
                    database.path, out this._db, sqlite_flags, null
                )
            );
        } catch (DatabaseError derr) {
            // don't throw BUSY error for open unless no db object was returned, as it's possible for
            // open_v2() to return an error *and* a valid Database object, see:
            // http://www.sqlite.org/c3ref/open.html
            if (!(derr is DatabaseError.BUSY) || (db == null))
                throw derr;
        }
    }

    /**
     * Sets the connection's busy timeout in milliseconds.
     *
     * @see busy_timeout
     */
    public void set_busy_timeout_msec(int timeout_msec) throws GLib.Error {
        if (this.busy_timeout != timeout_msec) {
            throw_on_error(
                "Database.set_busy_timeout",
                this.db.busy_timeout(timeout_msec)
            );
            this.busy_timeout = timeout_msec;
        }
    }

    /** {@inheritDoc} */
    public Statement prepare(string sql) throws DatabaseError {
        return new Statement(this, sql);
    }

    /** {@inheritDoc} */
    public Result query(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return prepare(sql).exec(cancellable);
    }

    /** {@inheritDoc} */
    public void exec(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_cancelled("Connection.exec", cancellable);
        if (Db.Context.enable_sql_logging) {
            debug(sql);
        }
        var timer = new GLib.Timer();
        throw_on_error("Connection.exec_file", this.db.exec(sql), sql);
        check_elapsed("Query \"%s\"".printf(sql), timer);
    }

    /** {@inheritDoc} */
    public void exec_file(GLib.File file, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_cancelled("Connection.exec_file", cancellable);
        if (Db.Context.enable_sql_logging) {
            debug(file.get_path());
        }

        string sql;
        FileUtils.get_contents(file.get_path(), out sql);
        var timer = new GLib.Timer();
        throw_on_error("Connection.exec_file", this.db.exec(sql), sql);
        check_elapsed(file.get_path(), timer);
    }

    /**
     * Executes a transaction using this connection.
     *
     * Executes one or more queries inside an SQLite transaction.
     * This call will initiate a transaction according to the
     * TransactionType specified (although this is merely an
     * optimization -- no matter the transaction type, SQLite
     * guarantees the subsequent operations to be atomic).  The
     * commands executed inside the TransactionMethod against the
     * supplied Db.Connection will be in the context of the
     * transaction.  If the TransactionMethod returns
     * TransactionOutcome.COMMIT, the transaction will be committed to
     * the database, otherwise it will be rolled back and the database
     * left unchanged.
     *
     * See [[http://www.sqlite.org/lang_transaction.html]]
     */
    public TransactionOutcome exec_transaction(TransactionType type,
                                               TransactionMethod cb,
                                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        var txn_cx = new TransactionConnection(this);

        // initiate the transaction
        try {
            txn_cx.exec(type.sql(), cancellable);
        } catch (GLib.Error err) {
            if (!(err is GLib.IOError.CANCELLED))
                debug("Connection.exec_transaction: unable to %s: %s", type.sql(), err.message);

            throw err;
        }

        // If transaction throws an Error, must rollback, always
        TransactionOutcome outcome = TransactionOutcome.ROLLBACK;
        Error? caught_err = null;
        try {
            // perform the transaction
            outcome = cb(txn_cx, cancellable);
        } catch (GLib.Error err) {
            if (!(err is GLib.IOError.CANCELLED)) {
                debug("Connection.exec_transaction: transaction threw error: %s", err.message);
                // XXX txn logs really should be passed up with the
                // error, or made available after the transaction, but
                // neither GLib's error model nor Db's model allows
                // that
                foreach (var statement in txn_cx.transaction_log) {
                    debug(" - %s", statement);
                }
            }

            caught_err = err;
        }

        // commit/rollback ... don't use  GLib.Cancellable for
        // TransactionOutcome because it's SQL *must* execute in order
        // to unlock the database
        try {
            txn_cx.exec(outcome.sql());
        } catch (GLib.Error err) {
            debug("Connection.exec_transaction: Unable to %s transaction: %s", outcome.to_string(),
                err.message);
            if (caught_err == null) {
                // XXX as per above, txn logs really should be passed up
                // with the error, or made available after the
                // transaction, but neither GLib's error model nor Db's
                // model allows that
                foreach (var statement in txn_cx.transaction_log) {
                    debug(" - %s", statement);
                }
            }
        }

        if (caught_err != null) {
            throw caught_err;
        }

        return outcome;
    }

    /**
     * Executes an asynchronous transaction using this connection.
     *
     * Asynchronous transactions are handled via background
     * threads. The background thread calls {@link exec_transaction};
     * see that method for more information about coding a
     * transaction. The only caveat is that the {@link
     * TransactionMethod} passed to it must be thread-safe.
     *
     * Throws {@link DatabaseError.OPEN_REQUIRED} if not open.
     */
    public async TransactionOutcome exec_transaction_async(TransactionType type,
                                                           TransactionMethod cb,
                                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        // create job to execute in background thread
        TransactionAsyncJob job = new TransactionAsyncJob(
            this, type, cb, cancellable
        );

        this.database.add_async_job(job);
        return yield job.wait_for_completion_async();
    }

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(this, "%u", this.cx_number);
    }

    internal override DatabaseConnection? get_connection() {
        return this;
    }

}
