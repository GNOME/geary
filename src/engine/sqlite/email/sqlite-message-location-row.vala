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
    /**
     * Note that position is not stored in the database, but rather determined by its location
     * determined by the sorted ordering.  If the database call is unable to easily determine the
     * position of the message in the folder, this will be set to -1.
     */
    public int position { get; private set; }
    
    public MessageLocationRow(MessageLocationTable table, int64 id, int64 message_id, int64 folder_id,
        int64 ordering, int position) {
        base (table);
        
        this.id = id;
        this.message_id = message_id;
        this.folder_id = folder_id;
        this.ordering = ordering;
        this.position = position;
    }
    
    public MessageLocationRow.from_query_result(MessageLocationTable table, int position,
        SQLHeavy.QueryResult result) throws Error {
        base (table);
        
        id = fetch_int64_for(result, MessageLocationTable.Column.ID);
        message_id = fetch_int64_for(result, MessageLocationTable.Column.MESSAGE_ID);
        folder_id = fetch_int64_for(result, MessageLocationTable.Column.FOLDER_ID);
        ordering = fetch_int64_for(result, MessageLocationTable.Column.ORDERING);
        this.position = position;
    }
}

