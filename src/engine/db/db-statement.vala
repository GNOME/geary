/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


public class Geary.Db.Statement : Context {


    public string sql { get; private set; }

    /** {@inheritDoc} */
    public override Logging.Source? logging_parent {
        get { return this.connection; }
    }

    internal DatabaseConnection connection { get; private set; }

    internal Sqlite.Statement stmt;

    private Gee.HashMap<string, int>? column_map = null;
    private Gee.HashSet<Memory.Buffer> held_buffers = new Gee.HashSet<Memory.Buffer>();


    /**
     * Fired when the Statement is executed the first time (after creation or after a reset).
     */
    public signal void executed();

    /**
     * Fired when the Statement is reset.
     */
    public signal void was_reset();

    /**
     * Fired when the Statement's bindings are cleared.
     */
    public signal void bindings_cleared();


    internal Statement(DatabaseConnection connection, string sql)
        throws DatabaseError {
        this.connection = connection;
        this.sql = sql;
        throw_on_error(
            "Statement.ctor",
            connection.db.prepare_v2(sql, -1, out stmt, null)
        );
    }

    /** Returns SQL for the statement with bound parameters expanded. */
    public string? get_expanded_sql() {
        // The statement may be null if throw_on_error() in the ctor
        // does actually throw an error
        return (this.stmt != null) ? this.stmt.expanded_sql() : null;
    }

    /**
     * Reset the Statement for reuse, optionally clearing all bindings as well.  If bindings are
     * not cleared, valued bound previously will be maintained.
     *
     * See http://www.sqlite.org/c3ref/reset.html and http://www.sqlite.org/c3ref/clear_bindings.html
     */
    public Statement reset(ResetScope reset_scope) throws DatabaseError {
        if (reset_scope == ResetScope.CLEAR_BINDINGS)
            throw_on_error("Statement.clear_bindings", stmt.clear_bindings());

        throw_on_error("Statement.reset", stmt.reset());

        // fire signals after Statement has been altered -- this prevents reentrancy while the
        // Statement is in a halfway state
        if (reset_scope == ResetScope.CLEAR_BINDINGS)
            bindings_cleared();

        was_reset();

        return this;
    }

    /**
     * Returns the number of columns the Statement will return in a Result.
     */
    public int get_column_count() {
        return stmt.column_count();
    }

    /**
     * Returns the column name for column at the zero-based index.
     *
     * The name may be used with Result.int_for() (and other *_for() variants).
     */
    public unowned string? get_column_name(int index) {
        return stmt.column_name(index);
    }

    /**
     * Returns the zero-based column index matching the column name.  Column names are
     * case-insensitive.
     *
     * Returns -1 if column name is unknown.
     */
    public int get_column_index(string name) {
        // prepare column map only if names requested
        if (column_map == null) {
            column_map = new Gee.HashMap<string, int>(Geary.String.stri_hash, Geary.String.stri_equal);

            int cols = stmt.column_count();
            for (int ctr = 0; ctr < cols; ctr++) {
                string? column_name = stmt.column_name(ctr);
                if (!String.is_empty(column_name))
                    column_map.set(column_name, ctr);
            }
        }

        return column_map.has_key(name) ? column_map.get(name) : -1;
    }

    /**
     * Executes the Statement and returns a Result object.  The Result starts pointing at the first
     * row in the result set.  If empty, Result.finished will be true.
     */
    public Result exec(Cancellable? cancellable = null) throws Error {
        if (Db.Context.enable_sql_logging) {
            debug(this.get_expanded_sql());
        }

        Result results = new Result(this, cancellable);
        executed();

        return results;
    }

    /**
     * Executes the Statement and returns the last inserted rowid.  If this Statement is not
     * an INSERT, it will return the rowid of the last prior INSERT.
     *
     * See Connection.last_insert_rowid.
     */
    public int64 exec_insert(Cancellable? cancellable = null) throws Error {
        if (Db.Context.enable_sql_logging) {
            debug(this.get_expanded_sql());
        }

        new Result(this, cancellable);
        int64 rowid = connection.last_insert_rowid;

        // fire signal after safely retrieving the rowid
        executed();

        return rowid;
    }

    /**
     * Executes the Statement and returns the number of rows modified by the operation.  This
     * Statement should be an INSERT, UPDATE, or DELETE, otherwise this will return the number
     * of modified rows from the last INSERT, UPDATE, or DELETE.
     *
     * See Connection.last_modified_rows.
     */
    public int exec_get_modified(Cancellable? cancellable = null) throws Error {
        if (Db.Context.enable_sql_logging) {
            debug(this.get_expanded_sql());
        }

        new Result(this, cancellable);
        int modified = connection.last_modified_rows;

        // fire signal after safely retrieving the count
        executed();

        return modified;
    }

    /**
     * index is zero-based.
     */
    public Statement bind_double(int index, double d) throws DatabaseError {
        throw_on_error("Statement.bind_double", stmt.bind_double(index + 1, d));

        return this;
    }

    /**
     * index is zero-based.
     */
    public Statement bind_int(int index, int i) throws DatabaseError {
        throw_on_error("Statement.bind_int", stmt.bind_int(index + 1, i));

        return this;
    }

    /**
     * index is zero-based.
     */
    public Statement bind_uint(int index, uint u) throws DatabaseError {
        return bind_int64(index, (int64) u);
    }

    /**
     * index is zero-based.
     */
    public Statement bind_long(int index, long l) throws DatabaseError {
        return bind_int64(index, (int64) l);
    }

    /**
     * index is zero-based.
     */
    public Statement bind_int64(int index, int64 i64) throws DatabaseError {
        throw_on_error("Statement.bind_int64", stmt.bind_int64(index + 1, i64));

        return this;
    }

    /**
     * Binds a bool to the column.  A bool is stored as an integer, false == 0, true == 1.  Note
     * that fetching a bool via Result is more lenient; see Result.bool_at() and Result.bool_from().
     *
     * index is zero-based.
     */
    public Statement bind_bool(int index, bool b) throws DatabaseError {
        return bind_int(index, b ? 1 : 0);
    }

    /**
     * index is zero-based.
     *
     * This will bind the value to the column as an int64 unless it's INVALID_ROWID, in which case
     * the column is bound as NULL.  WARNING: This does *not* work in WHERE clauses. For WHERE, you
     * must use "field IS NULL".
     */
    public Statement bind_rowid(int index, int64 rowid) throws DatabaseError {
        return (rowid != Db.INVALID_ROWID) ? bind_int64(index, rowid) : bind_null(index);
    }

    /**
     * index is zero-based.
     *
     * WARNING: This does *not* work in WHERE clauses. For WHERE, you must use "field IS NULL".
     */
    public Statement bind_null(int index) throws DatabaseError {
        throw_on_error("Statement.bind_null", stmt.bind_null(index + 1));

        return this;
    }

    /**
     * index is zero-based.
     */
    public Statement bind_string(int index, string? s) throws DatabaseError {
        throw_on_error("Statement.bind_string", stmt.bind_text(index + 1, s));

        return this;
    }

    /**
     * Binds the string representation of a {@link Memory.Buffer} to the replacement value
     * in the {@link Statement}.
     *
     * If buffer supports {@link Memory.UnownedStringBuffer}, the unowned string will be used
     * to avoid a memory copy.  However, this means the Statement will hold a reference to the
     * buffer until the Statement is destroyed.
     *
     * index is zero-based.
     */
    public Statement bind_string_buffer(int index, Memory.Buffer? buffer) throws DatabaseError {
        if (buffer == null)
            return bind_string(index, null);

        Memory.UnownedStringBuffer? unowned_buffer = buffer as Memory.UnownedStringBuffer;
        if (unowned_buffer == null) {
            throw_on_error("Statement.bind_string_buffer", stmt.bind_text(index + 1, buffer.to_string()));

            return this;
        }

        // hold on to buffer for lifetime of Statement, SQLite's callback isn't enough for us to
        // selectively unref each Buffer as it's done with it
        held_buffers.add(unowned_buffer);

        // note use of _bind_text, which is for static and other strings with their own memory
        // management
        stmt._bind_text(index + 1, unowned_buffer.to_unowned_string());

        return this;
    }

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(this, this.sql);
    }

    internal override Statement? get_statement() {
        return this;
    }

}
