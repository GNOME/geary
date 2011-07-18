/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Account : Geary.AbstractAccount, Geary.LocalAccount {
    private class FolderReference : Geary.SmartReference {
        public Geary.FolderPath path;
        
        public FolderReference(Sqlite.Folder folder, Geary.FolderPath path) {
            base (folder);
            
            this.path = path;
        }
    }
    
    private ImapDatabase db;
    private FolderTable folder_table;
    private ImapFolderPropertiesTable folder_properties_table;
    private MessageTable message_table;
    private Gee.HashMap<Geary.FolderPath, FolderReference> folder_refs =
        new Gee.HashMap<Geary.FolderPath, FolderReference>(Hashable.hash_func, Equalable.equal_func);
    
    public Account(Geary.Credentials cred) {
        base ("SQLite account for %s".printf(cred.to_string()));
        
        try {
            db = new ImapDatabase(cred.user);
        } catch (Error err) {
            error("Unable to open database: %s", err.message);
        }
        
        folder_table = db.get_folder_table();
        folder_properties_table = db.get_imap_folder_properties_table();
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
        Geary.Imap.Folder imap_folder = (Geary.Imap.Folder) folder;
        Geary.Imap.FolderProperties? imap_folder_properties = (Geary.Imap.FolderProperties?)
            imap_folder.get_properties();
        
        // properties *must* be available to perform a clone
        assert(imap_folder_properties != null);
        
        int64 parent_id = yield fetch_parent_id_async(folder.get_path(), cancellable);
        
        int64 folder_id = yield folder_table.create_async(new FolderRow(folder_table,
            imap_folder.get_path().basename, parent_id), cancellable);
        
        yield folder_properties_table.create_async(
            new ImapFolderPropertiesRow.from_imap_properties(folder_properties_table, folder_id,
                imap_folder_properties));
    }
    
    public async void update_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error {
        Geary.Imap.Folder imap_folder = (Geary.Imap.Folder) folder;
        Geary.Imap.FolderProperties? imap_folder_properties = (Geary.Imap.FolderProperties?)
            imap_folder.get_properties();
        
        // properties *must* be available
        assert(imap_folder_properties != null);
        
        int64 parent_id = yield fetch_parent_id_async(folder.get_path(), cancellable);
        
        FolderRow? row = yield folder_table.fetch_async(parent_id, folder.get_path().basename,
            cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("Can't find in local store %s", folder.get_path().to_string());
        
        yield folder_properties_table.update_async(row.id,
            new ImapFolderPropertiesRow.from_imap_properties(folder_properties_table, row.id,
                imap_folder_properties));
        
        FolderReference? folder_ref = folder_refs.get(folder.get_path());
        if (folder_ref != null)
            ((Geary.Sqlite.Folder) folder_ref.get_reference()).update_properties(imap_folder_properties);
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
            ImapFolderPropertiesRow? properties = yield folder_properties_table.fetch_async(row.id,
                cancellable);
            
            Geary.FolderPath path = (parent != null)
                ? parent.get_child(row.name)
                : new Geary.FolderRoot(row.name, "/", Geary.Imap.Folder.CASE_SENSITIVE);
            
            Geary.Sqlite.Folder? folder = get_sqlite_folder(path);
            if (folder == null)
                folder = create_sqlite_folder(row,
                    (properties != null) ? properties.get_imap_folder_properties() : null, path);
            
            folders.add(folder);
        }
        
        return folders;
    }
    
    public override async bool folder_exists_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        try {
            int64 id = yield fetch_id_async(path, cancellable);
            
            return (id != Row.INVALID_ID);
        } catch (EngineError err) {
            if (err is EngineError.NOT_FOUND)
                return false;
            else
                throw err;
        }
    }
    
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        // check references table first
        Geary.Sqlite.Folder? folder = get_sqlite_folder(path);
        if (folder != null)
            return folder;
        
        // locate in database
        FolderRow? row =  yield folder_table.fetch_descend_async(path.as_list(), cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", path.to_string());
        
        // fetch it's IMAP-specific properties
        ImapFolderPropertiesRow? properties = yield folder_properties_table.fetch_async(row.id,
            cancellable);
        
        return create_sqlite_folder(row,
            (properties != null) ? properties.get_imap_folder_properties() : null, path);
    }
    
    public async bool has_message_id_async(Geary.RFC822.MessageID message_id, out int count,
        Cancellable? cancellable = null) throws Error {
        count = yield message_table.search_message_id_count_async(message_id);
        
        return (count > 0);
    }
    
    private Geary.Sqlite.Folder? get_sqlite_folder(Geary.FolderPath path) {
        FolderReference? folder_ref = folder_refs.get(path);
        
        return (folder_ref != null) ? (Geary.Sqlite.Folder) folder_ref.get_reference() : null;
    }
    
    private Geary.Sqlite.Folder create_sqlite_folder(FolderRow row, Imap.FolderProperties? properties,
        Geary.FolderPath path) throws Error {
        // create folder
        Geary.Sqlite.Folder folder = new Geary.Sqlite.Folder(db, row, properties, path);
        
        // build a reference to it
        FolderReference folder_ref = new FolderReference(folder, path);
        folder_ref.reference_broken.connect(on_folder_reference_broken);
        
        // add to the references table
        folder_refs.set(folder_ref.path, folder_ref);
        
        return folder;
    }
    
    private void on_folder_reference_broken(Geary.SmartReference reference) {
        FolderReference folder_ref = (FolderReference) reference;
        
        // drop from folder references table, all cleaned up
        folder_refs.unset(folder_ref.path);
    }
}

