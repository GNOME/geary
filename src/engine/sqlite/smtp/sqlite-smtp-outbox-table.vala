/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Sqlite.SmtpOutboxTable : Geary.Sqlite.Table {
    public SmtpOutboxTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base(gdb, table);
    }
    
    public async Geary.Sqlite.SmtpOutboxRow create_async(Transaction? transaction,
        string message, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "SmtpOutboxTable.create_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO SmtpOutboxTable "
            + "(message, ordering)"
            + "VALUES (?, (SELECT COALESCE(MAX(ordering), 0) + 1 FROM SmtpOutboxTable))");
        query.bind_string(0, message);
        
        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(null, locked, cancellable);
        
        SmtpOutboxRow? row = yield fetch_email_by_row_id_async(transaction, id);
        if (row == null)
            throw new EngineError.NOT_FOUND("Unable to locate created row %lld", id);
        
        return row;
    }
    
    public async int get_email_count_async(Transaction? transaction, Cancellable? cancellable)
        throws Error {
        Transaction locked = yield obtain_lock_async(transaction,
            "SmtpOutboxTable.get_email_count_async", cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT COUNT(*) FROM SmtpOutboxTable");
        
        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "get_email_count_for_folder_async");
        
        return (!results.finished) ? results.fetch_int(0) : 0;
    }
    
    public async Gee.List<Geary.Sqlite.SmtpOutboxRow>? list_email_async(Transaction? transaction,
        OutboxEmailIdentifier initial_id, int count, Cancellable? cancellable = null) throws Error {
        int64 low = initial_id.ordering;
        assert(low >= 1 || low == -1);
        assert(count >= 0 || count == -1);
        
        Transaction locked = yield obtain_lock_async(transaction, "SmtpOutboxTable.list_email_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id, ordering, message FROM SmtpOutboxTable "
            + "ORDER BY ordering %s %s".printf(count != -1 ? "LIMIT ?" : "",
            low != -1 ? "OFFSET ?" : ""));
        
        int bind = 0;
        if (count != -1)
            query.bind_int(bind++, count);
        
        if (low != -1)
            query.bind_int64(bind++, low - 1);
        
        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "list_email_async");
        
        if (results.finished)
            return null;
        
        Gee.List<SmtpOutboxRow> list = new Gee.ArrayList<SmtpOutboxRow>();
        do {
            list.add(new SmtpOutboxRow(this, results.fetch_int64(0), results.fetch_int64(1),
                results.fetch_string(2), -1));
            
            yield results.next_async();
            
            check_cancel(cancellable, "list_email_async");
        } while (!results.finished);
        
        return list;
    }
    
    public async Gee.List<Geary.Sqlite.SmtpOutboxRow>? list_email_by_sparse_id_async(
        Transaction? transaction, Gee.Collection<OutboxEmailIdentifier> ids,
        Cancellable? cancellable = null) throws Error {
        
        Gee.List<SmtpOutboxRow> list = new Gee.ArrayList<SmtpOutboxRow>();
        
        foreach (OutboxEmailIdentifier id in ids) {
            Geary.Sqlite.SmtpOutboxRow? row = yield fetch_email_internal_async(transaction,
                id, cancellable);
            if (row != null)
                list.add(row);
        }
        
        return list.size > 0 ? list : null;
    }
    
    public async int fetch_position_async(Transaction? transaction, int64 ordering,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "SmtpOutboxTable.fetch_position_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT ordering FROM SmtpOutboxTable ORDER BY ordering");
        
        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "fetch_position_async");
        
        int position = 1;
        while (!results.finished) {
            if (results.fetch_int64(0) == ordering)
                return position;
            
            yield results.next_async();
            
            check_cancel(cancellable, "fetch_position_async");
            
            position++;
        }
        
        // not found
        return -1;
    }
    
    // Fetch an email given an outbox ID.
    public async Geary.Sqlite.SmtpOutboxRow? fetch_email_async(Transaction? transaction,
        OutboxEmailIdentifier id, Cancellable? cancellable = null) throws Error {
        return yield fetch_email_internal_async(transaction, id, cancellable);
    }
    
    private async Geary.Sqlite.SmtpOutboxRow? fetch_email_internal_async(Transaction? transaction,
        OutboxEmailIdentifier id, Cancellable? cancellable = null) throws Error {
        Transaction locked = yield obtain_lock_async(transaction,
            "SmtpOutboxTable.fetch_email_internal_async", cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id, ordering, message FROM SmtpOutboxTable "
            + "WHERE ordering = ?");
        query.bind_int64(0, id.ordering);
        
        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "fetch_email_internal_async");
        
        if (results.finished)
            return null;
        
        SmtpOutboxRow? ret = new SmtpOutboxRow(this, results.fetch_int64(0), results.fetch_int64(1),
            results.fetch_string(2), -1);
            
        check_cancel(cancellable, "fetch_email_internal_async");
        return ret;
    }
    
    // Fetch an email given a database row ID.
    private async Geary.Sqlite.SmtpOutboxRow? fetch_email_by_row_id_async(Transaction? transaction,
        int64 id, Cancellable? cancellable = null) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "SmtpOutboxTable.fetch_email_by_row_id_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id, ordering, message FROM SmtpOutboxTable WHERE id = ?");
        query.bind_int64(0, id);
        
        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "fetch_email_by_row_id_async");
        
        if (results.finished)
            return null;
        
        SmtpOutboxRow? ret = new SmtpOutboxRow(this, results.fetch_int64(0), results.fetch_int64(1),
            results.fetch_string(2), -1);
            
        check_cancel(cancellable, "fetch_email_by_row_id_async");
        return ret;
    }
    
    public async void remove_single_email_async(Transaction? transaction, OutboxEmailIdentifier id,
        Cancellable? cancellable = null) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "SmtpOutboxTable.remove_email_async",
            cancellable);

        SQLHeavy.Query query = locked.prepare(
            "DELETE FROM SmtpOutboxTable WHERE ordering=?");
        query.bind_int64(0, id.ordering);
        
        yield query.execute_async();
    }
}

