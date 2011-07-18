/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Folder : Geary.AbstractFolder, Geary.RemoteFolder, Geary.Imap.FolderExtensions {
    public const bool CASE_SENSITIVE = true;
    
    private ClientSessionManager session_mgr;
    private MailboxInformation info;
    private Geary.FolderPath path;
    private Trillian readonly;
    private Imap.FolderProperties properties;
    private Mailbox? mailbox = null;
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, StatusResults? status,
        MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        readonly = Trillian.UNKNOWN;
        
        properties = (status != null)
            ? new Imap.FolderProperties.status(status , info.attrs)
            : new Imap.FolderProperties(0, 0, 0, null, null, info.attrs);
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
        
        // update with new information
        this.readonly = Trillian.from_boolean(readonly);
        
        properties = new Imap.FolderProperties(mailbox.count, mailbox.recent, mailbox.unseen,
            mailbox.uid_validity, mailbox.uid_next, properties.attrs);
        
        notify_opened(Geary.Folder.OpenState.REMOTE);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            return;
        
        mailbox = null;
        readonly = Trillian.UNKNOWN;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
    }
    
    public override async int get_email_count(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        // TODO: Need to monitor folder for updates to the message count
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
        
        // TODO: Need to use a monitored count
        normalize_span_specifiers(ref low, ref count, mailbox.count);
        
        return yield mailbox.list_set_async(new MessageSet.range(low, count), fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.sparse(by_position), fields, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_uid_async(Geary.Imap.UID? low,
        Geary.Imap.UID? high, Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        MessageSet msg_set = (high != null)
            ? new MessageSet.uid_range((low != null) ? low : new Geary.Imap.UID(1), high)
            : new MessageSet.uid_range_to_highest(low);
        
        return yield mailbox.list_set_async(msg_set, fields, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(int position, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        // TODO: If position out of range, throw EngineError.NOT_FOUND
        
        return yield mailbox.fetch_async(position, fields, cancellable);
    }
    
    public override async void remove_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Geary.Imap.UID? uid = ((Geary.Imap.EmailLocation) email.location).uid;
        if (uid == null)
            throw new EngineError.NOT_FOUND("Removing email requires UID");
        
        throw new EngineError.READONLY("IMAP currently read-only");
    }
}

