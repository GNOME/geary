/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Account : Geary.AbstractAccount, Geary.LocalAccount {
    private MailDatabase db;
    private FolderTable folder_table;
    private MessageTable message_table;
    
    public Account(Geary.Credentials cred) {
        base ("SQLite account for %s".printf(cred.to_string()));
        
        try {
            db = new MailDatabase(cred.user);
        } catch (Error err) {
            error("Unable to open database: %s", err.message);
        }
        
        folder_table = db.get_folder_table();
        message_table = db.get_message_table();
    }
    
    public override Geary.Email.Field get_required_fields_for_writing() {
        return Geary.Email.Field.NONE;
    }
    
    private async int64 fetch_id_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        FolderRow? row = yield folder_table.fetch_descend_async(path.as_list(), cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("Cannot find local path to %s", path.to_string());
        
        return row.id;
    }
    
    private async int64 fetch_parent_id_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        return path.is_root() ? Row.INVALID_ID : yield fetch_id_async(path.get_parent(), cancellable);
    }
    
    public async void clone_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error {
        int64 parent_id = yield fetch_parent_id_async(folder.get_path(), cancellable);
        yield folder_table.create_async(new FolderRow(folder_table, folder.get_path().basename,
            parent_id), cancellable);
    }
    
    public async void clone_many_folders_async(Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        Gee.List<FolderRow> rows = new Gee.ArrayList<FolderRow>();
        foreach (Geary.Folder folder in folders) {
            int64 parent_id = yield fetch_parent_id_async(folder.get_path(), cancellable);
            rows.add(new FolderRow(db.get_folder_table(), folder.get_path().basename, parent_id));
        }
        
        yield folder_table.create_many_async(rows, cancellable);
    }
    
    public override async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        int64 parent_id = (parent != null)
            ? yield fetch_id_async(parent, cancellable)
            : Row.INVALID_ID;
        
        if (parent != null)
            assert(parent_id != Row.INVALID_ID);
        
        Gee.List<FolderRow> rows = yield folder_table.list_async(parent_id, cancellable);
        if (rows.size == 0) {
            throw new EngineError.NOT_FOUND("No local folders in %s",
                (parent != null) ? parent.get_fullpath() : "root");
        }
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Sqlite.Folder>();
        foreach (FolderRow row in rows) {
            Geary.FolderPath path = (parent != null)
                ? parent.get_child(row.name)
                : new Geary.FolderRoot(row.name, "/", Geary.Imap.Folder.CASE_SENSITIVE);
            
            folders.add(new Geary.Sqlite.Folder(db, row, path));
        }
        
        return folders;
    }
    
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        FolderRow? row =  yield folder_table.fetch_descend_async(path.as_list(), cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", path.to_string());
        
        return new Geary.Sqlite.Folder(db, row, path);
    }
    
    public async bool has_message_id_async(Geary.RFC822.MessageID message_id, out int count,
        Cancellable? cancellable = null) throws Error {
        count = yield message_table.search_message_id_count_async(message_id);
        
        return (count > 0);
    }
}

