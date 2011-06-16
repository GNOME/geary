/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageLocationTable : Geary.Sqlite.Table {
    // This row *must* match the order in the schema
    public enum Column {
        ID,
        MESSAGE_ID,
        FOLDER_ID,
        ORDERING
    }
    
    public MessageLocationTable(Geary.Sqlite.Database db, SQLHeavy.Table table) {
        base (db, table);
    }
    
    public async int64 create_async(MessageLocationRow row, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "INSERT INTO MessageLocationTable (message_id, folder_id, ordering) VALUES (?, ?, ?)");
        query.bind_int64(0, row.message_id);
        query.bind_int64(1, row.folder_id);
        query.bind_int64(2, row.ordering);
        
        return yield query.execute_insert_async(cancellable);
    }
    
    /**
     * low is zero-based.
     */
    public async Gee.List<MessageLocationRow>? list_async(int64 folder_id, int low, int count,
        Cancellable? cancellable = null) throws Error {
        assert(low >= 0);
        
        SQLHeavy.Query query = db.prepare(
            "SELECT id, message_id, ordering FROM MessageLocationTable WHERE folder_id = ? "
            + "LIMIT ? OFFSET ? ORDER BY ordering");
        query.bind_int64(0, folder_id);
        query.bind_int(1, count);
        query.bind_int(2, low);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<MessageLocationRow> list = new Gee.ArrayList<MessageLocationRow>();
        do {
            list.add(new MessageLocationRow(this, results.fetch_int64(0), results.fetch_int64(1),
                folder_id, results.fetch_int64(2)));
            yield results.next_async(cancellable);
        } while (!results.finished);
        
        return list;
    }
    
    /**
     * num is zero-based.
     */
    public async MessageLocationRow? fetch_async(int64 folder_id, int num,
        Cancellable? cancellable = null) throws Error {
        assert(num >= 0);
        
        SQLHeavy.Query query = db.prepare(
            "SELECT id, message_id, ordering FROM MessageLocationTable WHERE folder_id = ? "
            + "LIMIT 1 OFFSET ? ORDER BY ordering");
        query.bind_int64(0, folder_id);
        query.bind_int64(1, num);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        return new MessageLocationRow(this, results.fetch_int64(0), results.fetch_int64(1), folder_id,
            results.fetch_int64(2));
    }
}

