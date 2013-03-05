/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Geary.Db is a simple wrapper around SQLite to make it more GObject-ish and easier to code in
 * Vala.  It also uses threads and some concurrency features of SQLite to allow for asynchronous
 * access to the database.
 *
 * There is no attempt here to hide or genericize the backing database library; this is designed with
 * SQLite in mind.  As such, many of the calls are merely direct front-ends to the underlying
 * SQLite call.
 *
 * The design of the classes and interfaces owes a debt to SQLHeavy (http://code.google.com/p/sqlheavy/).
 */

namespace Geary.Db {

public const int64 INVALID_ROWID = -1;

private const int MAX_RETRY_SLEEP_MSEC = 1000;
private const int RETRY_SLEEP_INC_MSEC = 50;

[Flags]
public enum DatabaseFlags {
    NONE = 0,
    CREATE_DIRECTORY,
    CREATE_FILE,
    READ_ONLY
}

public enum ResetScope {
    SAVE_BINDINGS,
    CLEAR_BINDINGS
}

/*
 * PrepareConnection is called from Database when a Connection is created.  Database may pool
 * Connections, especially for asynchronous queries, so this is only called when a new
 * Connection is created and not when its reused.
 *
 * PrepareConnection may be used as an opportunity to modify or configure the Connection.
 * This callback is called prior to the Connection being used, either internally or handed off to
 * a caller for normal use.
 *
 * This callback may be called in the context of a background thread.
 */
public delegate void PrepareConnection(Connection cx, bool master) throws Error;

/**
 * See Connection.exec_transaction() for more information on how this delegate is used.
 */
public delegate TransactionOutcome TransactionMethod(Connection cx, Cancellable? cancellable) throws Error;

// Used by exec_retry_locked().
private delegate int SqliteExecOperation();

/**
 * See http://www.sqlite.org/c3ref/threadsafe.html
 */
public bool threadsafe() {
    return Sqlite.threadsafe() != 0;
}

/**
 * See http://www.sqlite.org/c3ref/libversion.html
 */
public unowned string sqlite_version() {
    return Sqlite.libversion();
}

/**
 * See http://www.sqlite.org/c3ref/libversion.html
 */
public int sqlite_version_number() {
    return Sqlite.libversion_number();
}

private void check_cancelled(string? method, Cancellable? cancellable) throws IOError {
    if (cancellable != null && cancellable.is_cancelled())
        throw new IOError.CANCELLED("%s cancelled", !String.is_empty(method) ? method : "Operation");
}

// This method is useful for dealing with BUSY retries in a consistent manner.
private int exec_retry_locked(Context ctx, string? method, SqliteExecOperation op, string? raw = null)
    throws Error {
    int count = 0;
    int sleep_msec = RETRY_SLEEP_INC_MSEC;
    int total_msec = 0;
    int max_retry_msec = ctx.get_max_retry_msec();
    for (;;) {
        try {
            return throw_on_error(ctx, method, op(), raw);
        } catch (DatabaseError derr) {
            // if not BUSY, then immediately throw
            if (!(derr is DatabaseError.BUSY))
                throw derr;
            
            // if BUSY and total time has elapsed, throw
            if ((max_retry_msec > 0) && (total_msec >= max_retry_msec))
                throw derr;
        }
        
        // sleep and retry
        Thread.usleep(sleep_msec * 1000);
        
        total_msec += sleep_msec;
        sleep_msec = Numeric.int_ceiling(sleep_msec + RETRY_SLEEP_INC_MSEC, MAX_RETRY_SLEEP_MSEC);
        
        debug("%s retrying: [%d] %s", method, ++count, (raw != null) ? raw : "");
    }
}

// Returns result if exception is not thrown
private int throw_on_error(Context ctx, string? method, int result, string? raw = null) throws DatabaseError {
    // fast-fail
    switch (result) {
        case Sqlite.OK:
        case Sqlite.DONE:
        case Sqlite.ROW:
            return result;
    }
    
    string location = !String.is_empty(method) ? "(%s) ".printf(method) : "";
    string errmsg = (ctx.get_connection() != null) ? " - %s".printf(ctx.get_connection().db.errmsg()) : "";
    string sql;
    if (ctx.get_statement() != null)
        sql = " (%s)".printf(ctx.get_statement().sql);
    else if (!String.is_empty(raw))
        sql = " (%s)".printf(raw);
    else
        sql = "";
    
    string msg = "%s[err=%d]%s%s".printf(location, result, errmsg, sql);
    
    switch (result) {
        case Sqlite.BUSY:
            throw new DatabaseError.BUSY(msg);
        
        case Sqlite.PERM:
        case Sqlite.READONLY:
        case Sqlite.IOERR:
        case Sqlite.CORRUPT:
        case Sqlite.CANTOPEN:
        case Sqlite.NOLFS:
        case Sqlite.AUTH:
        case Sqlite.FORMAT:
        case Sqlite.NOTADB:
            throw new DatabaseError.BACKING(msg);
        
        case Sqlite.NOMEM:
            throw new DatabaseError.MEMORY(msg);
        
        case Sqlite.ABORT:
        case Sqlite.LOCKED:
            throw new DatabaseError.ABORT(msg);
        
        case Sqlite.INTERRUPT:
            throw new DatabaseError.INTERRUPT(msg);
        
        case Sqlite.FULL:
        case Sqlite.EMPTY:
        case Sqlite.TOOBIG:
        case Sqlite.CONSTRAINT:
        case Sqlite.RANGE:
            throw new DatabaseError.LIMITS(msg);
        
        case Sqlite.SCHEMA:
        case Sqlite.MISMATCH:
            throw new DatabaseError.TYPESPEC(msg);
        
        case Sqlite.ERROR:
        case Sqlite.INTERNAL:
        case Sqlite.MISUSE:
        default:
            throw new DatabaseError.GENERAL(msg);
    }
}

}

