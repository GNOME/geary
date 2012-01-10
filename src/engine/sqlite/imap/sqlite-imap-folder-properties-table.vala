/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapFolderPropertiesTable : Geary.Sqlite.Table {
    // This *must* be in the same order as the schema.
    public enum Column {
        ID,
        FOLDER_ID,
        LAST_SEEN_TOTAL,
        UID_VALIDITY,
        UID_NEXT,
        ATTRIBUTES
    }
    
    public ImapFolderPropertiesTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(Transaction? transaction, ImapFolderPropertiesRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "ImapFolderPropertiesTable.create_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO ImapFolderPropertiesTable (folder_id, last_seen_total, uid_validity, uid_next, attributes) "
            + "VALUES (?, ?, ?, ?, ?)");
        query.bind_int64(0, row.folder_id);
        query.bind_int(1, row.last_seen_total);
        query.bind_int64(2, (row.uid_validity != null) ? row.uid_validity.value : -1);
        query.bind_int64(3, (row.uid_next != null) ? row.uid_next.value : -1);
        query.bind_string(4, row.attributes);
        
        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
        
        return id;
    }
    
    public async void update_async(Transaction? transaction, int64 folder_id, 
        ImapFolderPropertiesRow row, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "ImapFolderPropertiesTable.update_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "UPDATE ImapFolderPropertiesTable "
            + "SET last_seen_total = ?, uid_validity = ?, uid_next = ?, attributes = ? "
            + "WHERE folder_id = ?");
        query.bind_int(0, row.last_seen_total);
        query.bind_int64(1, (row.uid_validity != null) ? row.uid_validity.value : -1);
        query.bind_int64(2, (row.uid_next != null) ? row.uid_next.value : -1);
        query.bind_string(3, row.attributes);
        query.bind_int64(4, folder_id);
        
        yield query.execute_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
    }
    
    public async ImapFolderPropertiesRow? fetch_async(Transaction? transaction,
        int64 folder_id, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "ImapFolderPropertiesTable.fetch_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id, last_seen_total, uid_validity, uid_next, attributes "
            + "FROM ImapFolderPropertiesTable WHERE folder_id = ?");
        query.bind_int64(0, folder_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        Geary.Imap.UIDValidity? uid_validity = null;
        if (result.fetch_int64(2) >= 0)
            uid_validity = new Geary.Imap.UIDValidity(result.fetch_int64(2));
        
        Geary.Imap.UID? uid_next = null;
        if (result.fetch_int64(3) >= 0)
            uid_next = new Geary.Imap.UID(result.fetch_int64(3));
        
        return new ImapFolderPropertiesRow(this, result.fetch_int64(0), folder_id, result.fetch_int(1),
            uid_validity, uid_next, result.fetch_string(4));
    }
}

