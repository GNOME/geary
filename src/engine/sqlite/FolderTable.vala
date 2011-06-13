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
        SUPPORTS_CHILDREN,
        IS_OPENABLE,
        PARENT_ID;
        
        public string colname() {
            switch (this) {
                case ID:
                    return "id";
                
                case NAME:
                    return "name";
                
                case SUPPORTS_CHILDREN:
                    return "supports_children";
                
                case IS_OPENABLE:
                    return "is_openable";
                
                case PARENT_ID:
                    return "parent_id";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    internal FolderTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async Gee.List<FolderRow> list_async(int64 parent_id, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare("SELECT * FROM FolderTable WHERE parent_id=?");
        query.bind_int64(0, parent_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        while (!result.finished) {
            rows.add(new FolderRow.from_query_result(result));
            
            yield result.next_async(cancellable);
        }
        
        return rows;
    }
    
    public async FolderRow? fetch_async(int64 parent_id, string name, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare("SELECT * FROM FolderTable WHERE parent_id=? AND name=?");
        query.bind_int64(0, parent_id);
        query.bind_string(1, name);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        return (!result.finished) ? new FolderRow.from_query_result(result) : null;
    }
    
    private SQLHeavy.Query create_query(SQLHeavy.Queryable? queryable = null) throws SQLHeavy.Error {
        SQLHeavy.Queryable q = queryable ?? db;
        SQLHeavy.Query query = q.prepare(
            "INSERT INTO FolderTable (name, supports_children, is_openable, parent_id) VALUES (?, ?, ?, ?)");
        
        return query;
    }
    
    private void create_binding(SQLHeavy.Query query, FolderRow row) throws SQLHeavy.Error {
        query.clear();
        query.bind_string(0, row.name);
        query.bind_int(1, row.supports_children.to_int());
        query.bind_int(2, row.is_openable.to_int());
        query.bind_int64(3, row.parent_id);
    }
    
    public async void create_async(FolderRow row, Cancellable? cancellable = null) throws Error {
        SQLHeavy.Query query = create_query();
        create_binding(query, row);
        
        yield query.execute_insert_async(cancellable);
    }
    
    public async void create_many_async(Gee.Collection<FolderRow> rows, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Transaction transaction = db.begin_transaction();
        
        SQLHeavy.Query query = create_query(transaction);
        foreach (FolderRow row in rows) {
            create_binding(query, row);
            query.execute_insert();
        }
        
        // TODO: Need an async transaction commit
        transaction.commit();
    }
}

