/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.Folder : Object {
    public const bool CASE_SENSITIVE = true;
    
    private ClientSessionManager session_mgr;
    private MailboxInformation info;
    private Geary.FolderPath path;
    private Trillian readonly;
    private Imap.FolderProperties properties;
    private Mailbox? mailbox = null;
    
    public signal void messages_appended(int exists);
    
    public signal void message_at_removed(int position, int total);
    
    public signal void disconnected(Geary.Folder.CloseReason reason);
    
    internal Folder(ClientSessionManager session_mgr, Geary.FolderPath path, StatusResults? status,
        MailboxInformation info) {
        this.session_mgr = session_mgr;
        this.info = info;
        this.path = path;
        
        readonly = Trillian.UNKNOWN;
        
        properties = (status != null)
            ? new Imap.FolderProperties.status(status, info.attrs)
            : new Imap.FolderProperties(0, 0, 0, null, null, info.attrs);
    }
    
    public Geary.FolderPath get_path() {
        return path;
    }
    
    public Geary.Imap.FolderProperties get_properties() {
        return properties;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
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
        mailbox.disconnected.connect(on_disconnected);
        
        properties = new Imap.FolderProperties(mailbox.exists, mailbox.recent, mailbox.unseen,
            mailbox.uid_validity, mailbox.uid_next, properties.attrs);
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        disconnect_mailbox();
    }
    
    private void disconnect_mailbox() {
        if (mailbox == null)
            return;
        
        mailbox.exists_altered.disconnect(on_exists_altered);
        mailbox.flags_altered.disconnect(on_flags_altered);
        mailbox.expunged.disconnect(on_expunged);
        mailbox.disconnected.disconnect(on_disconnected);
        
        mailbox = null;
        readonly = Trillian.UNKNOWN;
    }
    
    private void on_exists_altered(int old_exists, int new_exists) {
        assert(mailbox != null);
        assert(old_exists != new_exists);
        
        // only use this signal to notify of additions; removals are handled with the expunged
        // signal
        if (new_exists > old_exists)
            messages_appended(new_exists);
    }
    
    private void on_flags_altered(MailboxAttributes flags) {
        assert(mailbox != null);
        // TODO: Notify of changes
    }
    
    private void on_expunged(MessageNumber expunged, int total) {
        assert(mailbox != null);
        
        message_at_removed(expunged.value, total);
    }
    
    private void on_disconnected(Geary.Folder.CloseReason reason) {
        disconnect_mailbox();
        
        disconnected(reason);
    }
    
    public int get_email_count() throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.exists;
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
    
    public string to_string() {
        return path.to_string();
    }
}

