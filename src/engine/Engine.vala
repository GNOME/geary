/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine : Object, Geary.Account {
    private NetworkAccount net;
    private LocalAccount local;
    
    private Engine(NetworkAccount net, LocalAccount local) {
        this.net = net;
        this.local = local;
    }
    
    public static Account open(Geary.Credentials cred) throws Error {
        return new Engine(
            new Geary.Imap.Account(cred, Imap.ClientConnection.DEFAULT_PORT_TLS),
            new Geary.Sqlite.Account(cred));
    }
    
    public async Gee.Collection<Geary.Folder> list_async(string? parent_folder,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<Geary.Folder> local_list = yield local.list_async(parent_folder, cancellable);
        
        Gee.Collection<Geary.Folder> engine_list = new Gee.ArrayList<Geary.Folder>();
        foreach (Geary.Folder local_folder in local_list)
            engine_list.add(new EngineFolder(net, local, local_folder));
        
        background_update_folders.begin(parent_folder, engine_list);
        
        debug("Reporting %d folders", engine_list.size);
        
        return engine_list;
    }
    
    public async Geary.Folder fetch_async(string? parent_folder, string folder_name,
        Cancellable? cancellable = null) throws Error {
        Geary.Folder local_folder = yield local.fetch_async(parent_folder, folder_name, cancellable);
        Geary.Folder engine_folder = new EngineFolder(net, local, local_folder);
        
        return engine_folder;
    }
    
    private Gee.Set<string> get_folder_names(Gee.Collection<Geary.Folder> folders) {
        Gee.Set<string> names = new Gee.HashSet<string>();
        foreach (Geary.Folder folder in folders)
            names.add(folder.get_name());
        
        return names;
    }
    
    private Gee.List<Geary.Folder> get_excluded_folders(Gee.Collection<Geary.Folder> folders,
        Gee.Set<string> names) {
        Gee.List<Geary.Folder> excluded = new Gee.ArrayList<Geary.Folder>();
        foreach (Geary.Folder folder in folders) {
            if (!names.contains(folder.get_name()))
                excluded.add(folder);
        }
        
        return excluded;
    }
    
    private async void background_update_folders(string? parent_folder,
        Gee.Collection<Geary.Folder> engine_folders) {
        Gee.Collection<Geary.Folder> net_folders;
        try {
            net_folders = yield net.list_async(parent_folder);
        } catch (Error neterror) {
            error("Unable to retrieve folder list from server: %s", neterror.message);
        }
        
        Gee.Set<string> local_names = get_folder_names(engine_folders);
        Gee.Set<string> net_names = get_folder_names(net_folders);
        
        debug("%d local names, %d net names", local_names.size, net_names.size);
        
        Gee.List<Geary.Folder>? to_add = get_excluded_folders(net_folders, local_names);
        Gee.List<Geary.Folder>? to_remove = get_excluded_folders(engine_folders, net_names);
        
        debug("Adding %d, removing %d to/from local store", to_add.size, to_remove.size);
        
        if (to_add.size == 0)
            to_add = null;
        
        if (to_remove.size == 0)
            to_remove = null;
        
        try {
            if (to_add != null)
                yield local.create_many_async(to_add);
        } catch (Error err) {
            error("Unable to add/remove folders: %s", err.message);
        }
        
        Gee.Collection<Geary.Folder> engine_added = null;
        if (to_add != null) {
            engine_added = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Folder net_folder in to_add) {
                try {
                    engine_added.add(new EngineFolder(net, local,
                        yield local.fetch_async(parent_folder, net_folder.get_name())));
                } catch (Error convert_err) {
                    error("Unable to fetch local folder: %s", convert_err.message);
                }
            }
        }
        
        if (engine_added != null)
            notify_folders_added_removed(engine_added, null);
    }
    
    public async void create_async(Geary.Folder folder, Cancellable? cancellable = null) throws Error {
    }
    
    public async void create_many_async(Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
    }
    
    public async void remove_async(string folder, Cancellable? cancellable = null) throws Error {
    }
    
    public async void remove_many_async(Gee.Set<string> folders, Cancellable? cancellable = null)
        throws Error {
    }
}

