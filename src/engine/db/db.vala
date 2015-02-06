/* Copyright 2012-2015 Yorba Foundation
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

extern int sqlite3_enable_shared_cache(int enabled);

namespace Geary.Db {

public const int64 INVALID_ROWID = -1;

[Flags]
public enum DatabaseFlags {
    NONE = 0,
    CREATE_DIRECTORY,
    CREATE_FILE,
    READ_ONLY,
    CHECK_CORRUPTION
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
 * See [[http://www.sqlite.org/c3ref/threadsafe.html]]
 */
public bool threadsafe() {
    return Sqlite.threadsafe() != 0;
}

/**
 * See [[http://www.sqlite.org/c3ref/libversion.html]]
 */
public unowned string sqlite_version() {
    return Sqlite.libversion();
}

/**
 * See [[http://www.sqlite.org/c3ref/libversion.html]]
 */
public int sqlite_version_number() {
    return Sqlite.libversion_number();
}

/**
 * See [[http://www.sqlite.org/c3ref/enable_shared_cache.html]]
 */
public bool set_shared_cache_mode(bool enabled) {
    return sqlite3_enable_shared_cache(enabled ? 1 : 0) == Sqlite.OK;
}

private void check_cancelled(string? method, Cancellable? cancellable) throws IOError {
    if (cancellable != null && cancellable.is_cancelled())
        throw new IOError.CANCELLED("%s cancelled", !String.is_empty(method) ? method : "Operation");
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
    
    string location = !String.is_empty(method)
        ? "(%s %s) ".printf(method, ctx.get_database().db_file.get_path())
        : "(%s) ".printf(ctx.get_database().db_file.get_path());
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
        case Sqlite.LOCKED:
            throw new DatabaseError.BUSY(msg);
        
        case Sqlite.IOERR:
        case Sqlite.PERM:
        case Sqlite.READONLY:
        case Sqlite.CANTOPEN:
        case Sqlite.NOLFS:
        case Sqlite.AUTH:
            throw new DatabaseError.ACCESS(msg);
        
        case Sqlite.CORRUPT:
        case Sqlite.FORMAT:
        case Sqlite.NOTADB:
            throw new DatabaseError.CORRUPT(msg);
        
        case Sqlite.NOMEM:
            throw new DatabaseError.MEMORY(msg);
        
        case Sqlite.ABORT:
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

