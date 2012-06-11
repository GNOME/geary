/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Sqlite.MailDatabase : Geary.Sqlite.Database {
    public const string FILENAME = "geary.db";

    public MailDatabase(string user, File user_data_dir, File resource_dir) throws Error {
        base (user_data_dir.get_child(user).get_child(FILENAME), resource_dir.get_child("sql"));
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
    
    public Geary.Sqlite.MessageAttachmentTable get_message_attachment_table() {
        SQLHeavy.Table heavy_table;
        MessageAttachmentTable? attachment_table = get_table("MessageAttachmentTable", out heavy_table)
            as MessageAttachmentTable;
        
        return (attachment_table != null)
            ? attachment_table
            : (MessageAttachmentTable) add_table(new MessageAttachmentTable(this, heavy_table));
    }
    
    public Geary.Sqlite.SmtpOutboxTable get_smtp_outbox_table() {
        SQLHeavy.Table heavy_table;
        SmtpOutboxTable? outbox_table = get_table("OutboxTable", out heavy_table) as SmtpOutboxTable;
        
        return (outbox_table != null)
            ? outbox_table
            : (SmtpOutboxTable) add_table(new SmtpOutboxTable(this, heavy_table));
    }
}

