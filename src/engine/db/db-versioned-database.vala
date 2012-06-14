/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Db.VersionedDatabase : Geary.Db.Database {
    public File schema_dir { get; private set; }
    
    public virtual signal void pre_upgrade(int version) {
    }
    
    public virtual signal void post_upgrade(int version) {
    }
    
    public VersionedDatabase(File db_file, File schema_dir) {
        base (db_file);
        
        this.schema_dir = schema_dir;
    }
    
    protected virtual void notify_pre_upgrade(int version) {
        pre_upgrade(version);
    }
    
    protected virtual void notify_post_upgrade(int version) {
        post_upgrade(version);
    }
    
    // TODO: Initialize database from version-001.sql and upgrade with version-nnn.sql
    public override void open(DatabaseFlags flags, PrepareConnection? prepare_cb,
        Cancellable? cancellable = null) throws Error {
        base.open(flags, prepare_cb, cancellable);
        
        // get Connection for upgrade activity
        Connection cx = open_connection(cancellable);
        
        int db_version = cx.get_user_version_number();
        debug("VersionedDatabase.upgrade: current database version %d", db_version);
        
        // Initialize new database to version 1 (note the preincrement in the loop below)
        if (db_version < 0)
            db_version = 0;
        
        // Go through all the version scripts in the schema directory and apply each of them.
        for (;;) {
            File upgrade_script = schema_dir.get_child("version-%03d.sql".printf(++db_version));
            if (!upgrade_script.query_exists(cancellable))
                break;
            
            notify_pre_upgrade(db_version);
            
            check_cancelled("VersionedDatabase.open", cancellable);
            
            try {
                debug("Upgrading database to to version %d with %s", db_version, upgrade_script.get_path());
                cx.exec_transaction(TransactionType.EXCLUSIVE, (cx) => {
                    cx.exec_file(upgrade_script, cancellable);
                    cx.set_user_version_number(db_version);
                    
                    return TransactionOutcome.COMMIT;
                }, cancellable);
            } catch (Error err) {
                warning("Error upgrading database to version %d: %s", db_version, err.message);
                
                throw err;
            }
            
            notify_post_upgrade(db_version);
        }
    }
}

