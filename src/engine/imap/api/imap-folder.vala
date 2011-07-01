/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Folder : Geary.AbstractFolder, Geary.RemoteFolder {
    public const bool CASE_SENSITIVE = true;
    
    private ClientSessionManager session_mgr;
    private MailboxInformation info;
    private Geary.FolderPath path;
    private Trillian readonly;
    private Imap.FolderProperties properties;
    private Mailbox? mailbox = null;
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        readonly = Trillian.UNKNOWN;
        properties = new Imap.FolderProperties(null, info.attrs);
    }
    
    public override Geary.FolderPath get_path() {
        return path;
    }
    
    public Trillian is_readonly() {
        return readonly;
    }
    
    public override Geary.FolderProperties? get_properties() {
        return properties;
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (mailbox != null)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        mailbox = yield session_mgr.select_examine_mailbox(path.get_fullpath(info.delim), !readonly,
            cancellable);
        // TODO: hook up signals
        
        this.readonly = Trillian.from_boolean(readonly);
        properties.uid_validity = mailbox.uid_validity;
        
        notify_opened();
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            return;
        
        mailbox = null;
        readonly = Trillian.UNKNOWN;
        properties.uid_validity = null;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
    }
    
    public override async int get_email_count(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.count;
    }
    
    public override async void create_email_async(Geary.Email email, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        throw new EngineError.READONLY("IMAP currently read-only");
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.range(low, count), fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.sparse(by_position), fields, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(int position, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        // TODO: If position out of range, throw EngineError.NOT_FOUND
        
        return yield mailbox.fetch_async(position, fields, cancellable);
    }
}

