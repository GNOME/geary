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
        
        // update with new information
        this.readonly = Trillian.from_boolean(readonly);
        
        // connect to signals
        mailbox.exists_altered.connect(on_exists_altered);
        mailbox.flags_altered.connect(on_flags_altered);
        mailbox.expunged.connect(on_expunged);
        
        properties = new Imap.FolderProperties(mailbox.exists, mailbox.recent, mailbox.unseen,
            mailbox.uid_validity, mailbox.uid_next, properties.attrs);
        
        notify_opened(Geary.Folder.OpenState.REMOTE);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            return;
        
        mailbox.exists_altered.disconnect(on_exists_altered);
        mailbox.flags_altered.disconnect(on_flags_altered);
        mailbox.expunged.disconnect(on_expunged);
        
        mailbox = null;
        readonly = Trillian.UNKNOWN;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
    }
    
    private void on_exists_altered(int old_exists, int new_exists) {
        assert(mailbox != null);
        assert(old_exists != new_exists);
        
        // only use this signal to notify of additions; removals are handled with the expunged
        // signal
        if (new_exists > old_exists)
            notify_messages_appended(new_exists);
    }
    
    private void on_flags_altered(FetchResults flags) {
        assert(mailbox != null);
        // TODO: Notify of changes
    }
    
    private void on_expunged(MessageNumber expunged, int total) {
        assert(mailbox != null);
        
        notify_message_removed(expunged.value, total);
    }
    
    public override async int get_email_count_async(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.exists;
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
        
        normalize_span_specifiers(ref low, ref count, mailbox.exists);
        
        return yield mailbox.list_set_async(this, new MessageSet.range(low, count), fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(this, new MessageSet.sparse(by_position), fields, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_uid_async(Geary.Imap.UID? low,
        Geary.Imap.UID? high, Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        MessageSet msg_set = (high != null)
            ? new MessageSet.uid_range((low != null) ? low : new Geary.Imap.UID(1), high)
            : new MessageSet.uid_range_to_highest(low);
        
        return yield mailbox.list_set_async(this, msg_set, fields, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        // TODO: If position out of range, throw EngineError.NOT_FOUND
        
        return yield mailbox.fetch_async(this, ((Imap.EmailIdentifier) id).uid, fields, cancellable);
    }
    
    public override async void remove_email_async(int position, Cancellable? cancellable = null)
        throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        throw new EngineError.READONLY("IMAP currently read-only");
    }
}

