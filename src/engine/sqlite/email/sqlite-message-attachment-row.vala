/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageAttachmentRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 message_id { get; private set; }
    public int64 filesize { get; private set; }
    public string filename { get; private set; }
    public string mime_type { get; private set; }

    public MessageAttachmentRow(MessageAttachmentTable table, int64 id, int64 message_id,
        string filename, string mime_type, int64 filesize) {
        base (table);

        this.id = id;
        this.message_id = message_id;
        this.filename = filename;
        this.mime_type = mime_type;
        this.filesize = filesize;
    }

    public MessageAttachmentRow.from_query_result(MessageAttachmentTable table,
        SQLHeavy.QueryResult result) throws Error {
        base (table);

        id = fetch_int64_for(result, MessageAttachmentTable.Column.ID);
        message_id = fetch_int64_for(result, MessageAttachmentTable.Column.MESSAGE_ID);
        filename = fetch_string_for(result, MessageAttachmentTable.Column.FILENAME);
        mime_type = fetch_string_for(result, MessageAttachmentTable.Column.MIME_TYPE);
    }

    public Geary.Attachment to_attachment() {
        return new Attachment(table.gdb.data_dir, filename, mime_type, filesize, message_id, id);
    }
}

