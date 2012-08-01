/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
 
public class MessageListStore : Gtk.ListStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS;
    
    public const Geary.Email.Field WITH_PREVIEW_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS | Geary.Email.Field.PREVIEW;
    
    public enum Column {
        MESSAGE_DATA,
        MESSAGE_OBJECT;
        
        public static Type[] get_types() {
            return {
                typeof (FormattedMessageData), // MESSAGE_DATA
                typeof (Geary.Conversation)    // MESSAGE_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case MESSAGE_DATA:
                    return "data";
                case MESSAGE_OBJECT:
                    return "envelope";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public string? account_owner_email { get; set; default = null; }
    
    private Geary.ConversationMonitor conversation_monitor;
    private Geary.Folder? current_folder = null;
    private Cancellable? cancellable_folder = null;
    private bool loading_local_only = true;
    private int conversations_added_counter = 0;
    
    public signal void conversations_added_began();
    
    public signal void conversations_added_finished();
    
    public MessageListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(Gtk.SortColumn.DEFAULT, Gtk.SortType.DESCENDING);
        
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
    }
    
    ~MessageListStore() {
        set_conversation_monitor(null);
    }
    
    public void set_conversation_monitor(Geary.ConversationMonitor? new_conversation_monitor) {
        if (conversation_monitor != null) {
            conversation_monitor.scan_completed.disconnect(on_scan_completed);
            conversation_monitor.conversations_added.disconnect(on_conversations_added);
            conversation_monitor.conversation_removed.disconnect(on_conversation_removed);
            conversation_monitor.conversation_appended.disconnect(on_conversation_appended);
            conversation_monitor.conversation_trimmed.disconnect(on_conversation_trimmed);
            conversation_monitor.email_flags_changed.disconnect(on_email_flags_changed);
        }
        
        clear();
        conversation_monitor = new_conversation_monitor;
        
        if (conversation_monitor != null) {
            conversation_monitor.scan_completed.connect(on_scan_completed);
            conversation_monitor.conversations_added.connect(on_conversations_added);
            conversation_monitor.conversation_removed.connect(on_conversation_removed);
            conversation_monitor.conversation_appended.connect(on_conversation_appended);
            conversation_monitor.conversation_trimmed.connect(on_conversation_trimmed);
            conversation_monitor.email_flags_changed.connect(on_email_flags_changed);
        }
    }
    
    public void set_current_folder(Geary.Folder? current_folder, Cancellable? cancellable_folder) {
        this.current_folder = current_folder;
        this.cancellable_folder = cancellable_folder;
    }
    
    public Geary.EmailIdentifier? get_lowest_email_id() {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return null;
        
        Geary.EmailIdentifier? lowest_id = null;
        do {
            Geary.Conversation? conversation = get_conversation_at_iter(iter);
            if (conversation == null)
                continue;
            
            Gee.List<Geary.Email> emails = conversation.get_emails(Geary.Conversation.Ordering.ID_DESCENDING);
            if (emails.size == 0)
                continue;
            
            Geary.EmailIdentifier id = emails.first().id;
            if (lowest_id == null || id.ordering < lowest_id.ordering)
                lowest_id = id;
        } while (iter_next(ref iter));
        
        return lowest_id;
    }
    
    public Geary.Conversation? get_conversation_at_path(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        return get_conversation_at_iter(iter);
    }
    
    public Gtk.TreePath? get_path_for_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter))
            return null;
        
        return get_path(iter);
    }
    
    private async void refresh_previews_async(Geary.ConversationMonitor conversation_monitor) {
        if (current_folder == null || !GearyApplication.instance.config.display_preview)
            return;
        
        Gee.Collection<Geary.EmailIdentifier> emails_needing_previews = get_emails_needing_previews();
        if (emails_needing_previews.size < 1)
            return;
            
        Geary.Folder.ListFlags flags = (loading_local_only) ? Geary.Folder.ListFlags.LOCAL_ONLY
            : Geary.Folder.ListFlags.NONE;
        Gee.List<Geary.Email>? emails = null;
        try {
            emails = yield current_folder.list_email_by_sparse_id_async(emails_needing_previews,
                MessageListStore.WITH_PREVIEW_FIELDS, flags, cancellable_folder);
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }
        
        if (current_folder == null || emails == null)
            return;
        
        foreach (Geary.Email email in emails) {
            Geary.Conversation? conversation = conversation_monitor.get_conversation_for_email(email.id);
            if (conversation != null)
                set_preview_for_conversation(conversation, email);
            else
                debug("Couldn't find conversation for %s", email.id.to_string());
        }
    }
    
    private Gee.Collection<Geary.EmailIdentifier> get_emails_needing_previews() {
        // sort the conversations so the previews are fetched from the newest to the oldest, matching
        // the user experience
        Gee.TreeSet<Geary.Conversation> sorted_conversations = new Gee.TreeSet<Geary.Conversation>(
            (CompareFunc) compare_conversation_descending);
        sorted_conversations.add_all(conversation_monitor.get_conversations());
        
        Gee.Set<Geary.EmailIdentifier> emails_needing_previews = new Gee.HashSet<Geary.EmailIdentifier>(
            Geary.Hashable.hash_func, Geary.Equalable.equal_func);
        foreach (Geary.Conversation conversation in sorted_conversations) {
            Geary.Email? need_preview = conversation.get_latest_email();
            Geary.Email? current_preview = get_preview_for_conversation(conversation);
            
            // if all preview fields present and it's the same email, don't need to refresh
            if (need_preview == null || (current_preview != null &&
                need_preview.id.equals(current_preview.id) &&
                current_preview.fields.is_all_set(MessageListStore.WITH_PREVIEW_FIELDS))) {
                continue;
            }
            
            emails_needing_previews.add(need_preview.id);
        }
        
        return emails_needing_previews;
    }
    
    private Geary.Email? get_preview_for_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            debug("Unable to find preview for conversation");
            return null;
        }
        
        FormattedMessageData? message_data = get_message_data_at_iter(iter);
        return message_data == null ? null : message_data.preview;
    }
    
    private void set_preview_for_conversation(Geary.Conversation conversation, Geary.Email preview) {
        Gtk.TreeIter iter;
        if (get_iter_for_conversation(conversation, out iter))
            set_row(iter, conversation, preview);
        else
            debug("Unable to find preview for conversation");
    }
    
    private void set_row(Gtk.TreeIter iter, Geary.Conversation conversation, Geary.Email preview) {
        FormattedMessageData message_data = new FormattedMessageData(conversation, preview,
            current_folder, account_owner_email);
        set(iter,
            Column.MESSAGE_DATA, message_data,
            Column.MESSAGE_OBJECT, conversation);
    }
    
    private void refresh_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            add_conversation(conversation);
            return;
        }
        
        Geary.Email? last_email = conversation.get_latest_email();
        if (last_email == null) {
            remove(iter);
            return;
        }
        
        FormattedMessageData? existing_message_data = get_message_data_at_iter(iter);
        
        if (existing_message_data == null || !existing_message_data.preview.id.equals(last_email.id))
            set_row(iter, conversation, last_email);
    }
    
    private void refresh_flags(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            add_conversation(conversation);
            return;
        }
        
        FormattedMessageData? existing_message_data = get_message_data_at_iter(iter);
        if (existing_message_data == null)
            return;
        
        existing_message_data.is_unread = conversation.is_unread();
        existing_message_data.is_flagged = conversation.is_flagged();
        
        Gtk.TreePath? path = get_path(iter);
        if (path != null)
            row_changed(path, iter);
    }
    
    private bool get_iter_for_conversation(Geary.Conversation conversation, out Gtk.TreeIter iter) {
        if (!get_iter_first(out iter))
            return false;
        
        do {
            if (get_conversation_at_iter(iter) == conversation)
                return true;
        } while (iter_next(ref iter));
        
        return false;
    }
    
    private bool has_conversation(Geary.Conversation conversation) {
        return get_iter_for_conversation(conversation, null);
    }
    
    private Geary.Conversation? get_conversation_at_iter(Gtk.TreeIter iter) {
        Geary.Conversation? conversation;
        get(iter, Column.MESSAGE_OBJECT, out conversation);
        
        return conversation;
    }
    
    private FormattedMessageData? get_message_data_at_iter(Gtk.TreeIter iter) {
        FormattedMessageData? message_data;
        get(iter, Column.MESSAGE_DATA, out message_data);
        
        return message_data;
    }
    
    private void remove_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (get_iter_for_conversation(conversation, out iter))
            remove(iter);
    }
    
    private void add_conversation(Geary.Conversation conversation) {
        Geary.Email? last_email = conversation.get_latest_email();
        if (last_email == null)
            return;
        
        if (has_conversation(conversation))
            return;
        
        Gtk.TreeIter iter;
        append(out iter);
        set_row(iter, conversation, last_email);
    }
    
    private void on_scan_completed(Geary.ConversationMonitor sender) {
        refresh_previews_async.begin(sender);
        
        if (!loading_local_only)
            return;
        
        debug("Loading all emails now");
        loading_local_only = false;
        sender.lazy_load(-1, GearyController.FETCH_EMAIL_CHUNK_COUNT, Geary.Folder.ListFlags.NONE,
            cancellable_folder);
    }
    
    private void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        conversations_added_began();
        
        debug("Adding %d conversations.", conversations.size);
        foreach (Geary.Conversation conversation in conversations)
            add_conversation(conversation);
        int stage = ++conversations_added_counter;
        debug("Added %d conversations. (%d)", conversations.size, stage);
        
        while (Gtk.events_pending()) {
            if (Gtk.main_iteration() || conversations_added_counter != stage)
                return;
        }
        
        conversations_added_finished();
    }
    
    private void on_conversation_removed(Geary.Conversation conversation) {
        remove_conversation(conversation);
    }
    
    private void on_conversation_appended(Geary.Conversation conversation) {
        if (has_conversation(conversation))
            refresh_conversation(conversation);
    }
    
    private void on_conversation_trimmed(Geary.Conversation conversation) {
        refresh_conversation(conversation);
    }
    
    private void on_display_preview_changed() {
        refresh_previews_async.begin(conversation_monitor);
    }
    
    private void on_email_flags_changed(Geary.Conversation conversation) {
        refresh_flags(conversation);
    }
    
    private int sort_by_date(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        Geary.Conversation a, b;
        
        get(aiter, Column.MESSAGE_OBJECT, out a);
        get(biter, Column.MESSAGE_OBJECT, out b);
        
        return compare_conversation_ascending(a, b);
    }
}

