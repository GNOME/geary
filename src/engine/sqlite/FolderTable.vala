/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.FolderTable : Geary.Sqlite.Table {
    // This *must* match the column order in the database
    public enum Column {
        ID,
        NAME,
        PARENT_ID
    }
    
    internal FolderTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    private SQLHeavy.Query create_query(SQLHeavy.Queryable? queryable = null) throws SQLHeavy.Error {
        SQLHeavy.Queryable q = queryable ?? db;
        SQLHeavy.Query query = q.prepare(
            "INSERT INTO FolderTable (name, parent_id) VALUES (?, ?)");
        
        return query;
    }
    
    private void create_binding(SQLHeavy.Query query, FolderRow row) throws SQLHeavy.Error {
        query.clear();
        query.bind_string(0, row.name);
        if (row.parent_id != Row.INVALID_ID)
            query.bind_int64(1, row.parent_id);
        else
            query.bind_null(1);
    }
    
    public async void create_async(FolderRow row, Cancellable? cancellable = null) throws Error {
        SQLHeavy.Query query = create_query();
        create_binding(query, row);
        
        yield query.execute_insert_async(cancellable);
    }
    
    public async void create_many_async(Gee.Collection<FolderRow> rows, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = create_query();
        foreach (FolderRow row in rows) {
            create_binding(query, row);
            query.execute_insert();
        }
    }
    
    public async Gee.List<FolderRow> list_async(int64 parent_id, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query;
        if (parent_id != Row.INVALID_ID) {
            query = db.prepare("SELECT * FROM FolderTable WHERE parent_id=?");
            query.bind_int64(0, parent_id);
        } else {
            query = db.prepare("SELECT * FROM FolderTable WHERE parent_id IS NULL");
        }
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        while (!result.finished) {
            rows.add(new FolderRow.from_query_result(this, result));
            
            yield result.next_async(cancellable);
        }
        
        return rows;
    }
    
    public async FolderRow? fetch_async(int64 parent_id, string name, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query;
        if (parent_id != Row.INVALID_ID) {
            query = db.prepare("SELECT * FROM FolderTable WHERE parent_id=? AND name=?");
            query.bind_int64(0, parent_id);
            query.bind_string(1, name);
        } else {
            query = db.prepare("SELECT * FROM FolderTable WHERE name=? AND parent_id IS NULL");
            query.bind_string(0, name);
        }
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        return (!result.finished) ? new FolderRow.from_query_result(this, result) : null;
    }
}

