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
    private Trillian supports_children;
    private Trillian children;
    private Trillian openable;
    private Mailbox? mailbox = null;
    
    internal Folder(ClientSessionManager session_mgr, MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        
        name = info.name;
        readonly = Trillian.UNKNOWN;
        supports_children = Trillian.from_boolean(!info.attrs.contains(MailboxAttribute.NO_INFERIORS));
        // \HasNoChildren is an optional attribute and lack of presence doesn't indiciate anything
        children = info.attrs.contains(MailboxAttribute.HAS_NO_CHILDREN) ? Trillian.TRUE
            : Trillian.UNKNOWN;
        openable = Trillian.from_boolean(!info.attrs.contains(MailboxAttribute.NO_SELECT));
    }
    
    public string get_name() {
        return name;
    }
    
    public Trillian is_readonly() {
        return readonly;
    }
    
    public Trillian does_support_children() {
        return supports_children;
    }
    
    public Trillian has_children() {
        return children;
    }
    
    public Trillian is_openable() {
        return openable;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (mailbox != null)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        mailbox = yield session_mgr.select_examine_mailbox(name, !readonly, cancellable);
        // hook up signals
        
        this.readonly = Trillian.from_boolean(readonly);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        mailbox = null;
        readonly = Trillian.UNKNOWN;
    }
    
    public int get_message_count() throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.count;
    }
    
    public async Gee.List<Geary.EmailHeader>? read_async(int low, int count,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.read(low, count, cancellable);
    }
    
    public async Geary.Email fetch_async(Geary.EmailHeader header,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.fetch(header, cancellable);
    }
    
    public string to_string() {
        return name;
    }
}

