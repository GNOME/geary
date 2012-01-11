/* Copyright 2011-2012 Yorba Foundation
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
    
    public async int64 create_async(Transaction? transaction, FolderRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "FolderTable.create_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO FolderTable (name, parent_id) VALUES (?, ?)");
        query.bind_string(0, row.name);
        if (row.parent_id != Row.INVALID_ID)
            query.bind_int64(1, row.parent_id);
        else
            query.bind_null(1);
        
        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
        
        return id;
    }
    
    public async Gee.List<FolderRow> list_async(Transaction? transaction, int64 parent_id, 
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "FolderTable.list_async",
            cancellable);
        
        SQLHeavy.Query query;
        if (parent_id != Row.INVALID_ID) {
            query = locked.prepare("SELECT * FROM FolderTable WHERE parent_id=?");
            query.bind_int64(0, parent_id);
        } else {
            query = locked.prepare("SELECT * FROM FolderTable WHERE parent_id IS NULL");
        }
        
        SQLHeavy.QueryResult result = yield query.execute_async();
        check_cancel(cancellable, "list_async");
        
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        while (!result.finished) {
            rows.add(new FolderRow.from_query_result(this, result));
            
            yield result.next_async();
            check_cancel(cancellable, "list_async");
        }
        
        return rows;
    }
    
    public async FolderRow? fetch_async(Transaction? transaction, int64 parent_id, 
        string name, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "FolderTable.fetch_async",
            cancellable);
        
        SQLHeavy.Query query;
        if (parent_id != Row.INVALID_ID) {
            query = locked.prepare("SELECT * FROM FolderTable WHERE parent_id=? AND name=?");
            query.bind_int64(0, parent_id);
            query.bind_string(1, name);
        } else {
            query = locked.prepare("SELECT * FROM FolderTable WHERE name=? AND parent_id IS NULL");
            query.bind_string(0, name);
        }
        
        SQLHeavy.QueryResult result = yield query.execute_async();
        check_cancel(cancellable, "fetch_async");
        
        return (!result.finished) ? new FolderRow.from_query_result(this, result) : null;
    }
    
    public async FolderRow? fetch_descend_async(Transaction? transaction, 
        Gee.List<string> path, Cancellable? cancellable) throws Error {
        assert(path.size > 0);
        
        Transaction locked = yield obtain_lock_async(transaction, "FolderTable.fetch_descend_async",
            cancellable);
        
        int64 parent_id = Row.INVALID_ID;
        
        // walk the folder tree to the final node (which is at length - 1 - 1)
        int length = path.size;
        for (int ctr = 0; ctr < length - 1; ctr++) {
            SQLHeavy.Query query;
            if (parent_id != Row.INVALID_ID) {
                query = locked.prepare(
                    "SELECT id FROM FolderTable WHERE parent_id=? AND name=?");
                query.bind_int64(0, parent_id);
                query.bind_string(1, path[ctr]);
            } else {
                query = locked.prepare(
                    "SELECT id FROM FolderTable WHERE parent_id IS NULL AND name=?");
                query.bind_string(0, path[ctr]);
            }
            
            SQLHeavy.QueryResult result = yield query.execute_async();
            check_cancel(cancellable, "fetch_descend_async");
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
        return yield fetch_async(locked, parent_id, path.last(), cancellable);
    }
}

