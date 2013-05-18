/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.GenericAccount : Geary.AbstractAccount {
    private const int REFRESH_FOLDER_LIST_SEC = 10 * 60;
    
    private static Geary.FolderPath? inbox_path = null;
    private static Geary.FolderPath? outbox_path = null;
    
    private Imap.Account remote;
    private ImapDB.Account local;
    private bool open = false;
    private Gee.HashMap<FolderPath, Imap.FolderProperties> properties_map = new Gee.HashMap<
        FolderPath, Imap.FolderProperties>();
    private Gee.HashMap<FolderPath, GenericFolder> existing_folders = new Gee.HashMap<
        FolderPath, GenericFolder>();
    private Gee.HashMap<FolderPath, Folder> local_only = new Gee.HashMap<FolderPath, Folder>();
    private uint refresh_folder_timeout_id = 0;
    private bool in_refresh_enumerate = false;
    private Cancellable refresh_cancellable = new Cancellable();
    
    public GenericAccount(string name, Geary.AccountInformation information, Imap.Account remote,
        ImapDB.Account local) {
        base (name, information);
        
        this.remote = remote;
        this.local = local;
        
        this.remote.login_failed.connect(on_login_failed);
        this.remote.email_sent.connect(on_email_sent);
        
        if (inbox_path == null) {
            inbox_path = new Geary.FolderRoot(Imap.Account.INBOX_NAME, Imap.Account.ASSUMED_SEPARATOR,
                Imap.Folder.CASE_SENSITIVE);
        }
        
        if (outbox_path == null) {
            outbox_path = new SmtpOutboxFolderRoot();
        }
    }
    
    internal Imap.FolderProperties? get_properties_for_folder(FolderPath path) {
        return properties_map.get(path);
    }
    
    private void check_open() throws EngineError {
        if (!open)
            throw new EngineError.OPEN_REQUIRED("Account %s not opened", to_string());
    }
    
    public override async void open_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account %s already opened", to_string());
        
        // To prevent spurious connection failures, we make sure we have the
        // IMAP password before attempting a connection.  This might have to be
        // reworked when we allow passwordless logins.
        if (!information.imap_credentials.is_complete())
            yield information.fetch_passwords_async(Geary.CredentialsMediator.ServiceFlag.IMAP);
        
        yield local.open_async(information.settings_dir, Engine.instance.resource_dir.get_child("sql"), cancellable);
        
        // outbox is now available
        local.outbox.report_problem.connect(notify_report_problem);
        local_only.set(outbox_path, local.outbox);
        
        // need to back out local.open_async() if remote fails
        try {
            yield remote.open_async(cancellable);
        } catch (Error err) {
            // back out
            try {
                yield local.close_async(cancellable);
            } catch (Error close_err) {
                // ignored
            }
            
            throw err;
        }
        
        open = true;
        
        notify_opened();

        notify_folders_available_unavailable(local_only.values, null);
        
        // schedule an immediate sweep of the folders; once this is finished, folders will be
        // regularly enumerated
        reschedule_folder_refresh(true);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;

        notify_folders_available_unavailable(null, local_only.values);
        notify_folders_available_unavailable(null, existing_folders.values);
        
        local.outbox.report_problem.disconnect(notify_report_problem);
        
        // attempt to close both regardless of errors
        Error? local_err = null;
        try {
            yield local.close_async(cancellable);
        } catch (Error lclose_err) {
            local_err = lclose_err;
        }
        
        Error? remote_err = null;
        try {
            yield remote.close_async(cancellable);
        } catch (Error rclose_err) {
            remote_err = rclose_err;
        }

        properties_map.clear();
        existing_folders.clear();
        local_only.clear();
        open = false;
        
        if (local_err != null)
            throw local_err;
        
        if (remote_err != null)
            throw remote_err;
    }
    
    public override bool is_open() {
        return open;
    }
    
    // Subclasses should implement this to return their flavor of a GenericFolder with the
    // appropriate interfaces attached.  The returned folder should have its SpecialFolderType
    // set using either the properties from the local folder or its path.
    //
    // This won't be called to build the Outbox, but for all others (including Inbox) it will.
    protected abstract GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder);
    
    private GenericFolder build_folder(ImapDB.Folder local_folder) {
        return Geary.Collection.get_first(build_folders(new Collection.SingleItem<ImapDB.Folder>(local_folder)));
    }

    private Gee.Collection<GenericFolder> build_folders(Gee.Collection<ImapDB.Folder> local_folders) {
        Gee.ArrayList<ImapDB.Folder> folders_to_build = new Gee.ArrayList<ImapDB.Folder>();
        Gee.ArrayList<GenericFolder> built_folders = new Gee.ArrayList<GenericFolder>();
        Gee.ArrayList<GenericFolder> return_folders = new Gee.ArrayList<GenericFolder>();

        foreach(ImapDB.Folder local_folder in local_folders) {
            if (existing_folders.has_key(local_folder.get_path()))
                return_folders.add(existing_folders.get(local_folder.get_path()));
            else
                folders_to_build.add(local_folder);
        }

        foreach(ImapDB.Folder folder_to_build in folders_to_build) {
            GenericFolder folder = new_folder(folder_to_build.get_path(), remote, local, folder_to_build);
            existing_folders.set(folder.get_path(), folder);
            built_folders.add(folder);
            return_folders.add(folder);
        }

        if (built_folders.size > 0)
            notify_folders_available_unavailable(built_folders, null);
        
        return return_folders;
    }
    
    public override Gee.Collection<Geary.Folder> list_matching_folders(
        Geary.FolderPath? parent) throws Error {
        check_open();
        
        Gee.ArrayList<Geary.Folder> matches = new Gee.ArrayList<Geary.Folder>();

        foreach(FolderPath path in existing_folders.keys) {
            FolderPath? path_parent = path.get_parent();
            if ((parent == null && path_parent == null) ||
                (parent != null && path_parent != null && path_parent.equal_to(parent))) {
                matches.add(existing_folders.get(path));
            }
        }
        return matches;
    }

    public override Gee.Collection<Geary.Folder> list_folders() throws Error {
        check_open();
        
        return existing_folders.values;
    }
    
    private void reschedule_folder_refresh(bool immediate) {
        if (in_refresh_enumerate)
            return;
        
        cancel_folder_refresh();
        
        refresh_folder_timeout_id = immediate
            ? Idle.add(on_refresh_folders)
            : Timeout.add_seconds(REFRESH_FOLDER_LIST_SEC, on_refresh_folders);
    }
    
    private void cancel_folder_refresh() {
        if (refresh_folder_timeout_id != 0) {
            Source.remove(refresh_folder_timeout_id);
            refresh_folder_timeout_id = 0;
        }
    }
    
    private bool on_refresh_folders() {
        in_refresh_enumerate = true;
        enumerate_folders_async.begin(null, refresh_cancellable, on_refresh_completed);
        
        refresh_folder_timeout_id = 0;
        
        return false;
    }
    
    private void on_refresh_completed(Object? source, AsyncResult result) {
        try {
            enumerate_folders_async.end(result);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Refresh of account %s folders did not complete: %s", to_string(), err.message);
        }
        
        in_refresh_enumerate = false;
        reschedule_folder_refresh(false);
    }
    
    private async void enumerate_folders_async(Geary.FolderPath? parent, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Gee.Collection<ImapDB.Folder>? local_list = null;
        try {
            local_list = yield local.list_folders_async(parent, cancellable);
        } catch (EngineError err) {
            // don't pass on NOT_FOUND's, that means we need to go to the server for more info
            if (!(err is EngineError.NOT_FOUND))
                throw err;
        }
        
        Gee.Collection<Geary.Folder> engine_list = new Gee.ArrayList<Geary.Folder>();
        if (local_list != null && local_list.size > 0) {
            engine_list.add_all(build_folders(local_list));
        }
        
        // Add local folders (assume that local-only folders always go in root)
        if (parent == null)
            engine_list.add_all(local_only.values);
        
        background_update_folders.begin(parent, engine_list, cancellable);
    }
    
    public override Geary.ContactStore get_contact_store() {
        return local.contact_store;
    }
    
    public override async bool folder_exists_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        if (yield local.folder_exists_async(path, cancellable))
            return true;
        
        return (yield remote.list_mailbox_async(path, cancellable)) != null;
    }
    
    // TODO: This needs to be made into a single transaction
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        if (local_only.has_key(path))
            return local_only.get(path);
        
        try {
            return build_folder((ImapDB.Folder) yield local.fetch_folder_async(path, cancellable));
        } catch (EngineError err) {
            // don't thrown NOT_FOUND's, that means we need to fall through and clone from the
            // server
            if (!(err is EngineError.NOT_FOUND))
                throw err;
        }
        
        // clone the entire path
        int length = path.get_path_length();
        for (int ctr = 0; ctr < length; ctr++) {
            Geary.FolderPath folder = path.get_folder_at(ctr);
            
            if (yield local.folder_exists_async(folder))
                continue;
            
            Imap.Folder remote_folder = (Imap.Folder) yield remote.fetch_folder_async(folder,
                cancellable);
            
            yield local.clone_folder_async(remote_folder, cancellable);
        }
        
        // Fetch the local account's version of the folder for the GenericFolder
        return build_folder((ImapDB.Folder) yield local.fetch_folder_async(path, cancellable));
    }
    
    private async void background_update_folders(Geary.FolderPath? parent,
        Gee.Collection<Geary.Folder> engine_folders, Cancellable? cancellable) {
        Gee.Collection<Geary.Imap.Folder> remote_folders;
        try {
            remote_folders = yield remote.list_children_async(parent, cancellable);
        } catch (Error remote_error) {
            debug("Unable to retrieve folder list from server: %s", remote_error.message);
            
            return;
        }
        
        // update all remote folders properties in the local store and active in the system
        Gee.HashSet<Geary.FolderPath> altered_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Imap.Folder remote_folder in remote_folders) {
            // only worry about alterations if the remote is openable
            if (remote_folder.properties.is_openable.is_possible()) {
                ImapDB.Folder? local_folder = null;
                try {
                    local_folder = yield local.fetch_folder_async(remote_folder.path, cancellable);
                } catch (Error err) {
                    if (!(err is EngineError.NOT_FOUND)) {
                        debug("Unable to fetch local folder for remote %s: %s", remote_folder.path.to_string(),
                            err.message);
                    }
                }
                
                if (local_folder != null) {
                    if (remote_folder.properties.have_contents_changed(local_folder.get_properties()).is_possible())
                        altered_paths.add(remote_folder.path);
                }
            }
            
            try {
                yield local.update_folder_status_async(remote_folder, cancellable);
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.to_string(), update_error.message);
            }
        }
        
        // Get local paths of all engine (local) folders
        Gee.Set<Geary.FolderPath> local_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Geary.Folder local_folder in engine_folders)
            local_paths.add(local_folder.get_path());
        
        // Get remote paths of all remote folders
        Gee.Set<Geary.FolderPath> remote_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Geary.Imap.Folder remote_folder in remote_folders) {
            remote_paths.add(remote_folder.path);
            
            // use this iteration to add discovered properties to map
            properties_map.set(remote_folder.path, remote_folder.properties);
            
            // also use this iteration to set the local folder's special type
            // (but only promote, not demote, since getting the special folder type via its
            // properties relies on the optional XLIST extension)
            GenericFolder? local_folder = existing_folders.get(remote_folder.path);
            if (local_folder != null && local_folder.get_special_folder_type() == SpecialFolderType.NONE)
                local_folder.set_special_folder_type(remote_folder.properties.attrs.get_special_folder_type());
        }
        
        // If path in remote but not local, need to add it
        Gee.List<Geary.Imap.Folder> to_add = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Imap.Folder folder in remote_folders) {
            if (!local_paths.contains(folder.path))
                to_add.add(folder);
        }
        
        // If path in local but not remote (and isn't local-only, i.e. the Outbox), need to remove
        // it
        Gee.List<Geary.Folder>? to_remove = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Folder folder in engine_folders) {
            if (!remote_paths.contains(folder.get_path()) && !local_only.keys.contains(folder.get_path()))
                to_remove.add(folder);
        }
        
        if (to_add.size == 0)
            to_add = null;
        
        if (to_remove.size == 0)
            to_remove = null;
        
        // For folders to add, clone them and their properties locally
        if (to_add != null) {
            foreach (Geary.Imap.Folder folder in to_add) {
                try {
                    yield local.clone_folder_async(folder, cancellable);
                } catch (Error err) {
                    debug("Unable to add/remove folder %s: %s", folder.path.to_string(),
                        err.message);
                }
            }
        }
        
        // Create Geary.Folder objects for all added folders
        Gee.Collection<Geary.Folder> engine_added = null;
        if (to_add != null) {
            engine_added = new Gee.ArrayList<Geary.Folder>();

            Gee.ArrayList<ImapDB.Folder> folders_to_build = new Gee.ArrayList<ImapDB.Folder>();
            foreach (Geary.Imap.Folder remote_folder in to_add) {
                try {
                    folders_to_build.add((ImapDB.Folder) yield local.fetch_folder_async(
                        remote_folder.path, cancellable));
                } catch (Error convert_err) {
                    // This isn't fatal, but irksome ... in the future, when local folders are
                    // removed, it's possible for one to disappear between cloning it and fetching
                    // it
                    debug("Unable to fetch local folder after cloning: %s", convert_err.message);
                }
            }

            engine_added.add_all(build_folders(folders_to_build));
        }
        
        // TODO: Remove local folders no longer available remotely.
        if (to_remove != null) {
            foreach (Geary.Folder folder in to_remove) {
                debug(@"Need to remove folder $folder");
            }
        }
        
        if (engine_added != null)
            notify_folders_added_removed(engine_added, null);
        
        // report all altered folders
        if (altered_paths.size > 0) {
            Gee.ArrayList<Geary.Folder> altered = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.FolderPath path in altered_paths) {
                if (existing_folders.has_key(path))
                    altered.add(existing_folders.get(path));
                else
                    debug("Unable to report %s altered: no local representation", path.to_string());
            }
            
            if (altered.size > 0)
                notify_folders_contents_altered(altered);
        }
        
        // enumerate children of each remote folder
        foreach (Imap.Folder remote_folder in remote_folders) {
            if (remote_folder.properties.has_children.is_possible()) {
                try {
                    yield enumerate_folders_async(remote_folder.path, cancellable);
                } catch (Error err) {
                    debug("Unable to enumerate children of %s: %s", remote_folder.path.to_string(),
                        err.message);
                }
            }
        }
    }
    
    public override async void send_email_async(Geary.ComposedEmail composed,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        Geary.RFC822.Message rfc822 = new Geary.RFC822.Message.from_composed_email(composed);
        
        // don't use create_email_async() as that requires the folder be open to use
        yield local.outbox.enqueue_email_async(rfc822, cancellable);
    }

    private void on_email_sent(Geary.RFC822.Message rfc822) {
        notify_email_sent(rfc822);
    }
    
    public override async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Cancellable? cancellable = null) throws Error {
        return yield local.search_message_id_async(
            message_id, requested_fields, partial_ok, folder_blacklist, cancellable);
    }
    
    public override async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        return yield local.fetch_email_async(email_id, required_fields, cancellable);
    }
    
    private void on_login_failed(Geary.Credentials? credentials) {
        do_login_failed_async.begin(credentials);
    }
    
    private async void do_login_failed_async(Geary.Credentials? credentials) {
        try {
            if (yield information.fetch_passwords_async(CredentialsMediator.ServiceFlag.IMAP))
                return;
        } catch (Error e) {
            debug("Error prompting for IMAP password: %s", e.message);
        }
        
        notify_report_problem(Geary.Account.Problem.RECV_EMAIL_LOGIN_FAILED, null);
    }
}

