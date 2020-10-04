/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A connection to the database for transactions.
 */
internal class Geary.Db.TransactionConnection : BaseObject, Connection {


    /** {@inheritDoc} */
    public Database database { get { return this.db_cx.database; } }

    /** {@inheritDoc} */
    internal Sqlite.Database db { get { return this.db_cx.db; } }

    internal string[] transaction_log = {};

    private DatabaseConnection db_cx;


    internal TransactionConnection(DatabaseConnection db_cx) {
        this.db_cx = db_cx;
    }

    /** {@inheritDoc} */
    public Statement prepare(string sql) throws DatabaseError {
        this.transaction_log += sql;
        return this.db_cx.prepare(sql);
    }

    /** {@inheritDoc} */
    public Result query(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.transaction_log += sql;
        return this.db_cx.query(sql, cancellable);
    }

    /** {@inheritDoc} */
    public void exec(string sql, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.transaction_log += sql;
        this.db_cx.exec(sql, cancellable);
    }

    /** {@inheritDoc} */
    public void exec_file(GLib.File file, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.transaction_log += file.get_uri();
        this.db_cx.exec_file(file, cancellable);
    }

}
