/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.FolderRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public string name { get; private set; }
    public Trillian supports_children { get; private set; }
    public Trillian is_openable { get; private set; }
    public int64 parent_id { get; private set; }
    
    public FolderRow(string name, Trillian supports_children, Trillian is_openable, 
        int64 parent_id = INVALID_ID) {
        this.id = -1;
        this.name = name;
        this.supports_children = supports_children;
        this.is_openable = is_openable;
        this.parent_id = parent_id;
    }
    
    public FolderRow.from_query_result(SQLHeavy.QueryResult result) throws Error {
        id = fetch_int64_for(result, FolderTable.Column.ID.colname());
        name = fetch_string_for(result, FolderTable.Column.NAME.colname());
        supports_children = Trillian.from_int(fetch_int_for(result,
            FolderTable.Column.SUPPORTS_CHILDREN.colname()));
        is_openable = Trillian.from_int(fetch_int_for(result,
            FolderTable.Column.IS_OPENABLE.colname()));
        parent_id = fetch_int64_for(result, FolderTable.Column.PARENT_ID.colname());
    }
}

