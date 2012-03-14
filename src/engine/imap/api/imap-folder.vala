/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.Folder : Geary.AbstractFolder, Geary.RemoteFolder {
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
    
    protected void notify_message_at_removed(int position, int total) {
        message_at_removed(position, total);
    }
    
    public override Geary.FolderPath get_path() {
        return path;
    }
    
    public override Geary.FolderProperties? get_properties() {
        return properties;
    }
    
    public override Geary.Folder.ListFlags get_supported_list_flags() {
        return Geary.Folder.ListFlags.NONE;
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
        
        notify_opened(Geary.Folder.OpenState.REMOTE, mailbox.exists);
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
    
    private void on_flags_altered(MailboxAttributes flags) {
        assert(mailbox != null);
        // TODO: Notify of changes
    }
    
    private void on_expunged(MessageNumber expunged, int total) {
        assert(mailbox != null);
        
        notify_message_at_removed(expunged.value, total);
    }
    
    public override async int get_email_count_async(Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return mailbox.exists;
    }
    
    public override async bool create_email_async(Geary.Email email, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        throw new EngineError.READONLY("IMAP currently read-only");
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count, Geary.Email.Field fields,
        Geary.Folder.ListFlags flags, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        normalize_span_specifiers(ref low, ref count, mailbox.exists);
        
        return yield mailbox.list_set_async(new MessageSet.range(low, count), fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        return yield mailbox.list_set_async(new MessageSet.sparse(by_position), fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier email_id,
        int count, Geary.Email.Field fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
            throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        UID uid = ((Imap.EmailIdentifier) email_id).uid;
        if (flags.is_all_set(Geary.Folder.ListFlags.EXCLUDING_ID)) {
            if (count > 1)
                uid = new UID(uid.value + 1);
            else if (count < 0)
                uid = new UID(uid.value - 1);
        }
        
        MessageSet msg_set;
        if (count > 0) {
            msg_set = (count == int.MAX)
                ? new MessageSet.uid_range_to_highest(uid)
                : new MessageSet.uid_range_by_count(uid, count);
        } else if (count < 0) {
            msg_set = (count != int.MIN)
                ? new MessageSet.uid_range(new UID(1), uid)
                : new MessageSet.uid_range_by_count(uid, count);
        } else {
            // count == 0
            msg_set = new MessageSet.uid(uid);
        }
        
        return yield mailbox.list_set_async(msg_set, fields, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<Geary.Email>? list = yield mailbox.list_set_async(
            new MessageSet.uid(((Imap.EmailIdentifier) id).uid), fields, cancellable);
        
        if (list == null || list.size == 0) {
            throw new EngineError.NOT_FOUND("Unable to fetch email %s from %s", id.to_string(),
                to_string());
        }
        
        if (list.size != 1) {
            throw new EngineError.BAD_RESPONSE("Too many responses (%d) from %s when fetching %s",
                list.size, to_string(), id.to_string());
        }
        
        return list[0];
    }
    
    public override async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids, 
        Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        flags.add(MessageFlag.DELETED);
        
        yield mailbox.mark_email_async(message_set_from_id_list(email_ids), flags, null, cancellable);
        yield mailbox.expunge_email_async(cancellable);
    }
    
    public override async void mark_email_async(
        Gee.List<Geary.EmailIdentifier> to_mark, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable = null) throws Error {
        if (mailbox == null)
            throw new EngineError.OPEN_REQUIRED("%s not opened", to_string());
        
        Gee.List<MessageFlag> msg_flags_add = new Gee.ArrayList<MessageFlag>();
        Gee.List<MessageFlag> msg_flags_remove = new Gee.ArrayList<MessageFlag>();
        MessageFlag.from_email_flags(flags_to_add, flags_to_remove, out msg_flags_add, 
            out msg_flags_remove);
        
        yield mailbox.mark_email_async(message_set_from_id_list(to_mark), msg_flags_add,
            msg_flags_remove, cancellable);
    }
    
    private MessageSet message_set_from_id_list(Gee.List<Geary.EmailIdentifier> list) {
        Geary.Imap.UID[] sparse_set = new Geary.Imap.UID[list.size];
        int i = 0;
        foreach(Geary.EmailIdentifier id in list) {
            sparse_set[i] = ((Geary.Imap.EmailIdentifier) id).uid;
            i++;
        }
        
        return new MessageSet.uid_sparse(sparse_set);
    }
}

