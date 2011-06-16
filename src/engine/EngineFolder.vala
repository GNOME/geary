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
    
    public async void create_email_async(Geary.Email email, Geary.EmailOrdering ordering, 
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
    
    public async Gee.List<Geary.Email> list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        return yield net_folder.list_email_async(low, count, fields, cancellable);
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

