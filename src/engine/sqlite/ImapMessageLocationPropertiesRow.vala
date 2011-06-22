/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessageLocationPropertiesRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 location_id { get; private set; }
    public int64 uid { get; private set; }
    
    public ImapMessageLocationPropertiesRow(ImapMessageLocationPropertiesTable table, int64 id,
        int64 location_id, int64 uid) {
        base (table);
        
        this.id = id;
        this.location_id = location_id;
        this.uid = uid;
    }
}

