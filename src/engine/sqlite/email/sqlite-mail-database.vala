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
        
        return (folder_table != null)
            ? folder_table
            : (FolderTable) add_table(new FolderTable(this, heavy_table));
    }
    
    public Geary.Sqlite.MessageTable get_message_table() {
        SQLHeavy.Table heavy_table;
        MessageTable? message_table = get_table("MessageTable", out heavy_table) as MessageTable;
        
        return (message_table != null)
            ? message_table
            : (MessageTable) add_table(new MessageTable(this, heavy_table));
    }
    
    public Geary.Sqlite.MessageLocationTable get_message_location_table() {
        SQLHeavy.Table heavy_table;
        MessageLocationTable? location_table = get_table("MessageLocationTable", out heavy_table)
            as MessageLocationTable;
        
        return (location_table != null)
            ? location_table
            : (MessageLocationTable) add_table(new MessageLocationTable(this, heavy_table));
    }
    
    // TODO: This belongs in a subclass.
    public Geary.Sqlite.ImapMessageLocationPropertiesTable get_imap_message_location_table() {
        SQLHeavy.Table heavy_table;
        ImapMessageLocationPropertiesTable? imap_location_table = get_table(
            "ImapMessageLocationPropertiesTable", out heavy_table) as ImapMessageLocationPropertiesTable;
        
        return (imap_location_table != null)
            ? imap_location_table
            : (ImapMessageLocationPropertiesTable) add_table(new ImapMessageLocationPropertiesTable(this, heavy_table));
    }
    
    // TODO: This belongs in a subclass.
    public Geary.Sqlite.ImapFolderPropertiesTable get_imap_folder_properties_table() {
        SQLHeavy.Table heavy_table;
        ImapFolderPropertiesTable? imap_folder_properties_table = get_table(
            "ImapFolderPropertiesTable", out heavy_table) as ImapFolderPropertiesTable;
        
        return imap_folder_properties_table 
            ?? (ImapFolderPropertiesTable) add_table(new ImapFolderPropertiesTable(this, heavy_table));
    }
    
    // TODO: This belongs in a subclass.
    public Geary.Sqlite.ImapMessagePropertiesTable get_imap_message_properties_table() {
        SQLHeavy.Table heavy_table;
        ImapMessagePropertiesTable? imap_message_properties_table = get_table(
            "ImapMessagePropertiesTable", out heavy_table) as ImapMessagePropertiesTable;
        
        return imap_message_properties_table 
            ?? (ImapMessagePropertiesTable) add_table(new ImapMessagePropertiesTable(this, heavy_table));
    }
}

