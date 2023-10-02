/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An interface between the high-level engine API and the IMAP stack.
 *
 * Because of the complexities of the IMAP protocol, class takes
 * common operations that a Geary.Account implementation would need
 * (in particular, {@link Geary.ImapEngine.GenericAccount}) and makes
 * them into simple async calls.
 *
 * Geary.Imap.Account manages the {@link Imap.Folder} objects it
 * returns, but only in the sense that it will not create new
 * instances repeatedly.  Otherwise, it does not refresh or update the
 * Imap.Folders themselves (such as update their {@link
 * Imap.StatusData} periodically). That's the responsibility of the
 * higher layers of the stack.
 */
internal class Geary.Imap.AccountSession : Geary.Imap.SessionObject {

    private FolderRoot root;
    private Gee.HashMap<FolderPath,Imap.Folder> folders =
        new Gee.HashMap<FolderPath,Imap.Folder>();

    private Nonblocking.Mutex cmd_mutex = new Nonblocking.Mutex();
    private Gee.List<MailboxInformation>? list_collector = null;
    private Gee.List<StatusData>? status_collector = null;


    internal AccountSession(FolderRoot root, ClientSession session) {
        base(session);
        this.root = root;

        session.list.connect(on_list_data);
        session.status.connect(on_status_data);
    }

    /**
     * Returns the root path for the default personal namespace.
     */
    public async FolderPath get_default_personal_namespace(Cancellable? cancellable)
    throws Error {
        ClientSession session = get_session();
        Gee.List<Namespace> personal = session.get_personal_namespaces();
        if (personal.is_empty) {
            throw new ImapError.INVALID("No personal namespace found");
        }

        Namespace ns = personal[0];
        string prefix = ns.prefix;
        string? delim = ns.delim;
        if (delim != null && prefix.has_suffix(delim)) {
            prefix = prefix.substring(0, prefix.length - delim.length);
        }

        return Geary.String.is_empty(prefix)
            ? this.root
            : this.root.get_child(prefix);
    }

    /**
     * Determines if the given folder path appears to a valid mailbox.
     */
    public bool is_folder_path_valid(FolderPath? path) throws GLib.Error {
        bool is_valid = false;
        if (path != null) {
            ClientSession session = get_session();
            try {
                session.get_mailbox_for_path(path);
                is_valid = true;
            } catch (GLib.Error err) {
                // still not valid
            }
        }
        return is_valid;
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
                                          Geary.Folder.SpecialUse? use,
                                          Cancellable? cancellable)
    throws Error {
        ClientSession session = get_session();
        MailboxSpecifier mailbox = session.get_mailbox_for_path(path);
        bool can_create_special = session.capabilities.has_capability(Capabilities.CREATE_SPECIAL_USE);
        CreateCommand cmd = (
            use != null && can_create_special
            ? new CreateCommand.special_use(mailbox, use, cancellable)
            : new CreateCommand(mailbox, cancellable)
        );

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
     * Returns a single folder, from the account's cache or fetched fresh.
     *
     * If the folder has previously been retrieved, that is returned
     * instead of fetching it again. If not, it is fetched from the
     * server and cached for future use.
     */
    public async Imap.Folder fetch_folder_async(FolderPath path,
                                                Cancellable? cancellable)
        throws Error {
        ClientSession session = get_session();
        Imap.Folder? folder = this.folders.get(path);
        if (folder == null) {
            Gee.List<MailboxInformation>? mailboxes = yield send_list_async(
                session, path, false, cancellable
            );
            if (mailboxes.is_empty) {
                throw_not_found(path);
            }

            MailboxInformation mailbox_info = mailboxes.get(0);
            Imap.FolderProperties? props = null;
            if (!mailbox_info.attrs.is_no_select) {
                StatusData status = yield send_status_async(
                    session,
                    mailbox_info.mailbox,
                    StatusDataType.all(),
                    cancellable
                );
                props = new Imap.FolderProperties.selectable(
                    mailbox_info.attrs,
                    status,
                    session.capabilities
                );
            } else {
                props = new Imap.FolderProperties.not_selectable(mailbox_info.attrs);
            }

            folder = new Imap.Folder(path, props);
            this.folders.set(path, folder);
        }
        return folder;
    }

    /**
     * Returns a list of children of the given folder.
     *
     * This method will perform a pipe-lined IMAP SELECT for all
     * folders found, and hence should be used with care.
     */
    public async Gee.List<Folder>
        fetch_child_folders_async(FolderPath parent,
                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
        ClientSession session = get_session();
        Gee.List<Imap.Folder> children = new Gee.ArrayList<Imap.Folder>();
        Gee.List<MailboxInformation> mailboxes = yield send_list_async(
            session, parent, true, cancellable
        );
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
                    new StatusCommand(
                        mailbox_info.mailbox, StatusDataType.all(), cancellable
                    ),
                    mailbox_info.mailbox
                );
            } else {
                // Mailbox is unselectable, so doesn't need a STATUS,
                // so we can create it now if it does not already
                // exist
                FolderPath path = session.get_path_for_mailbox(
                    this.root, mailbox_info.mailbox
                );
                Folder? child = this.folders.get(path);
                if (child == null) {
                    child = new Imap.Folder(
                        path,
                        new Imap.FolderProperties.not_selectable(mailbox_info.attrs)
                    );
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
                    warning("Unable to get STATUS of %s: %s", mailbox.to_string(), response.to_string());
                    warning("STATUS command: %s", cmd.to_string());
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
                    warning("Unable to get STATUS of %s: not returned from server", mailbox.to_string());
                    continue;
                }
                status_results.remove(status);

                FolderPath child_path = session.get_path_for_mailbox(
                    this.root, mailbox_info.mailbox
                );
                Imap.Folder? child = this.folders.get(child_path);

                if (child != null) {
                    child.properties.update_status(status);
                } else {
                    child = new Imap.Folder(
                        child_path,
                        new Imap.FolderProperties.selectable(
                            mailbox_info.attrs,
                            status,
                            session.capabilities
                        )
                    );
                    this.folders.set(child_path, child);
                }

                children.add(child);
            }

            if (status_results.size > 0)
                debug("%d STATUS results leftover", status_results.size);
        }

        return children;
    }

    internal void folders_removed(Gee.Collection<FolderPath> paths) {
        foreach (FolderPath path in paths) {
            if (folders.has_key(path))
                folders.unset(path);
        }
    }

    /** {@inheritDoc} */
    public override ClientSession? close() {
        ClientSession old_session = base.close();
        if (old_session != null) {
            old_session.list.disconnect(on_list_data);
            old_session.status.disconnect(on_status_data);
        }
        return old_session;
    }

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%s, folder root: %s",
            base.to_logging_state().format_message(), // XXX this is cruddy
            this.root.to_string()
        );
    }

    // Performs a LIST against the server, returning the results
    private async Gee.List<MailboxInformation> send_list_async(ClientSession session,
                                                               FolderPath folder,
                                                               bool list_children,
                                                               Cancellable? cancellable)
        throws Error {
        // Request SPECIAL-USE or else XLIST if available
        ListReturnParameter? return_param = null;
        bool use_xlist = false;
        if (session.capabilities.supports_special_use()) {
            return_param = new ListReturnParameter();
            return_param.add_special_use();
        } else {
            use_xlist = session.capabilities.has_capability(Capabilities.XLIST);
        }

        ListCommand cmd;
        if (folder.is_root) {
            // List the server root
            cmd = new ListCommand.wildcarded(
                "", new MailboxSpecifier("%"),
                use_xlist,
                return_param,
                cancellable
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
            cmd = new ListCommand(
                new MailboxSpecifier(specifier),
                use_xlist,
                return_param,
                cancellable
            );
        }

        Gee.List<MailboxInformation> list_results = new Gee.ArrayList<MailboxInformation>();
        StatusResponse response = yield send_command_async(session, cmd, list_results, null, cancellable);
        if (response.status != Status.OK) {
            throw new ImapError.SERVER_ERROR("Unable to list children of %s: %s",
                (folder != null) ? folder.to_string() : "root", response.to_string());
        }

        // We use a hash to filter duplicated mailboxes
        Gee.HashMap<string, MailboxInformation> filtered =
            new Gee.HashMap<string, MailboxInformation>();
        foreach (MailboxInformation information in list_results) {
            // See note at ListCommand about some servers returning the
            // parent's name alongside their children ... this filters
            // this out
            if (folder != null && list_children) {
                FolderPath list_path = session.get_path_for_mailbox(
                    this.root, information.mailbox
                );
                if (list_path.equal_to(folder)) {
                    debug("Removing parent from LIST results: %s", list_path.to_string());
                    continue;
                }
            }
            filtered.set(information.mailbox.name, information);
        }

        return Geary.traverse(filtered.values).to_array_list();
    }

    private async StatusData send_status_async(ClientSession session,
                                               MailboxSpecifier mailbox,
                                               StatusDataType[] status_types,
                                               Cancellable? cancellable)
    throws Error {
        Gee.List<StatusData> status_results = new Gee.ArrayList<StatusData>();
        StatusResponse response = yield send_command_async(
            session,
            new StatusCommand(mailbox, status_types, cancellable),
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

        var response = Collection.first(responses.values);
        if (response == null) {
            throw new ImapError.SERVER_ERROR(
                "No status response received from server"
            );
        }
        return response;
    }

    private async Gee.Map<Command, StatusResponse>
        send_multiple_async(ClientSession session,
                            Gee.Collection<Command> cmds,
                            Gee.List<MailboxInformation>? list_results,
                            Gee.List<StatusData>? status_results,
                            Cancellable? cancellable)
    throws Error {
        Gee.Map<Command, StatusResponse>? responses = null;
        int token = yield this.cmd_mutex.claim_async(cancellable);

        // set up collectors
        this.list_collector = list_results;
        this.status_collector = status_results;

        Error? cmd_err = null;
        try {
            responses = yield session.send_multiple_commands_async(
                cmds, cancellable
            );
        } catch (Error err) {
            cmd_err = err;
        }

        // tear down collectors
        this.list_collector = null;
        this.status_collector = null;

        this.cmd_mutex.release(ref token);

        if (cmd_err != null) {
            throw cmd_err;
        }

        return responses;
    }

    [NoReturn]
    private void throw_not_found(Geary.FolderPath? path) throws EngineError {
        throw new EngineError.NOT_FOUND(
            "Folder not found: %s",
            (path != null) ? path.to_string() : "[root]"
        );
    }

    private void on_list_data(MailboxInformation mailbox_info) {
        if (list_collector != null)
            list_collector.add(mailbox_info);
    }

    private void on_status_data(StatusData status_data) {
        if (status_collector != null)
            status_collector.add(status_data);
    }

}
