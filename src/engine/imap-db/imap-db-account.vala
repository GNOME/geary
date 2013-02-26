/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapDB.Account : Object {
    private class FolderReference : Geary.SmartReference {
        public Geary.FolderPath path;
        
        public FolderReference(ImapDB.Folder folder, Geary.FolderPath path) {
            base (folder);
            
            this.path = path;
        }
    }
    
    // Only available when the Account is opened
    public SmtpOutboxFolder? outbox { get; private set; default = null; }
    
    private string name;
    private AccountInformation account_information;
    private ImapDB.Database? db = null;
    private Gee.HashMap<Geary.FolderPath, FolderReference> folder_refs =
        new Gee.HashMap<Geary.FolderPath, FolderReference>(Hashable.hash_func, Equalable.equal_func);
    public ContactStore contact_store { get; private set; }
    
    public Account(Geary.AccountInformation account_information) {
        this.account_information = account_information;
        contact_store = new ContactStore();
        
        name = "IMAP database account for %s".printf(account_information.imap_credentials.user);
    }
    
    private void check_open() throws Error {
        if (db == null)
            throw new EngineError.OPEN_REQUIRED("Database not open");
    }
    
    public async void open_async(File user_data_dir, File schema_dir, Cancellable? cancellable)
        throws Error {
        if (db != null)
            throw new EngineError.ALREADY_OPEN("IMAP database already open");
        
        db = new ImapDB.Database(user_data_dir, schema_dir, account_information.email);
        
        try {
            db.open(Db.DatabaseFlags.CREATE_DIRECTORY | Db.DatabaseFlags.CREATE_FILE, null,
                cancellable);
        } catch (Error err) {
            warning("Unable to open database: %s", err.message);
            
            // close database before exiting
            db = null;
            
            throw err;
        }
        
        Geary.Account account;
        try {
            account = Geary.Engine.instance.get_account_instance(account_information);
        } catch (Error e) {
            // If they're opening an account, the engine should already be
            // open, and there should be no reason for this to fail.  Thus, if
            // we get here, it's a programmer error.
            
            error("Error finding account from its information: %s", e.message);
        }
        
        initialize_contacts(cancellable);
        
        // ImapDB.Account holds the Outbox, which is tied to the database it maintains
        outbox = new SmtpOutboxFolder(db, account);
        
        // Need to clear duplicate folders due to old bug that caused multiple folders to be
        // created in the database ... benign due to other logic, but want to prevent this from
        // happening if possible
        clear_duplicate_folders();
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        if (db == null)
            return;
        
        // close and always drop reference
        try {
            db.close(cancellable);
        } finally {
            db = null;
        }
        
        outbox = null;
    }
    
    public async void clone_folder_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties? properties = imap_folder.get_properties();
        
        // properties *must* be available to perform a clone
        assert(properties != null);
        
        Geary.FolderPath path = imap_folder.get_path();
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            // get the parent of this folder, creating parents if necessary ... ok if this fails,
            // that just means the folder has no parents
            int64 parent_id = Db.INVALID_ROWID;
            if (!do_fetch_parent_id(cx, path, true, out parent_id, cancellable)) {
                debug("Unable to find parent ID to %s clone folder", path.to_string());
                
                return Db.TransactionOutcome.ROLLBACK;
            }
            
            // create the folder object
            Db.Statement stmt = cx.prepare(
                "INSERT INTO FolderTable (name, parent_id, last_seen_total, last_seen_status_total, "
                + "uid_validity, uid_next, attributes) VALUES (?, ?, ?, ?, ?, ?)");
            stmt.bind_string(0, path.basename);
            stmt.bind_rowid(1, parent_id);
            stmt.bind_int(2, Numeric.int_floor(properties.select_examine_messages, 0));
            stmt.bind_int(3, Numeric.int_floor(properties.status_messages, 0));
            stmt.bind_int64(4, (properties.uid_validity != null) ? properties.uid_validity.value
                : Imap.UIDValidity.INVALID);
            stmt.bind_int64(5, (properties.uid_next != null) ? properties.uid_next.value
                : Imap.UID.INVALID);
            stmt.bind_string(6, properties.attrs.serialize());
            
            stmt.exec(cancellable);
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
    }
    
    public async void update_folder_async(Geary.Imap.Folder imap_folder, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.FolderProperties properties = imap_folder.get_properties();
        Geary.FolderPath path = imap_folder.get_path();
        
        yield db.exec_transaction_async(Db.TransactionType.RW, (cx) => {
            int64 parent_id;
            if (!do_fetch_parent_id(cx, path, true, out parent_id, cancellable)) {
                debug("Unable to find parent ID of %s to update properties", path.to_string());
                
                return Db.TransactionOutcome.ROLLBACK;
            }
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare(
                    "UPDATE FolderTable SET uid_validity=?, uid_next=?, attributes=? "
                    + "WHERE parent_id=? AND name=?");
                stmt.bind_int64(0, (properties.uid_validity != null) ? properties.uid_validity.value
                    : Imap.UIDValidity.INVALID);
                stmt.bind_int64(1, (properties.uid_next != null) ? properties.uid_next.value
                    : Imap.UID.INVALID);
                stmt.bind_string(2, properties.attrs.serialize());
                stmt.bind_rowid(3, parent_id);
                stmt.bind_string(4, path.basename);
            } else {
                stmt = cx.prepare(
                    "UPDATE FolderTable SET uid_validity=?, uid_next=?, attributes=? "
                    + "WHERE parent_id IS NULL AND name=?");
                stmt.bind_int64(0, (properties.uid_validity != null) ? properties.uid_validity.value
                    : Imap.UIDValidity.INVALID);
                stmt.bind_int64(1, (properties.uid_next != null) ? properties.uid_next.value
                    : Imap.UID.INVALID);
                stmt.bind_string(2, properties.attrs.serialize());
                stmt.bind_string(3, path.basename);
            }
            
            stmt.exec();
            
            if (properties.select_examine_messages >= 0) {
                do_update_last_seen_total(cx, parent_id, path.basename, properties.select_examine_messages,
                    cancellable);
            }
            
            if (properties.status_messages >= 0) {
                do_update_last_seen_status_total(cx, parent_id, path.basename, properties.status_messages,
                    cancellable);
            }
            
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);
        
        // update properties in the local folder
        ImapDB.Folder? db_folder = get_local_folder(path);
        if (db_folder != null)
            db_folder.set_properties(properties);
    }
    
    private void initialize_contacts(Cancellable? cancellable = null) throws Error {
        check_open();
        
        Gee.Collection<Contact> contacts = new Gee.LinkedList<Contact>();
        Db.TransactionOutcome outcome = db.exec_transaction(Db.TransactionType.RO,
            (context) => {
            Db.Statement statement = context.prepare(
                "SELECT email, real_name, highest_importance, normalized_email " +
                "FROM ContactTable WHERE highest_importance >= ?");
            statement.bind_int(0, ContactImportance.VISIBILITY_THRESHOLD);
            
            Db.Result result = statement.exec(cancellable);
            while (!result.finished) {
                try {
                    Contact contact = new Contact(result.string_at(0), result.string_at(1),
                        result.int_at(2), result.string_at(3));
                    contacts.add(contact);
                } catch (Geary.DatabaseError err) {
                    // We don't want to abandon loading all contacts just because there was a
                    // problem with one.
                    debug("Problem loading contact: %s", err.message);
                }
                
                result.next();
            }
                
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (outcome == Db.TransactionOutcome.DONE)
            contact_store.update_contacts(contacts);
    }
    
    public async Gee.Collection<Geary.ImapDB.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO: A better solution here would be to only pull the FolderProperties if the Folder
        // object itself doesn't already exist
        Gee.HashMap<Geary.FolderPath, int64?> id_map = new Gee.HashMap<
            Geary.FolderPath, int64?>(Hashable.hash_func, Equalable.equal_func);
        Gee.HashMap<Geary.FolderPath, Geary.Imap.FolderProperties> prop_map = new Gee.HashMap<
            Geary.FolderPath, Geary.Imap.FolderProperties>(Hashable.hash_func, Equalable.equal_func);
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            int64 parent_id = Db.INVALID_ROWID;
            if (parent != null) {
                if (!do_fetch_folder_id(cx, parent, false, out parent_id, cancellable)) {
                    debug("Unable to find folder ID for %s to list folders", parent.to_string());
                    
                    return Db.TransactionOutcome.ROLLBACK;
                }
                
                if (parent_id == Db.INVALID_ROWID)
                    throw new EngineError.NOT_FOUND("Folder %s not found", parent.to_string());
            }
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare(
                    "SELECT id, name, last_seen_total, last_seen_status_total, uid_validity, uid_next, attributes "
                    + "FROM FolderTable WHERE parent_id=?");
                stmt.bind_rowid(0, parent_id);
            } else {
                stmt = cx.prepare(
                    "SELECT id, name, last_seen_total, last_seen_status_total, uid_validity, uid_next, attributes "
                    + "FROM FolderTable WHERE parent_id IS NULL");
            }
            
            Db.Result result = stmt.exec(cancellable);
            while (!result.finished) {
                string basename = result.string_for("name");
                Geary.FolderPath path = (parent != null)
                    ? parent.get_child(basename)
                    : new Geary.FolderRoot(basename, "/", Geary.Imap.Folder.CASE_SENSITIVE);
                
                Geary.Imap.FolderProperties properties = new Geary.Imap.FolderProperties(
                    result.int_for("last_seen_total"), 0, 0,
                    new Imap.UIDValidity(result.int64_for("uid_validity")),
                    new Imap.UID(result.int64_for("uid_next")),
                    Geary.Imap.MailboxAttributes.deserialize(result.string_for("attributes")));
                properties.set_status_message_count(result.int_for("last_seen_status_total"));
                
                id_map.set(path, result.rowid_for("id"));
                prop_map.set(path, properties);
                
                result.next(cancellable);
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        assert(id_map.size == prop_map.size);
        
        if (id_map.size == 0) {
            throw new EngineError.NOT_FOUND("No local folders in %s",
                (parent != null) ? parent.get_fullpath() : "root");
        }
        
        Gee.Collection<Geary.ImapDB.Folder> folders = new Gee.ArrayList<Geary.ImapDB.Folder>();
        foreach (Geary.FolderPath path in id_map.keys) {
            Geary.ImapDB.Folder? folder = get_local_folder(path);
            if (folder == null && id_map.has_key(path) && prop_map.has_key(path))
                folder = create_local_folder(path, id_map.get(path), prop_map.get(path));
            
            folders.add(folder);
        }
        
        return folders;
    }
    
    public async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        bool exists = false;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            try {
                int64 folder_id;
                do_fetch_folder_id(cx, path, false, out folder_id, cancellable);
                
                exists = (folder_id != Db.INVALID_ROWID);
            } catch (EngineError err) {
                // treat NOT_FOUND as non-exceptional situation
                if (!(err is EngineError.NOT_FOUND))
                    throw err;
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        return exists;
    }
    
    public async Geary.ImapDB.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // check references table first
        Geary.ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null)
            return folder;
        
        int64 folder_id = Db.INVALID_ROWID;
        Imap.FolderProperties? properties = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            if (!do_fetch_folder_id(cx, path, false, out folder_id, cancellable)) {
                debug("Unable to find folder ID for %s to fetch", path.to_string());
                
                return Db.TransactionOutcome.DONE;
            }
            
            if (folder_id == Db.INVALID_ROWID)
                return Db.TransactionOutcome.DONE;
            
            Db.Statement stmt = cx.prepare(
                "SELECT last_seen_total, last_seen_status_total, uid_validity, uid_next, attributes "
                + "FROM FolderTable WHERE id=?");
            stmt.bind_rowid(0, folder_id);
            
            Db.Result results = stmt.exec(cancellable);
            if (!results.finished) {
                properties = new Imap.FolderProperties(results.int_for("last_seen_total"), 0, 0,
                    new Imap.UIDValidity(results.int64_for("uid_validity")),
                    new Imap.UID(results.int64_for("uid_next")),
                    Geary.Imap.MailboxAttributes.deserialize(results.string_for("attributes")));
                properties.set_status_message_count(results.int_for("last_seen_status_total"));
            }
            
            return Db.TransactionOutcome.DONE;
        }, cancellable);
        
        if (folder_id == Db.INVALID_ROWID || properties == null)
            throw new EngineError.NOT_FOUND("%s not found in local database", path.to_string());
        
        return create_local_folder(path, folder_id, properties);
    }
    
    private Geary.ImapDB.Folder? get_local_folder(Geary.FolderPath path) {
        FolderReference? folder_ref = folder_refs.get(path);
        
        return (folder_ref != null) ? (Geary.ImapDB.Folder) folder_ref.get_reference() : null;
    }
    
    private Geary.ImapDB.Folder create_local_folder(Geary.FolderPath path, int64 folder_id,
        Imap.FolderProperties properties) throws Error {
        // return current if already created
        ImapDB.Folder? folder = get_local_folder(path);
        if (folder != null) {
            // update properties
            folder.set_properties(properties);
            
            return folder;
        }
        
        // create folder
        folder = new Geary.ImapDB.Folder(db, path, contact_store, account_information.email, folder_id,
            properties);
        
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
    
    private void clear_duplicate_folders() {
        int count = 0;
        
        try {
            // Find all folders with duplicate names
            Db.Result result = db.query("SELECT id, name FROM FolderTable WHERE name IN "
                + "(SELECT name FROM FolderTable GROUP BY name HAVING (COUNT(name) > 1))");
            while (!result.finished) {
                int64 id = result.int64_at(0);
                
                // see if any folders have this folder as a parent OR if there are messages associated
                // with this folder
                Db.Statement child_stmt = db.prepare("SELECT id FROM FolderTable WHERE parent_id=?");
                child_stmt.bind_int64(0, id);
                Db.Result child_result = child_stmt.exec();
                
                Db.Statement message_stmt = db.prepare(
                    "SELECT id FROM MessageLocationTable WHERE folder_id=?");
                message_stmt.bind_int64(0, id);
                Db.Result message_result = message_stmt.exec();
                
                if (child_result.finished && message_result.finished) {
                    // no children, delete it
                    Db.Statement delete_stmt = db.prepare("DELETE FROM FolderTable WHERE id=?");
                    delete_stmt.bind_int64(0, id);
                    
                    delete_stmt.exec();
                    count++;
                }
                
                result.next();
            }
        } catch (Error err) {
            debug("Error attempting to clear duplicate folders from account: %s", err.message);
        }
        
        if (count > 0)
            debug("Deleted %d duplicate folders", count);
    }
    
    //
    // Transaction helper methods
    // 
    
    // If the FolderPath has no parent, returns true and folder_id will be set to Db.INVALID_ROWID.
    // If cannot create path or there is a logical problem traversing it, returns false with folder_id
    // set to Db.INVALID_ROWID.
    private bool do_fetch_folder_id(Db.Connection cx, Geary.FolderPath path, bool create, out int64 folder_id,
        Cancellable? cancellable) throws Error {
        check_open();
        
        int length = path.get_path_length();
        if (length < 0)
            throw new EngineError.BAD_PARAMETERS("Invalid path %s", path.to_string());
        
        folder_id = Db.INVALID_ROWID;
        int64 parent_id = Db.INVALID_ROWID;
        
        // walk the folder tree to the final node (which is at length - 1 - 1)
        for (int ctr = 0; ctr < length; ctr++) {
            string basename = path.get_folder_at(ctr).basename;
            
            Db.Statement stmt;
            if (parent_id != Db.INVALID_ROWID) {
                stmt = cx.prepare("SELECT id FROM FolderTable WHERE parent_id=? AND name=?");
                stmt.bind_rowid(0, parent_id);
                stmt.bind_string(1, basename);
            } else {
                stmt = cx.prepare("SELECT id FROM FolderTable WHERE parent_id IS NULL AND name=?");
                stmt.bind_string(0, basename);
            }
            
            int64 id = Db.INVALID_ROWID;
            
            Db.Result result = stmt.exec(cancellable);
            if (!result.finished) {
                id = result.rowid_at(0);
            } else if (!create) {
                debug("Unable to return folder ID for %s: not creating paths in table",
                    path.to_string());
                
                return false;
            } else {
                // not found, create it
                Db.Statement create_stmt = cx.prepare(
                    "INSERT INTO FolderTable (name, parent_id) VALUES (?, ?)");
                create_stmt.bind_string(0, basename);
                create_stmt.bind_rowid(1, parent_id);
                
                id = create_stmt.exec_insert(cancellable);
            }
            
            // watch for path loops, real bad if it happens ... could be more thorough here, but at
            // least one level of checking is better than none
            if (id == parent_id) {
                warning("Loop found in database: parent of %s is %s in FolderTable",
                    parent_id.to_string(), id.to_string());
                
                return false;
            }
            
            parent_id = id;
        }
        
        // parent_id is now the folder being searched for
        folder_id = parent_id;
        
        return true;
    }
    
    // See do_fetch_folder_id() for return semantics.
    private bool do_fetch_parent_id(Db.Connection cx, Geary.FolderPath path, bool create, out int64 parent_id,
        Cancellable? cancellable = null) throws Error {
        if (path.is_root()) {
            parent_id = Db.INVALID_ROWID;
            
            return true;
        }
        
        return do_fetch_folder_id(cx, path.get_parent(), create, out parent_id, cancellable);
    }
    
    private void do_update_last_seen_total(Db.Connection cx, int64 parent_id, string name, int total,
        Cancellable? cancellable) throws Error {
        do_update_total(cx, parent_id, name, "last_seen_total", total, cancellable);
    }
    
    private void do_update_last_seen_status_total(Db.Connection cx, int64 parent_id, string name,
        int total, Cancellable? cancellable) throws Error {
        do_update_total(cx, parent_id, name, "last_seen_status_total", total, cancellable);
    }
    
    private void do_update_total(Db.Connection cx, int64 parent_id, string name, string colname,
        int total, Cancellable? cancellable) throws Error {
        Db.Statement stmt;
        if (parent_id != Db.INVALID_ROWID) {
            stmt = cx.prepare(
                "UPDATE FolderTable SET %s=? WHERE parent_id=? AND name=?".printf(colname));
            stmt.bind_int(0, Numeric.int_floor(total, 0));
            stmt.bind_rowid(1, parent_id);
            stmt.bind_string(2, name);
        } else {
            stmt = cx.prepare(
                "UPDATE FolderTable SET %s=? WHERE parent_id IS NULL AND name=?".printf(colname));
            stmt.bind_int(0, Numeric.int_floor(total, 0));
            stmt.bind_string(1, name);
        }
        
        stmt.exec(cancellable);
    }
}

