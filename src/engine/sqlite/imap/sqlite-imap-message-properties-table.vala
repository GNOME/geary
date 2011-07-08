/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessagePropertiesTable : Geary.Sqlite.Table {
    // This *must* be in the same order as the schema.
    public enum Column {
        ID,
        FLAGS
    }
    
    public ImapMessagePropertiesTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(ImapMessagePropertiesRow row, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "INSERT INTO ImapMessagePropertiesTable (message_id, flags) VALUES (?, ?)");
        query.bind_int64(0, row.message_id);
        query.bind_string(1, row.flags);
        
        return yield query.execute_insert_async(cancellable);
    }
    
    public async ImapMessagePropertiesRow? fetch_async(int64 message_id, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "SELECT id, flags FROM ImapMessagePropertiesTable WHERE message_id = ?");
        query.bind_int64(0, message_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        return new ImapMessagePropertiesRow(this, result.fetch_int64(0), message_id,
            result.fetch_string(1));
    }
    
    public async void update_async(int64 message_id, string flags, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "UPDATE ImapMessagePropertiesTable SET flags = ? WHERE message_id = ?");
        query.bind_string(0, flags);
        query.bind_int64(1, message_id);
        
        yield query.execute_async(cancellable);
    }
}

