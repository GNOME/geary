/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Account : Object, Geary.Account, Geary.LocalAccount {
    private MailDatabase db;
    private FolderTable folder_table;
    
    public Account(Geary.Credentials cred) {
        try {
            db = new MailDatabase(cred.user);
        } catch (Error err) {
            error("Unable to open database: %s", err.message);
        }
        
        folder_table = db.get_folder_table();
    }
    
    public async Gee.Collection<Geary.Folder> list_async(string? parent_folder,
        Cancellable? cancellable = null) throws Error {
        Gee.List<FolderRow> rows = yield folder_table.list_async(Row.INVALID_ID, cancellable);
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Sqlite.Folder>();
        foreach (FolderRow row in rows)
            folders.add(new Geary.Sqlite.Folder(row));
        
        return folders;
    }
    
    public async Geary.Folder fetch_async(string? parent_folder, string folder_name,
        Cancellable? cancellable = null) throws Error {
        FolderRow? row =  yield folder_table.fetch_async(Row.INVALID_ID, folder_name, cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", folder_name);
        
        return new Geary.Sqlite.Folder(row);
    }
    
    public async void create_async(Geary.Folder folder, Cancellable? cancellable = null) throws Error {
        yield folder_table.create_async(
            new FolderRow(folder.get_name(), folder.does_support_children(), folder.is_openable()),
            cancellable);
    }
    
    public async void create_many_async(Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        foreach (Geary.Folder folder in folders) {
            rows.add(new FolderRow(folder.get_name(), folder.does_support_children(),
                folder.is_openable()));
        }
        
        yield folder_table.create_many_async(rows, cancellable);
    }
    
    public async void remove_async(string folder, Cancellable? cancellable = null) throws Error {
        // TODO
    }
    
    public async void remove_many_async(Gee.Set<string> folders, Cancellable? cancellable = null)
        throws Error {
        // TODO
    }
}

