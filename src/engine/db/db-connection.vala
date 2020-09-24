/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Represents a connection to an opened database.
 *
 * Connections are associated with a specific {@link Database}
 * instance. Because SQLite uses a synchronous interface, all calls on
 * a single connection instance are blocking. Use multiple connections
 * for concurrent access to a single database, or use the asynchronous
 * transaction support provided by {@link Database}.
 *
 * A connection will be automatically closed when its last reference
 * is dropped.
 */
public interface Geary.Db.Connection : BaseObject {

    private const string PRAGMA_FOREIGN_KEYS = "foreign_keys";
    private const string PRAGMA_RECURSIVE_TRIGGERS = "recursive_triggers";
    private const string PRAGMA_USER_VERSION = "user_version";
    private const string PRAGMA_SCHEMA_VERSION = "schema_version";
    private const string PRAGMA_SECURE_DELETE = "secure_delete";
    private const string PRAGMA_SYNCHRONOUS = "synchronous";
    private const string PRAGMA_FREELIST_COUNT = "freelist_count";
    private const string PRAGMA_PAGE_COUNT = "page_count";
    private const string PRAGMA_PAGE_SIZE = "page_size";


    /**
     * See [[http://www.sqlite.org/c3ref/last_insert_rowid.html]]
     */
    public int64 last_insert_rowid { get {
        return this.db.last_insert_rowid();
    } }

    /**
     * See [[http://www.sqlite.org/c3ref/changes.html]]
     */
    public int last_modified_rows { get {
        return this.db.changes();
    } }

    /**
     * See [[http://www.sqlite.org/c3ref/total_changes.html]]
     */
    public int total_modified_rows { get {
        return this.db.total_changes();
    } }

    /** The database this connection is associated with. */
    public abstract Database database { get; }

    /** The underlying SQLite database connection. */
    internal abstract Sqlite.Database db { get; }


    /**
     * Returns the result of a PRAGMA as a boolean.  See [[http://www.sqlite.org/pragma.html]]
     *
     * Note that if the PRAGMA does not return a boolean, the results are undefined.  A boolean
     * in SQLite, however, includes 1 and 0, so an integer may be mistaken as a boolean.
     */
    public bool get_pragma_bool(string name) throws GLib.Error {
        string response = query("PRAGMA %s".printf(name)).nonnull_string_at(0);
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
    public void set_pragma_bool(string name, bool b) throws GLib.Error {
        exec("PRAGMA %s=%s".printf(name, b ? "true" : "false"));
    }

    /**
     * Returns the result of a PRAGMA as an integer.  See [[http://www.sqlite.org/pragma.html]]
     *
     * Note that if the PRAGMA does not return an integer, the results are undefined.  Since a
     * boolean in SQLite includes 1 and 0, it's possible for those values to be converted to an
     * integer.
     */
    public int get_pragma_int(string name) throws GLib.Error {
        return query("PRAGMA %s".printf(name)).int_at(0);
    }

    /**
     * Sets an integer PRAGMA value.
     */
    public void set_pragma_int(string name, int d) throws GLib.Error {
        exec("PRAGMA %s=%d".printf(name, d));
    }

    /**
     * Returns the result of a PRAGMA as a 64-bit integer. See [[http://www.sqlite.org/pragma.html]]
     *
     * Note that if the PRAGMA does not return an integer, the results are undefined.  Since a
     * boolean in SQLite includes 1 and 0, it's possible for those values to be converted to an
     * integer.
     */
    public int64 get_pragma_int64(string name) throws GLib.Error {
        return query("PRAGMA %s".printf(name)).int64_at(0);
    }

    /**
     * Sets a 64-bit integer PRAGMA value.
     */
    public void set_pragma_int64(string name, int64 ld) throws GLib.Error {
        exec("PRAGMA %s=%s".printf(name, ld.to_string()));
    }

    /**
     * Returns the result of a PRAGMA as a string.  See [[http://www.sqlite.org/pragma.html]]
     */
    public string get_pragma_string(string name) throws GLib.Error {
        return query("PRAGMA %s".printf(name)).nonnull_string_at(0);
    }

    /**
     * Sets a string PRAGMA value.
     */
    public void set_pragma_string(string name, string str) throws GLib.Error {
        exec("PRAGMA %s=%s".printf(name, str));
    }

    /**
     * Returns the user_version number maintained by SQLite.
     *
     * A new database has a user version number of zero.
     *
     * @see set_user_version_number
     */
    public int get_user_version_number() throws GLib.Error {
        return get_pragma_int(PRAGMA_USER_VERSION);
    }

    /**
     * Sets the user version number, which is a private number maintained by the user.
     * VersionedDatabase uses this to maintain the version number of the database.
     *
     * See [[http://www.sqlite.org/pragma.html#pragma_schema_version]]
     */
    public void set_user_version_number(int version) throws GLib.Error {
        set_pragma_int(PRAGMA_USER_VERSION, version);
    }

    /**
     * Gets the schema version number, which is maintained by SQLite. See
     * [[http://www.sqlite.org/pragma.html#pragma_schema_version]]
     *
     * Since this number is maintained by SQLite, Geary.Db doesn't offer a way to set it.
     */
    public int get_schema_version_number() throws GLib.Error {
        return get_pragma_int(PRAGMA_SCHEMA_VERSION);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_foreign_keys]]
     */
    public void set_foreign_keys(bool enabled) throws GLib.Error {
        set_pragma_bool(PRAGMA_FOREIGN_KEYS, enabled);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_foreign_keys]]
     */
    public bool get_foreign_keys() throws GLib.Error {
        return get_pragma_bool(PRAGMA_FOREIGN_KEYS);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_recursive_triggers]]
     */
    public void set_recursive_triggers(bool enabled) throws GLib.Error {
        set_pragma_bool(PRAGMA_RECURSIVE_TRIGGERS, enabled);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_recursive_triggers]]
     */
    public bool get_recursive_triggers() throws GLib.Error {
        return get_pragma_bool(PRAGMA_RECURSIVE_TRIGGERS);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_secure_delete]]
     */
    public void set_secure_delete(bool enabled) throws GLib.Error {
        set_pragma_bool(PRAGMA_SECURE_DELETE, enabled);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_secure_delete]]
     */
    public bool get_secure_delete() throws GLib.Error {
        return get_pragma_bool(PRAGMA_SECURE_DELETE);
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_synchronous]]
     */
    public void set_synchronous(SynchronousMode mode) throws GLib.Error {
        set_pragma_string(PRAGMA_SYNCHRONOUS, mode.sql());
    }

    /**
     * See [[http://www.sqlite.org/pragma.html#pragma_synchronous]]
     */
    public SynchronousMode get_synchronous() throws GLib.Error {
        return SynchronousMode.parse(get_pragma_string(PRAGMA_SYNCHRONOUS));
    }

    /**
     * See [[https://www.sqlite.org/pragma.html#pragma_freelist_count]]
     */
    public int64 get_free_page_count() throws GLib.Error {
        return get_pragma_int64(PRAGMA_FREELIST_COUNT);
    }

    /**
     * See [[https://www.sqlite.org/pragma.html#pragma_page_count]]
     */
    public int64 get_total_page_count() throws GLib.Error {
        return get_pragma_int64(PRAGMA_PAGE_COUNT);
    }

    /**
     * See [[https://www.sqlite.org/pragma.html#pragma_page_size]]
     */
    public int get_page_size() throws GLib.Error {
        return get_pragma_int(PRAGMA_PAGE_SIZE);
    }

    /**
     * Prepares a single SQL statement for execution.
     *
     * Only a single SQL statement may be included in the string. See
     * [[http://www.sqlite.org/lang.html]] for more information on
     * SQLite's SQL syntax.
     *
     * The given SQL string may contain placeholders for values, which
     * must then be bound with actual values by calls such as {@link
     * Statement.bind_string} prior to executing.
     *
     * SQLite reference: [[http://www.sqlite.org/c3ref/prepare.html]]
     */
    public abstract Statement prepare(string sql)
        throws DatabaseError;

    /**
     * Executes a single SQL statement, returning a result.
     *
     * Only a single SQL statement may be included in the string. See
     * [[http://www.sqlite.org/lang.html]] for more information on
     * SQLite's SQL syntax.
     *
     * @see exec
     */
    public abstract Result query(string sql,
                                 GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Executes or more SQL statements without returning a result.
     *
     * More than one SQL statement may be in the string. See
     * [[http://www.sqlite.org/lang.html]] for more information on
     * SQLite's SQL syntax.
     *
     * There is no way to retrieve a result iterator from this
     * call. If needed, use {@link query} instead.
     *
     * SQLite reference: [[http://www.sqlite.org/c3ref/exec.html]]
     */
    public abstract void exec(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Executes SQL commands from a plain text file.
     *
     * The given file is read into memory and executed via a single
     * call to {@link exec}.
     *
     * There is no way to retrieve a result iterator from this call.
     *
     * @see Connection.exec
     */
    public abstract void exec_file(GLib.File file,
                                   GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
