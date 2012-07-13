/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapDB.Database : Geary.Db.VersionedDatabase {
    private const string DB_FILENAME = "geary.db";
    private const int BUSY_TIMEOUT_MSEC = 1000;
    
    public Database(File db_dir, File schema_dir) {
        base (db_dir.get_child(DB_FILENAME), schema_dir);
    }
    
    public override void open(Db.DatabaseFlags flags, Db.PrepareConnection? prepare_cb,
        Cancellable? cancellable = null) throws Error {
        // have to do it this way because delegates don't play well with the ternary or nullable
        // operators
        if (prepare_cb != null)
            base.open(flags, prepare_cb, cancellable);
        else
            base.open(flags, on_prepare_database_connection, cancellable);
    }
    
    private void on_prepare_database_connection(Db.Connection cx) throws Error {
        cx.set_busy_timeout_msec(BUSY_TIMEOUT_MSEC);
        cx.set_foreign_keys(true);
        cx.set_recursive_triggers(true);
        cx.set_synchronous(Db.SynchronousMode.OFF);
    }
}

