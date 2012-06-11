/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Sqlite.ImapDatabase : Geary.Sqlite.MailDatabase {
    public ImapDatabase(string user, File user_data_dir, File resource_dir) throws Error {
        base (user, user_data_dir, resource_dir);
    }
    
    public Geary.Sqlite.ImapFolderPropertiesTable get_imap_folder_properties_table() {
        SQLHeavy.Table heavy_table;
        ImapFolderPropertiesTable? imap_folder_properties_table = get_table(
            "ImapFolderPropertiesTable", out heavy_table) as ImapFolderPropertiesTable;
        
        return imap_folder_properties_table 
            ?? (ImapFolderPropertiesTable) add_table(new ImapFolderPropertiesTable(this, heavy_table));
    }
    
    public Geary.Sqlite.ImapMessagePropertiesTable get_imap_message_properties_table() {
        SQLHeavy.Table heavy_table;
        ImapMessagePropertiesTable? imap_message_properties_table = get_table(
            "ImapMessagePropertiesTable", out heavy_table) as ImapMessagePropertiesTable;
        
        return imap_message_properties_table 
            ?? (ImapMessagePropertiesTable) add_table(new ImapMessagePropertiesTable(this, heavy_table));
    }
}

