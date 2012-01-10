/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessagePropertiesTable : Geary.Sqlite.Table {
    // This *must* be in the same order as the schema.
    public enum Column {
        ID,
        MESSAGE_ID,
        FLAGS,
        INTERNALDATE,
        RFC822_SIZE
    }
    
    public ImapMessagePropertiesTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(Transaction? transaction, ImapMessagePropertiesRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction,
            "ImapMessagePropertiesTable.create_async", cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO ImapMessagePropertiesTable (message_id, flags, internaldate, rfc822_size) "
            + "VALUES (?, ?, ?, ?)");
        query.bind_int64(0, row.message_id);
        query.bind_string(1, row.flags);
        query.bind_string(2, row.internaldate);
        query.bind_int64(3, row.rfc822_size);
        
        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
        
        return id;
    }
    
    public async ImapMessagePropertiesRow? fetch_async(Transaction? transaction, int64 message_id,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "ImapMessagePropertiesTable.fetch_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id, flags, internaldate, rfc822_size FROM ImapMessagePropertiesTable "
            + "WHERE message_id = ?");
        query.bind_int64(0, message_id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        return new ImapMessagePropertiesRow(this, result.fetch_int64(0), message_id,
            result.fetch_string(1), result.fetch_string(2), (long) result.fetch_int64(3));
    }
    
    public async void update_async(Transaction? transaction, int64 message_id, string? flags,
        string? internaldate, long rfc822_size, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "ImapMessagePropertiesTable.update_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "UPDATE ImapMessagePropertiesTable SET flags = ?, internaldate = ?, rfc822_size = ? "
            + "WHERE message_id = ?");
        query.bind_string(0, flags);
        query.bind_string(1, internaldate);
        query.bind_int64(2, rfc822_size);
        query.bind_int64(3, message_id);
        
        yield query.execute_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
    }
    
    public async void update_flags_async(Transaction? transaction, int64 message_id, string? flags,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, 
            "ImapMessagePropertiesTable.update_flags_async", cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "UPDATE ImapMessagePropertiesTable SET flags = ? WHERE message_id = ?");
        query.bind_string(0, flags);
        query.bind_int64(1, message_id);
        
        yield query.execute_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
    }
    
    public async Gee.List<int64?>? search_for_duplicates_async(Transaction? transaction, string? internaldate,
        long rfc822_size, Cancellable? cancellable) throws Error {
        bool has_internaldate = !String.is_empty(internaldate);
        bool has_size = rfc822_size >= 0;
        
        // at least one parameter must be available
        if (!has_internaldate && !has_size)
            throw new EngineError.BAD_PARAMETERS("Cannot search for IMAP duplicates without a valid parameter");
        
        Transaction locked = yield obtain_lock_async(transaction, "ImapMessagePropertiesTable.search_for_duplicates",
            cancellable);
        
        SQLHeavy.Query query;
        if (has_internaldate && has_size) {
            query = locked.prepare(
                "SELECT message_id FROM ImapMessagePropertiesTable WHERE internaldate=? AND rfc822_size=?");
            query.bind_string(0, internaldate);
            query.bind_int64(1, rfc822_size);
        } else if (has_internaldate) {
            query = locked.prepare(
                "SELECT message_id FROM ImapMessagePropertiesTable WHERE internaldate=?");
            query.bind_string(0, internaldate);
        } else {
            assert(has_size);
            query = locked.prepare(
                "SELECT message_id FROM ImapMessagePropertiesTable WHERE rfc822_size=?");
            query.bind_int64(0, rfc822_size);
        }
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return null;
        
        Gee.List<int64?> list = new Gee.ArrayList<int64?>();
        do {
            list.add(result.fetch_int64(0));
            yield result.next_async(cancellable);
        } while (!result.finished);
        
        return list;
    }
}

