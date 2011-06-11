/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MailDatabase : Geary.Sqlite.Database {
    public const string FILENAME = "geary.db";
    
    public MailDatabase(string user) throws Error {
        base (YorbaApplication.instance.get_user_data_directory().get_child(user).get_child(FILENAME),
            YorbaApplication.instance.get_resource_directory().get_child("sql"));
    }
    
    public Geary.Sqlite.FolderTable get_folder_table() {
        SQLHeavy.Table heavy_table;
        FolderTable? folder_table = get_table("FolderTable", out heavy_table) as FolderTable;
        if (folder_table != null)
            return folder_table;
        
        folder_table = new FolderTable(this, heavy_table);
        add_table(folder_table);
        
        return folder_table;
    }
}

