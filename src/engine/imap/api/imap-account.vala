/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Account : Object, Geary.Account, Geary.RemoteAccount {
    private ClientSessionManager session_mgr;
    
    public Account(Credentials cred, uint default_port) {
        session_mgr = new ClientSessionManager(cred, default_port);
    }
    
    public Geary.Email.Field get_required_fields_for_writing() {
        return Geary.Email.Field.HEADER | Geary.Email.Field.BODY;
    }
    
    public async void create_folder_async(Geary.Folder? parent, Geary.Folder folder,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.READONLY("IMAP readonly");
    }
    
    public async void create_many_folders_async(Geary.Folder? parent, Gee.Collection<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.READONLY("IMAP readonly");
    }
    
    public async Gee.Collection<Geary.Folder> list_folders_async(Geary.Folder? parent,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<MailboxInformation> mboxes = yield session_mgr.list(
            (parent != null) ? parent.get_name() : null, cancellable);
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Folder>();
        foreach (MailboxInformation mbox in mboxes)
            folders.add(new Geary.Imap.Folder(session_mgr, mbox));
        
        return folders;
    }
    
    public async Geary.Folder fetch_folder_async(Geary.Folder? parent, string folder_name,
        Cancellable? cancellable = null) throws Error {
        MailboxInformation? mbox = yield session_mgr.fetch_async(
            (parent != null) ? parent.get_name() : null, folder_name, cancellable);
        if (mbox == null)
            throw new EngineError.NOT_FOUND("Folder %s not found on server", folder_name);
        
        return new Geary.Imap.Folder(session_mgr, mbox);
    }
    
    public async void remove_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error {
        throw new EngineError.READONLY("IMAP readonly");
    }
    
    public async void remove_many_folders_async(Gee.Set<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.READONLY("IMAP readonly");
    }
}

