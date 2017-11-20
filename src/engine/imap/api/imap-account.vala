/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An interface between the high-level engine API and the IMAP stack.
 *
 * Because of the complexities of the IMAP protocol, this private
 * class takes common operations that a Geary.Account implementation
 * would need (in particular, {@link Geary.ImapEngine.Account} and
 * makes them into simple async calls.
 *
 * Geary.Imap.Account manages the {@link Imap.Folder} objects it
 * returns, but only in the sense that it will not create new
 * instances repeatedly.  Otherwise, it does not refresh or update the
 * Imap.Folders themselves (such as update their {@link
 * Imap.StatusData} periodically).  That's the responsibility of the
 * higher layers of the stack.
 */
private class Geary.Imap.Account : BaseObject {

    /** Determines if the IMAP account has been opened. */
    public bool is_open { get; private set; default = false; }

    /**
     * Determines if the IMAP account has a working connection.
     *
     * See {@link ClientSessionManager.is_open} for more details.
     */
    public bool is_ready { get { return this.session_mgr.is_ready; } }

    private string name;
    private AccountInformation account;
    private ClientSessionManager session_mgr;
    private uint authentication_failures = 0;
    private ClientSession? account_session = null;
    private Nonblocking.Mutex account_session_mutex = new Nonblocking.Mutex();
    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.HashMap<FolderPath, Imap.Folder> folders = new Gee.HashMap<FolderPath, Imap.Folder>();
    private Gee.List<MailboxInformation>? list_collector = null;
    private Gee.List<StatusData>? status_collector = null;
    private Gee.List<ServerData>? server_data_collector = null;


    /**
     * Fired after opening when the account has a working connection.
     *
     * This may be fired multiple times, see @{link
     * ClientSessionManager.ready} for details.
     */
    public signal void ready();

    /** Fired if a user-notifiable problem occurs. */
    public signal void report_problem(ProblemReport report);


    public Account(Geary.AccountInformation account) {
        this.name = account.id + ":imap";
        this.account = account;
        this.session_mgr = new ClientSessionManager(account);
        this.session_mgr.ready.connect(on_session_ready);
        this.session_mgr.connection_failed.connect(on_connection_failed);
        this.session_mgr.login_failed.connect(on_login_failed);
    }

    public async void open_async(Cancellable? cancellable = null) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("Imap.Account already open");

        // Reset this so we start trying to authenticate again
        this.authentication_failures = 0;

        // This will cause the session manager to open at least one
        // connection. We can't attempt to claim one straight away
        // since we might not be online.
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

    /**
     * Returns the root path for the default personal namespace.
     */
    public async FolderPath get_default_personal_namespace(Cancellable? cancellable)
    throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        if (session.personal_namespaces.is_empty) {
            throw new ImapError.INVALID("No personal namespace found");
        }

        Namespace ns = session.personal_namespaces[0];
        string prefix = ns.prefix;
        string? delim = ns.delim;
        if (delim != null && prefix.has_suffix(delim)) {
            prefix = prefix.substring(0, prefix.length - delim.length);
        }

        return new FolderRoot(prefix);
    }

    public async bool folder_exists_async(FolderPath path, Cancellable? cancellable)
    throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        Gee.List<MailboxInformation> mailboxes = yield send_list_async(session, path, false, cancellable);
        bool exists = mailboxes.is_empty;
        if (!exists) {
            this.folders.remove(path);
        }

        // XXX fire some signal here

        return exists;
    }

    /**
     * Creates a new special folder on the remote server.
     *
     * The given path must be a fully-qualified path, including
     * namespace prefix.
     *
     * If the optional special folder type is specified, and
     * CREATE-SPECIAL-USE is supported by the connection, that will be
     * used to specify the type of the new folder.
     */
    public async void create_folder_async(FolderPath path,
                                          Geary.SpecialFolderType? type,
                                          Cancellable? cancellable)
    throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        MailboxSpecifier mailbox = session.get_mailbox_for_path(path);
        bool can_create_special = session.capabilities.has_capability(Capabilities.CREATE_SPECIAL_USE);
        CreateCommand cmd = (type != null && can_create_special)
            ? new CreateCommand.special_use(mailbox, type)
            : new CreateCommand(mailbox);

        StatusResponse response = yield send_command_async(
            session, cmd, null, null, cancellable
        );

        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR(
                "Server reports error creating folder %s: %s",
                mailbox.to_string(), response.to_string()
            );
        }
    }

    /**
     * Returns a single folder from the server.
     *
     * The folder is not cached by the account and hence will not be
     * used my multiple callers or containers.  This is useful for
     * one-shot operations on the server.
     */
    public async Imap.Folder fetch_folder_async(FolderPath path, Cancellable? cancellable)
        throws Error {
        ClientSession session = yield claim_session_async(cancellable);

        Gee.List<MailboxInformation>? mailboxes = yield send_list_async(session, path, false, cancellable);
        if (mailboxes.is_empty)
            throw_not_found(path);

        Imap.Folder? folder = null;
        MailboxInformation mailbox_info = mailboxes.get(0);
        if (!mailbox_info.attrs.is_no_select) {
            StatusData status = yield send_status_async(
                session,
                mailbox_info.mailbox,
                StatusDataType.all(),
                cancellable
            );
            folder = new_selectable_folder(path, status, mailbox_info.attrs);
        } else {
            folder = new_unselectable_folder(path, mailbox_info.attrs);
        }

        return folder;
    }

    /**
     * Returns a single folder, from the account's cache or fetched fresh.
     *
     * If the folder has previously been retrieved, that is returned
     * instead of fetching it again. If not, it is fetched from the
     * server and cached for future use.
     */
    public async Imap.Folder fetch_folder_cached_async(FolderPath path,
                                                       bool refresh_counts,
                                                       Cancellable? cancellable)
    throws Error {
        check_open();

        Imap.Folder? folder = this.folders.get(path);
        if (folder == null) {
            folder = yield fetch_folder_async(path, cancellable);
            this.folders.set(path, folder);
        } else {
            if (refresh_counts && !folder.properties.attrs.is_no_select) {
                try {
                    ClientSession session = yield claim_session_async(cancellable);
                    StatusData data = yield send_status_async(
                        session,
                        session.get_mailbox_for_path(path),
                        { StatusDataType.UNSEEN, StatusDataType.MESSAGES },
                        cancellable
                     );
                    folder.properties.set_status_unseen(data.unseen);
                    folder.properties.set_status_message_count(data.messages, false);
                } catch (ImapError e) {
                    this.folders.remove(path);
                    // XXX notify someone
                    throw_not_found(path);
                }
            }
        }
        return folder;
    }

    /**
     * Returns a list of children of the given folder.
     *
     * If the parent folder is `null`, then the root of the server
     * will be listed.
     *
     * This method will perform a pipe-lined IMAP SELECT for all
     * folders found, and hence should be used with care.
     */
    public async Gee.List<Imap.Folder> fetch_child_folders_async(FolderPath? parent, Cancellable? cancellable)
    throws Error {
        ClientSession session = yield claim_session_async(cancellable);
        Gee.List<Imap.Folder> children = new Gee.ArrayList<Imap.Folder>();
        Gee.List<MailboxInformation> mailboxes = yield send_list_async(session, parent, true, cancellable);
        if (mailboxes.size == 0) {
            return children;
        }

        // Work out which folders need a STATUS and send them all
        // pipe-lined to minimise network and server latency.
        Gee.Map<MailboxSpecifier, MailboxInformation> info_map = new Gee.HashMap<
            MailboxSpecifier, MailboxInformation>();
        Gee.Map<StatusCommand, MailboxSpecifier> cmd_map = new Gee.HashMap<
            StatusCommand, MailboxSpecifier>();
        foreach (MailboxInformation mailbox_info in mailboxes) {
            if (!mailbox_info.attrs.is_no_select) {
                // Mailbox needs a SELECT
                info_map.set(mailbox_info.mailbox, mailbox_info);
                cmd_map.set(
                    new StatusCommand(mailbox_info.mailbox, StatusDataType.all()),
                    mailbox_info.mailbox
                );
            } else {
                // Mailbox is unselectable, so doesn't need a STATUS,
                // so we can create it now if it does not already
                // exist
                FolderPath path = session.get_path_for_mailbox(mailbox_info.mailbox);
                Folder? child = this.folders.get(path);
                if (child == null) {
                    child = new_unselectable_folder(path, mailbox_info.attrs);
                    this.folders.set(path, child);
                }
                children.add(child);
            }
        }

        if (!cmd_map.is_empty) {
            Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
            Gee.Map<Command, StatusResponse> responses = yield send_multiple_async(
                session,
                cmd_map.keys,
                null,
                status_results,
                cancellable
            );

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

                // Server might return results in any order, so need
                // to find it
                StatusData? status = null;
                foreach (StatusData status_data in status_results) {
                    if (status_data.mailbox.equal_to(mailbox)) {
                        status = status_data;
                        break;
                    }
                }
                if (status == null) {
                    message("Unable to get STATUS of %s: not returned from server", mailbox.to_string());
                    continue;
                }
                status_results.remove(status);

                FolderPath child_path = session.get_path_for_mailbox(mailbox_info.mailbox);
                Imap.Folder? child = this.folders.get(child_path);
                if (child != null) {
                    child.properties.update_status(status);
                } else {
                    child = new_selectable_folder(child_path, status, mailbox_info.attrs);
                    this.folders.set(child_path, child);
                }

                children.add(child);
            }

            if (status_results.size > 0)
                debug("%d STATUS results leftover", status_results.size);
        }

        return children;
    }

    internal Imap.Folder new_selectable_folder(FolderPath path, StatusData status, MailboxAttributes attrs) {
        return new Imap.Folder(
            path, new Imap.FolderProperties.status(status, attrs), this.session_mgr
        );
    }

    internal void folders_removed(Gee.Collection<FolderPath> paths) {
        foreach (FolderPath path in paths) {
            if (folders.has_key(path))
                folders.unset(path);
        }
    }

    // Claiming session in open_async() would delay opening, which make take too long ... rather,
    // this is used by the various calls to put off claiming a session until needed (which
    // possibly is long enough for ClientSessionManager to get a few ready).
    private async ClientSession claim_session_async(Cancellable? cancellable)
    throws Error {
        check_open();
        // check if available session is in good state
        if (account_session != null
            && account_session.get_protocol_state(null) != ClientSession.ProtocolState.AUTHORIZED) {
            yield drop_session_async(cancellable);
        }

        int token = yield account_session_mutex.claim_async(cancellable);

        Error? err = null;
        if (account_session == null) {
            try {
                account_session = yield session_mgr.claim_authorized_session_async(cancellable);

                account_session.list.connect(on_list_data);
                account_session.status.connect(on_status_data);
                account_session.server_data_received.connect(on_server_data_received);
                account_session.disconnected.connect(on_disconnected);
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

    private async void drop_session_async(Cancellable? cancellable) {
        debug("[%s] Dropping account session...", to_string());

        int token;
        try {
            token = yield account_session_mutex.claim_async(cancellable);
        } catch (Error err) {
            debug("Unable to claim Imap.Account session mutex: %s", err.message);

            return;
        }

        string desc = account_session != null ? account_session.to_string() : "(none)";

        if (account_session != null) {
            // disconnect signals before releasing (in particular, "disconnected" will in turn
            // reenter this method, so avoid that)
            account_session.list.disconnect(on_list_data);
            account_session.status.disconnect(on_status_data);
            account_session.server_data_received.disconnect(on_server_data_received);
            account_session.disconnected.disconnect(on_disconnected);

            debug("[%s] Releasing account session %s", to_string(), desc);

            try {
                yield session_mgr.release_session_async(account_session, cancellable);
            } catch (Error err) {
                // ignored
            }

            debug("[%s] Released account session %s", to_string(), desc);

            account_session = null;
        }

        try {
            account_session_mutex.release(ref token);
        } catch (Error err) {
            // ignored
        }

        debug("[%s] Dropped account session (%s)", to_string(), desc);
    }

    // Performs a LIST against the server, returning the results
    private async Gee.List<MailboxInformation> send_list_async(ClientSession session,
                                                               FolderPath? folder,
                                                               bool list_children,
                                                               Cancellable? cancellable)
        throws Error {
        bool can_xlist = session.capabilities.has_capability(Capabilities.XLIST);

        // Request SPECIAL-USE if available and not using XLIST
        ListReturnParameter? return_param = null;
        if (session.capabilities.supports_special_use() && !can_xlist) {
            return_param = new ListReturnParameter();
            return_param.add_special_use();
        }

        ListCommand cmd;
        if (folder == null) {
            // List the server root
            cmd = new ListCommand.wildcarded(
                "", new MailboxSpecifier("%"), can_xlist, return_param
            );
        } else {
            // List either the given folder or its children
            string specifier = session.get_mailbox_for_path(folder).name;
            if (list_children) {
                string? delim = session.get_delimiter_for_path(folder);
                if (delim == null) {
                    throw new ImapError.INVALID("Cannot list children of namespace with no delimiter");
                }
                specifier = specifier + delim + "%";
            }
            cmd = new ListCommand(new MailboxSpecifier(specifier), can_xlist, return_param);
        }

        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        StatusResponse response = yield send_command_async(session, cmd, list_results, null, cancellable);
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Unable to list children of %s: %s",
                (folder != null) ? folder.to_string() : "root", response.to_string());
        }

        // See note at ListCommand about some servers returning the
        // parent's name alongside their children ... this filters
        // this out
        if (folder != null && list_children) {
            Gee.Iterator<MailboxInformation> iter = list_results.iterator();
            while (iter.next()) {
                FolderPath list_path = session.get_path_for_mailbox(iter.get().mailbox);
                if (list_path.equal_to(folder)) {
                    debug("Removing parent from LIST results: %s", list_path.to_string());
                    iter.remove();
                }
            }
        }

        return list_results;
    }

    private async StatusData send_status_async(ClientSession session,
                                               MailboxSpecifier mailbox,
                                               StatusDataType[] status_types,
                                               Cancellable? cancellable)
    throws Error {
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        StatusResponse response = yield send_command_async(
            session,
            new StatusCommand(mailbox, status_types),
            null,
            status_results,
            cancellable
        );

        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Error fetching \"%s\" STATUS: %s",
                                             mailbox.to_string(),
                                             response.to_string());
        }

        if (status_results.size != 1) {
            throw new ImapError.INVALID("Invalid result count (%d) \"%s\" STATUS: %s",
                                        status_results.size,
                                        mailbox.to_string(),
                                        response.to_string());
        }

        return status_results[0];
    }

    private async StatusResponse send_command_async(ClientSession session,
                                                    Command cmd,
                                                    Gee.List<MailboxInformation>? list_results,
                                                    Gee.List<StatusData>? status_results,
        Cancellable? cancellable) throws Error {
        Gee.Map<Command, StatusResponse> responses = yield send_multiple_async(
            session,
            Geary.iterate<Command>(cmd).to_array_list(),
            list_results,
            status_results,
            cancellable
        );
        
        assert(responses.size == 1);
        
        return Geary.Collection.get_first(responses.values);
    }
    
    private async Gee.Map<Command, StatusResponse> send_multiple_async(
        ClientSession session,
        Gee.Collection<Command> cmds,
        Gee.List<MailboxInformation>? list_results,
        Gee.List<StatusData>? status_results,
        Cancellable? cancellable)
    throws Error {
        int token = yield cmd_mutex.claim_async(cancellable);
        
        // set up collectors
        list_collector = list_results;
        status_collector = status_results;
        
        Gee.Map<Command, StatusResponse>? responses = null;
        Error? err = null;
        try {
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

    private void check_open() throws Error {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("Imap.Account not open");
    }

    private inline Imap.Folder new_unselectable_folder(FolderPath path, MailboxAttributes attrs) {
        return new Imap.Folder(
            path, new Imap.FolderProperties(0, 0, 0, null, null, attrs), this.session_mgr
        );
    }

    private void notify_report_problem(ProblemType problem, Error? err) {
        report_problem(new ServiceProblemReport(problem, this.account, Service.IMAP, err));
    }

    [NoReturn]
    private void throw_not_found(Geary.FolderPath? path) throws EngineError {
        throw new EngineError.NOT_FOUND("Folder %s not found on %s",
            (path != null) ? path.to_string() : "root", session_mgr.to_string());
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

    private void on_session_ready() {
        // Now have a valid session, so credentials must be good
        this.authentication_failures = 0;
        ready();
    }

    private void on_connection_failed(Error error) {
        // There was an error connecting to the IMAP host
        this.authentication_failures = 0;
        if (error is ImapError.UNAUTHENTICATED) {
            // This is effectively a login failure
            on_login_failed(null);
        } else {
            notify_report_problem(ProblemType.CONNECTION_ERROR, error);
        }
    }

    private void on_login_failed(Geary.Imap.StatusResponse? response) {
        this.authentication_failures++;
        if (this.authentication_failures >= Geary.Account.AUTH_ATTEMPTS_MAX) {
            // We have tried auth too many times, so bail out
            notify_report_problem(ProblemType.LOGIN_FAILED, null);
        } else {
            // login can fail due to an invalid password hence we
            // should re-ask it but it can also fail due to server
            // inaccessibility, for instance "[UNAVAILABLE] / Maximum
            // number of connections from user+IP exceeded". In that
            // case, resetting password seems unneeded.
            bool reask_password = false;
            Error? login_error = null;
            try {
                reask_password = (
                    response == null ||
                    response.response_code == null ||
                    response.response_code.get_response_code_type().value != Geary.Imap.ResponseCodeType.UNAVAILABLE
                );
            } catch (ImapError err) {
                login_error = err;
                debug("Unable to parse ResponseCode %s: %s", response.response_code.to_string(),
                      err.message);
            }

            if (!reask_password) {
                // Either the server was unavailable, or we were unable to
                // parse the login response. Either way, indicate a
                // non-login error.
                notify_report_problem(ProblemType.SERVER_ERROR, login_error);
            } else {
                // Now, we should ask the user for their password
                this.account.fetch_passwords_async.begin(
                    ServiceFlag.IMAP, true,
                    (obj, ret) => {
                        try {
                            if (this.account.fetch_passwords_async.end(ret)) {
                                // Have a new password, so try that
                                this.session_mgr.credentials_updated();
                            } else {
                                // User cancelled, so indicate a login problem
                                notify_report_problem(ProblemType.LOGIN_FAILED, null);
                            }
                        } catch (Error err) {
                            notify_report_problem(ProblemType.GENERIC_ERROR, err);
                        }
                    });
            }
        }
    }

    public string to_string() {
        return name;
    }

}
