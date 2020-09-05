/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Context allows for an inspector or utility function to determine at runtime what Geary.Db
 * objects are available to it.  Primarily designed for logging, but could be used in other
 * circumstances.
 *
 * Geary.Db's major classes (Database, Connection, Statement, and Result) inherit from Context.
 */
public abstract class Geary.Db.Context : BaseObject, Logging.Source {


    /**
     * Determines if SQL queries and results will be logged.
     *
     * This will cause extremely verbose logging, so enable with care.
     */
    public static bool enable_sql_logging = false;


    /** The GLib logging domain used by this class. */
    public const string LOGGING_DOMAIN = Logging.DOMAIN + ".Db";

    /** {@inheritDoc} */
    public string logging_domain {
        get { return LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;


    internal virtual Database? get_database() {
        return get_connection() != null ? get_connection().database : null;
    }

    internal virtual DatabaseConnection? get_connection() {
        return get_statement() != null ? get_statement().connection : null;
    }

    internal virtual Statement? get_statement() {
        return get_result() != null ? get_result().statement : null;
    }

    internal virtual Result? get_result() {
        return null;
    }

    /** {@inheritDoc} */
    public void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    /** {@inheritDoc} */
    public abstract Logging.State to_logging_state();

    protected inline int throw_on_error(string? method, int result, string? raw = null) throws DatabaseError {
        return Db.throw_on_error(this, method, result, raw);
    }

}
