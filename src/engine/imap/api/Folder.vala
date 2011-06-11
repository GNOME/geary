/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Folder : Object, Geary.Folder {
    public string name { get; protected set; }
    // This is only for when a context has been selected
    public Trillian is_readonly { get; protected set; }
    public Trillian supports_children { get; protected set; }
    public Trillian has_children { get; protected set; }
    public Trillian is_openable { get; protected set; }
    
    private ClientSessionManager session_mgr;
    private MailboxInformation info;
    private Mailbox? mailbox = null;
    
    internal Folder(ClientSessionManager session_mgr, MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        
        name = info.name;
        is_readonly = Trillian.UNKNOWN;
        supports_children = Trillian.from_boolean(!info.attrs.contains(MailboxAttribute.NO_INFERIORS));
        // \HasNoChildren is an optional attribute and lack of presence doesn't indiciate anything
        has_children = info.attrs.contains(MailboxAttribute.HAS_NO_CHILDREN) ? Trillian.TRUE
            : Trillian.UNKNOWN;
        is_openable = Trillian.from_boolean(!info.attrs.contains(MailboxAttribute.NO_SELECT));
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (mailbox != null)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        mailbox = yield session_mgr.select_examine_mailbox(name, !readonly, cancellable);
        // hook up signals
        
        this.is_readonly = Trillian.from_boolean(readonly);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        mailbox = null;
        is_readonly = Trillian.UNKNOWN;
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

