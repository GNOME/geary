/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.Account : Object {
    // all references to Inbox are converted to this string, purely for sanity sake when dealing
    // with Inbox's case issues
    public const string INBOX_NAME = "INBOX";
    public const string ASSUMED_SEPARATOR = "/";
    
    public signal void email_sent(Geary.RFC822.Message rfc822);
    
    private class StatusOperation : Geary.NonblockingBatchOperation {
        public ClientSessionManager session_mgr;
        public MailboxInformation mbox;
        public Geary.FolderPath path;
        
        public StatusOperation(ClientSessionManager session_mgr, MailboxInformation mbox,
            Geary.FolderPath path) {
            this.session_mgr = session_mgr;
            this.mbox = mbox;
            this.path = path;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            return yield session_mgr.status_async(path.get_fullpath(), StatusDataType.all(), cancellable);
        }
    }
    
    private string name;
    private AccountSettings settings;
    private ClientSessionManager session_mgr;
    private Gee.HashMap<string, string?> delims = new Gee.HashMap<string, string?>();
    
    public signal void login_failed(Geary.Credentials cred);
    
    public Account(Geary.AccountSettings settings) {
        name = "IMAP Account for %s".printf(settings.credentials.to_string());
        this.settings = settings;
        
        session_mgr = new ClientSessionManager(settings);
        session_mgr.login_failed.connect(on_login_failed);
    }
    
    public async void open_async(Cancellable? cancellable) throws Error {
        // Nothing to do -- ClientSessionManager deals with maintaining connections
        // TODO: Start ClientSessionManager here, not in ctor
    }
    
    public async void close_async(Cancellable? cancellable) throws Error {
        // Nothing to do -- ClientSessionManager deals with maintaining connections
        // TODO: Stop ClientSessionManager here
    }
    
    public async Gee.Collection<Geary.Imap.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        Geary.FolderPath? processed = process_path(parent, null,
            (parent != null) ? parent.get_root().default_separator : ASSUMED_SEPARATOR);
        
        Gee.Collection<MailboxInformation> mboxes;
        try {
            mboxes = (processed == null)
                ? yield session_mgr.list_roots(cancellable)
                : yield session_mgr.list(processed.get_fullpath(), processed.get_root().default_separator,
                    cancellable);
        } catch (Error err) {
            if (err is ImapError.SERVER_ERROR)
                throw_not_found(parent);
            else
                throw err;
        }
        
        Gee.Collection<Geary.Imap.Folder> folders = new Gee.ArrayList<Geary.Imap.Folder>();
        
        Geary.NonblockingBatch batch = new Geary.NonblockingBatch();
        foreach (MailboxInformation mbox in mboxes) {
            Geary.FolderPath path = process_path(processed, mbox.get_basename(), mbox.delim);
            
            // only add to delims map if root-level folder (all sub-folders respect its delimiter)
            // also use the processed name, not the one reported off the wire
            if (processed == null)
                delims.set(path.get_root().basename, mbox.delim);
            
            if (!mbox.attrs.contains(MailboxAttribute.NO_SELECT))
                batch.add(new StatusOperation(session_mgr, mbox, path));
            else
                folders.add(new Geary.Imap.Folder(session_mgr, path, null, mbox));
        }
        
        yield batch.execute_all_async(cancellable);
        
        foreach (int id in batch.get_ids()) {
            StatusOperation op = (StatusOperation) batch.get_operation(id);
            try {
                folders.add(new Geary.Imap.Folder(session_mgr, op.path,
                    (StatusResults?) batch.get_result(id), op.mbox));
            } catch (Error status_err) {
                message("Unable to fetch status for %s: %s", op.path.to_string(), status_err.message);
            }
        }
        
        return folders;
    }
    
    public async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        return yield session_mgr.folder_exists_async(processed.get_fullpath(), cancellable);
    }
    
    public async Geary.Imap.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        try {
            MailboxInformation? mbox = yield session_mgr.fetch_async(processed.get_fullpath(),
                cancellable);
            if (mbox == null)
                throw_not_found(path);
            
            StatusResults? status = null;
            if (!mbox.attrs.contains(MailboxAttribute.NO_SELECT)) {
                try {
                    status = yield session_mgr.status_async(processed.get_fullpath(),
                        StatusDataType.all(), cancellable);
                } catch (Error status_err) {
                    debug("Unable to get status for %s: %s", processed.to_string(), status_err.message);
                }
            }
            
            return new Geary.Imap.Folder(session_mgr, processed, status, mbox);
        } catch (ImapError err) {
            if (err is ImapError.SERVER_ERROR)
                throw_not_found(path);
            else
                throw err;
        }
    }
    
    [NoReturn]
    private void throw_not_found(Geary.FolderPath? path) throws EngineError {
        throw new EngineError.NOT_FOUND("Folder %s not found on %s",
            (path != null) ? path.to_string() : "root", session_mgr.to_string());
    }
    
    // This method ensures that Inbox is dealt with in a consistent fashion throughout the
    // application.
    private static Geary.FolderPath? process_path(Geary.FolderPath? parent, string? basename,
        string? delim) throws ImapError {
        bool empty_basename = String.is_empty(basename);
        
        // 1. Both null, done
        if (parent == null && empty_basename)
            return null;
        
        // 2. Parent null but basename not, create FolderRoot for Inbox
        if (parent == null && !empty_basename && basename.up() == INBOX_NAME)
            return new Geary.FolderRoot(INBOX_NAME, delim, false);
        
        // 3. Parent and basename supplied, verify parent is not Inbox, as IMAP does not allow it
        //    to have children
        if (parent != null && !empty_basename && parent.get_root().basename.up() == INBOX_NAME)
            throw new ImapError.INVALID_PATH("Inbox may not have children");
        
        // 4. Parent supplied but basename is not; if parent points to Inbox, normalize it
        if (parent != null && empty_basename && parent.basename.up() == INBOX_NAME)
            return new Geary.FolderRoot(INBOX_NAME, delim, false);
        
        // 5. Default behavior: create child of basename or basename as root, otherwise return parent
        //    unmodified
        if (parent != null && !empty_basename)
            return parent.get_child(basename);
        
        if (!empty_basename)
            return new Geary.FolderRoot(basename, delim, Folder.CASE_SENSITIVE);
        
        return parent;
    }
    
    private void on_login_failed() {
        login_failed(settings.credentials);
    }
    
    public string to_string() {
        return name;
    }
}

