/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapDB.Database : Geary.Db.VersionedDatabase {
    private const string DB_FILENAME = "geary.db";
    
    public Database(File db_dir, File schema_dir) {
        base (db_dir.get_child(DB_FILENAME), schema_dir);
    }
}

