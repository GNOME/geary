/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
 
public class ConversationListStore : Gtk.ListStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS;
    
    public const Geary.Email.Field WITH_PREVIEW_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS | Geary.Email.Field.PREVIEW;
    
    public enum Column {
        CONVERSATION_DATA,
        CONVERSATION_OBJECT;
        
        public static Type[] get_types() {
            return {
                typeof (FormattedConversationData), // CONVERSATION_DATA
                typeof (Geary.Conversation)         // CONVERSATION_OBJECT
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
    
    private Geary.ConversationMonitor conversation_monitor;
    private Geary.Folder? current_folder = null;
    private Cancellable? cancellable_folder = null;
    private bool loading_local_only = true;
    private int conversations_added_counter = 0;
    private Geary.Nonblocking.Mutex refresh_mutex = new Geary.Nonblocking.Mutex();
    
    public signal void conversations_added_began();
    
    public signal void conversations_added_finished();
    
    public ConversationListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(Gtk.SortColumn.DEFAULT, Gtk.SortType.DESCENDING);
        
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
    }
    
    ~ConversationListStore() {
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
            
            Geary.EmailIdentifier? conversation_lowest = conversation.get_lowest_email_id();
            if (conversation_lowest == null)
                continue;
            
            if (lowest_id == null || conversation_lowest.compare_to(lowest_id) < 0)
                lowest_id = conversation_lowest;
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
        
        yield do_refresh_previews_async(conversation_monitor);
        
        try {
            refresh_mutex.release(ref token);
        } catch (Error err) {
            debug("Unable to release refresh mutex: %s", err.message);
        }
    }
    
    // should only be called by refresh_previews_async()
    private async void do_refresh_previews_async(Geary.ConversationMonitor conversation_monitor) {
        if (current_folder == null || !GearyApplication.instance.config.display_preview)
            return;
        
        Gee.Collection<Geary.EmailIdentifier> folder_emails_needing_previews;
        Gee.Collection<Geary.EmailIdentifier> account_emails_needing_previews;
        get_emails_needing_previews(out folder_emails_needing_previews, out account_emails_needing_previews);
        
        Gee.ArrayList<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        if (folder_emails_needing_previews.size > 0)
            emails.add_all(yield do_get_folder_previews_async(conversation_monitor,
                folder_emails_needing_previews));
        if (account_emails_needing_previews.size > 0)
            emails.add_all(yield do_get_account_previews_async(conversation_monitor,
                account_emails_needing_previews));
        if (emails.size < 1)
            return;
        
        debug("Displaying %d previews for %s...", emails.size, current_folder.to_string());
        foreach (Geary.Email email in emails) {
            Geary.Conversation? conversation = conversation_monitor.get_conversation_for_email(email.id);
            if (conversation != null)
                set_preview_for_conversation(conversation, email);
            else
                debug("Couldn't find conversation for %s", email.id.to_string());
        }
        debug("Displayed %d previews for %s", emails.size, current_folder.to_string());
    }
    
    private async Gee.List<Geary.Email> do_get_folder_previews_async(
        Geary.ConversationMonitor conversation_monitor,
        Gee.Collection<Geary.EmailIdentifier> emails_needing_previews) {
        Geary.Folder.ListFlags flags = (loading_local_only) ? Geary.Folder.ListFlags.LOCAL_ONLY
            : Geary.Folder.ListFlags.NONE;
        Gee.List<Geary.Email>? emails = null;
        try {
            debug("Loading %d previews for %s...", emails_needing_previews.size, current_folder.to_string());
            emails = yield current_folder.list_email_by_sparse_id_async(emails_needing_previews,
                ConversationListStore.WITH_PREVIEW_FIELDS, flags, cancellable_folder);
            debug("Loaded %d previews for %s...", emails_needing_previews.size, current_folder.to_string());
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }
        
        return emails ?? new Gee.ArrayList<Geary.Email>();
    }
    
    private async Gee.List<Geary.Email> do_get_account_previews_async(
        Geary.ConversationMonitor conversation_monitor,
        Gee.Collection<Geary.EmailIdentifier> emails_needing_previews) {
        debug("Loading %d previews from %s...", emails_needing_previews.size,
            current_folder.account.to_string());
        Gee.List<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        foreach (Geary.EmailIdentifier id in emails_needing_previews) {
            try {
                emails.add(yield current_folder.account.local_fetch_email_async(id,
                    ConversationListStore.WITH_PREVIEW_FIELDS, cancellable_folder));
            } catch (Error err) {
                debug("Unable to fetch preview for %s: %s", id.to_string(), err.message);
            }
        }
        debug("Loaded %d previews from %s...", emails_needing_previews.size,
            current_folder.account.to_string());
        
        return emails;
    }
    
    private void get_emails_needing_previews(out Gee.Collection<Geary.EmailIdentifier> folder_emails,
        out Gee.Collection<Geary.EmailIdentifier> account_emails) {
        // sort the conversations so the previews are fetched from the newest to the oldest, matching
        // the user experience
        Gee.TreeSet<Geary.Conversation> sorted_conversations = new Geary.Collection.FixedTreeSet<Geary.Conversation>(
            compare_conversation_descending);
        sorted_conversations.add_all(conversation_monitor.get_conversations());
        
        folder_emails = new Gee.HashSet<Geary.EmailIdentifier>();
        account_emails = new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (Geary.Conversation conversation in sorted_conversations) {
            Geary.Email? need_preview = conversation.get_latest_email();
            if (need_preview == null)
                continue;
            
            Geary.Email? current_preview = get_preview_for_conversation(conversation);
            
            // if all preview fields present and it's the same email, don't need to refresh
            if (current_preview != null
                && need_preview.id.equal_to(current_preview.id)
                && current_preview.fields.is_all_set(ConversationListStore.WITH_PREVIEW_FIELDS)) {
                continue;
            }
            
            if (need_preview.id.get_folder_path() == null)
                account_emails.add(need_preview.id);
            else
                folder_emails.add(need_preview.id);
        }
    }
    
    private Geary.Email? get_preview_for_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter)) {
            debug("Unable to find preview for conversation");
            
            return null;
        }
        
        FormattedConversationData? message_data = get_message_data_at_iter(iter);
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
        FormattedConversationData conversation_data = new FormattedConversationData(conversation,
            preview, current_folder, account_owner_email);
        set(iter,
            Column.CONVERSATION_DATA, conversation_data,
            Column.CONVERSATION_OBJECT, conversation);
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
    
    private void refresh_flags(Geary.Conversation conversation) {
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
        get(iter, Column.CONVERSATION_OBJECT, out conversation);
        
        return conversation;
    }
    
    private FormattedConversationData? get_message_data_at_iter(Gtk.TreeIter iter) {
        FormattedConversationData? message_data;
        get(iter, Column.CONVERSATION_DATA, out message_data);
        
        return message_data;
    }
    
    private void remove_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (get_iter_for_conversation(conversation, out iter))
            remove(iter);
    }
    
    private bool add_conversation(Geary.Conversation conversation) {
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
    
    private void on_scan_completed(Geary.ConversationMonitor sender) {
        refresh_previews_async.begin(sender);
        
        if (!loading_local_only)
            return;
        
        debug("Loading all emails now");
        loading_local_only = false;
        sender.load_async.begin(-1, GearyController.FETCH_EMAIL_CHUNK_COUNT,
            Geary.Folder.ListFlags.NONE, cancellable_folder);
    }
    
    private void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        // this handler is used to initialize the display, so it's possible for an empty list to
        // be passed in (the ConversationMonitor signal should never do this)
        if (conversations.size == 0)
            return;
        
        conversations_added_began();
        
        debug("Adding %d conversations.", conversations.size);
        int added = 0;
        foreach (Geary.Conversation conversation in conversations) {
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
    
    private void on_conversation_removed(Geary.Conversation conversation) {
        remove_conversation(conversation);
    }
    
    private void on_conversation_appended(Geary.Conversation conversation) {
        if (has_conversation(conversation)) {
            refresh_conversation(conversation);
        } else {
            debug("Unable to append conversation; conversation not present in list store");
        }
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
        
        get(aiter, Column.CONVERSATION_OBJECT, out a);
        get(biter, Column.CONVERSATION_OBJECT, out b);
        
        return compare_conversation_ascending(a, b);
    }
}

