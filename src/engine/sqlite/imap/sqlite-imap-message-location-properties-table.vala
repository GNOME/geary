/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessageLocationPropertiesTable : Geary.Sqlite.Table {
    // This *must* be in the same order as the schema.
    public enum Column {
        ID,
        LOCATION_ID,
        UID
    }
    
    public ImapMessageLocationPropertiesTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(ImapMessageLocationPropertiesRow row,
        Cancellable? cancellable = null) throws Error {
        SQLHeavy.Query query = db.prepare(
            "INSERT INTO ImapMessageLocationPropertiesTable (location_id, uid) VALUES (?, ?)");
        query.bind_int64(0, row.location_id);
        query.bind_int64(1, row.uid.value);
        
        return yield query.execute_insert_async(cancellable);
    }
    
    public async ImapMessageLocationPropertiesRow? fetch_async(int64 location_id,
        Cancellable? cancellable = null) throws Error {
        SQLHeavy.Query query = db.prepare(
            "SELECT id, uid FROM ImapMessageLocationPropertiesTable WHERE location_id = ?");
        query.bind_int64(0, location_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        return new ImapMessageLocationPropertiesRow(this, result.fetch_int64(0), location_id,
            new Geary.Imap.UID(result.fetch_int64(1)));
    }
    
    public async bool search_uid_in_folder(Geary.Imap.UID uid, int64 folder_id,
        out int64 message_id, Cancellable? cancellable = null) throws Error {
        message_id = Row.INVALID_ID;
        
        SQLHeavy.Query query = db.prepare(
            "SELECT MessageLocationTable.message_id "
            + "FROM ImapMessageLocationPropertiesTable "
            + "INNER JOIN MessageLocationTable "
            + "WHERE MessageLocationTable.folder_id=? "
            + "AND ImapMessageLocationPropertiesTable.location_id=MessageLocationTable.id "
            + "AND ImapMessageLocationPropertiesTable.uid=?");
        query.bind_int64(0, folder_id);
        query.bind_int64(1, uid.value);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        if (!result.finished)
            message_id = result.fetch_int64(0);
        
        return !result.finished;
    }
}

