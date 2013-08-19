/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
 
public class ConversationListStore : Gtk.ListStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS | Geary.Email.Field.PROPERTIES;
    
    public const Geary.Email.Field WITH_PREVIEW_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS | Geary.Email.Field.PROPERTIES | Geary.Email.Field.PREVIEW;
    
    public enum Column {
        CONVERSATION_DATA,
        CONVERSATION_OBJECT;
        
        public static Type[] get_types() {
            return {
                typeof (FormattedConversationData), // CONVERSATION_DATA
                typeof (Geary.App.Conversation)     // CONVERSATION_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case CONVERSATION_DATA:
                    return "data";
                case CONVERSATION_OBJECT:
                    return "envelope";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public string? account_owner_email { get; set; default = null; }
    public Geary.ProgressMonitor preview_monitor { get; private set; default = 
        new Geary.SimpleProgressMonitor(Geary.ProgressType.ACTIVITY); }
    
    private Geary.App.ConversationMonitor conversation_monitor;
    private Geary.Folder? current_folder = null;
    private Geary.App.EmailStore? email_store = null;
    private Cancellable? cancellable_folder = null;
    private bool loading_local_only = true;
    private int conversations_added_counter = 0;
    private Geary.Nonblocking.Mutex refresh_mutex = new Geary.Nonblocking.Mutex();
    private uint update_id = 0;
    
    public signal void conversations_added_began();
    
    public signal void conversations_added_finished();
    
    public ConversationListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(Gtk.SortColumn.DEFAULT, Gtk.SortType.DESCENDING);
        
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
        update_id = Timeout.add_seconds_full(Priority.LOW, 60, update_date_strings);
        
        GearyApplication.instance.controller.notify[GearyController.PROP_CURRENT_CONVERSATION].
            connect(on_conversation_monitor_changed);
    }
    
    ~ConversationListStore() {
        if (update_id != 0)
            Source.remove(update_id);
    }
    
    private void on_conversation_monitor_changed() {
        if (conversation_monitor != null) {
            conversation_monitor.scan_completed.disconnect(on_scan_completed);
            conversation_monitor.conversations_added.disconnect(on_conversations_added);
            conversation_monitor.conversation_removed.disconnect(on_conversation_removed);
            conversation_monitor.conversation_appended.disconnect(on_conversation_appended);
            conversation_monitor.conversation_trimmed.disconnect(on_conversation_trimmed);
            conversation_monitor.email_flags_changed.disconnect(on_email_flags_changed);
        }
        
        clear();
        conversation_monitor = GearyApplication.instance.controller.current_conversations;
        
        if (conversation_monitor != null) {
            // add all existing conversations
            on_conversations_added(conversation_monitor.get_conversations());
            
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
        email_store = (current_folder == null ? null : new Geary.App.EmailStore(current_folder.account));
    }
    
    public Geary.EmailIdentifier? get_lowest_email_id() {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return null;
        
        Geary.EmailIdentifier? lowest_id = null;
        do {
            Geary.App.Conversation? conversation = get_conversation_at_iter(iter);
            if (conversation == null)
                continue;
            
            Geary.EmailIdentifier? conversation_lowest = conversation.get_lowest_email_id();
            if (conversation_lowest == null)
                continue;
            
            if (lowest_id == null || conversation_lowest.natural_sort_comparator(lowest_id) < 0)
                lowest_id = conversation_lowest;
        } while (iter_next(ref iter));
        
        return lowest_id;
    }
    
    public Geary.App.Conversation? get_conversation_at_path(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        return get_conversation_at_iter(iter);
    }
    
    public Gtk.TreePath? get_path_for_conversation(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter))
            return null;
        
        return get_path(iter);
    }
    
    private async void refresh_previews_async(Geary.App.ConversationMonitor conversation_monitor) {
        // Use a mutex because it's possible for the conversation monitor to fire multiple
        // "scan-started" signals as messages come in fast and furious, but only want to process
        // previews one at a time, otherwise it's possible to issue multiple requests for the
        // same set
        int token;
        try {
            token = yield refresh_mutex.claim_async();
        } catch (Error err) {
            debug("Unable to claim refresh mutex: %s", err.message);
            
            return;
        }
        
        preview_monitor.notify_start();
        
        yield do_refresh_previews_async(conversation_monitor);
        
        preview_monitor.notify_finish();
        
        try {
            refresh_mutex.release(ref token);
        } catch (Error err) {
            debug("Unable to release refresh mutex: %s", err.message);
        }
    }
    
    // should only be called by refresh_previews_async()
    private async void do_refresh_previews_async(Geary.App.ConversationMonitor conversation_monitor) {
        if (current_folder == null || !GearyApplication.instance.config.display_preview)
            return;
        
        Gee.Set<Geary.EmailIdentifier> needing_previews = get_emails_needing_previews();
        
        Gee.ArrayList<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        if (needing_previews.size > 0)
            emails.add_all(yield do_get_previews_async(needing_previews));
        if (emails.size < 1)
            return;
        
        debug("Displaying %d previews for %s...", emails.size, current_folder.to_string());
        foreach (Geary.Email email in emails) {
            Geary.App.Conversation? conversation = conversation_monitor.get_conversation_for_email(email.id);
            if (conversation != null)
                set_preview_for_conversation(conversation, email);
            else
                debug("Couldn't find conversation for %s", email.id.to_string());
        }
        debug("Displayed %d previews for %s", emails.size, current_folder.to_string());
    }
    
    private async Gee.Collection<Geary.Email> do_get_previews_async(
        Gee.Collection<Geary.EmailIdentifier> emails_needing_previews) {
        Geary.Folder.ListFlags flags = (loading_local_only) ? Geary.Folder.ListFlags.LOCAL_ONLY
            : Geary.Folder.ListFlags.NONE;
        Gee.Collection<Geary.Email>? emails = null;
        try {
            debug("Loading %d previews...", emails_needing_previews.size);
            emails = yield email_store.list_email_by_sparse_id_async(emails_needing_previews,
                ConversationListStore.WITH_PREVIEW_FIELDS, flags, cancellable_folder);
            debug("Loaded %d previews...", emails_needing_previews.size);
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }
        
        return emails ?? new Gee.ArrayList<Geary.Email>();
    }
    
    private Gee.Set<Geary.EmailIdentifier> get_emails_needing_previews() {
        Gee.Set<Geary.EmailIdentifier> needing = new Gee.HashSet<Geary.EmailIdentifier>();
        
        // sort the conversations so the previews are fetched from the newest to the oldest, matching
        // the user experience
        Gee.TreeSet<Geary.App.Conversation> sorted_conversations
            = new Geary.Collection.FixedTreeSet<Geary.App.Conversation>(
            compare_conversation_descending);
        sorted_conversations.add_all(conversation_monitor.get_conversations());
        foreach (Geary.App.Conversation conversation in sorted_conversations) {
            // find oldest unread message for the preview
            Geary.Email? need_preview = null;
            foreach (Geary.Email email in conversation.get_emails(Geary.App.Conversation.Ordering.DATE_ASCENDING)) {
                if (email.email_flags.is_unread()) {
                    need_preview = email;
                    
                    break;
                }
            }
            
            // if all are read, use newest in-folder message
            if (need_preview == null)
                need_preview = conversation.get_latest_email(true);
            
            if (need_preview == null)
                continue;
            
            Geary.Email? current_preview = get_preview_for_conversation(conversation);
            
            // if all preview fields present and it's the same email, don't need to refresh
            if (current_preview != null
                && need_preview.id.equal_to(current_preview.id)
                && current_preview.fields.is_all_set(ConversationListStore.WITH_PREVIEW_FIELDS)) {
                continue;
            }
            
            needing.add(need_preview.id);
        }
        
        return needing;
    }
    
    private Geary.Email? get_preview_for_conversation(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            debug("Unable to find preview for conversation");
            
            return null;
        }
        
        FormattedConversationData? message_data = get_message_data_at_iter(iter);
        return message_data == null ? null : message_data.preview;
    }
    
    private void set_preview_for_conversation(Geary.App.Conversation conversation, Geary.Email preview) {
        Gtk.TreeIter iter;
        if (get_iter_for_conversation(conversation, out iter))
            set_row(iter, conversation, preview);
        else
            debug("Unable to find preview for conversation");
    }
    
    private void set_row(Gtk.TreeIter iter, Geary.App.Conversation conversation, Geary.Email preview) {
        FormattedConversationData conversation_data = new FormattedConversationData(conversation,
            preview, current_folder, account_owner_email);
        set(iter,
            Column.CONVERSATION_DATA, conversation_data,
            Column.CONVERSATION_OBJECT, conversation);
    }
    
    private void refresh_conversation(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            add_conversation(conversation);
            return;
        }
        
        Geary.Email? last_email = conversation.get_latest_email();
        if (last_email == null) {
            debug("Cannot refresh conversation: last email is null");
            
            remove(iter);
            return;
        }
        
        FormattedConversationData? existing_message_data = get_message_data_at_iter(iter);
        
        if (existing_message_data == null || !existing_message_data.preview.id.equal_to(last_email.id)) {
            set_row(iter, conversation, last_email);
        } else if (existing_message_data != null &&
            existing_message_data.num_emails != conversation.get_count()) {
            existing_message_data.num_emails = conversation.get_count();
            
            Gtk.TreePath? path = get_path(iter);
            if (path != null) {
                row_changed(path, iter);
            } else {
                debug("Cannot refresh conversation: no path for iterator");
            }
        }
    }
    
    private void refresh_flags(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            add_conversation(conversation);
            return;
        }
        
        FormattedConversationData? existing_message_data = get_message_data_at_iter(iter);
        if (existing_message_data == null)
            return;
        
        existing_message_data.is_unread = conversation.is_unread();
        existing_message_data.is_flagged = conversation.is_flagged();
        
        Gtk.TreePath? path = get_path(iter);
        if (path != null)
            row_changed(path, iter);
    }
    
    private bool get_iter_for_conversation(Geary.App.Conversation conversation, out Gtk.TreeIter iter) {
        if (!get_iter_first(out iter))
            return false;
        
        do {
            if (get_conversation_at_iter(iter) == conversation)
                return true;
        } while (iter_next(ref iter));
        
        return false;
    }
    
    private bool has_conversation(Geary.App.Conversation conversation) {
        return get_iter_for_conversation(conversation, null);
    }
    
    private Geary.App.Conversation? get_conversation_at_iter(Gtk.TreeIter iter) {
        Geary.App.Conversation? conversation;
        get(iter, Column.CONVERSATION_OBJECT, out conversation);
        
        return conversation;
    }
    
    private FormattedConversationData? get_message_data_at_iter(Gtk.TreeIter iter) {
        FormattedConversationData? message_data;
        get(iter, Column.CONVERSATION_DATA, out message_data);
        
        return message_data;
    }
    
    private void remove_conversation(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (get_iter_for_conversation(conversation, out iter))
            remove(iter);
    }
    
    private bool add_conversation(Geary.App.Conversation conversation) {
        Geary.Email? last_email = conversation.get_latest_email();
        if (last_email == null) {
            debug("Cannot add conversation: last email is null");
            
            return false;
        }
        
        if (has_conversation(conversation)) {
            debug("Conversation already present; not adding");
            
            return false;
        }
        
        Gtk.TreeIter iter;
        append(out iter);
        set_row(iter, conversation, last_email);
        
        return true;
    }
    
    private void on_scan_completed(Geary.App.ConversationMonitor sender) {
        refresh_previews_async.begin(sender);
        loading_local_only = false;
    }
    
    private void on_conversations_added(Gee.Collection<Geary.App.Conversation> conversations) {
        // this handler is used to initialize the display, so it's possible for an empty list to
        // be passed in (the ConversationMonitor signal should never do this)
        if (conversations.size == 0)
            return;
        
        conversations_added_began();
        
        debug("Adding %d conversations.", conversations.size);
        int added = 0;
        foreach (Geary.App.Conversation conversation in conversations) {
            if (add_conversation(conversation))
                added++;
        }
        int stage = ++conversations_added_counter;
        debug("Added %d/%d conversations. (stage=%d)", added, conversations.size, stage);
        
        while (Gtk.events_pending()) {
            if (Gtk.main_iteration() || conversations_added_counter != stage)
                return;
        }
        
        conversations_added_finished();
    }
    
    private void on_conversation_removed(Geary.App.Conversation conversation) {
        remove_conversation(conversation);
    }
    
    private void on_conversation_appended(Geary.App.Conversation conversation) {
        if (has_conversation(conversation)) {
            refresh_conversation(conversation);
        } else {
            debug("Unable to append conversation; conversation not present in list store");
        }
    }
    
    private void on_conversation_trimmed(Geary.App.Conversation conversation) {
        refresh_conversation(conversation);
    }
    
    private void on_display_preview_changed() {
        refresh_previews_async.begin(conversation_monitor);
    }
    
    private void on_email_flags_changed(Geary.App.Conversation conversation) {
        refresh_flags(conversation);
        
        // refresh previews because the oldest unread message is displayed as the preview, and if
        // that's changed, need to change the preview
        // TODO: need support code to load preview for single conversation, not scan all
        refresh_previews_async.begin(conversation_monitor);
    }
    
    private int sort_by_date(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        Geary.App.Conversation a, b;
        
        get(aiter, Column.CONVERSATION_OBJECT, out a);
        get(biter, Column.CONVERSATION_OBJECT, out b);
        
        return compare_conversation_ascending(a, b);
    }
    
    private bool update_date_strings() {
        this.foreach(update_date_string);
        // Keep calling this SourceFunc
        return true;
    }
    
    private bool update_date_string(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
        FormattedConversationData? message_data;
        model.get(iter, Column.CONVERSATION_DATA, out message_data);
        
        if (message_data != null && message_data.update_date_string())
            row_changed(path, iter);
        
        // Continue iterating, don't stop
        return false;
    }
}

