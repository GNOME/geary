/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine : Object, Geary.Account {
    private NetworkAccount net;
    private LocalAccount local;
    
    public ImapEngine(NetworkAccount net, LocalAccount local) {
        this.net = net;
        this.local = local;
    }
    
    public async void create_folder_async(Geary.Folder? parent, Geary.Folder folder,
        Cancellable? cancellable = null) throws Error {
    }
    
    public async void create_many_folders_async(Geary.Folder? parent,
        Gee.Collection<Geary.Folder> folders, Cancellable? cancellable = null) throws Error {
    }
    
    public async Gee.Collection<Geary.Folder> list_folders_async(Geary.Folder? parent,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<Geary.Folder> local_list = yield local.list_folders_async(parent, cancellable);
        
        Gee.Collection<Geary.Folder> engine_list = new Gee.ArrayList<Geary.Folder>();
        foreach (Geary.Folder local_folder in local_list)
            engine_list.add(new EngineFolder(net, local, local_folder));
        
        background_update_folders.begin(parent, engine_list);
        
        debug("Reporting %d folders", engine_list.size);
        
        return engine_list;
    }
    
    public async Geary.Folder fetch_folder_async(Geary.Folder? parent, string folder_name,
        Cancellable? cancellable = null) throws Error {
        Geary.Folder local_folder = yield local.fetch_folder_async(parent, folder_name, cancellable);
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
    
    private async void background_update_folders(Geary.Folder? parent,
        Gee.Collection<Geary.Folder> engine_folders) {
        Gee.Collection<Geary.Folder> net_folders;
        try {
            net_folders = yield net.list_folders_async(parent);
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
                yield local.create_many_folders_async(parent, to_add);
        } catch (Error err) {
            error("Unable to add/remove folders: %s", err.message);
        }
        
        Gee.Collection<Geary.Folder> engine_added = null;
        if (to_add != null) {
            engine_added = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Folder net_folder in to_add) {
                try {
                    engine_added.add(new EngineFolder(net, local,
                        yield local.fetch_folder_async(parent, net_folder.get_name())));
                } catch (Error convert_err) {
                    error("Unable to fetch local folder: %s", convert_err.message);
                }
            }
        }
        
        if (engine_added != null)
            notify_folders_added_removed(engine_added, null);
    }
    
    public async void remove_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error {
    }
    
    public async void remove_many_folders_async(Gee.Set<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
    }
}

