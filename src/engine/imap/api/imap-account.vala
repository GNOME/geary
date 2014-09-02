/* Copyright 2011-2014 Yorba Foundation
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
 * Geary.Imap.Account manages the {@link Imap.Folder} objects it returns, but only in the sense
 * that it will not create new instances repeatedly.  Otherwise, it does not refresh or update the
 * Imap.Folders themselves (such as update their {@link Imap.StatusData} periodically).
 * That's the responsibility of the higher layers of the stack.
 */

private class Geary.Imap.Account : BaseObject {
    public bool is_open { get; private set; default = false; }
    
    private string name;
    private AccountInformation account_information;
    private ClientSessionManager session_mgr;
    private ClientSession? account_session = null;
    private Nonblocking.Mutex account_session_mutex = new Nonblocking.Mutex();
    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.HashMap<FolderPath, MailboxInformation> path_to_mailbox = new Gee.HashMap<
        FolderPath, MailboxInformation>();
    private Gee.HashMap<FolderPath, Imap.Folder> folders = new Gee.HashMap<FolderPath, Imap.Folder>();
    private Gee.List<MailboxInformation>? list_collector = null;
    private Gee.List<StatusData>? status_collector = null;
    private Gee.List<ServerData>? server_data_collector = null;
    private Imap.MailboxSpecifier? inbox_specifier = null;
    
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
        
        yield drop_session_async(cancellable);
        
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
        // check if available session is in good state
        if (account_session != null && account_session.get_context(null) != ClientSession.Context.AUTHORIZED)
            yield drop_session_async(cancellable);
        
        int token = yield account_session_mutex.claim_async(cancellable);
        
        Error? err = null;
        if (account_session == null) {
            try {
                account_session = yield session_mgr.claim_authorized_session_async(cancellable);
                
                account_session.list.connect(on_list_data);
                account_session.status.connect(on_status_data);
                account_session.server_data_received.connect(on_server_data_received);
                account_session.disconnected.connect(on_disconnected);
                
                // Learn the magic XLIST <translated Inbox name> -> Inbox mapping
                if (account_session.capabilities.has_capability(Imap.Capabilities.XLIST))
                    yield determine_xlist_inbox(account_session, cancellable);
                else
                    inbox_specifier = MailboxSpecifier.inbox;
            } catch (Error claim_err) {
                err = claim_err;
            }
        }
        
        account_session_mutex.release(ref token);
        
        if (err != null) {
            if (account_session != null)
                yield drop_session_async(null);
            
            throw err;
        }
        
        return account_session;
    }
    
    private async void determine_xlist_inbox(ClientSession session, Cancellable? cancellable) throws Error {
        // can't use send_command_async() directly because this is called by claim_session_async(),
        // which is called by send_command_async()
        
        int token = yield cmd_mutex.claim_async(cancellable);
        
        // clear for now
        inbox_specifier = null;
        
        // collect server data directly for direct decoding
        server_data_collector = new Gee.ArrayList<ServerData>();
        
        Error? throw_err = null;
        try {
            Imap.StatusResponse response = yield session.send_command_async(
                new ListCommand(MailboxSpecifier.inbox, true, null), cancellable);
            if (response.status == Imap.Status.OK && server_data_collector.size > 0)
                inbox_specifier = MailboxInformation.decode(server_data_collector[0], false).mailbox;
        } catch (Error err) {
            throw_err = err;
        }
        
        server_data_collector = null;
        
        // fall back on standard name
        if (inbox_specifier == null)
            inbox_specifier = MailboxSpecifier.inbox;
        
        debug("[%s] INBOX specifier: %s", to_string(), inbox_specifier.to_string());
        
        cmd_mutex.release(ref token);
        
        if (throw_err != null)
            throw throw_err;
    }
    
    private async void drop_session_async(Cancellable? cancellable) {
        int token;
        try {
            token = yield account_session_mutex.claim_async(cancellable);
        } catch (Error err) {
            debug("Unable to claim Imap.Account session mutex: %s", err.message);
            
            return;
        }
        
        if (account_session != null) {
            try {
                yield session_mgr.release_session_async(account_session, cancellable);
            } catch (Error err) {
                // ignored
            }
            
            account_session.list.disconnect(on_list_data);
            account_session.status.disconnect(on_status_data);
            account_session.server_data_received.disconnect(on_server_data_received);
            account_session.disconnected.disconnect(on_disconnected);
            
            account_session = null;
        }
        
        try {
            account_session_mutex.release(ref token);
        } catch (Error err) {
            // ignored
        }
    }
    
    private void on_list_data(MailboxInformation mailbox_info) {
        if (list_collector != null)
            list_collector.add(mailbox_info);
    }
    
    private void on_status_data(StatusData status_data) {
        if (status_collector != null)
            status_collector.add(status_data);
    }
    
    private void on_server_data_received(ServerData server_data) {
        if (server_data_collector != null)
            server_data_collector.add(server_data);
    }
    
    private void on_disconnected() {
        drop_session_async.begin(null);
    }
    
    public async bool folder_exists_async(FolderPath path, Cancellable? cancellable) throws Error {
        return path_to_mailbox.has_key(path);
    }
    
    public async void create_folder_async(FolderPath path, Cancellable? cancellable) throws Error {
        check_open();
        
        StatusResponse response = yield send_command_async(new CreateCommand(
            new MailboxSpecifier.from_folder_path(path, null)), null, null, cancellable);
        
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Server reports error creating path %s: %s", path.to_string(),
                response.to_string());
        }
    }
    
    public async Imap.Folder fetch_folder_async(FolderPath path, out bool created,
        Cancellable? cancellable) throws Error {
        check_open();
        
        created = false;
        
        if (folders.has_key(path))
            return folders.get(path);
        
        created = true;
        
        // if not in map, use list_children_async to add it (if it exists)
        if (!path_to_mailbox.has_key(path)) {
            debug("Listing children to find %s", path.to_string());
            yield list_children_async(path.get_parent(), cancellable);
        }
        
        MailboxInformation? mailbox_info = path_to_mailbox.get(path);
        if (mailbox_info == null)
            throw_not_found(path);
        
        // construct folder path for new folder, converting XLIST Inbox name to canonical INBOX
        FolderPath folder_path = mailbox_info.get_path(inbox_specifier);
        
        Imap.Folder folder;
        if (!mailbox_info.attrs.is_no_select) {
            StatusData status = yield fetch_status_async(path, StatusDataType.all(), cancellable);
            
            folder = new Imap.Folder(folder_path, session_mgr, status, mailbox_info);
        } else {
            folder = new Imap.Folder.unselectable(folder_path, session_mgr, mailbox_info);
        }
        
        folders.set(path, folder);
        
        return folder;
    }
    
    internal void folders_removed(Gee.Collection<FolderPath> paths) {
        foreach (FolderPath path in paths) {
            if (path_to_mailbox.has_key(path))
                path_to_mailbox.unset(path);
            if (folders.has_key(path))
                folders.unset(path);
        }
    }
    
    public async int fetch_unseen_count_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();
        
        MailboxInformation? mailbox_info = path_to_mailbox.get(path);
        if (mailbox_info == null)
            throw_not_found(path);
        if (mailbox_info.attrs.is_no_select) {
            throw new EngineError.UNSUPPORTED("Can't fetch unseen count for unselectable folder %s",
                path.to_string());
        }
        
        StatusData data = yield fetch_status_async(path, { StatusDataType.UNSEEN }, cancellable);
        return data.unseen;
    }
    
    private async StatusData fetch_status_async(FolderPath path, StatusDataType[] status_types,
        Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        StatusResponse response = yield send_command_async(
            new StatusCommand(new MailboxSpecifier.from_folder_path(path, null), status_types),
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
        if (child_info == null || child_info.size == 0) {
            debug("No children found listing %s", (parent != null) ? parent.to_string() : "root");
            
            return null;
        }
        
        Gee.List<Imap.Folder> child_folders = new Gee.ArrayList<Imap.Folder>();
        
        Gee.Map<MailboxSpecifier, MailboxInformation> info_map = new Gee.HashMap<
            MailboxSpecifier, MailboxInformation>();
        Gee.Map<StatusCommand, MailboxSpecifier> cmd_map = new Gee.HashMap<
            StatusCommand, MailboxSpecifier>();
        foreach (MailboxInformation mailbox_info in child_info) {
            // if new mailbox is unselectable, don't bother doing a STATUS command
            if (mailbox_info.attrs.is_no_select) {
                Imap.Folder folder = new Imap.Folder.unselectable(mailbox_info.get_path(inbox_specifier),
                    session_mgr, mailbox_info);
                folders.set(folder.path, folder);
                child_folders.add(folder);
                
                continue;
            }
            
            info_map.set(mailbox_info.mailbox, mailbox_info);
            cmd_map.set(new StatusCommand(mailbox_info.mailbox, StatusDataType.all()),
                mailbox_info.mailbox);
        }
        
        // if no STATUS results are needed, bail out with what's been collected
        if (cmd_map.size == 0)
            return child_folders;
        
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
                message("STATUS command: %s", cmd.to_string());
                
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
            
            FolderPath folder_path = mailbox_info.get_path(inbox_specifier);
            
            // if already have an Imap.Folder for this mailbox, use that
            Imap.Folder? folder = folders.get(folder_path);
            if (folder != null) {
                folder.properties.update_status(found_status);
            } else {
                folder = new Imap.Folder(folder_path, session_mgr, found_status, mailbox_info);
                folders.set(folder.path, folder);
            }
            
            child_folders.add(folder);
        }
        
        if (status_results.size > 0)
            debug("%d STATUS results leftover", status_results.size);
        
        return child_folders;
    }
    
    private async Gee.List<MailboxInformation>? list_children_async(FolderPath? parent, Cancellable? cancellable)
        throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        bool can_xlist = session.capabilities.has_capability(Capabilities.XLIST);
        
        // Request SPECIAL-USE if available and not using XLIST
        ListReturnParameter? return_param = null;
        if (session.capabilities.supports_special_use() && !can_xlist) {
            return_param = new ListReturnParameter();
            return_param.add_special_use();
        }
        
        ListCommand cmd;
        if (parent == null) {
            cmd = new ListCommand.wildcarded("", new MailboxSpecifier("%"), can_xlist, return_param);
        } else {
            string? specifier = parent.get_fullpath(null);
            string? delim = parent.get_root().default_separator;
            if (specifier == null || delim == null) {
                throw new ImapError.INVALID("Unable to list children of %s: no delimiter specified",
                    parent.to_string());
            }
            
            specifier += specifier.has_suffix(delim) ? "%" : (delim + "%");
            
            cmd = new ListCommand(new MailboxSpecifier(specifier), can_xlist, return_param);
        }
        
        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        StatusResponse response = yield send_command_async(cmd, list_results, null, cancellable);
        
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Unable to list children of %s: %s",
                (parent != null) ? parent.to_string() : "root", response.to_string());
        }
        
        // See note at ListCommand about some servers returning the parent's name alongside their
        // children ... this filters this out
        if (parent != null) {
            Gee.Iterator<MailboxInformation> iter = list_results.iterator();
            while (iter.next()) {
                FolderPath list_path = iter.get().mailbox.to_folder_path(parent.get_root().default_separator,
                    inbox_specifier);
                if (list_path.equal_to(parent)) {
                    debug("Removing parent from LIST results: %s", list_path.to_string());
                    iter.remove();
                }
            }
        }
        
        // stash all MailboxInformation by path
        // TODO: remove any MailboxInformation for this parent that is not found (i.e. has been
        // removed on the server)
        foreach (MailboxInformation mailbox_info in list_results)
            path_to_mailbox.set(mailbox_info.get_path(inbox_specifier), mailbox_info);
        
        return (list_results.size > 0) ? list_results : null;
    }
    
    private async StatusResponse send_command_async(Command cmd,
        Gee.List<MailboxInformation>? list_results, Gee.List<StatusData>? status_results,
        Cancellable? cancellable) throws Error {
        Gee.Map<Command, StatusResponse> responses = yield send_multiple_async(
            Geary.iterate<Command>(cmd).to_array_list(), list_results, status_results,
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

