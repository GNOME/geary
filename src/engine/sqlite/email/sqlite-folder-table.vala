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
    
    public async int64 create_async(FolderRow row, Cancellable? cancellable = null) throws Error {
        SQLHeavy.Query query = create_query();
        create_binding(query, row);
        
        return yield query.execute_insert_async(cancellable);
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
    
    public async FolderRow? fetch_descend_async(Gee.List<string> path, Cancellable? cancellable = null)
        throws Error {
        assert(path.size > 0);
        
        int64 parent_id = Row.INVALID_ID;
        
        // walk the folder tree to the final node (which is at length - 1 - 1)
        int length = path.size;
        for (int ctr = 0; ctr < length - 1; ctr++) {
            SQLHeavy.Query query;
            if (parent_id != Row.INVALID_ID) {
                query = db.prepare("SELECT id FROM FolderTable WHERE parent_id=? AND name=?");
                query.bind_int64(0, parent_id);
                query.bind_string(1, path[ctr]);
            } else {
                query = db.prepare("SELECT id FROM FolderTable WHERE parent_id IS NULL AND name=?");
                query.bind_string(0, path[ctr]);
            }
            
            SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
            if (result.finished)
                return null;
            
            int64 id = result.fetch_int64(0);
            
            // watch for loops, real bad if it happens ... could be more thorough here, but at least
            // one level of checking is better than none
            if (id == parent_id) {
                warning("Loop found in database: parent of %lld is %lld in FolderTable",
                    parent_id, id);
                
                return null;
            }
            
            parent_id = id;
        }
        
        // do full fetch on this folder
        return yield fetch_async(parent_id, path.last(), cancellable);
    }
}

