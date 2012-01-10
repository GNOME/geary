/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.FolderRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public string name { get; private set; }
    public int64 parent_id { get; private set; }
    
    public FolderRow(FolderTable table, string name, int64 parent_id) {
        base (table);
        
        this.id = INVALID_ID;
        this.name = name;
        this.parent_id = parent_id;
    }
    
    public FolderRow.from_query_result(FolderTable table, SQLHeavy.QueryResult result) throws Error {
        base (table);
        
        id = fetch_int64_for(result, FolderTable.Column.ID);
        name = fetch_string_for(result, FolderTable.Column.NAME);
        parent_id = fetch_int64_for(result, FolderTable.Column.PARENT_ID);
    }
}

