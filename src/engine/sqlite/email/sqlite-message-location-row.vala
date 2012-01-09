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
    
    private int position;
    
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
    
    /**
     * Note that position is not stored in the database, but rather determined by its location
     * determined by the sorted ordering column.  In some cases the database can determine the
     * position easily and will supply it to this object at construction time.  In other cases it's
     * not so straightforward and another database query will be required.  This method handles
     * both cases.
     *
     * If the call ever returns a position of -1, that indicates the message does not exist in the
     * database.
     */
    public async int get_position_async(Transaction? transaction, bool include_removed, 
        Cancellable? cancellable) throws Error {
        if (position >= 1)
            return position;
        
        position = yield ((MessageLocationTable) table).fetch_position_async(transaction, id, folder_id,
            include_removed, cancellable);
        
        return (position >= 1) ? position : -1;
    }
}

