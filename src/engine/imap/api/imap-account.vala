/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Account : Geary.AbstractAccount, Geary.RemoteAccount {
    private ClientSessionManager session_mgr;
    private Gee.HashMap<string, string?> delims = new Gee.HashMap<string, string?>();
    
    public Account(Credentials cred, uint default_port) {
        base ("IMAP Account for %s".printf(cred.to_string()));
        
        session_mgr = new ClientSessionManager(cred, default_port);
    }
    
    public override Geary.Email.Field get_required_fields_for_writing() {
        return Geary.Email.Field.HEADER | Geary.Email.Field.BODY;
    }
    
    public async string? get_folder_delimiter_async(string toplevel,
        Cancellable? cancellable = null) throws Error {
        if (delims.has_key(toplevel))
            return delims.get(toplevel);
        
        MailboxInformation? mbox = yield session_mgr.fetch_async(toplevel, cancellable);
        if (mbox == null) {
            throw new EngineError.NOT_FOUND("Toplevel folder %s not found on %s", toplevel,
                session_mgr.to_string());
        }
        
        delims.set(toplevel, mbox.delim);
        
        return mbox.delim;
    }
    
    public override async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error {
        Gee.Collection<MailboxInformation> mboxes;
        try {
            mboxes = (parent == null)
                ? yield session_mgr.list_roots(cancellable)
                : yield session_mgr.list(parent.get_fullpath(), parent.get_root().default_separator,
                    cancellable);
        } catch (Error err) {
            if (err is ImapError.SERVER_ERROR)
                throw_not_found(parent);
            else
                throw err;
        }
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Folder>();
        foreach (MailboxInformation mbox in mboxes) {
            if (parent == null)
                delims.set(mbox.name, mbox.delim);
            
            string basename = mbox.get_path().last();
            
            Geary.FolderPath path = (parent != null)
                ? parent.get_child(basename)
                : new Geary.FolderRoot(basename, mbox.delim, Folder.CASE_SENSITIVE);
            
            folders.add(new Geary.Imap.Folder(session_mgr, path, mbox));
        }
        
        return folders;
    }
    
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        try {
            MailboxInformation? mbox = yield session_mgr.fetch_async(path.get_fullpath(), cancellable);
            if (mbox == null)
                throw_not_found(path);
            
            return new Geary.Imap.Folder(session_mgr, path, mbox);
        } catch (ImapError err) {
            if (err is ImapError.SERVER_ERROR)
                throw_not_found(path);
            else
                throw err;
        }
    }
    
    [NoReturn]
    private void throw_not_found(Geary.FolderPath? path) throws EngineError {
        throw new EngineError.NOT_FOUND("Folder %s not found on %s",
            (path != null) ? path.to_string() : "root", session_mgr.to_string());
    }
}
