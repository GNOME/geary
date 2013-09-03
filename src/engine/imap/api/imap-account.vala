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
    public bool is_open { get; private set; default = false; }
    
    private string name;
    private AccountInformation account_information;
    private ClientSessionManager session_mgr;
    private ClientSession? account_session = null;
    private Nonblocking.Mutex account_session_mutex = new Nonblocking.Mutex();
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
        
        is_open = true;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;
        
        int token = yield account_session_mutex.claim_async(cancellable);
        
        ClientSession? dropped = drop_session();
        if (dropped != null) {
            try {
                yield session_mgr.release_session_async(dropped, cancellable);
            } catch (Error err) {
                // ignored
            }
        }
        
        try {
            account_session_mutex.release(ref token);
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
    
    // Claiming session in open_async() would delay opening, which make take too long ... rather,
    // this is used by the various calls to put off claiming a session until needed (which
    // possibly is long enough for ClientSessionManager to get a few ready).
    private async ClientSession claim_session_async(Cancellable? cancellable) throws Error {
        int token = yield account_session_mutex.claim_async(cancellable);
        
        Error? err = null;
        if (account_session == null) {
            try {
                account_session = yield session_mgr.claim_authorized_session_async(cancellable);
                
                account_session.list.connect(on_list_data);
                account_session.status.connect(on_status_data);
                account_session.disconnected.connect(on_disconnected);
            } catch (Error claim_err) {
                err = claim_err;
            }
        }
        
        account_session_mutex.release(ref token);
        
        if (err != null)
            throw err;
        
        return account_session;
    }
    
    // Can be called locked or unlocked, but only unlocked if you know what you're doing -- i.e.
    // not yielding.
    private ClientSession? drop_session() {
        if (account_session == null)
            return null;
        
        account_session.list.disconnect(on_list_data);
        account_session.status.disconnect(on_status_data);
        account_session.disconnected.disconnect(on_disconnected);
        
        ClientSession dropped = account_session;
        account_session = null;
        
        return dropped;
    }
    
    private void on_list_data(MailboxInformation mailbox_info) {
        if (list_collector != null)
            list_collector.add(mailbox_info);
    }
    
    private void on_status_data(StatusData status_data) {
        if (status_collector != null)
            status_collector.add(status_data);
    }
    
    private void on_disconnected() {
        drop_session();
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
            
            return new Imap.Folder(session_mgr, status, mailbox_info);
        } else {
            return new Imap.Folder.unselectable(session_mgr, mailbox_info);
        }
    }
    
    private async MailboxInformation fetch_mailbox_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        
        // USE XLIST *unless* listing INBOX, as Imap.FolderPath always refers to it as "INBOX"
        // but some servers (Freemail) only respond to the translated name with XLIST
        bool can_xlist = session.capabilities.has_capability(Capabilities.XLIST);
        if (MailboxSpecifier.folder_path_is_inbox(path))
            can_xlist = false;
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        StatusResponse response = yield send_command_async(
            new ListCommand(new MailboxSpecifier.from_folder_path(path, null), can_xlist),
            list_results, null, cancellable);
        
        throw_fetch_error(response, path, list_results.size);
        
        return list_results[0];
    }
    
    private async StatusData fetch_status_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        StatusResponse response = yield send_command_async(
            new StatusCommand(new MailboxSpecifier.from_folder_path(path, null), StatusDataType.all()),
            null, status_results, cancellable);
        
        throw_fetch_error(response, path, status_results.size);
        
        return status_results[0];
    }
    
    private void throw_fetch_error(StatusResponse response, FolderPath path, int result_count)
        throws Error {
        assert(response.is_completion);
        
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
        
        Gee.List<MailboxInformation>? child_info = yield list_children_async(parent, cancellable);
        if (child_info == null || child_info.size == 0)
            return null;
        
        Gee.List<Imap.Folder> child_folders = new Gee.ArrayList<Imap.Folder>();
        
        Gee.Map<MailboxSpecifier, MailboxInformation> info_map = new Gee.HashMap<
            MailboxSpecifier, MailboxInformation>();
        Gee.Map<StatusCommand, MailboxSpecifier> cmd_map = new Gee.HashMap<
            StatusCommand, MailboxSpecifier>();
        foreach (MailboxInformation mailbox_info in child_info) {
            if (mailbox_info.attrs.contains(MailboxAttribute.NO_SELECT)) {
                child_folders.add(new Imap.Folder.unselectable(session_mgr, mailbox_info));
                
                continue;
            }
            
            info_map.set(mailbox_info.mailbox, mailbox_info);
            cmd_map.set(new StatusCommand(mailbox_info.mailbox, StatusDataType.all()),
                mailbox_info.mailbox);
        }
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        Gee.Map<Command, StatusResponse> responses = yield send_multiple_async(cmd_map.keys,
            null, status_results, cancellable);
        
        foreach (Command cmd in responses.keys) {
            StatusCommand status_cmd = (StatusCommand) cmd;
            StatusResponse response = responses.get(cmd);
            
            MailboxSpecifier mailbox = cmd_map.get(status_cmd);
            MailboxInformation mailbox_info = info_map.get(mailbox);
            
            if (response.status != Status.OK) {
                message("Unable to get STATUS of %s: %s", mailbox.to_string(), response.to_string());
                
                continue;
            }
            
            StatusData? found_status = null;
            foreach (StatusData status_data in status_results) {
                if (status_data.mailbox.equal_to(mailbox)) {
                    found_status = status_data;
                    
                    break;
                }
            }
            
            if (found_status == null) {
                message("Unable to get STATUS of %s: not returned from server", mailbox.to_string());
                
                continue;
            }
            
            status_results.remove(found_status);
            child_folders.add(new Imap.Folder(session_mgr, found_status, mailbox_info));
        }
        
        if (status_results.size > 0)
            debug("%d STATUS results leftover", status_results.size);
        
        return child_folders;
    }
    
    private async Gee.List<MailboxInformation>? list_children_async(FolderPath? parent, Cancellable? cancellable)
        throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        bool can_xlist = session.capabilities.has_capability(Capabilities.XLIST);
        
        ListCommand cmd;
        if (parent == null) {
            cmd = new ListCommand.wildcarded("", new MailboxSpecifier("%"), can_xlist);
        } else {
            string? specifier = parent.get_fullpath(null);
            string? delim = parent.get_root().default_separator;
            if (specifier == null || delim == null) {
                throw new ImapError.INVALID("Unable to list children of %s: no delimiter specified",
                    parent.to_string());
            }
            
            specifier += specifier.has_suffix(delim) ? "%" : (delim + "%");
            
            cmd = new ListCommand(new MailboxSpecifier(specifier), can_xlist);
        }
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        StatusResponse response = yield send_command_async(cmd, list_results, null, cancellable);
        
        if (response.status != Status.OK)
            throw_not_found(parent);
        
        // See note at ListCommand about some servers returning the parent's name alongside their
        // children ... this filters this out
        if (parent != null) {
            Gee.Iterator<MailboxInformation> iter = list_results.iterator();
            while (iter.next()) {
                FolderPath list_path = iter.get().mailbox.to_folder_path(parent.get_root().default_separator);
                if (list_path.equal_to(parent)) {
                    debug("Removing parent from LIST results: %s", list_path.to_string());
                    iter.remove();
                }
            }
        }
        
        return (list_results.size > 0) ? list_results : null;
    }
    
    private async StatusResponse send_command_async(Command cmd,
        Gee.List<MailboxInformation>? list_results, Gee.List<StatusData>? status_results,
        Cancellable? cancellable) throws Error {
        Gee.Map<Command, StatusResponse> responses = yield send_multiple_async(
            new Geary.Collection.SingleItem<Command>(cmd), list_results, status_results,
            cancellable);
        
        assert(responses.size == 1);
        
        return Geary.Collection.get_first(responses.values);
    }
    
    private async Gee.Map<Command, StatusResponse> send_multiple_async(
        Gee.Collection<Command> cmds, Gee.List<MailboxInformation>? list_results,
        Gee.List<StatusData>? status_results, Cancellable? cancellable) throws Error {
        int token = yield cmd_mutex.claim_async(cancellable);
        
        // set up collectors
        list_collector = list_results;
        status_collector = status_results;
        
        Gee.Map<Command, StatusResponse>? responses = null;
        Error? err = null;
        try {
            ClientSession session = yield claim_session_async(cancellable);
            responses = yield session.send_multiple_commands_async(cmds, cancellable);
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
    
    private void on_login_failed() {
        login_failed(account_information.imap_credentials);
    }
    
    public string to_string() {
        return name;
    }
}

