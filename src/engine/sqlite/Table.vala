/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Sqlite.Table {
    internal SQLHeavy.Database db {
        get {
            return gdb.db;
        }
    }
    
    internal weak Geary.Sqlite.Database gdb;
    internal SQLHeavy.Table table;
    
    internal Table(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        this.gdb = gdb;
        this.table = table;
    }
}

