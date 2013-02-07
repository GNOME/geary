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
    private AccountInformation account_information;
    private ClientSessionManager session_mgr;
    private Gee.HashMap<string, string?> delims = new Gee.HashMap<string, string?>();
    private ClientSession? account_session = null;
    private NonblockingMutex cmd_mutex = new NonblockingMutex();
    private Gee.ArrayList<MailboxInformation> mailbox_collector = new Gee.ArrayList<MailboxInformation>();
    private Gee.ArrayList<StatusData> status_collector = new Gee.ArrayList<StatusData>();
    
    public signal void login_failed(Geary.Credentials cred);
    
    public Account(Geary.AccountInformation account_information) {
        name = "IMAP Account for %s".printf(account_information.imap_credentials.to_string());
        this.account_information = account_information;
        
        session_mgr = new ClientSessionManager(account_information);
        session_mgr.login_failed.connect(on_login_failed);
    }
    
    public async void open_async(Cancellable? cancellable = null) throws Error {
        yield session_mgr.open_async(cancellable);
        
        // claim a ClientSession for use for all account-level activity
        account_session = yield session_mgr.claim_authorized_session_async(cancellable);
        account_session.list.connect(on_list_data);
        account_session.status.connect(on_status_data);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (account_session != null) {
            account_session.list.disconnect(on_list_data);
            account_session.status.disconnect(on_status_data);
            
            yield session_mgr.release_session_async(account_session, cancellable);
            
            account_session = null;
        }
        
        yield session_mgr.close_async(cancellable);
    }
    
    private void on_list_data(MailboxInformation mailbox_info) {
        list_collector.add(mailbox_info);
    }
    
    private void on_status_data(StatusData status_data) {
        status_collector.add(status_data);
    }
    
    public async Gee.Collection<Geary.Imap.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
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
        check_open();
        
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        bool can_xlist = account_session.capabilities.has_capability(Capabilities.XLIST);
        
        Gee.ArrayList<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        CompletionStatusResponse response = yield send_command_async(
            new ListCommand(processed.get_fullpath(), can_xlist), list_results, null, cancellable);
        
        return response.status == Status.OK && lists_results.size == 1;
    }
    
    public async Geary.Imap.Folder fetch_folder_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        try {
            Gee.ArrayList<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
            CompletionStatusResponse response = yield send_command_async(
                new ListCommand(processed.get_fullpath(), session_has_xlist()), list_results, null,
                cancellable);
            
            if (response.status != Status.OK || list_results.size == 0)
                throw_not_found(path);
            
            // can only STATUS a mailbox that can be SELECTed
            if (!list_results[0].attrs.contains(MailboxAttribute.NO_SELECT)) {
                try {
            
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
    
    // cache w/ force flag?
    public async Gee.List<MailboxInformation>? list_command_async(FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        bool can_xlist = account_session.capabilities.has_capability(Capabilities.XLIST);
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        CompletionStatusResponse response = yield send_command_async(
            new ListCommand(processed.get_fullpath(), can_xlist), list_results, null, cancellable);
        
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server reports LIST error for path %s: %s", path.to_string(),
                response.to_string());
        }
        
        return (list_results.size > 0) ? list_results : null;
    }
    
    public async Gee.List<MailboxInformation>? list_children_command(FolderPath? parent, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        /*
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
        */
    }
    
    public async Gee.List<StatusData>? status_command_async(FolderPath path, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        CompletionStatusResponse response = yield send_command_async(
            new StatusCommand(processed.get_fullpath(), StatusDataType.all()), null, status_results,
            cancellable);
        
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server reports STATUS error for path %s: %s", path.to_string(),
                response.to_string());
        }
        
        return (status_results.size > 0) ? status_results : null;
    }
    
    private async CompletionStatusResponse send_command_async(Command cmd,
        Gee.List<MailboxInformation>? list_results, Gee.List<StatusData>? status_results,
        Cancellable? cancellable) throws Error {
        int token = yield cmd_mutex.claim_async(cancellable);
        
        CompletionStatusResponse? response = null;
        Error? err = null;
        try {
            response = yield account_session.send_command_async(cmd, cancellable);
            
            if (list_results != null)
                list_results.add_all(list_collector);
            
            list_collector.clear();
            
            if (status_results != null)
                status_results.add_all(status_collector);
            
            status_collector.clear();
        } catch (Error send_err) {
            err = send_err;
        }
        
        cmd_mutex.release(ref token);
        
        if (err != null)
            throw err;
        
        assert(response != null);
        
        return response;
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
        login_failed(account_information.imap_credentials);
    }
    
    public string to_string() {
        return name;
    }
}

