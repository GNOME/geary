/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Account : Geary.AbstractAccount, Geary.RemoteAccount {
    // all references to Inbox are converted to this string, purely for sanity sake when dealing
    // with Inbox's case issues
    public const string INBOX_NAME = "INBOX";
    public const string ASSUMED_SEPARATOR = "/";
    
    private Geary.Credentials cred;
    private ClientSessionManager session_mgr;
    private Geary.Smtp.ClientSession smtp;
    private Gee.HashMap<string, string?> delims = new Gee.HashMap<string, string?>();
    
    public Account(Geary.Endpoint imap_endpoint, Geary.Endpoint smtp_endpoint, Geary.Credentials cred) {
        base ("IMAP Account for %s".printf(cred.to_string()));
        
        this.cred = cred;
        
        session_mgr = new ClientSessionManager(imap_endpoint, cred);
        smtp = new Geary.Smtp.ClientSession(smtp_endpoint);
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
        Geary.FolderPath? processed = process_path(parent, null,
            (parent != null) ? parent.get_root().default_separator : ASSUMED_SEPARATOR);
        
        Gee.Collection<MailboxInformation> mboxes;
        try {
            mboxes = (processed == null)
                ? yield session_mgr.list_roots(cancellable)
                : yield session_mgr.list(processed.get_fullpath(), processed.get_root().default_separator,
                    cancellable);
        } catch (Error err) {
            if (err is ImapError.SERVER_ERROR)
                throw_not_found(parent);
            else
                throw err;
        }
        
        Gee.Collection<Geary.Folder> folders = new Gee.ArrayList<Geary.Folder>();
        foreach (MailboxInformation mbox in mboxes) {
            Geary.FolderPath path = process_path(processed, mbox.name, mbox.delim);
            
            // only add to delims map if root-level folder (all sub-folders respect its delimiter)
            // also use the processed name, not the one reported off the wire
            if (processed == null)
                delims.set(path.get_root().basename, mbox.delim);
            
            StatusResults? status = null;
            if (!mbox.attrs.contains(MailboxAttribute.NO_SELECT)) {
                try {
                    status = yield session_mgr.status_async(path.get_fullpath(),
                        StatusDataType.all(), cancellable);
                } catch (Error status_err) {
                    message("Unable to fetch status for %s: %s", path.to_string(), status_err.message);
                }
            }
            
            folders.add(new Geary.Imap.Folder(session_mgr, path, status, mbox));
        }
        
        return folders;
    }
    
    public override async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        return yield session_mgr.folder_exists_async(processed.get_fullpath(), cancellable);
    }
    
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        Geary.FolderPath? processed = process_path(path, null, path.get_root().default_separator);
        if (processed == null)
            throw new ImapError.INVALID_PATH("Invalid path %s", path.to_string());
        
        try {
            MailboxInformation? mbox = yield session_mgr.fetch_async(processed.get_fullpath(),
                cancellable);
            if (mbox == null)
                throw_not_found(path);
            
            StatusResults? status = null;
            if (!mbox.attrs.contains(MailboxAttribute.NO_SELECT)) {
                try {
                    status = yield session_mgr.status_async(processed.get_fullpath(),
                        StatusDataType.all(), cancellable);
                } catch (Error status_err) {
                    debug("Unable to get status for %s: %s", processed.to_string(), status_err.message);
                }
            }
            
            return new Geary.Imap.Folder(session_mgr, processed, status, mbox);
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
    
    // This method ensures that Inbox is dealt with in a consistent fashion throughout the
    // application.
    private static Geary.FolderPath? process_path(Geary.FolderPath? parent, string? basename,
        string? delim) throws ImapError {
        bool empty_basename = String.is_empty(basename);
        
        // 1. Both null, done
        if (parent == null && empty_basename)
            return null;
        
        // 2. Parent null but basename not, create FolderRoot for Inbox
        if (parent == null && !empty_basename && basename.up() == INBOX_NAME)
            return new Geary.FolderRoot(INBOX_NAME, delim, false);
        
        // 3. Parent and basename supplied, verify parent is not Inbox, as IMAP does not allow it
        //    to have children
        if (parent != null && !empty_basename && parent.get_root().basename.up() == INBOX_NAME)
            throw new ImapError.INVALID_PATH("Inbox may not have children");
        
        // 4. Parent supplied but basename is not; if parent points to Inbox, normalize it
        if (parent != null && empty_basename && parent.basename.up() == INBOX_NAME)
            return new Geary.FolderRoot(INBOX_NAME, delim, false);
        
        // 5. Default behavior: create child of basename or basename as root, otherwise return parent
        //    unmodified
        if (parent != null && !empty_basename)
            return parent.get_child(basename);
        
        if (!empty_basename)
            return new Geary.FolderRoot(basename, delim, Folder.CASE_SENSITIVE);
        
        return parent;
    }
    
    public async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error {
        Geary.RFC822.Message rfc822 = new Geary.RFC822.Message.from_composed_email(composed);
        assert(rfc822.message != null);
        
        yield smtp.login_async(cred, cancellable);
        try {
            yield smtp.send_email_async(rfc822.message, cancellable);
        } finally {
            // always logout
            try {
                yield smtp.logout_async(cancellable);
            } catch (Error err) {
                message("Unable to disconnect from SMTP server %s: %s", smtp.to_string(), err.message);
            }
        }
    }
}

