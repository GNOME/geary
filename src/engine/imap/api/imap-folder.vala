/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.Folder : Object {
    public const bool CASE_SENSITIVE = true;
    
    public bool is_open { get; private set; default = false; }
    public FolderPath path { get; private set; }
    public Imap.FolderProperties properties { get; private set; }
    public MailboxInformation info { get; private set; }
    public Trillian readonly { get; private set; }
    
    private ClientSessionManager session_mgr;
    private ClientSession? session = null;
    
    public signal void exists(int count);
    
    public signal void expunge(MessageNumber num);
    
    public signal void fetch(FetchedData fetched);
    
    public signal void recent(int count);
    
    /**
     * Note that close_async() still needs to be called after this signal is fired.
     */
    public signal void disconnected(Geary.Folder.CloseReason reason);
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, StatusData? status,
        MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        readonly = Trillian.UNKNOWN;
        
        properties = (status != null)
            ? new Imap.FolderProperties.status(status, info.attrs)
            : new Imap.FolderProperties(0, 0, 0, null, null, info.attrs);
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        is_open = true;
        
        session = yield session_mgr.claim_authorized_session_async(cancellable);
        
        // connect to interesting signals *before* SELECTing
        session.exists.connect(on_exists);
        session.expunge.connect(on_expunge);
        session.fetch.connect(on_fetch);
        session.recent.connect(on_recent);
        session.coded_status_response.connect(on_coded_status_response);
        session.disconnected.connect(on_disconnected);
        
        CompletionStatusResponse response = yield session.select_examine_async(path.get_fullpath(info.delim),
            !readonly, cancellable);
        if (response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Unable to SELECT %s: %s", path.to_string(), response.to_string());
        
        // update with new information
        this.readonly = Trillian.from_boolean(readonly);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (!is_open)
            return;
        
        session.exists.disconnect(on_exists);
        session.expunge.disconnect(on_expunge);
        session.fetch.disconnect(on_fetch);
        session.recent.disconnect(on_recent);
        session.coded_status_response.disconnect(on_coded_status_response);
        session.disconnected.disconnect(on_disconnected);
        
        try {
            yield session.close_mailbox_async(cancellable);
            yield session_mgr.release_session_async(session, cancellable);
        } finally {
            session = null;
            readonly = Trillian.UNKNOWN;
            
            is_open = false;
        }
    }
    
    private void on_exists(int count) {
        properties.messages = count;
        
        exists(count);
    }
    
    private void on_expunge(MessageNumber num) {
        expunge(num);
    }
    
    private void on_fetch(FetchedData fetched) {
        fetch(fetched);
    }
    
    private void on_recent(int count) {
        properties.recent = count;
        
        recent(count);
    }
    
    private void on_coded_status_response(CodedStatusResponse coded_response) {
        switch (coded_response.response_code_type) {
            case ResponseCodeType.UIDNEXT:
                properties.uid_next = coded_response.get_uid_next();
            break;
        }
    }
    
    private void on_completion_status_response(CompletionStatusResponse completion_response) {
    /*
            case ResponseCodeType.READONLY:
                readonly = Trillian.TRUE;
            break;
            
            case ResponseCodeType.READWRITE:
                readonly = Trillian.FALSE;
            break;
            
    */
    }
    
    private void on_disconnected(Geary.Folder.CloseReason reason) {
        disconnected(reason);
    }
    
    public async Gee.List<Geary.Email>? list_email_async(MessageSet msg_set, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(msg_set, fields, cancellable);
    }
    
    public async void remove_email_async(MessageSet msg_set, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);
        
        yield mailbox.mark_email_async(msg_set, flags, null, cancellable);
        
        // mailbox could've closed during call
        if (mailbox != null)
            yield mailbox.expunge_email_async(msg_set, cancellable);
    }
    
    public async void mark_email_async(MessageSet msg_set, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add, 
            out msg_flags_remove);
        
        yield mailbox.mark_email_async(msg_set, msg_flags_add, msg_flags_remove, cancellable);
    }

    public async void copy_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());

        yield mailbox.copy_email_async(msg_set, destination, cancellable);
    }

    public async void move_email_async(MessageSet msg_set, Geary.FolderPath destination,
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());

        yield copy_email_async(msg_set, destination, cancellable);
        yield remove_email_async(msg_set, cancellable);
    }

    public string to_string() {
        return path.to_string();
    }
}

