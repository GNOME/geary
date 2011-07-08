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
        POSITION
    }
    
    public MessageLocationTable(Geary.Sqlite.Database db, SQLHeavy.Table table) {
        base (db, table);
    }
    
    public async int64 create_async(MessageLocationRow row, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "INSERT INTO MessageLocationTable (message_id, folder_id, position) VALUES (?, ?, ?)");
        query.bind_int64(0, row.message_id);
        query.bind_int64(1, row.folder_id);
        query.bind_int(2, row.position);
        
        return yield query.execute_insert_async(cancellable);
    }
    
    /**
     * low is one-based.  If count is -1, all messages starting at low are returned.
     */
    public async Gee.List<MessageLocationRow>? list_async(int64 folder_id, int low, int count,
        Cancellable? cancellable = null) throws Error {
        assert(low >= 1);
        assert(count >= 0 || count == -1);
        
        SQLHeavy.Query query;
        if (count >= 0) {
            query = db.prepare(
                "SELECT id, message_id, position FROM MessageLocationTable WHERE folder_id = ? "
                + "ORDER BY position LIMIT ? OFFSET ?");
            query.bind_int64(0, folder_id);
            query.bind_int(1, count);
            query.bind_int(2, low - 1);
        } else {
            // count == -1
            query = db.prepare(
                "SELECT id, message_id, position FROM MessageLocationTable WHERE folder_id = ? "
                + "ORDER BY position OFFSET ?");
            query.bind_int64(0, folder_id);
            query.bind_int(1, low - 1);
        }
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<MessageLocationRow> list = new Gee.ArrayList<MessageLocationRow>();
        do {
            list.add(new MessageLocationRow(this, results.fetch_int64(0), results.fetch_int64(1),
                folder_id, results.fetch_int(2)));
            yield results.next_async(cancellable);
        } while (!results.finished);
        
        return list;
    }
    
    /**
     * All positions are one-based.
     */
    public async Gee.List<MessageLocationRow>? list_sparse_async(int64 folder_id, int[] by_position,
        Cancellable? cancellable = null) throws Error {
        // build a vector for the IN expression
        StringBuilder vector = new StringBuilder("(");
        for (int ctr = 0; ctr < by_position.length; ctr++) {
            assert(by_position[ctr] >= 1);
            
            if (ctr < (by_position.length - 1))
                vector.append_printf("%d, ", by_position[ctr]);
            else
                vector.append_printf("%d", by_position[ctr]);
        }
        vector.append(")");
        
        SQLHeavy.Query query = db.prepare(
            "SELECT id, message_id, position FROM MessageLocationTable WHERE folder_id = ? AND position IN ?");
        query.bind_int64(0, folder_id);
        query.bind_string(1, vector.str);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<MessageLocationRow> list = new Gee.ArrayList<MessageLocationRow>();
        do {
            list.add(new MessageLocationRow(this, results.fetch_int64(0), results.fetch_int64(1),
                folder_id, results.fetch_int(2)));
            yield results.next_async(cancellable);
        } while (!results.finished);
        
        return list;
    }
    
    /**
     * position is one-based.
     */
    public async MessageLocationRow? fetch_async(int64 folder_id, int position,
        Cancellable? cancellable = null) throws Error {
        assert(position >= 1);
        
        SQLHeavy.Query query = db.prepare(
            "SELECT id, message_id, position FROM MessageLocationTable WHERE folder_id = ? "
            + "AND position = ?");
        query.bind_int64(0, folder_id);
        query.bind_int(1, position);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        return new MessageLocationRow(this, results.fetch_int64(0), results.fetch_int64(1), folder_id,
            results.fetch_int(2));
    }
}

