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
    
    public Trillian is_readonly() {
        return local_folder.is_readonly();
    }
    
    public Trillian does_support_children() {
        return local_folder.does_support_children();
    }
    
    public Trillian has_children() {
        return local_folder.has_children();
    }
    
    public Trillian is_openable() {
        return local_folder.is_openable();
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (net_folder == null) {
            net_folder = yield net.fetch_async(null, local_folder.get_name(), cancellable);
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
    
    public async Gee.List<Geary.EmailHeader>? read_async(int low, int count,
        Cancellable? cancellable = null) throws Error {
        if (net_folder == null)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", get_name());
        
        return yield net_folder.read_async(low, count, cancellable);
    }
    
    public async Geary.Email fetch_async(Geary.EmailHeader header,
        Cancellable? cancellable = null) throws Error {
        if (net_folder == null)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", get_name());
        
        return yield net_folder.fetch_async(header, cancellable);
    }
    
    private void on_local_updated() {
    }
    
    private void on_net_updated() {
    }
}

