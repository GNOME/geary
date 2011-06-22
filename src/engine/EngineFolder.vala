/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.EngineFolder : Object, Geary.Folder {
    private NetworkAccount net;
    private LocalAccount local;
    private Geary.Folder local_folder;
    private Geary.Folder net_folder;
    
    public EngineFolder(NetworkAccount net, LocalAccount local, Geary.Folder local_folder) {
        this.net = net;
        this.local = local;
        this.local_folder = local_folder;
        
        local_folder.updated.connect(on_local_updated);
    }
    
    ~EngineFolder() {
        local_folder.updated.disconnect(on_local_updated);
    }
    
    public string get_name() {
        return local_folder.get_name();
    }
    
    public Geary.FolderProperties? get_properties() {
        return null;
    }
    
    public async void create_email_async(Geary.Email email, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        throw new EngineError.READONLY("Engine currently read-only");
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (net_folder == null) {
            net_folder = yield net.fetch_folder_async(null, local_folder.get_name(), cancellable);
            net_folder.updated.connect(on_net_updated);
        }
        
        yield net_folder.open_async(readonly, cancellable);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (net_folder != null) {
            net_folder.updated.disconnect(on_net_updated);
            yield net_folder.close_async(cancellable);
        }
        
        net_folder = null;
    }
    
    public int get_message_count() throws Error {
        return 0;
    }
    
    public async Gee.List<Geary.Email>? list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        assert(low >= 1);
        assert(count >= 0);
        
        if (count == 0)
            return null;
        
        Gee.List<Geary.Email>? local_list = yield local_folder.list_email_async(low, count, fields,
            cancellable);
        int local_list_size = (local_list != null) ? local_list.size : 0;
        debug("local list found %d", local_list_size);
        
        if (net_folder != null && local_list_size != count) {
            // go through the positions from (low) to (low + count) and see if they're not already
            // present in local_list; whatever isn't present needs to be fetched
            int[] needed_by_position = new int[0];
            int position = low;
            for (int index = 0; (index < count) && (position <= (low + count - 1)); position++) {
                while ((index < local_list_size) && (local_list[index].location.position < position))
                    index++;
                
                if (index >= local_list_size || local_list[index].location.position != position)
                    needed_by_position += position;
            }
            
            if (needed_by_position.length != 0)
                background_update_email_list.begin(needed_by_position, fields, cancellable);
        }
        
        return local_list;
    }
    
    public async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (by_position.length == 0)
            return null;
        
        Gee.List<Geary.Email>? local_list = yield local_folder.list_email_sparse_async(by_position,
            fields, cancellable);
        int local_list_size = (local_list != null) ? local_list.size : 0;
        
        if (net_folder != null && local_list_size != by_position.length) {
            // go through the list looking for anything not already in the sparse by_position list
            // to fetch from the server; since by_position is not guaranteed to be sorted, the local
            // list needs to be searched each iteration.
            //
            // TODO: Optimize this, especially if large lists/sparse sets are supplied
            int[] needed_by_position = new int[0];
            foreach (int position in by_position) {
                bool found = false;
                if (local_list != null) {
                    foreach (Geary.Email email in local_list) {
                        if (email.location.position == position) {
                            found = true;
                            
                            break;
                        }
                    }
                }
                
                if (!found)
                    needed_by_position += position;
            }
            
            if (needed_by_position.length != 0)
                background_update_email_list.begin(needed_by_position, fields, cancellable);
        }
        
        return local_list;
    }
    
    private async void background_update_email_list(int[] needed_by_position, Geary.Email.Field fields,
        Cancellable? cancellable) {
        debug("Background fetching %d emails for %s", needed_by_position.length, get_name());
        
        Gee.List<Geary.Email>? net_list = null;
        try {
            net_list = yield net_folder.list_email_sparse_async(needed_by_position, fields,
                cancellable);
        } catch (Error net_err) {
            message("Unable to fetch emails from server: %s", net_err.message);
            
            if (net_err is IOError.CANCELLED)
                return;
        }
        
        if (net_list != null && net_list.size == 0)
            net_list = null;
        
        if (net_list != null)
            notify_email_added_removed(net_list, null);
        
        if (net_list != null) {
            foreach (Geary.Email email in net_list) {
                try {
                    yield local_folder.create_email_async(email, fields, cancellable);
                } catch (Error local_err) {
                    message("Unable to create email in local store: %s", local_err.message);
                    
                    if (local_err is IOError.CANCELLED)
                        return;
                }
            }
        }
    }
    
    public async Geary.Email fetch_email_async(int num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (net_folder == null)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", get_name());
        
        return yield net_folder.fetch_email_async(num, fields, cancellable);
    }
    
    private void on_local_updated() {
    }
    
    private void on_net_updated() {
    }
}

