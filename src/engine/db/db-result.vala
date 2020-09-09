/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Db.Result : Geary.Db.Context {
    public bool finished { get; private set; default = false; }


    /** The statement this result was generated from. */
    public Statement statement { get; private set; }

    /** The current row represented by this result. */
    public uint64 row { get; private set; default = 0; }

    /** {@inheritDoc} */
    public override Logging.Source? logging_parent {
        get { return this.statement; }
    }

    // This results in an automatic first next().
    internal Result(Statement statement, Cancellable? cancellable) throws Error {
        this.statement = statement;
        statement.was_reset.connect(on_query_finished);
        statement.bindings_cleared.connect(on_query_finished);

        next(cancellable);
    }

    ~Result() {
        statement.was_reset.disconnect(on_query_finished);
        statement.bindings_cleared.disconnect(on_query_finished);
    }

    private void on_query_finished() {
        finished = true;
    }

    /**
     * Returns true if results are waiting, false if finished, or throws a DatabaseError.
     */
    public bool next(Cancellable? cancellable = null) throws Error {
        check_cancelled("Result.next", cancellable);

        if (!this.finished) {
            this.row++;
            var timer = new GLib.Timer();
            this.finished = throw_on_error(
                "Result.next", statement.stmt.step(), statement.sql
            ) != Sqlite.ROW;
            check_elapsed("Result.next", timer);
            log_result(this.finished ? "NO ROW" : "ROW");
        }

        return !finished;
    }

    /**
     * column is zero-based.
     */
    public bool is_null_at(int column) throws DatabaseError {
        verify_at(column);

        bool is_null = statement.stmt.column_type(column) == Sqlite.NULL;
        log_result("is_null_at(%d) -> %s", column, is_null.to_string());

        return is_null;
    }

    /**
     * column is zero-based.
     */
    public double double_at(int column) throws DatabaseError {
        verify_at(column);

        double d = statement.stmt.column_double(column);
        log_result("double_at(%d) -> %lf", column, d);

        return d;
    }

    /**
     * column is zero-based.
     */
    public int int_at(int column) throws DatabaseError {
        verify_at(column);

        int i = statement.stmt.column_int(column);
        log_result("int_at(%d) -> %d", column, i);

        return i;
    }

    /**
     * column is zero-based.
     */
    public uint uint_at(int column) throws DatabaseError {
        return (uint) int64_at(column);
    }

    /**
     * column is zero-based.
     */
    public long long_at(int column) throws DatabaseError {
        return (long) int64_at(column);
    }

    /**
     * column is zero-based.
     */
    public int64 int64_at(int column) throws DatabaseError {
        verify_at(column);

        int64 i64 = statement.stmt.column_int64(column);
        log_result("int64_at(%d) -> %s", column, i64.to_string());

        return i64;
    }

    /**
     * Returns the column value as a bool.  The value is treated as an int and converted into a
     * bool: false == 0, true == !0.
     *
     * column is zero-based.
     */
    public bool bool_at(int column) throws DatabaseError {
        return int_at(column) != 0;
    }

    /**
     * column is zero-based.
     *
     * This is merely a front for int64_at().  It's provided to make the caller's code more verbose.
     */
    public int64 rowid_at(int column) throws DatabaseError {
        return int64_at(column);
    }

    /**
     * column is zero-based.
     *
     * Returns a null string if the element is NULL.
     *
     * @see nonnull_string_at
     */
    public unowned string? string_at(int column) throws DatabaseError {
        verify_at(column);

        unowned string? s = statement.stmt.column_text(column);
        log_result("string_at(%d) -> %s", column, (s != null) ? s : "(null)");

        return s;
    }

    /**
     * column is zero-based.
     *
     * Returns an empty string if the element is NULL.
     *
     * @see string_at
     */
    public unowned string nonnull_string_at(int column) throws DatabaseError {
        unowned string? s = string_at(column);

        return (s != null) ? s : "";
    }

    /**
     * column is zero-based.
     */
    public Memory.Buffer string_buffer_at(int column) throws DatabaseError {
        // Memory.StringBuffer is not entirely suited for this, as it can result in extra copies
        // internally ... GrowableBuffer is better for large blocks
        Memory.GrowableBuffer buffer = new Memory.GrowableBuffer();
        buffer.append(nonnull_string_at(column).data);

        return buffer;
    }

    private void verify_at(int column) throws DatabaseError {
        if (finished)
            throw new DatabaseError.FINISHED("Query finished");

        if (column < 0)
            throw new DatabaseError.LIMITS("column %d < 0", column);

        int count = statement.get_column_count();
        if (column >= count)
            throw new DatabaseError.LIMITS("column %d >= %d", column, count);
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public bool is_null_for(string name) throws DatabaseError {
        return is_null_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public double double_for(string name) throws DatabaseError {
        return double_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public int int_for(string name) throws DatabaseError {
        return int_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public uint uint_for(string name) throws DatabaseError {
        return (uint) int64_for(name);
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public long long_for(string name) throws DatabaseError {
        return long_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public int64 int64_for(string name) throws DatabaseError {
        return int64_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     *
     * See bool_at() for information on how the column's value is converted to a bool.
     */
    public bool bool_for(string name) throws DatabaseError {
        return bool_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     *
     * This is merely a front for int64_at().  It's provided to make the caller's code more verbose.
     */
    public int64 rowid_for(string name) throws DatabaseError {
        return int64_for(name);
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     *
     * Returns a null string if the element is NULL.
     *
     * @see nonnull_string_for
     */
    public unowned string? string_for(string name) throws DatabaseError {
        return string_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     *
     * Returns an empty string if the element is NULL.
     *
     * @see string_for
     */
    public unowned string nonnull_string_for(string name) throws DatabaseError {
        return nonnull_string_at(convert_for(name));
    }

    /**
     * name is the name of the column in the result set.  See Statement.get_column_index() for name
     * matching rules.
     */
    public Memory.Buffer string_buffer_for(string name) throws DatabaseError {
        return string_buffer_at(convert_for(name));
    }

    private int convert_for(string name) throws DatabaseError {
        if (finished)
            throw new DatabaseError.FINISHED("Query finished");

        int column = statement.get_column_index(name);
        if (column < 0)
            throw new DatabaseError.LIMITS("column \"%s\" not in result set", name);

        return column;
    }

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%llu, %s",
            this.row,
            this.finished ? "finished" : "!finished"
        );
    }

    internal override Result? get_result() {
        return this;
    }

    [PrintfFormat]
    private inline void log_result(string fmt, ...) {
        if (Db.Context.enable_result_logging) {
            debug(fmt.vprintf(va_list()));
        }
    }

}
