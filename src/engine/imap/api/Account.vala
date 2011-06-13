/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Account : Object, Geary.Account, Geary.NetworkAccount {
    private ClientSessionManager session_mgr;
    
    public Account(Credentials cred, uint default_port) {
        session_mgr = new ClientSessionManager(cred, default_port);
    }
    
    public bool is_online() {
        return true;
    }
    
    public async Gee.Collection<Geary.Folder> list_async(string? parent_folder,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<MailboxInformation> mboxes = yield session_mgr.list(parent_folder, cancellable);
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Folder>();
        foreach (MailboxInformation mbox in mboxes)
            folders.add(new Geary.Imap.Folder(session_mgr, mbox));
        
        return folders;
    }
    
    public async Geary.Folder fetch_async(string? parent_folder, string folder_name,
        Cancellable? cancellable = null) throws Error {
        MailboxInformation? mbox = yield session_mgr.fetch_async(parent_folder, folder_name,
            cancellable);
        if (mbox == null)
            throw new EngineError.NOT_FOUND("Folder %s not found on server", folder_name);
        
        return new Geary.Imap.Folder(session_mgr, mbox);
    }
    
    public async void create_async(Geary.Folder folder, Cancellable? cancellable = null) throws Error {
        // TODO
    }
    
    public async void create_many_async(Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        // TODO
    }
    
    public async void remove_async(string folder, Cancellable? cancellable = null) throws Error {
        // TODO
    }
    
    public async void remove_many_async(Gee.Set<string> folders, Cancellable? cancellable = null)
        throws Error {
        // TODO
    }
}

