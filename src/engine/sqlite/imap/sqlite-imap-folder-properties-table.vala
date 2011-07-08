/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapFolderPropertiesTable : Geary.Sqlite.Table {
    // This *must* be in the same order as the schema.
    public enum Column {
        ID,
        FOLDER_ID,
        UID_VALIDITY,
        FLAGS
    }
    
    public ImapFolderPropertiesTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(ImapFolderPropertiesRow row, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "INSERT INTO ImapFolderPropertiesTable (folder_id, uid_validity, attributes) VALUES (?, ?, ?)");
        query.bind_int64(0, row.folder_id);
        query.bind_int64(1, (row.uid_validity != null) ? row.uid_validity.value : -1);
        query.bind_string(2, row.attributes);
        
        return yield query.execute_insert_async(cancellable);
    }
    
    public async ImapFolderPropertiesRow? fetch_async(int64 folder_id, Cancellable? cancellable = null)
        throws Error {
        SQLHeavy.Query query = db.prepare(
            "SELECT id, uid_validity, attributes FROM ImapFolderPropertiesTable WHERE folder_id = ?");
        query.bind_int64(0, folder_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        Geary.Imap.UIDValidity? uid_validity = null;
        if (result.fetch_int64(1) >= 0)
            uid_validity = new Geary.Imap.UIDValidity(result.fetch_int64(1));
        
        return new ImapFolderPropertiesRow(this, result.fetch_int64(0), folder_id, uid_validity,
            result.fetch_string(2));
    }
}

