/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.App.ConversationMonitor : BaseObject {
    /**
     * These are the fields Conversations require to thread emails together.  These fields will
     * be retrieved regardless of the Field parameter passed to the constructor.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = Geary.Email.Field.REFERENCES |
        Geary.Email.Field.FLAGS | Geary.Email.Field.DATE;
    
    private const int RETRY_CONNECTION_SEC = 15;
    
    // # of messages to load at a time as we attempt to fill the min window.
    private const int WINDOW_FILL_MESSAGE_COUNT = 5;
    
    private class ProcessJobContext : BaseObject {
        public Gee.HashMap<Geary.EmailIdentifier, Geary.Email> emails
            = new Gee.HashMap<Geary.EmailIdentifier, Geary.Email>();
        
        public bool inside_scan;
        
        public ProcessJobContext(bool inside_scan) {
            this.inside_scan = inside_scan;
        }
    }
    
    public Geary.Folder folder { get; private set; }
    public bool reestablish_connections { get; set; default = true; }
    public bool is_monitoring { get; private set; default = false; }
    public int min_window_count { get { return _min_window_count; }
        set {
            _min_window_count = value;
            operation_queue.add(new FillWindowOperation(this, false));
        }
    }
    
    public Geary.ProgressMonitor progress_monitor { get { return operation_queue.progress_monitor; } }
    
    private ConversationSet conversations = new ConversationSet();
    private Geary.Email.Field required_fields;
    private Geary.Folder.OpenFlags open_flags;
    private Cancellable? cancellable_monitor = null;
    private bool reseed_notified = false;
    private int _min_window_count = 0;
    private ConversationOperationQueue operation_queue = new ConversationOperationQueue();
    
    /**
     * "monitoring-started" is fired when the Conversations folder has been opened for monitoring.
     * This may be called multiple times if a connection is being reestablished.
     */
    public virtual signal void monitoring_started() {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::monitoring_started",
            folder.to_string());
    }
    
    /**
     * "monitoring-stopped" is fired when the Geary.Folder object has closed (either due to error
     * or user) and the Conversations object is therefore unable to continue monitoring.
     *
     * retrying is set to true if the Conversations object will, in the background, attempt to
     * reestablish a connection to the Folder and continue operating.
     */
    public virtual signal void monitoring_stopped(bool retrying) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::monitoring_stopped retrying=%s",
            folder.to_string(), retrying.to_string());
    }
    
    /**
     * "scan-started" is fired whenever beginning to load messages into the Conversations object.
     *
     * Note that more than one load can be initiated, due to Conversations being completely
     * asynchronous.  "scan-started", "scan-error", and "scan-completed" will be fired (as
     * appropriate) for each individual load request; that is, there is no internal counter to ensure
     * only a single "scan-completed" is fired to indicate multiple loads have finished.
     */
    public virtual signal void scan_started() {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::scan_started",
            folder.to_string());
    }
    
    /**
     * "scan-error" is fired when an Error is encounted while loading messages.  It will be followed
     * by a "scan-completed" signal.
     */
    public virtual signal void scan_error(Error err) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::scan_error %s",
            folder.to_string(), err.message);
    }
    
    /**
     * "scan-completed" is fired when the scan of the email has finished.
     */
    public virtual signal void scan_completed() {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::scan_completed",
            folder.to_string());
    }
    
    /**
     * "seed-completed" is fired when the folder has opened and email has been populated.
     */
    public virtual signal void seed_completed() {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::seed_completed",
            folder.to_string());
    }
    
    /**
     * "conversations-added" indicates that one or more new Conversations have been detected while
     * processing email, either due to a user-initiated load request or due to monitoring.
     */
    public virtual signal void conversations_added(Gee.Collection<Conversation> conversations) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::conversations_added %d",
            folder.to_string(), conversations.size);
    }
    
    /**
     * "conversations-removed" is fired when all the email in a Conversation has been removed.
     * It's possible this will be called without a signal alerting that it's emails have been
     * removed, i.e. a "conversation-removed" signal may fire with no accompanying
     * "conversation-trimmed".
     *
     * Note that this can only occur when monitoring is enabled.  There is (currently) no
     * user call to manually remove email from Conversations.
     */
    public virtual signal void conversation_removed(Conversation conversation) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::conversation_removed",
            folder.to_string());
    }
    
    /**
     * "conversation-appended" is fired when one or more Email objects have been added to the
     * specified Conversation.  This can happen due to a user-initiated load or while monitoring
     * the Folder.
     */
    public virtual signal void conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::conversation_appended",
            folder.to_string());
    }
    
    /**
     * "conversation-trimmed" is fired when one or more Emails have been removed from the Folder,
     * and therefore from the specified Conversation.  If the trimmed Email is the last usable
     * Email in the Conversation, this signal will be followed by "conversation-removed".  However,
     * it's possible for "conversation-removed" to fire without "conversation-trimmed" preceding
     * it, in the case of all emails being removed from a Conversation at once.
     *
     * There is (currently) no user-specified call to manually remove Email from Conversations.
     * This is only called when monitoring is enabled.
     */
    public virtual signal void conversation_trimmed(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::conversation_trimmed",
            folder.to_string());
    }
    
    /**
     * "email-flags-changed" is fired when the flags of an email in a conversation have changed,
     * as reported by the monitored folder.  The local copy of the Email is updated and this
     * signal is fired.
     *
     * Note that if the flags of an email not captured by the Conversations object change, no signal
     * is fired.  To know of all changes to all flags, subscribe to the Geary.Folder's
     * "email-flags-changed" signal.
     */
    public virtual signal void email_flags_changed(Conversation conversation, Geary.Email email) {
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::email_flag_changed",
            folder.to_string());
    }
    
    /**
     * Creates a conversation monitor for the given folder.
     *
     * @param folder Folder to monitor
     * @param open_flags See {@link Geary.Folder}
     * @param required_fields See {@link Geary.Folder}
     * @param min_window_count Minimum number of conversations that will be loaded
     */
    public ConversationMonitor(Geary.Folder folder, Geary.Folder.OpenFlags open_flags,
        Geary.Email.Field required_fields, int min_window_count) {
        this.folder = folder;
        this.open_flags = open_flags;
        this.required_fields = required_fields | REQUIRED_FIELDS;
        _min_window_count = min_window_count;
    }
    
    ~ConversationMonitor() {
        if (is_monitoring)
            debug("Warning: Conversations object destroyed without stopping monitoring");
        
        // Manually detach all the weak refs in the Conversation objects
        conversations.clear_owners();
    }
    
    protected virtual void notify_monitoring_started() {
        monitoring_started();
    }
    
    protected virtual void notify_monitoring_stopped(bool retrying) {
        monitoring_stopped(retrying);
    }
    
    protected virtual void notify_scan_started() {
        scan_started();
    }
    
    protected virtual void notify_scan_error(Error err) {
        scan_error(err);
    }
    
    protected virtual void notify_scan_completed() {
        scan_completed();
    }
    
    protected virtual void notify_seed_completed() {
        seed_completed();
    }
    
    protected virtual void notify_conversations_added(Gee.Collection<Conversation> conversations) {
        conversations_added(conversations);
    }
    
    protected virtual void notify_conversation_removed(Conversation conversation) {
        conversation_removed(conversation);
    }
    
    protected virtual void notify_conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> emails) {
        conversation_appended(conversation, emails);
    }
    
    protected virtual void notify_conversation_trimmed(Conversation conversation,
        Gee.Collection<Geary.Email> emails) {
        conversation_trimmed(conversation, emails);
    }
    
    protected virtual void notify_email_flags_changed(Conversation conversation, Geary.Email email) {
        email_flags_changed(conversation, email);
    }
    
    public int get_conversation_count() {
        return conversations.size;
    }
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.conversations;
    }
    
    public Geary.App.Conversation? get_conversation_for_email(Geary.EmailIdentifier email_id) {
        return conversations.get_by_email_identifier(email_id);
    }
    
    public async bool start_monitoring_async(Cancellable? cancellable = null)
        throws Error {
        if (is_monitoring)
            return false;
        
        // set before yield to guard against reentrancy
        is_monitoring = true;
        
        cancellable_monitor = cancellable;
        
        // Double check that the last run of the queue got stopped and that
        // it's empty.
        if (operation_queue.is_processing)
            yield operation_queue.stop_processing_async(cancellable_monitor);
        operation_queue.clear();
        
        bool reseed_now = (folder.get_open_state() != Geary.Folder.OpenState.CLOSED);
        
        // Add the necessary initial operations ahead of anything the folder
        // might add as it opens.
        operation_queue.add(new LocalLoadOperation(this));
        // if already opened, go ahead and do a full load now from remote and local; otherwise,
        // the reseed has to wait until the folder's remote is opened (handled in on_folder_opened)
        if (reseed_now)
            operation_queue.add(new ReseedOperation(this, "already opened"));
        operation_queue.add(new FillWindowOperation(this, false));
        
        folder.email_appended.connect(on_folder_email_appended);
        folder.email_inserted.connect(on_folder_email_inserted);
        folder.email_removed.connect(on_folder_email_removed);
        folder.opened.connect(on_folder_opened);
        folder.account.email_flags_changed.connect(on_account_email_flags_changed);
        folder.account.email_locally_complete.connect(on_account_email_locally_complete);
        // TODO: handle removed email
        
        try {
            yield folder.open_async(open_flags, cancellable);
        } catch (Error err) {
            is_monitoring = false;
            
            folder.email_appended.disconnect(on_folder_email_appended);
            folder.email_inserted.disconnect(on_folder_email_inserted);
            folder.email_removed.disconnect(on_folder_email_removed);
            folder.opened.disconnect(on_folder_opened);
            folder.account.email_flags_changed.disconnect(on_account_email_flags_changed);
            folder.account.email_locally_complete.disconnect(on_account_email_locally_complete);
            
            throw err;
        }
        
        notify_monitoring_started();
        reseed_notified = false;
        
        // Process operations in the background.
        operation_queue.run_process_async.begin();
        
        return true;
    }
    
    internal async void local_load_async() {
        debug("ConversationMonitor seeding with local email for %s", folder.to_string());
        try {
            yield load_by_id_async(null, min_window_count, Folder.ListFlags.LOCAL_ONLY, cancellable_monitor);
        } catch (Error e) {
            debug("Error loading local messages: %s", e.message);
        }
        debug("ConversationMonitor seeded for %s", folder.to_string());
    }
    
    /**
     * Halt monitoring of the Folder and, if specified, close it.  Note that the Cancellable
     * supplied to start_monitoring_async() is used during monitoring but *not* for this method.
     * If null is supplied as the Cancellable, no cancellable is used; pass the original Cancellable
     * here to use that.
     */
    public async void stop_monitoring_async(Cancellable? cancellable) throws Error {
        yield stop_monitoring_internal_async(false, cancellable);
    }
    
    private async void stop_monitoring_internal_async(bool retrying, Cancellable? cancellable) throws Error {
        if (!is_monitoring)
            return;
        
        yield operation_queue.stop_processing_async(cancellable);
        
        // set now to prevent reentrancy during yield or signal
        is_monitoring = false;
        
        folder.email_appended.disconnect(on_folder_email_appended);
        folder.email_inserted.disconnect(on_folder_email_inserted);
        folder.email_removed.disconnect(on_folder_email_removed);
        folder.opened.disconnect(on_folder_opened);
        folder.account.email_flags_changed.disconnect(on_account_email_flags_changed);
        folder.account.email_locally_complete.disconnect(on_account_email_locally_complete);
        
        Error? close_err = null;
        try {
            yield folder.close_async(cancellable);
        } catch (Error err) {
            // throw, but only after cleaning up (which is to say, if close_async() fails,
            // then the Folder is still treated as closed, which is the best that can be
            // expected; it definitely shouldn't still be considered open).
            debug("Unable to close monitored folder %s: %s", folder.to_string(), err.message);
            
            close_err = err;
        }
        
        notify_monitoring_stopped(retrying);
        
        if (close_err != null)
            throw close_err;
    }
    
    /**
     * See Geary.Folder.list_email_by_id_async() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    private async void load_by_id_async(Geary.EmailIdentifier? initial_id, int count,
        Geary.Folder.ListFlags flags, Cancellable? cancellable) throws Error {
        notify_scan_started();
        try {
            yield process_email_async(yield folder.list_email_by_id_async(initial_id,
                count, required_fields, flags, cancellable), new ProcessJobContext(true));
        } catch (Error err) {
            list_error(err);
            throw err;
        }
    }
    
    private async void load_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Folder.ListFlags flags, Cancellable? cancellable) {
        notify_scan_started();
        
        try {
            yield process_email_async(yield folder.list_email_by_sparse_id_async(ids,
                required_fields, flags, cancellable), new ProcessJobContext(true));
        } catch (Error err) {
            list_error(err);
        }
    }
    
    private async void external_load_by_sparse_id(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Folder.ListFlags flags, Cancellable? cancellable) {
        bool opened = false;
        try {
            yield folder.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
            opened = true;
            
            debug("Listing %d external emails", ids.size);
            
            // First just get the bare minimum we need to determine if we even
            // care about the messages.
            Gee.List<Geary.Email>? emails = yield folder.list_email_by_sparse_id_async(ids,
                Geary.Email.Field.REFERENCES, flags, cancellable);
            
            debug("List found %d emails", (emails == null ? 0 : emails.size));
            
            Gee.HashSet<Geary.EmailIdentifier> relevant_ids = new Gee.HashSet<Geary.EmailIdentifier>();
            foreach (Geary.Email email in emails) {
                Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
                if (ancestors != null &&
                    Geary.traverse<RFC822.MessageID>(ancestors).any(id => conversations.has_message_id(id)))
                    relevant_ids.add(email.id);
            }
            
            debug("%d external emails are relevant to current conversations", relevant_ids.size);
            
            // List the relevant messages again with the full set of fields, to
            // make sure when we load them from the database we have all the
            // data we need.
            yield folder.list_email_by_sparse_id_async(relevant_ids, required_fields, flags, cancellable);
            yield folder.close_async(cancellable);
            opened = false;
            
            Gee.ArrayList<Geary.Email> search_emails = new Gee.ArrayList<Geary.Email>();
            foreach (Geary.EmailIdentifier id in relevant_ids) {
                // TODO: parallelize this.
                try {
                    Geary.Email email = yield folder.account.local_fetch_email_async(id,
                        required_fields, cancellable);
                    search_emails.add(email);
                } catch (Error e) {
                    debug("Error fetching out of folder message: %s", e.message);
                }
            }
            
            debug("Fetched %d relevant emails locally", search_emails.size);
            
            yield process_email_async(search_emails, new ProcessJobContext(false));
        } catch (Error e) {
            debug("Error loading external emails: %s", e.message);
            if (opened) {
                try {
                    yield folder.close_async(cancellable);
                } catch (Error e) {
                    debug("Error closing folder %s: %s", folder.to_string(), e.message);
                }
            }
        }
    }
    
    private void list_error(Error err) {
        debug("Error while assembling conversations in %s: %s", folder.to_string(), err.message);
        notify_scan_error(err);
        notify_scan_completed();
    }
    
    private async void process_email_async(Gee.Collection<Geary.Email>? emails, ProcessJobContext job) {
        if (emails == null || emails.size == 0) {
            yield process_email_complete_async(job);
            return;
        }
        
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::process_email: %d emails",
            folder.to_string(), emails.size);
        
        Gee.HashSet<RFC822.MessageID> new_message_ids = new Gee.HashSet<RFC822.MessageID>();
        foreach (Geary.Email email in emails) {
            if (!job.emails.has_key(email.id)) {
                job.emails.set(email.id, email);
            
                Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
                if (ancestors != null) {
                    Geary.traverse<RFC822.MessageID>(ancestors)
                        .filter(id => !new_message_ids.contains(id))
                        .add_all_to(new_message_ids);
                }
            }
        }
        
        // Expand the conversation to include any Message-IDs we know we need
        // and may have on disk, but aren't in the folder.
        yield expand_conversations_async(new_message_ids, job);
        
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::process_email completed: %d emails",
            folder.to_string(), emails.size);
    }
    
    private Gee.Collection<Geary.FolderPath> get_search_blacklist() {
        Geary.SpecialFolderType[] blacklisted_folder_types = {
            Geary.SpecialFolderType.SPAM,
            Geary.SpecialFolderType.TRASH,
            Geary.SpecialFolderType.DRAFTS,
        };
        
        Gee.ArrayList<Geary.FolderPath?> blacklist = new Gee.ArrayList<Geary.FolderPath?>();
        foreach (Geary.SpecialFolderType type in blacklisted_folder_types) {
            try {
                Geary.Folder? blacklist_folder = folder.account.get_special_folder(type);
                if (blacklist_folder != null)
                    blacklist.add(blacklist_folder.path);
            } catch (Error e) {
                debug("Error finding special folder %s on account %s: %s",
                    type.to_string(), folder.account.to_string(), e.message);
            }
        }
        
        // Add "no folders" so we omit results that have been deleted permanently from the server.
        blacklist.add(null);
        
        return blacklist;
    }
    
    private Geary.EmailFlags get_search_flag_blacklist() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.DRAFT);
        
        return flags;
    }
    
    private async void expand_conversations_async(Gee.Set<RFC822.MessageID> needed_message_ids,
        ProcessJobContext job) {
        if (needed_message_ids.size == 0) {
            yield process_email_complete_async(job);
            return;
        }
        
        Logging.debug(Logging.Flag.CONVERSATIONS,
            "[%s] ConversationMonitor::expand_conversations: %d email ids",
            folder.to_string(), needed_message_ids.size);
        
        Gee.Collection<Geary.FolderPath> folder_blacklist = get_search_blacklist();
        Geary.EmailFlags flag_blacklist = get_search_flag_blacklist();
        
        // execute all the local search operations at once
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (RFC822.MessageID message_id in needed_message_ids) {
            batch.add(new LocalSearchOperation(folder.account, message_id, required_fields,
                folder_blacklist, flag_blacklist));
        }
        
        try {
            yield batch.execute_all_async();
        } catch (Error err) {
            debug("Unable to search local mail for conversations: %s", err.message);
            
            yield process_email_complete_async(job);
            return;
        }
        
        // collect their results into a single collection of addt'l emails
        Gee.HashMap<Geary.EmailIdentifier, Geary.Email> needed_messages = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email>();
        foreach (int id in batch.get_ids()) {
            LocalSearchOperation op = (LocalSearchOperation) batch.get_operation(id);
            if (op.emails != null) {
                Geary.traverse<Geary.Email>(op.emails.get_keys())
                    .filter(e => !needed_messages.has_key(e.id))
                    .add_all_to_map<Geary.EmailIdentifier>(needed_messages, e => e.id);
            }
        }
        
        // process them as through they're been loaded from the folder; this, in turn, may
        // require more local searching of email
        yield process_email_async(needed_messages.values, job);
        
        Logging.debug(Logging.Flag.CONVERSATIONS,
            "[%s] ConversationMonitor::expand_conversations completed: %d email ids (%d found)",
            folder.to_string(), needed_message_ids.size, needed_messages.size);
    }
    
    private async void process_email_complete_async(ProcessJobContext job) {
        Gee.Collection<Geary.App.Conversation>? added = null;
        Gee.MultiMap<Geary.App.Conversation, Geary.Email>? appended = null;
        Gee.Collection<Conversation>? removed_due_to_merge = null;
        try {
            yield conversations.add_all_emails_async(job.emails.values, this, folder.path, out added, out appended,
                out removed_due_to_merge, null);
        } catch (Error err) {
            debug("Unable to add emails to conversation: %s", err.message);
            
            // fall-through
        }
        
        if (removed_due_to_merge != null) {
            foreach (Conversation conversation in removed_due_to_merge)
                notify_conversation_removed(conversation);
        }
        
        if (added != null && added.size > 0)
            notify_conversations_added(added);
        
        if (appended != null) {
            foreach (Geary.App.Conversation conversation in appended.get_keys())
                notify_conversation_appended(conversation, appended.get(conversation));
        }
        
        if (job.inside_scan)
            notify_scan_completed();
    }
    
    private void on_folder_email_appended(Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        operation_queue.add(new AppendOperation(this, appended_ids));
    }
    
    private void on_folder_email_inserted(Gee.Collection<Geary.EmailIdentifier> inserted_ids) {
        operation_queue.add(new FillWindowOperation(this, true));
    }
    
    private void on_folder_email_removed(Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        operation_queue.add(new RemoveOperation(this, removed_ids));
        operation_queue.add(new FillWindowOperation(this, false));
    }
    
    private void on_account_email_locally_complete(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> complete_ids) {
        operation_queue.add(new ExternalAppendOperation(this, folder, complete_ids));
    }
    
    internal async void append_emails_async(Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        debug("%d message(s) appended to %s, fetching to add to conversations...", appended_ids.size,
            folder.to_string());
        
        yield load_by_sparse_id(appended_ids, Geary.Folder.ListFlags.NONE, null);
    }
    
    internal async void remove_emails_async(Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        debug("%d messages(s) removed from %s, trimming/removing conversations...", removed_ids.size,
            folder.to_string());
        
        Gee.Collection<Geary.App.Conversation> removed;
        Gee.MultiMap<Geary.App.Conversation, Geary.Email> trimmed;
        yield conversations.remove_emails_and_check_in_folder_async(removed_ids, folder.account,
            folder.path, out removed, out trimmed, null);
        
        foreach (Conversation conversation in trimmed.get_keys())
            notify_conversation_trimmed(conversation, trimmed.get(conversation));
        
        foreach (Conversation conversation in removed)
            notify_conversation_removed(conversation);
        
        // For any still-existing conversations that we've trimmed messages
        // from, do a search for any messages that should still be there due to
        // full conversations.  This way, some removed messages are instead
        // "demoted" to out-of-folder emails.  This is kind of inefficient, but
        // it doesn't seem like there's a way around it.
        Gee.HashSet<RFC822.MessageID> search_message_ids = new Gee.HashSet<RFC822.MessageID>();
        foreach (Conversation conversation in trimmed.get_keys())
            search_message_ids.add_all(conversation.get_message_ids());
        yield expand_conversations_async(search_message_ids, new ProcessJobContext(false));
    }
    
    internal async void external_append_emails_async(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        if (get_search_blacklist().contains(folder.path))
            return;
        
        if (conversations.is_empty)
            return;
        
        debug("%d out of folder message(s) appended to %s, fetching to add to conversations...", appended_ids.size,
            folder.to_string());
        
        yield external_load_by_sparse_id(folder, appended_ids, Geary.Folder.ListFlags.NONE, null);
    }
    
    private void on_account_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map) {
        foreach (Geary.EmailIdentifier id in map.keys) {
            Conversation? conversation = conversations.get_by_email_identifier(id);
            if (conversation == null)
                continue;
            
            Email? email = conversation.get_email_by_id(id);
            if (email == null)
                continue;
            
            email.set_flags(map.get(id));
            notify_email_flags_changed(conversation, email);
        }
    }
    
    private async Geary.EmailIdentifier? get_lowest_email_id_async(Cancellable? cancellable) {
        Geary.EmailIdentifier? earliest_id = null;
        try {
            yield folder.find_boundaries_async(conversations.get_email_identifiers(),
                out earliest_id, null, cancellable);
        } catch (Error e) {
            debug("Error finding earliest email identifier: %s", e.message);
        }
        
        return earliest_id;
    }
    
    internal async void reseed_async(string why) {
        Geary.EmailIdentifier? earliest_id = yield get_lowest_email_id_async(null);
        try {
            if (earliest_id != null) {
                debug("ConversationMonitor (%s) reseeding starting from Email ID %s on opened %s", why,
                    earliest_id.to_string(), folder.to_string());
                yield load_by_id_async(earliest_id, int.MAX,
                    Geary.Folder.ListFlags.OLDEST_TO_NEWEST | Geary.Folder.ListFlags.INCLUDING_ID,
                    cancellable_monitor);
            } else {
                debug("ConversationMonitor (%s) reseeding latest %d emails on opened %s", why,
                    min_window_count, folder.to_string());
                yield load_by_id_async(null, min_window_count, Geary.Folder.ListFlags.NONE, cancellable_monitor);
            }
        } catch (Error e) {
            debug("Reseed error: %s", e.message);
        }
        
        if (!reseed_notified) {
            reseed_notified = true;
            notify_seed_completed();
        }
    }
    
    private void on_folder_opened(Geary.Folder.OpenState state, int count) {
        // once remote is open, reseed with messages from the earliest ID to the latest
        if (state == Geary.Folder.OpenState.BOTH || state == Geary.Folder.OpenState.REMOTE)
            operation_queue.add(new ReseedOperation(this, state.to_string()));
    }
    
    /**
     * Attempts to load enough conversations to fill min_window_count.
     */
    internal async void fill_window_async(bool is_insert) {
        if (!is_monitoring)
            return;
        
        if (!is_insert && min_window_count <= conversations.size)
            return;
        
        int initial_message_count = conversations.get_email_count();
        
        // only do local-load if the Folder isn't completely opened, otherwise this operation
        // will block other (more important) operations while it waits for the folder to
        // remote-open
        Folder.ListFlags flags;
        switch (folder.get_open_state()) {
            case Folder.OpenState.CLOSED:
            case Folder.OpenState.LOCAL:
            case Folder.OpenState.OPENING:
                flags = Folder.ListFlags.LOCAL_ONLY;
            break;
            
            case Folder.OpenState.BOTH:
            case Folder.OpenState.REMOTE:
                flags = Folder.ListFlags.NONE;
            break;
            
            default:
                assert_not_reached();
        }
        
        Geary.EmailIdentifier? low_id = yield get_lowest_email_id_async(null);
        if (low_id != null && !is_insert) {
            // Load at least as many messages as remianing conversations.
            int num_to_load = min_window_count - conversations.size;
            if (num_to_load < WINDOW_FILL_MESSAGE_COUNT)
                num_to_load = WINDOW_FILL_MESSAGE_COUNT;
            
            try {
                yield load_by_id_async(low_id, num_to_load, flags, cancellable_monitor);
            } catch(Error e) {
                debug("Error filling conversation window: %s", e.message);
            }
        } else {
            // No existing messages or an insert invalidated our existing list,
            // need to start from scratch.
            try {
                yield load_by_id_async(null, min_window_count, flags, cancellable_monitor);
            } catch(Error e) {
                debug("Error filling conversation window: %s", e.message);
            }
        }
        
        // Run again to make sure we're full unless we ran out of messages.
        if (conversations.get_email_count() != initial_message_count)
            operation_queue.add(new FillWindowOperation(this, is_insert));
    }
}
