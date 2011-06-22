/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Folder : Object, Geary.Folder {
    private ClientSessionManager session_mgr;
    private MailboxInformation info;
    private string name;
    private Trillian readonly;
    private Imap.FolderProperties properties;
    private Mailbox? mailbox = null;
    
    internal Folder(ClientSessionManager session_mgr, MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        
        name = info.name;
        readonly = Trillian.UNKNOWN;
        properties = new Imap.FolderProperties(null, info.attrs);
    }
    
    public string get_name() {
        return name;
    }
    
    public Trillian is_readonly() {
        return readonly;
    }
    
    public Geary.FolderProperties? get_properties() {
        return properties;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (mailbox != null)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        mailbox = yield session_mgr.select_examine_mailbox(name, !readonly, cancellable);
        // hook up signals
        
        this.readonly = Trillian.from_boolean(readonly);
        properties.uid_validity = mailbox.uid_validity;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        mailbox = null;
        readonly = Trillian.UNKNOWN;
        properties.uid_validity = null;
    }
    
    public int get_message_count() throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.count;
    }
    
    public async void create_email_async(Geary.Email email, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.READONLY("IMAP currently read-only");
    }
    
    public async Gee.List<Geary.Email>? list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.range(low, count), fields, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.sparse(by_position), fields, cancellable);
    }
    
    public async Geary.Email fetch_email_async(int position, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.fetch_async(position, fields, cancellable);
    }
    
    public string to_string() {
        return name;
    }
}

