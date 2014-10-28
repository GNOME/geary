/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.GenericAccount : Geary.AbstractAccount {
    private const int REFRESH_FOLDER_LIST_SEC = 2 * 60;
    private const int REFRESH_UNSEEN_SEC = 1;
    
    private static Geary.FolderPath? outbox_path = null;
    private static Geary.FolderPath? search_path = null;
    
    private Imap.Account remote;
    private ImapDB.Account local;
    private bool open = false;
    private Gee.HashMap<FolderPath, MinimalFolder> folder_map = new Gee.HashMap<
        FolderPath, MinimalFolder>();
    private Gee.HashMap<FolderPath, Folder> local_only = new Gee.HashMap<FolderPath, Folder>();
    private Gee.HashMap<FolderPath, uint> refresh_unseen_timeout_ids
        = new Gee.HashMap<FolderPath, uint>();
    private Gee.HashSet<Geary.Folder> in_refresh_unseen = new Gee.HashSet<Geary.Folder>();
    private uint refresh_folder_timeout_id = 0;
    private bool in_refresh_enumerate = false;
    private Cancellable refresh_cancellable = new Cancellable();
    private bool awaiting_credentials = false;
    
    public GenericAccount(string name, Geary.AccountInformation information, bool can_support_archive,
        Imap.Account remote, ImapDB.Account local) {
        base (name, information, can_support_archive);
        
        this.remote = remote;
        this.local = local;
        
        this.remote.login_failed.connect(on_login_failed);
        this.local.email_sent.connect(on_email_sent);
        
        search_upgrade_monitor = local.search_index_monitor;
        db_upgrade_monitor = local.upgrade_monitor;
        opening_monitor = new Geary.ReentrantProgressMonitor(Geary.ProgressType.ACTIVITY);
        sending_monitor = local.sending_monitor;
        
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
    
    protected override void notify_email_appended(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_appended(folder, ids);
        reschedule_unseen_update(folder);
    }
    
    protected override void notify_email_inserted(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_inserted(folder, ids);
        reschedule_unseen_update(folder);
    }
    
    protected override void notify_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_removed(folder, ids);
        reschedule_unseen_update(folder);
    }
    
    protected override void notify_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        base.notify_email_flags_changed(folder, flag_map);
        reschedule_unseen_update(folder);
    }
    
    private void check_open() throws EngineError {
        if (!open)
            throw new EngineError.OPEN_REQUIRED("Account %s not opened", to_string());
    }
    
    public override async void open_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account %s already opened", to_string());
        
        opening_monitor.notify_start();
        
        Error? throw_err = null;
        try {
            yield internal_open_async(cancellable);
        } catch (Error err) {
            throw_err = err;
        }
        
        opening_monitor.notify_finish();
        
        if (throw_err != null)
            throw throw_err;
    }
    
    private async void internal_open_async(Cancellable? cancellable) throws Error {
        try {
            yield local.open_async(information.settings_dir, Engine.instance.resource_dir.get_child("sql"),
                cancellable);
        } catch (Error err) {
            // convert database-open errors
            if (err is DatabaseError.CORRUPT)
                throw new EngineError.CORRUPT("%s", err.message);
            else if (err is DatabaseError.ACCESS)
                throw new EngineError.PERMISSIONS("%s", err.message);
            else if (err is DatabaseError.SCHEMA_VERSION)
                throw new EngineError.VERSION("%s", err.message);
            else
                throw err;
        }
        
        // outbox is now available
        local.outbox.report_problem.connect(notify_report_problem);
        local_only.set(outbox_path, local.outbox);
        
        // Search folder.
        local_only.set(search_path, local.search_folder);
        
        // To prevent spurious connection failures, we make sure we have the
        // IMAP password before attempting a connection.  This might have to be
        // reworked when we allow passwordless logins.
        if (!information.imap_credentials.is_complete())
            yield information.fetch_passwords_async(ServiceFlag.IMAP);
        
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
    
    public override async void rebuild_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account cannot be open during rebuild");
        
        message("%s: Rebuilding account local data", to_string());
        
        // get all the storage locations associated with this Account
        File db_file;
        File attachments_dir;
        ImapDB.Account.get_imap_db_storage_locations(information.settings_dir, out db_file,
            out attachments_dir);
        
        if (yield Files.query_exists_async(db_file, cancellable)) {
            message("%s: Deleting database file %s...", to_string(), db_file.get_path());
            yield db_file.delete_async(Priority.DEFAULT, cancellable);
        }
        
        if (yield Files.query_exists_async(attachments_dir, cancellable)) {
            message("%s: Deleting attachments directory %s...", to_string(), attachments_dir.get_path());
            yield Files.recursive_delete_async(attachments_dir, cancellable);
        }
        
        message("%s: Rebuild complete", to_string());
    }
    
    // Subclasses should implement this to return their flavor of a MinimalFolder with the
    // appropriate interfaces attached.  The returned folder should have its SpecialFolderType
    // set using either the properties from the local folder or its path.
    //
    // This won't be called to build the Outbox or search folder, but for all others (including Inbox) it will.
    protected abstract MinimalFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder);
    
    // Subclasses with specific SearchFolder implementations should override
    // this to return the correct subclass.
    internal virtual SearchFolder new_search_folder() {
        return new SearchFolder(this);
    }
    
    private MinimalFolder build_folder(ImapDB.Folder local_folder) {
        return Geary.Collection.get_first(build_folders(
            Geary.iterate<ImapDB.Folder>(local_folder).to_array_list()));
    }

    private Gee.Collection<MinimalFolder> build_folders(Gee.Collection<ImapDB.Folder> local_folders) {
        Gee.ArrayList<ImapDB.Folder> folders_to_build = new Gee.ArrayList<ImapDB.Folder>();
        Gee.ArrayList<MinimalFolder> built_folders = new Gee.ArrayList<MinimalFolder>();
        Gee.ArrayList<MinimalFolder> return_folders = new Gee.ArrayList<MinimalFolder>();
        
        foreach(ImapDB.Folder local_folder in local_folders) {
            if (folder_map.has_key(local_folder.get_path()))
                return_folders.add(folder_map.get(local_folder.get_path()));
            else
                folders_to_build.add(local_folder);
        }
        
        foreach(ImapDB.Folder folder_to_build in folders_to_build) {
            MinimalFolder folder = new_folder(folder_to_build.get_path(), remote, local, folder_to_build);
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
        
        return Geary.traverse<FolderPath>(folder_map.keys)
            .filter(p => {
                FolderPath? path_parent = p.get_parent();
                return ((parent == null && path_parent == null) ||
                    (parent != null && path_parent != null && path_parent.equal_to(parent)));
            })
            .map<Geary.Folder>(p => folder_map.get(p))
            .to_array_list();
    }

    public override Gee.Collection<Geary.Folder> list_folders() throws Error {
        check_open();
        Gee.HashSet<Geary.Folder> all_folders = new Gee.HashSet<Geary.Folder>();
        all_folders.add_all(folder_map.values);
        all_folders.add_all(local_only.values);
        
        return all_folders;
    }
    
    private void reschedule_unseen_update(Geary.Folder folder) {
        if (!folder_map.has_key(folder.path))
            return;
        
        if (refresh_unseen_timeout_ids.get(folder.path) != 0)
            Source.remove(refresh_unseen_timeout_ids.get(folder.path));
        
        refresh_unseen_timeout_ids.set(folder.path,
            Timeout.add_seconds(REFRESH_UNSEEN_SEC, () => on_refresh_unseen(folder)));
    }
    
    private bool on_refresh_unseen(Geary.Folder folder) {
        // If we're in the process already, reschedule for later.
        if (in_refresh_unseen.contains(folder))
            return true;
        
        refresh_unseen_async.begin(folder, null, on_refresh_unseen_completed);
        
        refresh_unseen_timeout_ids.unset(folder.path);
        return false;
    }
    
    private void on_refresh_unseen_completed(Object? source, AsyncResult result) {
        try {
            refresh_unseen_async.end(result);
        } catch (Error e) {
            debug("Error refreshing unseen counts: %s", e.message);
        }
    }
    
    private async void refresh_unseen_async(Geary.Folder folder, Cancellable? cancellable) throws Error {
        in_refresh_unseen.add(folder);
        
        debug("Refreshing unseen counts for %s", folder.to_string());
        
        bool folder_created;
        Imap.Folder remote_folder = yield remote.fetch_folder_async(folder.path,
            out folder_created, cancellable);
        
        if (!folder_created) {
            int unseen_count = yield remote.fetch_unseen_count_async(folder.path, cancellable);
            remote_folder.properties.set_status_unseen(unseen_count);
            yield local.update_folder_status_async(remote_folder, false, cancellable);
        }
        
        in_refresh_unseen.remove(folder);
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
        enumerate_folders_async.begin(refresh_cancellable, on_refresh_completed);
        
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
    
    private async void enumerate_folders_async(Cancellable? cancellable) throws Error {
        check_open();
        
        // enumerate local folders first
        Gee.HashMap<FolderPath, ImapDB.Folder> local_folders = yield enumerate_local_folders_async(
            null, cancellable);
        
        // convert to a list of Geary.Folder ... build_folder() also reports new folders, so this
        // gets the word out quickly (local_only folders have already been reported)
        Gee.Collection<Geary.Folder> existing_list = new Gee.ArrayList<Geary.Folder>();
        existing_list.add_all(build_folders(local_folders.values));
        existing_list.add_all(local_only.values);
        
        // build a map of all existing folders
        Gee.HashMap<FolderPath, Geary.Folder> existing_folders
            = Geary.traverse<Geary.Folder>(existing_list).to_hash_map<FolderPath>(f => f.path);
        
        // now that all local have been enumerated and reported (this is important to assist
        // startup of the UI), enumerate the remote folders
        bool remote_folders_suspect;
        Gee.HashMap<FolderPath, Imap.Folder>? remote_folders = yield enumerate_remote_folders_async(
            null, out remote_folders_suspect, cancellable);
        
        // pair the local and remote folders and make sure everything is up-to-date
        yield update_folders_async(existing_folders, remote_folders, remote_folders_suspect, cancellable);
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
        Geary.FolderPath? parent, out bool results_suspect, Cancellable? cancellable) throws Error {
        results_suspect = false;
        check_open();
        
        Gee.List<Imap.Folder>? remote_children = null;
        try {
            remote_children = yield remote.list_child_folders_async(parent, cancellable);
        } catch (Error err) {
            // ignore everything but I/O and IMAP errors (cancellation is an IOError)
            if (err is IOError || err is ImapError)
                throw err;
            debug("Ignoring error listing child folders of %s: %s",
                (parent != null ? parent.to_string() : "root"), err.message);
            results_suspect = true;
        }
        
        Gee.HashMap<FolderPath, Imap.Folder> result = new Gee.HashMap<FolderPath, Imap.Folder>();
        if (remote_children != null) {
            foreach (Imap.Folder remote_child in remote_children) {
                result.set(remote_child.path, remote_child);
                if (remote_child.properties.has_children.is_possible()) {
                    bool recursive_results_suspect;
                    Collection.map_set_all<FolderPath, Imap.Folder>(result,
                        yield enumerate_remote_folders_async(
                        remote_child.path, out recursive_results_suspect, cancellable));
                    if (recursive_results_suspect)
                        results_suspect = true;
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
                null, cancellable);
            
            yield local.clone_folder_async(remote_folder, cancellable);
        }
        
        // Fetch the local account's version of the folder for the MinimalFolder
        return build_folder((ImapDB.Folder) yield local.fetch_folder_async(path, cancellable));
    }
    
    private Gee.HashMap<Geary.SpecialFolderType, Gee.ArrayList<string>> get_mailbox_search_names() {
        Gee.HashMap<Geary.SpecialFolderType, string> mailbox_search_names
            = new Gee.HashMap<Geary.SpecialFolderType, string>();
        mailbox_search_names.set(Geary.SpecialFolderType.DRAFTS,
            // List of folder names to match for Drafts, separated by |.  Please add localized common
            // names for the Drafts folder, leaving in the English names as well.  The first in the list
            // will be the default, so please add the most common localized name to the front.
            _("Drafts | Draft"));
        mailbox_search_names.set(Geary.SpecialFolderType.SENT,
            // List of folder names to match for Sent Mail, separated by |.  Please add localized common
            // names for the Sent Mail folder, leaving in the English names as well.  The first in the list
            // will be the default, so please add the most common localized name to the front.
            _("Sent | Sent Mail | Sent Email | Sent E-Mail"));
        mailbox_search_names.set(Geary.SpecialFolderType.SPAM,
            // List of folder names to match for Spam, separated by |.  Please add localized common
            // names for the Spam folder, leaving in the English names as well.  The first in the list
            // will be the default, so please add the most common localized name to the front.
            _("Junk | Spam | Junk Mail | Junk Email | Junk E-Mail | Bulk Mail | Bulk Email | Bulk E-Mail"));
        mailbox_search_names.set(Geary.SpecialFolderType.TRASH,
            // List of folder names to match for Trash, separated by |.  Please add localized common
            // names for the Trash folder, leaving in the English names as well.  The first in the list
            // will be the default, so please add the most common localized name to the front.
            _("Trash | Rubbish | Rubbish Bin"));
        
        Gee.HashMap<Geary.SpecialFolderType, Gee.ArrayList<string>> compiled
            = new Gee.HashMap<Geary.SpecialFolderType, Gee.ArrayList<string>>();
        
        foreach (Geary.SpecialFolderType t in mailbox_search_names.keys) {
            compiled.set(t, Geary.iterate_array<string>(mailbox_search_names.get(t).split("|"))
                .map<string>(n => n.strip()).to_array_list());
        }
        
        return compiled;
    }
    
    private async Geary.Folder ensure_special_folder_async(Geary.SpecialFolderType special,
        Cancellable? cancellable) throws Error {
        Geary.Folder? folder = get_special_folder(special);
        if (folder != null)
            return folder;
        
        MinimalFolder? minimal_folder = null;
        Geary.FolderPath? path = information.get_special_folder_path(special);
        if (path != null) {
            debug("Previously used %s for special folder %s", path.to_string(), special.to_string());
        } else {
            // This is the first time we're turning a non-special folder into a special one.
            // After we do this, we'll record which one we picked in the account info.
            
            Gee.ArrayList<string> search_names = get_mailbox_search_names().get(special);
            foreach (string search_name in search_names) {
                Geary.FolderPath search_path = new Imap.FolderRoot(search_name, null);
                foreach (Geary.FolderPath test_path in folder_map.keys) {
                    if (test_path.compare_normalized_ci(search_path) == 0) {
                        path = search_path;
                        break;
                    }
                }
                if (path != null)
                    break;
            }
            if (path == null) {
                foreach (string search_name in search_names) {
                    Geary.FolderPath search_path = new Imap.FolderRoot(
                        Imap.MailboxSpecifier.CANONICAL_INBOX_NAME, null).get_child(search_name);
                    foreach (Geary.FolderPath test_path in folder_map.keys) {
                        if (test_path.compare_normalized_ci(search_path) == 0) {
                            path = search_path;
                            break;
                        }
                    }
                    if (path != null)
                        break;
                }
            }
            
            if (path == null)
                path = new Imap.FolderRoot(search_names[0], null);
            
            information.set_special_folder_path(special, path);
            yield information.store_async(cancellable);
        }
        
        if (path in folder_map.keys) {
            debug("Promoting %s to special folder %s", path.to_string(), special.to_string());
            
            minimal_folder = folder_map.get(path);
        } else {
            debug("Creating %s to use as special folder %s", path.to_string(), special.to_string());
            
            // TODO: ignore error due to already existing.
            yield remote.create_folder_async(path, cancellable);
            minimal_folder = (MinimalFolder) yield fetch_folder_async(path, cancellable);
        }
        
        minimal_folder.set_special_folder_type(special);
        return minimal_folder;
    }
    
    public override async Geary.Folder get_required_special_folder_async(Geary.SpecialFolderType special,
        Cancellable? cancellable) throws Error {
        switch (special) {
            case Geary.SpecialFolderType.DRAFTS:
            case Geary.SpecialFolderType.SENT:
            case Geary.SpecialFolderType.SPAM:
            case Geary.SpecialFolderType.TRASH:
            break;
            
            default:
                throw new EngineError.BAD_PARAMETERS(
                    "Invalid special folder type %s passed to get_required_special_folder_async",
                    special.to_string());
        }
        
        check_open();
        
        return yield ensure_special_folder_async(special, cancellable);
    }
    
    private async void ensure_special_folders_async(Cancellable? cancellable) throws Error {
        Geary.SpecialFolderType[] required = {
            Geary.SpecialFolderType.DRAFTS,
            Geary.SpecialFolderType.SENT,
            Geary.SpecialFolderType.SPAM,
            Geary.SpecialFolderType.TRASH,
        };
        foreach (Geary.SpecialFolderType special in required)
            yield ensure_special_folder_async(special, cancellable);
    }
    
    private async void update_folders_async(Gee.Map<FolderPath, Geary.Folder> existing_folders,
        Gee.Map<FolderPath, Imap.Folder> remote_folders, bool remote_folders_suspect, Cancellable? cancellable) {
        // update all remote folders properties in the local store and active in the system
        Gee.HashSet<Geary.FolderPath> altered_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Imap.Folder remote_folder in remote_folders.values) {
            MinimalFolder? minimal_folder = existing_folders.get(remote_folder.path)
                as MinimalFolder;
            if (minimal_folder == null)
                continue;
            
            // only worry about alterations if the remote is openable
            if (remote_folder.properties.is_openable.is_possible()) {
                ImapDB.Folder local_folder = minimal_folder.local_folder;
                
                if (remote_folder.properties.have_contents_changed(local_folder.get_properties(),
                    minimal_folder.to_string())) {
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
            if (minimal_folder.special_folder_type == SpecialFolderType.NONE)
                minimal_folder.set_special_folder_type(remote_folder.properties.attrs.get_special_folder_type());
        }
        
        // If path in remote but not local, need to add it
        Gee.ArrayList<Imap.Folder> to_add = Geary.traverse<Imap.Folder>(remote_folders.values)
            .filter(f => !existing_folders.has_key(f.path))
            .to_array_list();
        
        // If path in local but not remote (and isn't local-only, i.e. the Outbox), need to remove it
        Gee.ArrayList<Geary.Folder> to_remove
            = Geary.traverse<Gee.Map.Entry<FolderPath, Imap.Folder>>(existing_folders)
            .filter(e => !remote_folders.has_key(e.key) && !local_only.has_key(e.key))
            .map<Geary.Folder>(e => (Geary.Folder) e.value)
            .to_array_list();
        
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
        Gee.Collection<MinimalFolder> engine_added = new Gee.ArrayList<Geary.Folder>();
        engine_added.add_all(build_folders(folders_to_build));
        
        Gee.ArrayList<Geary.Folder> engine_removed = new Gee.ArrayList<Geary.Folder>();
        if (remote_folders_suspect) {
            debug("Skipping removing folders due to prior errors");
        } else {
            notify_folders_available_unavailable(null, to_remove);
            
            // Sort by path length descending, so we always remove children first.
            to_remove.sort((a, b) => b.path.get_path_length() - a.path.get_path_length());
            foreach (Geary.Folder folder in to_remove) {
                try {
                    debug("Locally deleting removed folder %s", folder.to_string());
                    
                    yield local.delete_folder_async(folder, cancellable);
                    engine_removed.add(folder);
                } catch (Error e) {
                    debug("Unable to locally delete removed folder %s: %s", folder.to_string(), e.message);
                }
            }
        }
        
        if (engine_added.size > 0 || engine_removed.size > 0)
            notify_folders_added_removed(sort_by_path(engine_added), sort_by_path(engine_removed));
        
        remote.folders_removed(Geary.traverse<Geary.Folder>(engine_removed)
            .map<FolderPath>(f => f.path).to_array_list());
        
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
        
        try {
            yield ensure_special_folders_async(cancellable);
        } catch (Error e) {
            warning("Unable to ensure special folders: %s", e.message);
        }
    }
    
    public override async void send_email_async(Geary.ComposedEmail composed,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO: we should probably not use someone else's FQDN in something
        // that's supposed to be globally unique...
        Geary.RFC822.Message rfc822 = new Geary.RFC822.Message.from_composed_email(
            composed, GMime.utils_generate_message_id(information.get_smtp_endpoint().remote_address.hostname));
        
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
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Geary.EmailFlags? flag_blacklist,
        Cancellable? cancellable = null) throws Error {
        return yield local.search_message_id_async(
            message_id, requested_fields, partial_ok, folder_blacklist, flag_blacklist, cancellable);
    }
    
    public override async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        return yield local.fetch_email_async(check_id(email_id), required_fields, cancellable);
    }
    
    public override async Gee.Collection<Geary.EmailIdentifier>? local_search_async(Geary.SearchQuery query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error {
        if (offset < 0)
            throw new EngineError.BAD_PARAMETERS("Offset must not be negative");
        
        return yield local.search_async(query, limit, offset, folder_blacklist, search_ids, cancellable);
    }
    
    public override async Gee.Collection<string>? get_search_matches_async(Geary.SearchQuery query,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        return yield local.get_search_matches_async(query, check_ids(ids), cancellable);
    }
    
    public override async Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? get_containing_folders_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        return yield local.get_containing_folders_async(ids, cancellable);
    }
    
    private void on_login_failed(Geary.Credentials? credentials) {
        if (awaiting_credentials)
            return; // We're already asking for the password.
        
        awaiting_credentials = true;
        do_login_failed_async.begin(credentials, () => { awaiting_credentials = false; });
    }
    
    private async void do_login_failed_async(Geary.Credentials? credentials) {
        try {
            if (yield information.fetch_passwords_async(ServiceFlag.IMAP, true))
                return;
        } catch (Error e) {
            debug("Error prompting for IMAP password: %s", e.message);
        }
        
        notify_report_problem(Geary.Account.Problem.RECV_EMAIL_LOGIN_FAILED, null);
    }
}

