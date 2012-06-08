/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageAttachmentTable : Geary.Sqlite.Table {
    // This row *must* match the order in the schema
    public enum Column {
        ID,
        MESSAGE_ID,
        FILENAME,
        MIME_TYPE,
        FILESIZE
    }

    public MessageAttachmentTable(Geary.Sqlite.Database db, SQLHeavy.Table table) {
        base (db, table);
    }

    public async int64 create_async(Transaction? transaction, MessageAttachmentRow row,
        Cancellable? cancellable) throws Error {
        Transaction locked = yield obtain_lock_async(transaction, "MessageAttachmentTable.create_async",
            cancellable);

        SQLHeavy.Query query = locked.prepare(
            "INSERT INTO MessageAttachmentTable (message_id, filename, mime_type, filesize) " +
            "VALUES (?, ?, ?, ?)");
        query.bind_int64(0, row.message_id);
        query.bind_string(1, row.filename);
        query.bind_string(2, row.mime_type);
        query.bind_int64(3, row.filesize);

        int64 id = yield query.execute_insert_async(cancellable);
        locked.set_commit_required();

        yield release_lock_async(transaction, locked, cancellable);

        check_cancel(cancellable, "create_async");

        return id;
    }

    public async Gee.List<MessageAttachmentRow>? list_async(Transaction? transaction,
        int64 message_id, Cancellable? cancellable) throws Error {

        Transaction locked = yield obtain_lock_async(transaction, "MessageAttachmentTable.list_async",
            cancellable);

        SQLHeavy.Query query = locked.prepare(
            "SELECT id, filename, mime_type, filesize FROM MessageAttachmentTable " +
            "WHERE message_id = ? ORDER BY id");
        query.bind_int64(0, message_id);

        SQLHeavy.QueryResult results = yield query.execute_async();
        check_cancel(cancellable, "list_async");

        Gee.List<MessageAttachmentRow> list = new Gee.ArrayList<MessageAttachmentRow>();
        if (results.finished)
            return list;

        do {
            list.add(new MessageAttachmentRow(this, results.fetch_int64(0), message_id,
                results.fetch_string(1), results.fetch_string(2), results.fetch_int64(3)));

            yield results.next_async();

            check_cancel(cancellable, "list_async");
        } while (!results.finished);

        return list;
    }

    public async void remove_async(Transaction? transaction, int64 attachment_id,
        Cancellable? cancellable) throws Error {

        Transaction locked = yield obtain_lock_async(transaction,
            "MessageAttachmentTable.remove_async", cancellable);

        SQLHeavy.Query query = locked.prepare(
            "DELETE FROM MessageAttachmentTable WHERE attachment_id = ?");
        query.bind_int64(0, attachment_id);

        yield query.execute_async();
        locked.set_commit_required();
        yield release_lock_async(transaction, locked, cancellable);
        check_cancel(cancellable, "remove_async");
    }
}

