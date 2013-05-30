/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Provides an interface into the IMAP stack that provides a simpler interface for a
 * Geary.Account implementation.
 *
 * Because of the complexities of the IMAP protocol, this private class takes common operations
 * that a Geary.Account implementation would need (in particular, {@link Geary.ImapEngine.Account}
 * and makes them into simple async calls.
 *
 * Geary.Imap.Account does __no__ management of the {@link Imap.Folder} objects it returns.  Thus,
 * calling a fetch or list operation several times in a row will return separate Folder objects
 * each time.  It is up to the higher layers of the stack to manage these objects.
 */
private class Geary.Imap.Account : BaseObject {
    // all references to Inbox are converted to this string, purely for sanity sake when dealing
    // with Inbox's case issues
    public const string INBOX_NAME = "INBOX";
    public const string ASSUMED_SEPARATOR = "/";
    
    public bool is_open { get; private set; default = false; }
    
    private string name;
    private AccountInformation account_information;
    private ClientSessionManager session_mgr;
    private ClientSession? account_session = null;
    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.List<MailboxInformation>? list_collector = null;
    private Gee.List<StatusData>? status_collector = null;
    
    public signal void email_sent(Geary.RFC822.Message rfc822);
    
    public signal void login_failed(Geary.Credentials cred);
    
    public Account(Geary.AccountInformation account_information) {
        name = "IMAP Account for %s".printf(account_information.imap_credentials.to_string());
        this.account_information = account_information;
        this.session_mgr = new ClientSessionManager(account_information);
        
        session_mgr.login_failed.connect(on_login_failed);
    }
    
    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Imap.Account not open");
    }
    
    public async void open_async(Cancellable? cancellable = null) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("Imap.Account already open");
        
        yield session_mgr.open_async(cancellable);
        
        try {
            // claim a ClientSession for use for all account-level activity
            account_session = yield session_mgr.claim_authorized_session_async(cancellable);
            account_session.list.connect(on_list_data);
            account_session.status.connect(on_status_data);
        } catch (Error err) {
            try {
                yield session_mgr.close_async(cancellable);
            } catch (Error close_err) {
                // ignored
            }
            
            throw err;
        }
        
        is_open = true;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;
        
        account_session.list.disconnect(on_list_data);
        account_session.status.disconnect(on_status_data);
        
        try {
            yield session_mgr.release_session_async(account_session, cancellable);
        } catch (Error err) {
            // ignored
        }
        
        try {
            yield session_mgr.close_async(cancellable);
        } catch (Error err) {
            // ignored
        }
        
        is_open = false;
    }
    
    private void on_list_data(MailboxInformation mailbox_info) {
        if (list_collector != null)
            list_collector.add(mailbox_info);
    }
    
    private void on_status_data(StatusData status_data) {
        if (status_collector != null)
            status_collector.add(status_data);
    }
    
    public async bool folder_exists_async(FolderPath path, Cancellable? cancellable) throws Error {
        try {
            yield fetch_mailbox_async(path, cancellable);
            
            return true;
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                throw err;
            
            return false;
        }
    }
    
    public async Imap.Folder fetch_folder_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();
        
        MailboxInformation mailbox_info = yield fetch_mailbox_async(path, cancellable);
        
        if (!mailbox_info.attrs.contains(MailboxAttribute.NO_SELECT)) {
            StatusData status = yield fetch_status_async(path, cancellable);
            
            return new Imap.Folder(session_mgr, path, status, mailbox_info);
        } else {
            return new Imap.Folder.unselectable(session_mgr, path, mailbox_info);
        }
    }
    
    private async MailboxInformation fetch_mailbox_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID("Invalid path %s", path.to_string());
        
        bool can_xlist = account_session.capabilities.has_capability(Capabilities.XLIST);
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        CompletionStatusResponse response = yield send_command_async(
            new ListCommand(new Imap.MailboxParameter(processed.get_fullpath()), can_xlist),
            list_results, null, cancellable);
        
        throw_fetch_error(response, processed, list_results.size);
        
        return list_results[0];
    }
    
    private async StatusData fetch_status_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();
        
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID("Invalid path %s", path.to_string());
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        CompletionStatusResponse response = yield send_command_async(
            new StatusCommand(new MailboxParameter(processed.get_fullpath()), StatusDataType.all()),
            null, status_results, cancellable);
        
        throw_fetch_error(response, processed, status_results.size);
        
        return status_results[0];
    }
    
    private void throw_fetch_error(CompletionStatusResponse response, FolderPath path, int result_count)
        throws Error {
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server reports error for path %s: %s", path.to_string(),
                response.to_string());
        }
        
        if (result_count != 1) {
            throw new ImapError.INVALID("Server reports %d results for fetch of path %s: %s",
                result_count, path.to_string(), response.to_string());
        }
    }
    
    public async Gee.List<Imap.Folder>? list_child_folders_async(FolderPath? parent, Cancellable? cancellable)
        throws Error {
        check_open();
        
        Geary.FolderPath? processed = process_path(parent, null,
            (parent != null) ? parent.get_root().default_separator : null);
        
        Gee.List<MailboxInformation>? child_info = yield list_children_async(processed, cancellable);
        if (child_info == null || child_info.size == 0)
            return null;
        
        Gee.List<Imap.Folder> child_folders = new Gee.ArrayList<Imap.Folder>();
        
        Gee.Map<FolderPath, MailboxInformation> info_map = new Gee.HashMap<FolderPath, MailboxInformation>();
        Gee.Map<StatusCommand, FolderPath> cmd_map = new Gee.HashMap<StatusCommand, FolderPath>();
        foreach (MailboxInformation mailbox_info in child_info) {
            FolderPath? child_path = process_path(processed, mailbox_info.get_basename(),
                mailbox_info.delim);
            if (child_path == null)
                continue;
            
            if (mailbox_info.attrs.contains(MailboxAttribute.NO_SELECT)) {
                child_folders.add(new Imap.Folder.unselectable(session_mgr, child_path, mailbox_info));
                
                continue;
            }
            
            info_map.set(child_path, mailbox_info);
            cmd_map.set(new StatusCommand(new MailboxParameter(child_path.get_fullpath()),
                StatusDataType.all()), child_path);
        }
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        Gee.Map<Command, CompletionStatusResponse> responses = yield send_multiple_async(cmd_map.keys,
            null, status_results, cancellable);
        
        foreach (Command cmd in responses.keys) {
            StatusCommand status_cmd = (StatusCommand) cmd;
            CompletionStatusResponse response = responses.get(cmd);
            
            FolderPath child_path = cmd_map.get(status_cmd);
            MailboxInformation mailbox_info = info_map.get(child_path);
            
            if (response.status != Status.OK) {
                message("Unable to get STATUS of %s: %s", child_path.to_string(), response.to_string());
                
                continue;
            }
            
            StatusData? found_status = null;
            foreach (StatusData status_data in status_results) {
                if (status_data.mailbox == child_path.get_fullpath()) {
                    found_status = status_data;
                    
                    break;
                }
            }
            
            if (found_status == null) {
                message("Unable to get STATUS of %s: not returned from server", child_path.to_string());
                
                continue;
            }
            
            status_results.remove(found_status);
            child_folders.add(new Imap.Folder(session_mgr, child_path, found_status, mailbox_info));
        }
        
        if (status_results.size > 0)
            debug("%d STATUS results leftover", status_results.size);
        
        return child_folders;
    }
    
    private async Gee.List<MailboxInformation>? list_children_async(FolderPath? parent, Cancellable? cancellable)
        throws Error {
        Geary.FolderPath? processed = process_path(parent, null,
            (parent != null) ? parent.get_root().default_separator : ASSUMED_SEPARATOR);
        
        bool can_xlist = account_session.capabilities.has_capability(Capabilities.XLIST);
        
        ListCommand cmd;
        if (processed == null) {
            cmd = new ListCommand.wildcarded("", new MailboxParameter("%"), can_xlist);
        } else {
            string specifier = processed.get_fullpath();
            string delim = processed.get_root().default_separator;
            
            specifier += specifier.has_suffix(delim) ? "%" : (delim + "%");
            
            cmd = new ListCommand(new Imap.MailboxParameter(specifier), can_xlist);
        }
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        CompletionStatusResponse response = yield send_command_async(cmd, list_results, null,
            cancellable);
        
        if (response.status != Status.OK)
            throw_not_found(processed ?? parent);
        
        return (list_results.size > 0) ? list_results : null;
    }
    
    private async CompletionStatusResponse send_command_async(Command cmd,
        Gee.List<MailboxInformation>? list_results, Gee.List<StatusData>? status_results,
        Cancellable? cancellable) throws Error {
        Gee.Map<Command, CompletionStatusResponse> responses = yield send_multiple_async(
            new Geary.Collection.SingleItem<Command>(cmd), list_results, status_results,
            cancellable);
        
        assert(responses.size == 1);
        
        return Geary.Collection.get_first(responses.values);
    }
    
    private async Gee.Map<Command, CompletionStatusResponse> send_multiple_async(
        Gee.Collection<Command> cmds, Gee.List<MailboxInformation>? list_results,
        Gee.List<StatusData>? status_results, Cancellable? cancellable) throws Error {
        int token = yield cmd_mutex.claim_async(cancellable);
        
        // set up collectors
        list_collector = list_results;
        status_collector = status_results;
        
        Gee.Map<Command, CompletionStatusResponse>? responses = null;
        Error? err = null;
        try {
            responses = yield account_session.send_multiple_commands_async(cmds, cancellable);
        } catch (Error send_err) {
            err = send_err;
        }
        
        // disconnect collectors
        list_collector = null;
        status_collector = null;
        
        cmd_mutex.release(ref token);
        
        if (err != null)
            throw err;
        
        assert(responses != null);
        
        return responses;
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
            throw new ImapError.INVALID("Inbox may not have children");
        
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

