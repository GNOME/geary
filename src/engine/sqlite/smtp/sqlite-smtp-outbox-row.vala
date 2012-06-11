/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Sqlite.SmtpOutboxRow : Geary.Sqlite.Row {
    public int64 id { get; set; default = INVALID_ID; }
    public int64 ordering { get; set; }
    public string? message { get; set; }
    
    private int position;
    
    public SmtpOutboxRow(SmtpOutboxTable table, int64 id, int64 ordering, string message, int position) {
        base (table);
        
        this.id = id;
        this.ordering = ordering;
        this.message = message;
        this.position = position;
    }
    
    public async int get_position_async(Transaction? transaction, Cancellable? cancellable)
        throws Error {
        if (position >= 1)
            return position;
        
        position = yield ((SmtpOutboxTable) table).fetch_position_async(transaction, ordering,
            cancellable);
        
        return (position >= 1) ? position : -1;
    }
    
    public string to_string() {
        return "%lld".printf(ordering);
    }
}

