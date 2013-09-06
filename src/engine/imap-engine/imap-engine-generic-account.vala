/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.GenericAccount : Geary.AbstractAccount {
    private const int REFRESH_FOLDER_LIST_SEC = 4 * 60;
    
    private static Geary.FolderPath? outbox_path = null;
    private static Geary.FolderPath? search_path = null;
    
    private Imap.Account remote;
    private ImapDB.Account local;
    private bool open = false;
    private Gee.HashMap<FolderPath, GenericFolder> folder_map = new Gee.HashMap<
        FolderPath, GenericFolder>();
    private Gee.HashMap<FolderPath, Folder> local_only = new Gee.HashMap<FolderPath, Folder>();
    private uint refresh_folder_timeout_id = 0;
    private bool in_refresh_enumerate = false;
    private Cancellable refresh_cancellable = new Cancellable();
    private string previous_prepared_search_query = "";
    
    public GenericAccount(string name, Geary.AccountInformation information, Imap.Account remote,
        ImapDB.Account local) {
        base (name, information);
        
        this.remote = remote;
        this.local = local;
        
        this.remote.login_failed.connect(on_login_failed);
        this.remote.email_sent.connect(on_email_sent);
        
        search_upgrade_monitor = local.search_index_monitor;
        db_upgrade_monitor = local.upgrade_monitor;
        opening_monitor = new Geary.SimpleProgressMonitor(Geary.ProgressType.ACTIVITY);
        
        if (outbox_path == null) {
            outbox_path = new SmtpOutboxFolderRoot();
        }
        
        if (search_path == null) {
            search_path = new SearchFolderRoot();
        }
    }
    
    protected override void notify_folders_available_unavailable(Gee.List<Geary.Folder>? available,
        Gee.List<Geary.Folder>? unavailable) {
        base.notify_folders_available_unavailable(available, unavailable);
        if (available != null) {
            foreach (Geary.Folder folder in available) {
                folder.email_appended.connect(notify_email_appended);
                folder.email_inserted.connect(notify_email_inserted);
                folder.email_removed.connect(notify_email_removed);
                folder.email_locally_complete.connect(notify_email_locally_complete);
                folder.email_flags_changed.connect(notify_email_flags_changed);
            }
        }
        if (unavailable != null) {
            foreach (Geary.Folder folder in unavailable) {
                folder.email_appended.disconnect(notify_email_appended);
                folder.email_inserted.disconnect(notify_email_inserted);
                folder.email_removed.disconnect(notify_email_removed);
                folder.email_locally_complete.disconnect(notify_email_locally_complete);
                folder.email_flags_changed.disconnect(notify_email_flags_changed);
            }
        }
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
        
        // Search folder.
        local_only.set(search_path, local.search_folder);
        
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

        notify_folders_available_unavailable(sort_by_path(local_only.values), null);
        
        // schedule an immediate sweep of the folders; once this is finished, folders will be
        // regularly enumerated
        reschedule_folder_refresh(true);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;

        notify_folders_available_unavailable(null, sort_by_path(local_only.values));
        notify_folders_available_unavailable(null, sort_by_path(folder_map.values));
        
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
        
        folder_map.clear();
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
    // This won't be called to build the Outbox or search folder, but for all others (including Inbox) it will.
    protected abstract GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder);
    
    // Subclasses with specific SearchFolder implementations should override
    // this to return the correct subclass.
    internal virtual SearchFolder new_search_folder() {
        return new SearchFolder(this);
    }
    
    private GenericFolder build_folder(ImapDB.Folder local_folder) {
        return Geary.Collection.get_first(build_folders(new Collection.SingleItem<ImapDB.Folder>(local_folder)));
    }

    private Gee.Collection<GenericFolder> build_folders(Gee.Collection<ImapDB.Folder> local_folders) {
        Gee.ArrayList<ImapDB.Folder> folders_to_build = new Gee.ArrayList<ImapDB.Folder>();
        Gee.ArrayList<GenericFolder> built_folders = new Gee.ArrayList<GenericFolder>();
        Gee.ArrayList<GenericFolder> return_folders = new Gee.ArrayList<GenericFolder>();
        
        foreach(ImapDB.Folder local_folder in local_folders) {
            if (folder_map.has_key(local_folder.get_path()))
                return_folders.add(folder_map.get(local_folder.get_path()));
            else
                folders_to_build.add(local_folder);
        }
        
        foreach(ImapDB.Folder folder_to_build in folders_to_build) {
            GenericFolder folder = new_folder(folder_to_build.get_path(), remote, local, folder_to_build);
            folder_map.set(folder.path, folder);
            built_folders.add(folder);
            return_folders.add(folder);
        }
        
        if (built_folders.size > 0)
            notify_folders_available_unavailable(sort_by_path(built_folders), null);
        
        return return_folders;
    }
    
    public override Gee.Collection<Geary.Folder> list_matching_folders(Geary.FolderPath? parent)
        throws Error {
        check_open();
        
        Gee.ArrayList<Geary.Folder> matches = new Gee.ArrayList<Geary.Folder>();
        
        foreach(FolderPath path in folder_map.keys) {
            FolderPath? path_parent = path.get_parent();
            if ((parent == null && path_parent == null) ||
                (parent != null && path_parent != null && path_parent.equal_to(parent))) {
                matches.add(folder_map.get(path));
            }
        }
        return matches;
    }

    public override Gee.Collection<Geary.Folder> list_folders() throws Error {
        check_open();
        Gee.HashSet<Geary.Folder> all_folders = new Gee.HashSet<Geary.Folder>();
        all_folders.add_all(folder_map.values);
        all_folders.add_all(local_only.values);
        
        return all_folders;
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
        opening_monitor.notify_start();
        enumerate_folders_async.begin(refresh_cancellable, on_refresh_completed);
        
        refresh_folder_timeout_id = 0;
        
        return false;
    }
    
    private void on_refresh_completed(Object? source, AsyncResult result) {
        opening_monitor.notify_finish();
        try {
            enumerate_folders_async.end(result);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Refresh of account %s folders did not complete: %s", to_string(), err.message);
        }
        
        in_refresh_enumerate = false;
        reschedule_folder_refresh(false);
    }
    
    private async void enumerate_folders_async(Cancellable? cancellable) throws Error {
        check_open();
        
        // get all local folders
        Gee.HashMap<FolderPath, ImapDB.Folder> local_children = yield enumerate_local_folders_async(null,
            cancellable);
        
        // convert to a list of Geary.Folder ... build_folder() also reports new folders, so this
        // gets the word out quickly
        Gee.Collection<Geary.Folder> existing_list = new Gee.ArrayList<Geary.Folder>();
        existing_list.add_all(build_folders(local_children.values));
        existing_list.add_all(local_only.values);
        
        Gee.HashMap<FolderPath, Geary.Folder> existing_folders = new Gee.HashMap<FolderPath, Geary.Folder>();
        foreach (Geary.Folder folder in existing_list)
            existing_folders.set(folder.path, folder);
        
        // get all remote (server) folder paths
        Gee.HashMap<FolderPath, Imap.Folder> remote_folders = yield enumerate_remote_folders_async(null,
            cancellable);
        
        // combine the two and make sure everything is up-to-date
        yield update_folders_async(existing_folders, remote_folders, cancellable);
    }
    
    private async Gee.HashMap<FolderPath, ImapDB.Folder> enumerate_local_folders_async(
        Geary.FolderPath? parent, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.Collection<ImapDB.Folder>? local_children = null;
        try {
            local_children = yield local.list_folders_async(parent, cancellable);
        } catch (EngineError err) {
            // don't pass on NOT_FOUND's, that means we need to go to the server for more info
            if (!(err is EngineError.NOT_FOUND))
                throw err;
        }
        
        Gee.HashMap<FolderPath, ImapDB.Folder> result = new Gee.HashMap<FolderPath, ImapDB.Folder>();
        if (local_children != null) {
            foreach (ImapDB.Folder local_child in local_children) {
                result.set(local_child.get_path(), local_child);
                Collection.map_set_all<FolderPath, ImapDB.Folder>(result,
                    yield enumerate_local_folders_async(local_child.get_path(), cancellable));
            }
        }
        
        return result;
    }
    
    private async Gee.HashMap<FolderPath, Imap.Folder> enumerate_remote_folders_async(
        Geary.FolderPath? parent, Cancellable? cancellable) throws Error {
        check_open();
        
        Gee.List<Imap.Folder>? remote_children = null;
        try {
            remote_children = yield remote.list_child_folders_async(parent, cancellable);
        } catch (Error err) {
            // ignore everything but I/O errors
            if (err is IOError)
                throw err;
        }
        
        Gee.HashMap<FolderPath, Imap.Folder> result = new Gee.HashMap<FolderPath, Imap.Folder>();
        if (remote_children != null) {
            foreach (Imap.Folder remote_child in remote_children) {
                result.set(remote_child.path, remote_child);
                if (remote_child.properties.has_children.is_possible()) {
                    Collection.map_set_all<FolderPath, Imap.Folder>(result,
                        yield enumerate_remote_folders_async(remote_child.path, cancellable));
                }
            }
        }
        
        return result;
    }
    
    public override Geary.ContactStore get_contact_store() {
        return local.contact_store;
    }
    
    public override async bool folder_exists_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        if (yield local.folder_exists_async(path, cancellable))
            return true;
        
        return yield remote.folder_exists_async(path, cancellable);
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
    
    private async void update_folders_async(Gee.Map<FolderPath, Geary.Folder> existing_folders,
        Gee.Map<FolderPath, Imap.Folder> remote_folders, Cancellable? cancellable) {
        // update all remote folders properties in the local store and active in the system
        Gee.HashSet<Geary.FolderPath> altered_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Imap.Folder remote_folder in remote_folders.values) {
            GenericFolder? generic_folder = existing_folders.get(remote_folder.path)
                as GenericFolder;
            if (generic_folder == null)
                continue;
            
            // only worry about alterations if the remote is openable
            if (remote_folder.properties.is_openable.is_possible()) {
                ImapDB.Folder local_folder = generic_folder.local_folder;
                
                if (remote_folder.properties.have_contents_changed(local_folder.get_properties(),
                    generic_folder.to_string())) {
                    altered_paths.add(remote_folder.path);
                }
            }
            
            // always update, openable or not; have the folder update the UID info the next time
            // it's opened
            try {
                yield local.update_folder_status_async(remote_folder, false, cancellable);
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.to_string(), update_error.message);
            }
            
            // set the engine folder's special type
            // (but only promote, not demote, since getting the special folder type via its
            // properties relies on the optional XLIST extension)
            // use this iteration to add discovered properties to map
            if (generic_folder.special_folder_type == SpecialFolderType.NONE)
                generic_folder.set_special_folder_type(remote_folder.properties.attrs.get_special_folder_type());
        }
        
        // If path in remote but not local, need to add it
        Gee.List<Imap.Folder>? to_add = new Gee.ArrayList<Imap.Folder>();
        foreach (Imap.Folder remote_folder in remote_folders.values) {
            if (!existing_folders.has_key(remote_folder.path))
                to_add.add(remote_folder);
        }
        
        // If path in local but not remote (and isn't local-only, i.e. the Outbox), need to remove it
        Gee.List<Geary.Folder>? to_remove = new Gee.ArrayList<Geary.Folder>();
        foreach (Geary.FolderPath existing_path in existing_folders.keys) {
            if (!remote_folders.has_key(existing_path) && !local_only.has_key(existing_path))
                to_remove.add(existing_folders.get(existing_path));
        }
        
        // For folders to add, clone them and their properties locally
        foreach (Geary.Imap.Folder remote_folder in to_add) {
            try {
                yield local.clone_folder_async(remote_folder, cancellable);
            } catch (Error err) {
                debug("Unable to add/remove folder %s to local store: %s", remote_folder.path.to_string(),
                    err.message);
            }
        }
        
        // Create Geary.Folder objects for all added folders
        Gee.ArrayList<ImapDB.Folder> folders_to_build = new Gee.ArrayList<ImapDB.Folder>();
        foreach (Geary.Imap.Folder remote_folder in to_add) {
            try {
                folders_to_build.add(yield local.fetch_folder_async(remote_folder.path, cancellable));
            } catch (Error convert_err) {
                // This isn't fatal, but irksome ... in the future, when local folders are
                // removed, it's possible for one to disappear between cloning it and fetching
                // it
                debug("Unable to fetch local folder after cloning: %s", convert_err.message);
            }
        }
        Gee.Collection<Geary.Folder> engine_added = new Gee.ArrayList<Geary.Folder>();
        engine_added.add_all(build_folders(folders_to_build));
        
        // TODO: Remove local folders no longer available remotely.
        foreach (Geary.Folder folder in to_remove)
            debug(@"Need to remove folder $folder");
        
        if (engine_added.size > 0)
            notify_folders_added_removed(sort_by_path(engine_added), null);
        
        // report all altered folders
        if (altered_paths.size > 0) {
            Gee.ArrayList<Geary.Folder> altered = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.FolderPath altered_path in altered_paths) {
                if (existing_folders.has_key(altered_path))
                    altered.add(existing_folders.get(altered_path));
                else
                    debug("Unable to report %s altered: no local representation", altered_path.to_string());
            }
            
            if (altered.size > 0)
                notify_folders_contents_altered(altered);
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
    
    private ImapDB.EmailIdentifier check_id(Geary.EmailIdentifier id) throws EngineError {
        ImapDB.EmailIdentifier? imapdb_id = id as ImapDB.EmailIdentifier;
        if (imapdb_id == null)
            throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not from ImapDB folder", id.to_string());
        
        return imapdb_id;
    }
    
    private Gee.Collection<ImapDB.EmailIdentifier> check_ids(Gee.Collection<Geary.EmailIdentifier> ids)
        throws EngineError {
        foreach (Geary.EmailIdentifier id in ids) {
            if (!(id is ImapDB.EmailIdentifier))
                throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not from ImapDB folder", id.to_string());
        }
        
        return (Gee.Collection<ImapDB.EmailIdentifier>) ids;
    }
    
    public override async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Cancellable? cancellable = null) throws Error {
        return yield local.search_message_id_async(
            message_id, requested_fields, partial_ok, folder_blacklist, cancellable);
    }
    
    public override async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        return yield local.fetch_email_async(check_id(email_id), required_fields, cancellable);
    }
    
    public override async Gee.Collection<Geary.EmailIdentifier>? local_search_async(string query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error {
        if (offset < 0)
            throw new EngineError.BAD_PARAMETERS("Offset must not be negative");
        
        previous_prepared_search_query = local.prepare_search_query(query);
        
        return yield local.search_async(previous_prepared_search_query,
            limit, offset, folder_blacklist, search_ids, cancellable);
    }
    
    public override async Gee.Collection<string>? get_search_matches_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        return yield local.get_search_matches_async(previous_prepared_search_query, check_ids(ids),
            cancellable);
    }
    
    public override async Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? get_containing_folders_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        // TODO: also handle other types of EmailIdentifiers, not just ImapDB.
        return yield local.get_containing_folders_async(check_ids(ids), cancellable);
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

