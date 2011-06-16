/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Sqlite.Row {
    public const int64 INVALID_ID = -1;
    
    private Table table;
    
    public Row(Table table) {
        this.table = table;
    }
    
    public int fetch_int_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_int(result.field_index(table.get_field_name(col)));
    }
    
    public int64 fetch_int64_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_int64(result.field_index(table.get_field_name(col)));
    }
    
    public string fetch_string_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_string(result.field_index(table.get_field_name(col)));
    }
}

