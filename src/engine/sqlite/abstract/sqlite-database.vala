/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Sqlite.Database {
    internal SQLHeavy.VersionedDatabase db;
    internal File data_dir;
    internal File schema_dir;

    private Gee.HashMap<SQLHeavy.Table, Geary.Sqlite.Table> table_map = new Gee.HashMap<
        SQLHeavy.Table, Geary.Sqlite.Table>();

    public signal void pre_upgrade(int version);

    public signal void post_upgrade(int version);

    public Database(File db_file, File schema_dir) throws Error {
        this.schema_dir = schema_dir;
        data_dir = db_file.get_parent();
        if (!data_dir.query_exists())
            data_dir.make_directory_with_parents();
        
        db = new SQLHeavy.VersionedDatabase(db_file.get_path(), schema_dir.get_path());
        db.foreign_keys = true;
        db.synchronous = SQLHeavy.SynchronousMode.OFF;
    }
    
    protected Geary.Sqlite.Table? get_table(string name, out SQLHeavy.Table heavy_table) {
        try {
            heavy_table = db.get_table(name);
        } catch (SQLHeavy.Error err) {
            error("Unable to load %s: %s", name, err.message);
        }
        
        return table_map.get(heavy_table);
    }
    
    protected Geary.Sqlite.Table add_table(Geary.Sqlite.Table table) {
        table_map.set(table.table, table);
        
        return table;
    }
    
    public async Transaction begin_transaction_async(string name, Cancellable? cancellable) throws Error {
        Transaction t = new Transaction(db, name);
        yield t.begin_async(cancellable);
        
        return t;
    }

    public int upgrade() throws Error {
        // Get the SQLite database version.
        SQLHeavy.QueryResult result = db.execute("PRAGMA user_version;");
        int db_version = result.fetch_int();
        debug("Current db version: %d", db_version);

        // Go through all the version scripts in the schema directory and apply each of them.
        File upgrade_script;
        while ((upgrade_script = get_upgrade_script(++db_version)).query_exists()) {
            pre_upgrade(db_version);
            
            try {
                debug("Upgrading database to to version %d at %s", db_version, upgrade_script.get_path());
                
                db.run_script(upgrade_script.get_path());
                db.run("PRAGMA user_version = %d;".printf(db_version));
            } catch (Error e) {
                // TODO Add rollback of changes here when switching away from SQLHeavy.
                warning("Error upgrading database: %s", e.message);
                throw e;
            }
            
            post_upgrade(db_version);
        }
        
        return db.execute("PRAGMA user_version;").fetch_int();
    }

    private File get_upgrade_script(int version) {
        return schema_dir.get_child("Version-%03d.sql".printf(version));
    }
}

