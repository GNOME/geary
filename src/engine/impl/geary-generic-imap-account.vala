/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapAccount : Geary.EngineAccount {
    private SpecialFolderMap? special_folders = null;
    
    private Imap.Account remote;
    private Sqlite.Account local;
    
    public GenericImapAccount(string name, string username, AccountInformation? account_info,
        File user_data_dir, Imap.Account remote, Sqlite.Account local) {
        base (name, username, account_info, user_data_dir);
        
        this.remote = remote;
        this.local = local;
        
        this.remote.login_failed.connect(on_login_failed);
        
        if (special_folders == null) {
            special_folders = new SpecialFolderMap();
            
            special_folders.set_folder(
                new SpecialFolder(
                    SpecialFolderType.INBOX,
                    _("Inbox"),
                    new Geary.FolderRoot(Imap.Account.INBOX_NAME, Imap.Account.ASSUMED_SEPARATOR, false),
                    0
                )
            );
        }
    }
    
    public override Geary.Email.Field get_required_fields_for_writing() {
        // Return the more restrictive of the two, which is the NetworkAccount's.
        // TODO: This could be determined at runtime rather than fixed in stone here.
        return Geary.Email.Field.HEADER | Geary.Email.Field.BODY;
    }
    
    public override async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<Geary.Sqlite.Folder>? local_list = null;
        try {
            local_list = yield local.list_folders_async(parent, cancellable);
        } catch (EngineError err) {
            // don't pass on NOT_FOUND's, that means we need to go to the server for more info
            if (!(err is EngineError.NOT_FOUND))
                throw err;
        }
        
        Gee.Collection<Geary.Folder> engine_list = new Gee.ArrayList<Geary.Folder>();
        if (local_list != null && local_list.size > 0) {
            foreach (Geary.Sqlite.Folder local_folder in local_list)
                engine_list.add(new GenericImapFolder(remote, local, local_folder));
        }
        
        background_update_folders.begin(parent, engine_list, cancellable);
        
        return engine_list;
    }
    
    public override async bool folder_exists_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        if (yield local.folder_exists_async(path, cancellable))
            return true;
        
        return yield remote.folder_exists_async(path, cancellable);
    }
    
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        Sqlite.Folder? local_folder = null;
        try {
            local_folder = (Sqlite.Folder) yield local.fetch_folder_async(path, cancellable);
            
            return new GenericImapFolder(remote, local, local_folder);
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
        local_folder = (Sqlite.Folder) yield local.fetch_folder_async(path, cancellable);
        
        return new GenericImapFolder(remote, local, local_folder);
    }
    
    private async void background_update_folders(Geary.FolderPath? parent,
        Gee.Collection<Geary.Folder> engine_folders, Cancellable? cancellable) {
        Gee.Collection<Geary.Imap.Folder> remote_folders;
        try {
            remote_folders = yield remote.list_folders_async(parent, cancellable);
        } catch (Error remote_error) {
            error("Unable to retrieve folder list from server: %s", remote_error.message);
        }
        
        Gee.Set<string> local_names = new Gee.HashSet<string>();
        foreach (Geary.Folder folder in engine_folders)
            local_names.add(folder.get_path().basename);
        
        Gee.Set<string> remote_names = new Gee.HashSet<string>();
        foreach (Geary.Imap.Folder folder in remote_folders)
            remote_names.add(folder.get_path().basename);
        
        Gee.List<Geary.Imap.Folder> to_add = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Imap.Folder folder in remote_folders) {
            if (!local_names.contains(folder.get_path().basename))
                to_add.add(folder);
        }
        
        Gee.List<Geary.Folder>? to_remove = new Gee.ArrayList<Geary.Imap.Folder>();
        foreach (Geary.Folder folder in engine_folders) {
            if (!remote_names.contains(folder.get_path().basename))
                to_remove.add(folder);
        }
        
        if (to_add.size == 0)
            to_add = null;
        
        if (to_remove.size == 0)
            to_remove = null;
        
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
        
        Gee.Collection<Geary.Folder> engine_added = null;
        if (to_add != null) {
            engine_added = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Imap.Folder remote_folder in to_add) {
                try {
                    Sqlite.Folder local_folder = (Sqlite.Folder) yield local.fetch_folder_async(
                        remote_folder.get_path(), cancellable);
                    engine_added.add(new GenericImapFolder(remote, local, local_folder));
                } catch (Error convert_err) {
                    error("Unable to fetch local folder: %s", convert_err.message);
                }
            }
        }
        
        if (engine_added != null)
            notify_folders_added_removed(engine_added, null);
    }
    
    public override string get_user_folders_label() {
        return _("Folders");
    }
    
    public override Geary.SpecialFolderMap? get_special_folder_map() {
        return special_folders;
    }
    
    public override Gee.Set<Geary.FolderPath>? get_ignored_paths() {
        return null;
    }
    
    public override bool delete_is_archive() {
        return false;
    }
    
    public override async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error {
        yield remote.send_email_async(composed, cancellable);
    }
    
    private void on_login_failed(Geary.Credentials? credentials) {
        notify_report_problem(Geary.Account.Problem.LOGIN_FAILED, credentials, null);
    }
}

