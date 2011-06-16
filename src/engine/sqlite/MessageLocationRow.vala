/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageLocationRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 message_id { get; private set; }
    public int64 folder_id { get; private set; }
    public int64 ordering { get; private set; }
    
    public MessageLocationRow(MessageLocationTable table, int64 id, int64 message_id, int64 folder_id,
        int64 ordering) {
        base (table);
        
        this.id = id;
        this.message_id = message_id;
        this.folder_id = folder_id;
        this.ordering = ordering;
    }
    
    public MessageLocationRow.from_query_result(MessageLocationTable table,
        SQLHeavy.QueryResult result) throws Error {
        base (table);
        
        id = fetch_int64_for(result, MessageLocationTable.Column.ID);
        message_id = fetch_int64_for(result, MessageLocationTable.Column.MESSAGE_ID);
        folder_id = fetch_int64_for(result, MessageLocationTable.Column.FOLDER_ID);
        ordering = fetch_int64_for(result, MessageLocationTable.Column.ORDERING);
    }
}

