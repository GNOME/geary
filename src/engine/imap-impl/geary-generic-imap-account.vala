/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.GenericImapAccount : Geary.EngineAccount {
    private static Geary.FolderPath? inbox_path = null;
    private static Geary.FolderPath? outbox_path = null;
    
    private Imap.Account remote;
    private ImapDB.Account local;
    private bool open = false;
    private Gee.HashMap<FolderPath, Imap.FolderProperties> properties_map = new Gee.HashMap<
        FolderPath, Imap.FolderProperties>(Hashable.hash_func, Equalable.equal_func);
    private Gee.HashMap<FolderPath, GenericImapFolder> existing_folders = new Gee.HashMap<
        FolderPath, GenericImapFolder>(Hashable.hash_func, Equalable.equal_func);
    private Gee.HashSet<FolderPath> local_only = new Gee.HashSet<FolderPath>(
        Hashable.hash_func, Equalable.equal_func);
    
    public GenericImapAccount(string name, Geary.AccountSettings settings, Imap.Account remote,
        ImapDB.Account local) {
        base (name, settings);
        
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
            local_only.add(outbox_path);
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
        
        yield local.open_async(Engine.user_data_dir.get_child(settings.credentials.user),
            Engine.resource_dir.get_child("sql"), cancellable);
        
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
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;
        
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
        
        if (local_err != null)
            throw local_err;
        
        if (remote_err != null)
            throw remote_err;
    }
    
    // Subclasses should implement this to return their flavor of a GenericImapFolder with the
    // appropriate interfaces attached.  The returned folder should have its SpecialFolderType
    // set using either the properties from the local folder or its path.
    //
    // This won't be called to build the Outbox, but for all others (including Inbox) it will.
    protected abstract GenericImapFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder);
    
    private GenericImapFolder build_folder(ImapDB.Folder local_folder) {
        GenericImapFolder? folder = existing_folders.get(local_folder.get_path());
        if (folder != null)
            return folder;
        
        folder = new_folder(local_folder.get_path(), remote, local, local_folder);
        existing_folders.set(folder.get_path(), folder);
        
        return folder;
    }
    
    public override async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
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
            foreach (ImapDB.Folder local_folder in local_list)
                engine_list.add(build_folder(local_folder));
        }
        
        // Add Outbox to root
        if (parent == null)
            engine_list.add(local.outbox);
        
        background_update_folders.begin(parent, engine_list, cancellable);
        
        return engine_list;
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
        
        if (path.equals(local.outbox.get_path()))
            return local.outbox;
        
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
        
        // Fetch the local account's version of the folder for the GenericImapFolder
        return build_folder((ImapDB.Folder) yield local.fetch_folder_async(path, cancellable));
    }
    
    private async void background_update_folders(Geary.FolderPath? parent,
        Gee.Collection<Geary.Folder> engine_folders, Cancellable? cancellable) {
        Gee.Collection<Geary.Imap.Folder> remote_folders;
        try {
            remote_folders = yield remote.list_folders_async(parent, cancellable);
        } catch (Error remote_error) {
            debug("Unable to retrieve folder list from server: %s", remote_error.message);
            
            return;
        }
        
        // update all remote folders properties in the local store and active in the system
        foreach (Imap.Folder remote_folder in remote_folders) {
            try {
                yield local.update_folder_async(remote_folder, cancellable);
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.to_string(), update_error.message);
            }
        }
        
        // Get local paths of all engine (local) folders
        Gee.Set<Geary.FolderPath> local_paths = new Gee.HashSet<Geary.FolderPath>(
            Geary.Hashable.hash_func, Geary.Equalable.equal_func);
        foreach (Geary.Folder local_folder in engine_folders)
            local_paths.add(local_folder.get_path());
        
        // Get remote paths of all remote folders
        Gee.Set<Geary.FolderPath> remote_paths = new Gee.HashSet<Geary.FolderPath>(
            Geary.Hashable.hash_func, Geary.Equalable.equal_func);
        foreach (Geary.Imap.Folder remote_folder in remote_folders) {
            remote_paths.add(remote_folder.get_path());
            
            // use this iteration to add discovered properties to map
            properties_map.set(remote_folder.get_path(), remote_folder.get_properties());
            
            // also use this iteration to set the local folder's special type
            GenericImapFolder? local_folder = existing_folders.get(remote_folder.get_path());
            if (local_folder != null)
                local_folder.set_special_folder_type(remote_folder.get_properties().attrs.get_special_folder_type());
        }
        
        // If path in remote but not local, need to add it
        Gee.List<Geary.Imap.Folder> to_add = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Imap.Folder folder in remote_folders) {
            if (!local_paths.contains(folder.get_path()))
                to_add.add(folder);
        }
        
        // If path in local but not remote (and isn't local-only, i.e. the Outbox), need to remove
        // it
        Gee.List<Geary.Folder>? to_remove = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Folder folder in engine_folders) {
            if (!remote_paths.contains(folder.get_path()) && !local_only.contains(folder.get_path()))
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
                    debug("Unable to add/remove folder %s: %s", folder.get_path().to_string(),
                        err.message);
                }
            }
        }
        
        // Create Geary.Folder objects for all added folders
        Gee.Collection<Geary.Folder> engine_added = null;
        if (to_add != null) {
            engine_added = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Imap.Folder remote_folder in to_add) {
                try {
                    engine_added.add(build_folder((ImapDB.Folder) yield local.fetch_folder_async(
                        remote_folder.get_path(), cancellable)));
                } catch (Error convert_err) {
                    // This isn't fatal, but irksome ... in the future, when local folders are
                    // removed, it's possible for one to disappear between cloning it and fetching
                    // it
                    debug("Unable to fetch local folder after cloning: %s", convert_err.message);
                }
            }
        }
        
        // TODO: Remove local folders no longer available remotely.
        if (to_remove != null) {
            foreach (Geary.Folder folder in to_remove) {
                debug(@"Need to remove folder $folder");
            }
        }
        
        if (engine_added != null)
            notify_folders_added_removed(engine_added, null);
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
    
    private void on_login_failed(Geary.Credentials? credentials) {
        notify_report_problem(Geary.Account.Problem.LOGIN_FAILED, credentials, null);
    }
}

