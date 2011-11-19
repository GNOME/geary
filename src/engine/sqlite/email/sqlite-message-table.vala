/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageTable : Geary.Sqlite.Table {
    // This *must* match the column order in the database
    public enum Column {
        ID,
        FIELDS,
        
        DATE_FIELD,
        DATE_TIME_T,
        
        FROM_FIELD,
        SENDER,
        REPLY_TO,
        
        TO_FIELD,
        CC,
        BCC,
        
        MESSAGE_ID,
        IN_REPLY_TO,
        REFERENCES,
        
        SUBJECT,
        
        HEADER,
        
        BODY,
        
        PREVIEW;
    }
    
    internal MessageTable(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        base (gdb, table);
    }
    
    public async int64 create_async(Transaction? transaction, MessageRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.create_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO MessageTable "
            + "(fields, date_field, date_time_t, from_field, sender, reply_to, to_field, cc, bcc, "
            + "message_id, in_reply_to, reference_ids, subject, header, body, preview) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        query.bind_int(0, row.fields);
        query.bind_string(1, row.date);
        query.bind_int64(2, row.date_time_t);
        query.bind_string(3, row.from);
        query.bind_string(4, row.sender);
        query.bind_string(5, row.reply_to);
        query.bind_string(6, row.to);
        query.bind_string(7, row.cc);
        query.bind_string(8, row.bcc);
        query.bind_string(9, row.message_id);
        query.bind_string(10, row.in_reply_to);
        query.bind_string(11, row.references);
        query.bind_string(12, row.subject);
        query.bind_string(13, row.header);
        query.bind_string(14, row.body);
        query.bind_string(15, row.preview);
        
        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();
        
        yield release_lock_async(transaction, locked, cancellable);
        
        return id;
    }
    
    // TODO: This could be made more efficient by executing a single SQL statement.
    public async void merge_async(Transaction? transaction, MessageRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.merge_async",
            cancellable);
        
        Geary.Email.Field available_fields;
        if (!yield fetch_fields_async(locked, row.id, out available_fields, cancellable))
            throw new EngineError.NOT_FOUND("No message with ID %lld found in database", row.id);
        
        // This calculates the fields in the row that are not in the database already
        Geary.Email.Field new_fields = (row.fields ^ available_fields) & row.fields;
        if (new_fields == Geary.Email.Field.NONE) {
            // nothing to add
            return;
        }
        
        NonblockingBatch batch = new NonblockingBatch();
        
        // since the following queries are all updates, the Transaction must be committed
        locked.set_commit_required();
        
        SQLHeavy.Query? query = null;
        if (new_fields.is_any_set(Geary.Email.Field.DATE)) {
            query = locked.prepare(
                "UPDATE MessageTable SET date_field=?, date_time_t=? WHERE id=?");
            query.bind_string(0, row.date);
            query.bind_int64(1, row.date_time_t);
            query.bind_int64(2, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.ORIGINATORS)) {
            query = locked.prepare(
                "UPDATE MessageTable SET from_field=?, sender=?, reply_to=? WHERE id=?");
            query.bind_string(0, row.from);
            query.bind_string(1, row.sender);
            query.bind_string(2, row.reply_to);
            query.bind_int64(3, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.RECEIVERS)) {
            query = locked.prepare(
                "UPDATE MessageTable SET to_field=?, cc=?, bcc=? WHERE id=?");
            query.bind_string(0, row.to);
            query.bind_string(1, row.cc);
            query.bind_string(2, row.bcc);
            query.bind_int64(3, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.REFERENCES)) {
            query = locked.prepare(
                "UPDATE MessageTable SET message_id=?, in_reply_to=?, reference_ids=? WHERE id=?");
            query.bind_string(0, row.message_id);
            query.bind_string(1, row.in_reply_to);
            query.bind_string(2, row.references);
            query.bind_int64(3, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.SUBJECT)) {
            query = locked.prepare(
                "UPDATE MessageTable SET subject=? WHERE id=?");
            query.bind_string(0, row.subject);
            query.bind_int64(1, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.HEADER)) {
            query = locked.prepare(
                "UPDATE MessageTable SET header=? WHERE id=?");
            query.bind_string(0, row.header);
            query.bind_int64(1, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.BODY)) {
            query = locked.prepare(
                "UPDATE MessageTable SET body=? WHERE id=?");
            query.bind_string(0, row.body);
            query.bind_int64(1, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        if (new_fields.is_any_set(Geary.Email.Field.PREVIEW)) {
            query = locked.prepare(
                "UPDATE MessageTable SET preview=? WHERE id=?");
            query.bind_string(0, row.preview);
            query.bind_int64(1, row.id);
            
            batch.add(new ExecuteQueryOperation(query));
        }
        
        yield batch.execute_all_async(cancellable);
        
        batch.throw_first_exception();
        
        // now merge the new fields in the row (do this *after* adding the fields, particularly
        // since we don't have full transaction backing out in the case of cancelled due to bugs
        // in SQLHeavy's async code
        query = locked.prepare(
            "UPDATE MessageTable SET fields = fields | ? WHERE id=?");
        query.bind_int(0, new_fields);
        query.bind_int64(1, row.id);
        
        yield query.execute_async(cancellable);
        
        yield release_lock_async(transaction, locked, cancellable);
    }
    
    public async Gee.List<MessageRow>? list_by_message_id_async(Transaction? transaction,
        Geary.RFC822.MessageID message_id, Geary.Email.Field fields, Cancellable? cancellable)
        throws Error {
        assert(fields != Geary.Email.Field.NONE);
        
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.list_by_message_id_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT %s FROM MessageTable WHERE message_id=?".printf(fields_to_columns(fields)));
        query.bind_string(0, message_id.value);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        Gee.List<MessageRow> list = new Gee.ArrayList<MessageRow>();
        do {
            list.add(new MessageRow.from_query_result(this, fields, results));
            yield results.next_async(cancellable);
        } while (!results.finished);
        
        return (list.size > 0) ? list : null;
    }
    
    public async MessageRow? fetch_async(Transaction? transaction, int64 id,
        Geary.Email.Field requested_fields, Cancellable? cancellable = null) throws Error {
        assert(requested_fields != Geary.Email.Field.NONE);
        // PROPERTIES are handled by the appropriate PropertiesTable
        assert(requested_fields != Geary.Email.Field.PROPERTIES);
        
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.fetch_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT %s FROM MessageTable WHERE id=?".printf(fields_to_columns(requested_fields)));
        query.bind_int64(0, id);
        
        SQLHeavy.QueryResult results = yield query.execute_async(cancellable);
        if (results.finished)
            return null;
        
        MessageRow row = new MessageRow.from_query_result(this, requested_fields, results);
        
        return row;
    }
    
    public async bool fetch_fields_async(Transaction? transaction, int64 id,
        out Geary.Email.Field available_fields, Cancellable? cancellable) throws Error {
        available_fields = Geary.Email.Field.NONE;
        
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.fetch_fields_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT fields FROM MessageTable WHERE id=?");
        query.bind_int64(0, id);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        if (result.finished)
            return false;
        
        available_fields = (Geary.Email.Field) result.fetch_int(0);
        
        return true;
    }
    
    private static string fields_to_columns(Geary.Email.Field fields) {
        StringBuilder builder = new StringBuilder("id, fields");
        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            string? append = null;
            if ((fields & field) != 0) {
                switch (field) {
                    case Geary.Email.Field.DATE:
                        append = "date_field, date_time_t";
                    break;
                    
                    case Geary.Email.Field.ORIGINATORS:
                        append = "from_field, sender, reply_to";
                    break;
                    
                    case Geary.Email.Field.RECEIVERS:
                        append = "to_field, cc, bcc";
                    break;
                    
                    case Geary.Email.Field.REFERENCES:
                        append = "message_id, in_reply_to, reference_ids";
                    break;
                    
                    case Geary.Email.Field.SUBJECT:
                        append = "subject";
                    break;
                    
                    case Geary.Email.Field.HEADER:
                        append = "header";
                    break;
                    
                    case Geary.Email.Field.BODY:
                        append = "body";
                    break;
                    
                    case Geary.Email.Field.PREVIEW:
                        append = "preview";
                    break;
                }
            }
            
            if (append != null) {
                builder.append(", ");
                builder.append(append);
            }
        }
        
        return builder.str;
    }
    
    public async int search_message_id_count_async(Transaction? transaction,
        Geary.RFC822.MessageID message_id, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.search_message_id_count",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT COUNT(*) FROM MessageTable WHERE message_id=?");
        query.bind_string(0, message_id.value);
        
        SQLHeavy.QueryResult result = yield query.execute_async(cancellable);
        
        return (result.finished) ? 0 : result.fetch_int(0);
    }
    
    public async Gee.List<int64?>? search_message_id_async(Transaction? transaction,
        Geary.RFC822.MessageID message_id, Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "MessageTable.search_message_id_async",
            cancellable);
        
        SQLHeavy.Query query = locked.prepare(
            "SELECT id FROM MessageTable WHERE message_id=?");
        query.bind_string(0, message_id.value);
        
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

