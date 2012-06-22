/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Sqlite.Account : Object {
    private class FolderReference : Geary.SmartReference {
        public Geary.FolderPath path;
        
        public FolderReference(Sqlite.Folder folder, Geary.FolderPath path) {
            base (folder);
            
            this.path = path;
        }
    }
    
    private string name;
    private ImapDatabase? db = null;
    private FolderTable? folder_table = null;
    private ImapFolderPropertiesTable? folder_properties_table = null;
    private MessageTable? message_table = null;
    private SmtpOutboxTable? outbox_table = null;
    private Gee.HashMap<Geary.FolderPath, FolderReference> folder_refs =
        new Gee.HashMap<Geary.FolderPath, FolderReference>(Hashable.hash_func, Equalable.equal_func);
    
    public Account(string username) {
        name = "SQLite account for %s".printf(username);
    }
    
    private void check_open() throws Error {
        if (db == null)
            throw new EngineError.OPEN_REQUIRED("Database not open");
    }
    
    public async void open_async(Geary.Credentials cred, File user_data_dir, File resource_dir,
        Cancellable? cancellable) throws Error {
        if (db != null)
            throw new EngineError.ALREADY_OPEN("IMAP database already open");
        
        try {
            db = new ImapDatabase(cred.user, user_data_dir, resource_dir);
            db.pre_upgrade.connect(on_pre_upgrade);
            db.post_upgrade.connect(on_post_upgrade);
            
            db.upgrade();
            
            // Need to clear duplicate folders (due to ticket #nnnn)
            clear_duplicate_folders();
        } catch (Error err) {
            warning("Unable to open database: %s", err.message);
            
            // close database before exiting
            db = null;
            
            throw err;
        }
        
        folder_table = db.get_folder_table();
        folder_properties_table = db.get_imap_folder_properties_table();
        message_table = db.get_message_table();
        outbox_table = db.get_smtp_outbox_table();
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (db == null)
            return;
        
        folder_table = null;
        folder_properties_table = null;
        message_table = null;
        outbox_table = null;
        
        db = null;
    }
    
    private async int64 fetch_id_async(Transaction? transaction, Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        FolderRow? row = yield folder_table.fetch_descend_async(transaction, path.as_list(),
            cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("Cannot find local path to %s", path.to_string());
        
        return row.id;
    }
    
    private async int64 fetch_parent_id_async(Transaction? transaction, Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        return path.is_root() ? Row.INVALID_ID : yield fetch_id_async(transaction, path.get_parent(),
            cancellable);
    }
    
    public async void clone_folder_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties? imap_folder_properties = imap_folder.get_properties();
        
        // properties *must* be available to perform a clone
        assert(imap_folder_properties != null);
        
        Transaction transaction = yield db.begin_transaction_async("Account.clone_folder_async",
            cancellable);
        
        int64 folder_id = Row.INVALID_ID;
        int64 parent_id = Row.INVALID_ID;
        for (int index = 0; index < imap_folder.get_path().get_path_length(); index++) {
            Geary.FolderPath? current_path = imap_folder.get_path().get_folder_at(index);
            assert(current_path != null);
            
            int64 current_id = Row.INVALID_ID;
            try {
                current_id = yield fetch_id_async(transaction, current_path, cancellable);
            } catch (Error err) {
                if (!(err is EngineError.NOT_FOUND))
                    throw err;
            }
            
            if (current_id == Row.INVALID_ID) {
                folder_id = yield folder_table.create_async(transaction, new FolderRow(folder_table,
                    current_path.basename, parent_id), cancellable);
            } else {
                folder_id = current_id;
            }
            
            parent_id = folder_id;
        }
        
        assert(folder_id != Row.INVALID_ID);
        
        yield folder_properties_table.create_async(transaction,
            new ImapFolderPropertiesRow.from_imap_properties(folder_properties_table, folder_id,
                imap_folder_properties), cancellable);
        
        yield transaction.commit_async(cancellable);
    }
    
    public async void update_folder_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties? imap_folder_properties = (Geary.Imap.FolderProperties?)
            imap_folder.get_properties();
        
        // properties *must* be available
        assert(imap_folder_properties != null);
        
        Transaction transaction = yield db.begin_transaction_async("Account.update_folder_async",
            cancellable);
        
        int64 parent_id = yield fetch_parent_id_async(transaction, imap_folder.get_path(), cancellable);
        
        FolderRow? row = yield folder_table.fetch_async(transaction, parent_id,
            imap_folder.get_path().basename, cancellable);
        if (row == null) {
            throw new EngineError.NOT_FOUND("Can't find in local store %s",
                imap_folder.get_path().to_string());
        }
        
        yield folder_properties_table.update_async(transaction, row.id,
            new ImapFolderPropertiesRow.from_imap_properties(folder_properties_table, row.id,
                imap_folder_properties), cancellable);
        
        FolderReference? folder_ref = folder_refs.get(imap_folder.get_path());
        if (folder_ref != null)
            ((Geary.Sqlite.Folder) folder_ref.get_reference()).update_properties(imap_folder_properties);
        
        yield transaction.commit_async(cancellable);
    }
    
    public async Gee.Collection<Geary.Sqlite.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        Transaction transaction = yield db.begin_transaction_async("Account.list_folders_async",
            cancellable);
        
        int64 parent_id = (parent != null)
            ? yield fetch_id_async(transaction, parent, cancellable)
            : Row.INVALID_ID;
        
        if (parent != null)
            assert(parent_id != Row.INVALID_ID);
        
        Gee.List<FolderRow> rows = yield folder_table.list_async(transaction, parent_id, cancellable);
        if (rows.size == 0) {
            throw new EngineError.NOT_FOUND("No local folders in %s",
                (parent != null) ? parent.get_fullpath() : "root");
        }
        
        Gee.Collection<Geary.Sqlite.Folder> folders = new Gee.ArrayList<Geary.Sqlite.Folder>();
        foreach (FolderRow row in rows) {
            ImapFolderPropertiesRow? properties = yield folder_properties_table.fetch_async(
                transaction, row.id, cancellable);
            
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
    
    public async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        try {
            int64 id = yield fetch_id_async(null, path, cancellable);
            
            return (id != Row.INVALID_ID);
        } catch (EngineError err) {
            if (err is EngineError.NOT_FOUND)
                return false;
            else
                throw err;
        }
    }
    
    public async Geary.Sqlite.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // check references table first
        Geary.Sqlite.Folder? folder = get_sqlite_folder(path);
        if (folder != null)
            return folder;
        
        Transaction transaction = yield db.begin_transaction_async("Account.fetch_folder_async",
            cancellable);
        
        // locate in database
        FolderRow? row =  yield folder_table.fetch_descend_async(transaction, path.as_list(),
            cancellable);
        if (row == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", path.to_string());
        
        // fetch it's IMAP-specific properties
        ImapFolderPropertiesRow? properties = yield folder_properties_table.fetch_async(
            transaction, row.id, cancellable);
        
        return create_sqlite_folder(row,
            (properties != null) ? properties.get_imap_folder_properties() : null, path);
    }
    
    private Geary.Sqlite.Folder? get_sqlite_folder(Geary.FolderPath path) {
        FolderReference? folder_ref = folder_refs.get(path);
        
        return (folder_ref != null) ? (Geary.Sqlite.Folder) folder_ref.get_reference() : null;
    }
    
    public SmtpOutboxTable get_outbox() {
        return outbox_table;
    }
    
    private Geary.Sqlite.Folder create_sqlite_folder(FolderRow row, Imap.FolderProperties? properties,
        Geary.FolderPath path) throws Error {
        check_open();
        
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

    private void on_pre_upgrade(int version){
        // TODO Add per-version data massaging.
    }

    private void on_post_upgrade(int version) {
        // TODO Add per-version data massaging.
    }
    
    private void clear_duplicate_folders() throws SQLHeavy.Error {
        int count = 0;
        
        // Find all folders with duplicate names
        SQLHeavy.Query dupe_name_query = db.db.prepare(
            "SELECT id, name FROM FolderTable WHERE name IN "
            + "(SELECT name FROM FolderTable GROUP BY name HAVING (COUNT(name) > 1))");
        SQLHeavy.QueryResult result = dupe_name_query.execute();
        while (!result.finished) {
            int64 id = result.fetch_int64(0);
            
            // see if any folders have this folder as a parent OR if there are messages associated
            // with this folder
            SQLHeavy.Query child_query = db.db.prepare(
                "SELECT id FROM FolderTable WHERE parent_id=?");
            child_query.bind_int64(0, id);
            SQLHeavy.QueryResult child_result = child_query.execute();
            
            SQLHeavy.Query message_query = db.db.prepare(
                "SELECT id FROM MessageLocationTable WHERE folder_id=?");
            message_query.bind_int64(0, id);
            SQLHeavy.QueryResult message_result = message_query.execute();
            
            if (child_result.finished && message_result.finished) {
                // no children, delete it
                SQLHeavy.Query child_delete = db.db.prepare(
                    "DELETE FROM FolderTable WHERE id=?");
                child_delete.bind_int64(0, id);
                
                child_delete.execute();
                count++;
            }
            
            result.next();
        }
        
        if (count > 0)
            debug("Deleted %d duplicate folders", count);
    }
}

