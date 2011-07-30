/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Sqlite.Row {
    public const int64 INVALID_ID = -1;
    
    protected Table table;
    
    public Row(Table table) {
        this.table = table;
    }
    
    public int fetch_int_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_int(field_index(result, col));
    }
    
    public int64 fetch_int64_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_int64(field_index(result, col));
    }
    
    public string fetch_string_for(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        return result.fetch_string(field_index(result, col));
    }
    
    private int field_index(SQLHeavy.QueryResult result, int col) throws SQLHeavy.Error {
        try {
            return result.field_index(table.get_field_name(col));
        } catch (SQLHeavy.Error err) {
            debug("Bad column #%d in %s: %s", col, table.to_string(), err.message);
            
            throw err;
        }
    }
}

