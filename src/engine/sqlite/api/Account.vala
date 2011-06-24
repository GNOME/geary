/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Account : Object, Geary.Account, Geary.LocalAccount {
    private MailDatabase db;
    private FolderTable folder_table;
    private MessageTable message_table;
    
    public Account(Geary.Credentials cred) {
        try {
            db = new MailDatabase(cred.user);
        } catch (Error err) {
            error("Unable to open database: %s", err.message);
        }
        
        folder_table = db.get_folder_table();
        message_table = db.get_message_table();
    }
    
    public Geary.Email.Field get_required_fields_for_writing() {
        return Geary.Email.Field.NONE;
    }
    
    public async void create_folder_async(Geary.Folder? parent, Geary.Folder folder,
        Cancellable? cancellable = null) throws Error {
        yield folder_table.create_async(new FolderRow(folder_table, folder.get_name(), Row.INVALID_ID),
            cancellable);
    }
    
    public async void create_many_folders_async(Geary.Folder? parent, Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        foreach (Geary.Folder folder in folders)
            rows.add(new FolderRow(db.get_folder_table(), folder.get_name(), Row.INVALID_ID));
        
        yield folder_table.create_many_async(rows, cancellable);
    }
    
    public async Gee.Collection<Geary.Folder> list_folders_async(Geary.Folder? parent,
        Cancellable? cancellable = null) throws Error {
        Gee.List<FolderRow> rows = yield folder_table.list_async(Row.INVALID_ID, cancellable);
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Sqlite.Folder>();
        foreach (FolderRow row in rows)
            folders.add(new Geary.Sqlite.Folder(db, row));
        
        return folders;
    }
    
    public async Geary.Folder fetch_folder_async(Geary.Folder? parent, string folder_name,
        Cancellable? cancellable = null) throws Error {
        FolderRow? row =  yield folder_table.fetch_async(Row.INVALID_ID, folder_name, cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("\"%s\" not found in local database", folder_name);
        
        return new Geary.Sqlite.Folder(db, row);
    }
    
    public async void remove_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error {
        // TODO
    }
    
    public async void remove_many_folders_async(Gee.Set<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        // TODO
    }
    
    public async bool has_message_id_async(Geary.RFC822.MessageID message_id, out int count,
        Cancellable? cancellable = null) throws Error {
        count = yield message_table.search_message_id_count_async(message_id);
        
        return (count > 0);
    }
}

