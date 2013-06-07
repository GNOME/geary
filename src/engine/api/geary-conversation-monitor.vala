/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.ConversationMonitor : BaseObject {
    /**
     * These are the fields Conversations require to thread emails together.  These fields will
     * be retrieved regardless of the Field parameter passed to the constructor.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = Geary.Email.Field.REFERENCES | 
        Geary.Email.Field.FLAGS | Geary.Email.Field.DATE;
    
    private const int RETRY_CONNECTION_SEC = 15;
    
    // # of messages to load at a time as we attempt to fill the min window.
    private const int WINDOW_FILL_MESSAGE_COUNT = 5;
    
    private class ImplConversation : Conversation {
        private static int next_convnum = 0;
        
        public Gee.HashMultiSet<RFC822.MessageID> message_ids = new Gee.HashMultiSet<RFC822.MessageID>();
        
        private int convnum;
        private weak Geary.ConversationMonitor? owner;
        private Gee.HashMap<EmailIdentifier, Email> emails = new Gee.HashMap<EmailIdentifier, Email>();
        private Geary.EmailIdentifier? lowest_id;
        
        // this isn't ideal but the cost of adding an email to multiple sorted sets once versus
        // the number of times they're accessed makes it worth it
        private Gee.SortedSet<Email> date_ascending = new Collection.FixedTreeSet<Email>(
            Geary.Email.compare_date_ascending);
        private Gee.SortedSet<Email> date_descending = new Collection.FixedTreeSet<Email>(
            Geary.Email.compare_date_descending);
        
        public ImplConversation(Geary.ConversationMonitor owner) {
            convnum = next_convnum++;
            this.owner = owner;
            lowest_id = null;
        }
        
        public void clear_owner() {
            owner = null;
        }
        
        public override int get_count(bool folder_email_ids_only = false) {
            if (!folder_email_ids_only)
                return emails.size;
            
            int folder_count = 0;
            foreach (Geary.EmailIdentifier id in emails.keys) {
                if (id.get_folder_path() != null)
                    ++folder_count;
            }
            return folder_count;
        }
        
        public override Gee.List<Geary.Email> get_emails(Conversation.Ordering ordering) {
            switch (ordering) {
                case Conversation.Ordering.DATE_ASCENDING:
                    return Collection.to_array_list<Email>(date_ascending);
                
                case Conversation.Ordering.DATE_DESCENDING:
                    return Collection.to_array_list<Email>(date_descending);
                
                case Conversation.Ordering.NONE:
                default:
                    return Collection.to_array_list<Email>(emails.values);
            }
        }
        
        public override Geary.Email? get_email_by_id(EmailIdentifier id) {
            return emails.get(id);
        }
        
        public override Gee.Collection<Geary.EmailIdentifier> get_email_ids(
            bool folder_email_ids_only = false) {
            if (!folder_email_ids_only)
                return emails.keys;
            
            Gee.ArrayList<Geary.EmailIdentifier> folder_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
            foreach (Geary.EmailIdentifier id in emails.keys) {
                if (id.get_folder_path() != null)
                    folder_ids.add(id);
            }
            return folder_ids;
        }
        
        public override Geary.EmailIdentifier? get_lowest_email_id() {
            return lowest_id;
        }
        
        public void add(Email email) {
            // since Email is mutable (and Conversations itself mutates them, and callers might as
            // well), don't replace known email with new
            //
            // TODO: Combine new email with old email
            if (emails.has_key(email.id))
                return;
            
            emails.set(email.id, email);
            date_ascending.add(email);
            date_descending.add(email);
            
            Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
            if (ancestors != null)
                message_ids.add_all(ancestors);
            
            check_lowest_id(email.id);
        }
        
        // Returns the removed Message-IDs
        public Gee.Set<RFC822.MessageID>? remove(Email email) {
            emails.unset(email.id);
            date_ascending.remove(email);
            date_descending.remove(email);
            
            Gee.Set<RFC822.MessageID> removed_message_ids = new Gee.HashSet<RFC822.MessageID>();
            
            Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
            if (ancestors != null) {
                foreach (RFC822.MessageID ancestor_id in ancestors) {
                    // if remove() changes set (i.e. it was present) but no longer present, that
                    // means the ancestor_id was the last one and is formally removed
                    if (message_ids.remove(ancestor_id) && !message_ids.contains(ancestor_id))
                        removed_message_ids.add(ancestor_id);
                }
            }
            
            lowest_id = null;
            foreach (Email e in emails.values)
                check_lowest_id(e.id);
            
            return (removed_message_ids.size > 0) ? removed_message_ids : null;
        }
        
        private void check_lowest_id(EmailIdentifier id) {
            if (id.get_folder_path() != null && (lowest_id == null || id.compare_to(lowest_id) < 0))
                lowest_id = id;
        }
        
        public string to_string() {
            return "[#%d] (%d emails)".printf(convnum, emails.size);
        }
    }
    
    private class ConversationOperationQueue : BaseObject {
        public bool is_processing { get; private set; default = false; }
        
        private Geary.Nonblocking.Mailbox<ConversationOperation> mailbox
            = new Geary.Nonblocking.Mailbox<ConversationOperation>();
        private Geary.Nonblocking.Spinlock processing_done_spinlock
            = new Geary.Nonblocking.Spinlock();
        
        public void clear() {
            mailbox.clear();
        }
        
        public void add(ConversationOperation op) {
            // There should only ever be one FillWindowOperation at a time.
            if (op is FillWindowOperation)
                mailbox.remove_matching((o) => { return (o is FillWindowOperation); });
            
            mailbox.send(op);
        }
        
        public async void stop_processing_async(Cancellable? cancellable) {
            clear();
            add(new TerminateOperation());
            
            try {
                yield processing_done_spinlock.wait_async(cancellable);
            } catch (Error e) {
                debug("Error waiting for conversation operation queue to finish processing: %s",
                    e.message);
            }
        }
        
        public async void run_process_async() {
            is_processing = true;
            
            for (;;) {
                ConversationOperation op;
                try {
                    op = yield mailbox.recv_async();
                } catch (Error e) {
                    debug("Error processing in conversation operation mailbox: %s", e.message);
                    break;
                }
                if (op is TerminateOperation)
                    break;
                
                yield op.execute_async();
            }
            
            is_processing = false;
            processing_done_spinlock.blind_notify();
        }
    }
    
    private abstract class ConversationOperation : BaseObject {
        protected ConversationMonitor? monitor = null;
        
        public ConversationOperation(ConversationMonitor? monitor) {
            this.monitor = monitor;
        }
        
        public abstract async void execute_async();
    }
    
    private class LocalLoadOperation : ConversationOperation {
        public LocalLoadOperation(ConversationMonitor monitor) {
            base(monitor);
        }
        
        public override async void execute_async() {
            yield monitor.local_load_async();
        }
    }
    
    private class ReseedOperation : ConversationOperation {
        private string why;
        
        public ReseedOperation(ConversationMonitor monitor, string why) {
            base(monitor);
            this.why = why;
        }
        
        public override async void execute_async() {
             yield monitor.reseed_async(why);
        }
    }
    
    private class AppendOperation : ConversationOperation {
        private Gee.Collection<Geary.EmailIdentifier> appended_ids;
        
        public AppendOperation(ConversationMonitor monitor, Gee.Collection<Geary.EmailIdentifier> appended_ids) {
            base(monitor);
            this.appended_ids = appended_ids;
        }
        
        public override async void execute_async() {
            yield monitor.append_emails_async(appended_ids);
        }
    }
    
    private class RemoveOperation : ConversationOperation {
        private Gee.Collection<Geary.EmailIdentifier> removed_ids;
        
        public RemoveOperation(ConversationMonitor monitor, Gee.Collection<Geary.EmailIdentifier> removed_ids) {
            base(monitor);
            this.removed_ids = removed_ids;
        }
        
        public override async void execute_async() {
            monitor.remove_emails(removed_ids);
        }
    }
    
    private class FillWindowOperation : ConversationOperation {
        public FillWindowOperation(ConversationMonitor monitor) {
            base(monitor);
        }
        
        public override async void execute_async() {
            yield monitor.fill_window_async();
        }
    }
    
    private class TerminateOperation : ConversationOperation {
        public TerminateOperation() {
            base(null);
        }
        
        public override async void execute_async() {
        }
    }
    
    private class LocalSearchOperation : Nonblocking.BatchOperation {
        // IN
        public Geary.Account account;
        public RFC822.MessageID message_id;
        public Geary.Email.Field required_fields;
        public Gee.Collection<Geary.FolderPath>? blacklist;
        
        // OUT
        public Gee.MultiMap<Geary.Email, Geary.FolderPath?>? emails = null;
        
        public LocalSearchOperation(Geary.Account account, RFC822.MessageID message_id,
            Geary.Email.Field required_fields, Gee.Collection<Geary.FolderPath?> blacklist) {
            this.account = account;
            this.message_id = message_id;
            this.required_fields = required_fields;
            this.blacklist = blacklist;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            emails = yield account.local_search_message_id_async(message_id, required_fields,
                false, blacklist);
            
            return null;
        }
    }
    
    public Geary.Folder folder { get; private set; }
    public bool reestablish_connections { get; set; default = true; }
    public bool is_monitoring { get; private set; default = false; }
    public int min_window_count { get { return _min_window_count; } 
        set {
            _min_window_count = value;
            operation_queue.add(new FillWindowOperation(this));
        }
    }
    
    private Geary.Email.Field required_fields;
    private Geary.Folder.OpenFlags open_flags;
    private Gee.Set<ImplConversation> conversations = new Gee.HashSet<ImplConversation>();
    private Gee.HashMap<Geary.EmailIdentifier, ImplConversation> geary_id_map = new Gee.HashMap<
        Geary.EmailIdentifier, ImplConversation>();
    private Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> message_id_map = new Gee.HashMap<
        Geary.RFC822.MessageID, ImplConversation>();
    private Cancellable? cancellable_monitor = null;
    private bool retry_connection = false;
    private int64 last_retry_time = 0;
    private uint retry_id = 0;
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
     * "conversation-trimmed" is fired when an Email has been removed from the Folder, and therefore
     * from the specified Conversation.  If the trimmed Email is the last usable Email in the
     * Conversation, this signal will be followed by "conversation-removed".  However, it's
     * possible for "conversation-removed" to fire without "conversation-trimmed" preceding it,
     * in the case of all emails being removed from a Conversation at once.
     *
     * There is (currently) no user-specified call to manually remove Email from Conversations.
     * This is only called when monitoring is enabled.
     */
    public virtual signal void conversation_trimmed(Conversation conversation, Geary.Email email) {
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
        
        folder.account.information.notify["imap-credentials"].connect(on_imap_credentials_notified);
    }
    
    ~ConversationMonitor() {
        if (is_monitoring)
            debug("Warning: Conversations object destroyed without stopping monitoring");
        
        // Manually detach all the weak refs in the Conversation objects
        foreach (ImplConversation conversation in conversations)
            conversation.clear_owner();
        
        folder.account.information.notify["imap-credentials"].disconnect(on_imap_credentials_notified);
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
    
    protected virtual void notify_conversation_trimmed(Conversation conversation, Geary.Email email) {
        conversation_trimmed(conversation, email);
    }
    
    protected virtual void notify_email_flags_changed(Conversation conversation, Geary.Email email) {
        email_flags_changed(conversation, email);
    }
    
    public int get_conversation_count() {
        return conversations.size;
    }
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.read_only_view;
    }
    
    public Geary.Conversation? get_conversation_for_email(Geary.EmailIdentifier email_id) {
        return geary_id_map.get(email_id);
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
        operation_queue.add(new FillWindowOperation(this));
        
        folder.email_appended.connect(on_folder_email_appended);
        folder.email_removed.connect(on_folder_email_removed);
        folder.email_flags_changed.connect(on_folder_email_flags_changed);
        folder.email_count_changed.connect(on_folder_email_count_changed);
        folder.opened.connect(on_folder_opened);
        folder.closed.connect(on_folder_closed);
        
        try {
            yield folder.open_async(open_flags, cancellable);
        } catch (Error err) {
            is_monitoring = false;
            
            folder.email_appended.disconnect(on_folder_email_appended);
            folder.email_removed.disconnect(on_folder_email_removed);
            folder.email_flags_changed.disconnect(on_folder_email_flags_changed);
            folder.email_count_changed.disconnect(on_folder_email_count_changed);
            folder.opened.disconnect(on_folder_opened);
            folder.closed.disconnect(on_folder_closed);
            
            throw err;
        }
        
        notify_monitoring_started();
        reseed_notified = false;
        
        // Process operations in the background.
        operation_queue.run_process_async.begin();
        
        return true;
    }
    
    private async void local_load_async() {
        debug("ConversationMonitor seeding with local email for %s", folder.to_string());
        try {
            yield load_async(-1, min_window_count, Folder.ListFlags.LOCAL_ONLY, cancellable_monitor);
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
    public async void stop_monitoring_async(bool close_folder, Cancellable? cancellable) throws Error {
        yield stop_monitoring_internal_async(close_folder, false, cancellable);
    }
    
    private async void stop_monitoring_internal_async(bool close_folder, bool retrying,
        Cancellable? cancellable) throws Error {
        // always unschedule, as Timeout will hold a reference to this object
        unschedule_retry();
        
        if (!is_monitoring)
            return;
        
        yield operation_queue.stop_processing_async(cancellable);
        
        // set now to prevent reentrancy during yield or signal
        is_monitoring = false;
        
        folder.email_appended.disconnect(on_folder_email_appended);
        folder.email_removed.disconnect(on_folder_email_removed);
        folder.email_flags_changed.disconnect(on_folder_email_flags_changed);
        folder.opened.disconnect(on_folder_opened);
        folder.closed.disconnect(on_folder_closed);
        
        Error? close_err = null;
        if (close_folder) {
            try {
                yield folder.close_async(cancellable);
            } catch (Error err) {
                // throw, but only after cleaning up (which is to say, if close_async() fails,
                // then the Folder is still treated as closed, which is the best that can be
                // expected; it definitely shouldn't still be considered open).
                debug("Unable to close monitored folder %s: %s", folder.to_string(), err.message);
                
                close_err = err;
            }
        }
        
        notify_monitoring_stopped(retrying);
        
        if (close_err != null)
            throw close_err;
    }
    
    /**
     * See Geary.Folder.list_email_async() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    private async void load_async(int low, int count, Geary.Folder.ListFlags flags,
        Cancellable? cancellable) throws Error {
        notify_scan_started();
        try {
            yield start_process_email_async(yield folder.list_email_async(low, count,
                required_fields, flags, cancellable));
        } catch (Error err) {
            list_error(err);
        }
    }
    
    /**
     * See Geary.Folder.list_email_by_id_async() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    private async void load_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Folder.ListFlags flags, Cancellable? cancellable) throws Error {
        notify_scan_started();
        try {
            yield start_process_email_async(yield folder.list_email_by_id_async(initial_id,
                count, required_fields, flags, cancellable));
        } catch (Error err) {
            list_error(err);
            throw err;
        }
    }
    
    private async void load_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Folder.ListFlags flags, Cancellable? cancellable) {
        notify_scan_started();
        
        try {
            yield start_process_email_async(yield folder.list_email_by_sparse_id_async(ids,
                required_fields, flags, cancellable));
        } catch (Error err) {
            list_error(err);
        }
    }
    
    private void list_error(Error err) {
        debug("Error while assembling conversations in %s: %s", folder.to_string(), err.message);
        notify_scan_error(err);
        notify_scan_completed();
    }
    
    private async void start_process_email_async(Gee.Collection<Geary.Email>? emails) {
        yield process_email_async(emails, new Gee.HashSet<ImplConversation>(),
            new Gee.HashMultiMap<ImplConversation, Geary.Email>(),
            new Gee.HashMap<Geary.EmailIdentifier, ImplConversation>(),
            new Gee.HashMap<Geary.RFC822.MessageID, ImplConversation>());
    }
    
    private async void process_email_async(Gee.Collection<Geary.Email>? emails,
        Gee.HashSet<ImplConversation> job_new_conversations,
        Gee.MultiMap<ImplConversation, Geary.Email> job_appended_conversations,
        Gee.HashMap<Geary.EmailIdentifier, ImplConversation> job_geary_id_map,
        Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> job_message_id_map) {
        if (emails == null || emails.size == 0) {
            process_email_complete(job_new_conversations, job_appended_conversations,
                job_geary_id_map, job_message_id_map);
            return;
        }
        
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::process_email: %d emails",
            folder.to_string(), emails.size);
        
        // MessageIDs we're adding to each conversation.
        Gee.HashSet<RFC822.MessageID> new_message_ids = new Gee.HashSet<RFC822.MessageID>();
        
        foreach (Geary.Email email in emails) {
            // Skip messages already assigned to a conversation; this also deals with the problem
            // of messages with no Message-ID being loaded twice (most often encountered when
            // the first pass is loading messages directly from the database and the second pass
            // are messages loaded from both)
            //
            // TODO: Combine fields from this email with existing email so the monitor is holding
            // the freshest stuff ... this may require more signals
            if (geary_id_map.has_key(email.id) || job_geary_id_map.has_key(email.id))
                continue;
            
            // Right now, all threading is done with Message-IDs (no parsing of subject lines, etc.)
            // If a message doesn't have a Message-ID, it's treated as its own conversation
            Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
            
            // see if any of these ancestor IDs maps to an existing conversation
            ImplConversation? conversation = null;
            if (ancestors != null) {
                foreach (RFC822.MessageID ancestor in ancestors) {
                    conversation = message_id_map.get(ancestor) ?? job_message_id_map.get(ancestor);
                    if (conversation != null)
                        break;
                }
            }
            
            // create new conversation if not seen before
            if (conversation == null) {
                conversation = new ImplConversation(this);
                job_new_conversations.add(conversation);
            }
            
            job_appended_conversations.set(conversation, email);
            
            // map email identifier to email (for later removal)
            job_geary_id_map.set(email.id, conversation);
            
            // map ancestors to this conversation
            if (ancestors != null) {
                foreach (RFC822.MessageID ancestor in ancestors) {
                    job_message_id_map.set(ancestor, conversation);
                    
                    // Log every new ancestor for later searching.
                    if (!new_message_ids.contains(ancestor))
                        new_message_ids.add(ancestor);
                }
            }
        }
        
        // Expand the conversation to include any Message-IDs we know we need
        // and may have on disk, but aren't in the folder.
        yield expand_conversations(new_message_ids, job_new_conversations, job_appended_conversations,
            job_geary_id_map, job_message_id_map);
        
        Logging.debug(Logging.Flag.CONVERSATIONS, "[%s] ConversationMonitor::process_email completed: %d emails",
            folder.to_string(), emails.size);
    }
    
    private Gee.Collection<Geary.FolderPath> get_search_blacklist() {
        Geary.SpecialFolderType[] blacklisted_folder_types = {
            Geary.SpecialFolderType.SPAM,
            Geary.SpecialFolderType.TRASH,
            Geary.SpecialFolderType.DRAFTS,
        };
        
        Gee.ArrayList<Geary.FolderPath?> blacklist
            = new Gee.ArrayList<Geary.FolderPath?>();
        foreach (Geary.SpecialFolderType type in blacklisted_folder_types) {
            try {
                Geary.Folder? blacklist_folder = folder.account.get_special_folder(type);
                if (blacklist_folder != null)
                    blacklist.add(blacklist_folder.get_path());
            } catch (Error e) {
                debug("Error finding special folder %s on account %s: %s",
                    type.to_string(), folder.account.to_string(), e.message);
            }
        }
        
        // Add the current folder so we omit search results we can find through
        // folder monitoring.  Add "no folders" so we omit results that have
        // been deleted permanently from the server.
        blacklist.add(folder.get_path());
        blacklist.add(null);
        
        return blacklist;
    }
    
    private async void expand_conversations(Gee.Set<RFC822.MessageID> needed_message_ids,
        Gee.HashSet<ImplConversation> job_new_conversations,
        Gee.MultiMap<ImplConversation, Geary.Email> job_appended_conversations,
        Gee.HashMap<Geary.EmailIdentifier, ImplConversation> job_geary_id_map,
        Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> job_message_id_map) {
        if (needed_message_ids.size == 0) {
            process_email_complete(job_new_conversations, job_appended_conversations,
                job_geary_id_map, job_message_id_map);
            return;
        }
        
        Logging.debug(Logging.Flag.CONVERSATIONS,
            "[%s] ConversationMonitor::expand_conversations: %d email ids",
            folder.to_string(), needed_message_ids.size);
        
        Gee.Collection<Geary.FolderPath> folder_blacklist = get_search_blacklist();
        
        // execute all the local search operations at once
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (RFC822.MessageID message_id in needed_message_ids) {
            batch.add(new LocalSearchOperation(folder.account, message_id, required_fields,
                folder_blacklist));
        }
        
        try {
            yield batch.execute_all_async();
        } catch (Error err) {
            debug("Unable to search local mail for conversations: %s", err.message);
            
            process_email_complete(job_new_conversations, job_appended_conversations,
                job_geary_id_map, job_message_id_map);
            return;
        }
        
        // collect their results into a single collection of addt'l emails
        Gee.HashMap<Geary.EmailIdentifier, Geary.Email> needed_messages = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email>();
        foreach (int id in batch.get_ids()) {
            LocalSearchOperation op = (LocalSearchOperation) batch.get_operation(id);
            if (op.emails != null) {
                foreach (Geary.Email email in op.emails.get_keys()) {
                    if (!needed_messages.has_key(email.id))
                        needed_messages.set(email.id, email);
                }
            }
        }
        
        // process them as through they're been loaded from the folder; this, in turn, may
        // require more local searching of email
        yield process_email_async(needed_messages.values, job_new_conversations,
            job_appended_conversations, job_geary_id_map, job_message_id_map);
        
        Logging.debug(Logging.Flag.CONVERSATIONS,
            "[%s] ConversationMonitor::expand_conversations completed: %d email ids (%d found)",
            folder.to_string(), needed_message_ids.size, needed_messages.size);
    }
    
    private void process_email_complete(Gee.HashSet<ImplConversation> job_new_conversations,
        Gee.MultiMap<ImplConversation, Geary.Email> job_appended_conversations,
        Gee.HashMap<Geary.EmailIdentifier, ImplConversation> job_geary_id_map,
        Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> job_message_id_map) {
        foreach(ImplConversation conversation in job_new_conversations)
            conversations.add(conversation);
        
        foreach (ImplConversation conversation in job_appended_conversations.get_keys()) {
            foreach (Geary.Email email in job_appended_conversations.get(conversation))
                conversation.add(email);
        }
        
        foreach (Geary.EmailIdentifier id in job_geary_id_map.keys)
            geary_id_map.set(id, job_geary_id_map.get(id));
        
        foreach (Geary.RFC822.MessageID message_id in job_message_id_map.keys)
            message_id_map.set(message_id, job_message_id_map.get(message_id));
        
        if (job_new_conversations.size > 0)
            notify_conversations_added(job_new_conversations);
        
        foreach (ImplConversation conversation in job_appended_conversations.get_keys()) {
            if (!job_new_conversations.contains(conversation))
                notify_conversation_appended(conversation, job_appended_conversations.get(conversation));
        }

        notify_scan_completed();
    }
    
    private void on_folder_email_appended(Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        operation_queue.add(new AppendOperation(this, appended_ids));
    }
    
    private void on_folder_email_removed(Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        operation_queue.add(new RemoveOperation(this, removed_ids));
        operation_queue.add(new FillWindowOperation(this));
    }
    
    private async void append_emails_async(Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        debug("%d message(s) appended to %s, fetching to add to conversations...", appended_ids.size,
            folder.to_string());
        
        yield load_by_sparse_id(appended_ids, Geary.Folder.ListFlags.NONE, null);
    }
    
    private void remove_emails(Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        debug("%d messages(s) removed to %s, trimming/removing conversations...", removed_ids.size,
            folder.to_string());
        
        Gee.HashSet<Conversation> removed = new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Email> trimmed = new Gee.HashMultiMap<Conversation, Email>();
        foreach (Geary.EmailIdentifier removed_id in removed_ids) {
            ImplConversation conversation;
            if (!geary_id_map.unset(removed_id, out conversation)) {
                debug("Removed email %s not found on conversations model", removed_id.to_string());
                
                continue;
            }
            
            Geary.Email? found = conversation.get_email_by_id(removed_id);
            if (found == null) {
                debug("WARNING: Unable to locate email ID %s in conversation %s", removed_id.to_string(),
                    conversation.to_string());
                
                continue;
            }
            
            Gee.Set<RFC822.MessageID>? removed_message_ids = conversation.remove(found);
            if (removed_message_ids != null) {
                foreach (RFC822.MessageID removed_message_id in removed_message_ids) {
                    // Warn if not found, but not hairy enough to skip continuing
                    if (!message_id_map.unset(removed_message_id)) {
                        debug("WARNING: Message-ID %s not associated with conversation",
                            removed_message_id.to_string());
                    }
                }
            }
            
            trimmed.set(conversation, found);
            
            if (conversation.get_count(true) == 0) {
                // remove non-folder message id's from the message_id_map to truly drop the
                // conversation (that's all that's remaining in Conversation at this point) ...
                // the Conversation must be *completely* dropped from this reverse lookup map,
                // otherwise future messages coming in will look like appends and not new
                // conversations
                foreach (RFC822.MessageID message_id in conversation.message_ids)
                    message_id_map.unset(message_id);
                assert(!message_id_map.values.contains(conversation));
                
                bool is_removed = conversations.remove((ImplConversation) conversation);
                if (is_removed) {
                    debug("Removing Email ID %s evaporates conversation %s", removed_id.to_string(),
                        conversation.to_string());
                    removed.add(conversation);
                } else {
                    debug("WARNING: Conversation %s already removed from master list (Email ID %s)",
                        conversation.to_string(), removed_id.to_string());
                }
            }
        }
        
        // for Conversations that have been removed, don't notify they're trimmed
        foreach (Conversation conversation in removed)
            trimmed.remove_all(conversation);
        
        foreach (Conversation conversation in trimmed.get_keys()) {
            foreach (Email email in trimmed.get(conversation))
                notify_conversation_trimmed(conversation, email);
        }
        
        foreach (Conversation conversation in removed)
            notify_conversation_removed(conversation);
    }
    
    private void on_folder_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map) {
        foreach (Geary.EmailIdentifier id in map.keys) {
            ImplConversation? conversation = geary_id_map.get(id);
            if (conversation == null)
                continue;
            
            Email? email = conversation.get_email_by_id(id);
            if (email == null)
                continue;
            
            email.set_flags(map.get(id));
            notify_email_flags_changed(conversation, email);
        }
    }
    
    private void on_folder_email_count_changed(int new_count, Geary.Folder.CountChangeReason reason) {
        // Only trap INSERTED here because append/remove is handled above.
        if ((reason & Geary.Folder.CountChangeReason.INSERTED) != 0)
            operation_queue.add(new FillWindowOperation(this));
    }
    
    private Geary.EmailIdentifier? get_lowest_email_id() {
        Geary.EmailIdentifier? earliest_id = null;
        foreach (Geary.Conversation conversation in conversations) {
            Geary.EmailIdentifier? id = conversation.get_lowest_email_id();
            if (id != null && (earliest_id == null || id.compare_to(earliest_id) < 0))
                earliest_id = id;
        }
        
        return earliest_id;
    }
    
    private async void reseed_async(string why) {
        Geary.EmailIdentifier? earliest_id = get_lowest_email_id();
        
        try {
            if (earliest_id != null) {
                debug("ConversationMonitor (%s) reseeding starting from Email ID %s on opened %s", why,
                    earliest_id.to_string(), folder.to_string());
                yield load_by_id_async(earliest_id, int.MAX, Geary.Folder.ListFlags.NONE,
                    cancellable_monitor);
            } else {
                debug("ConversationMonitor (%s) reseeding latest %d emails on opened %s", why,
                    min_window_count, folder.to_string());
                yield load_async(-1, min_window_count, Geary.Folder.ListFlags.NONE, cancellable_monitor);
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
    
    private void on_folder_closed(Folder.CloseReason reason) {
        debug("Folder %s close reason %s", folder.to_string(), reason.to_string());
        
        // watch for errors; these indicate a retry should occur
        if (reason.is_error() && reestablish_connections)
            retry_connection = true;
        
        // wait for the folder to be completely closed before retrying
        if (reason != Folder.CloseReason.FOLDER_CLOSED)
            return;
        
        if (!retry_connection) {
            debug("Folder %s closed due to error, not reestablishing connection", folder.to_string());
            
            stop_monitoring_internal_async.begin(false, false, null);
            
            return;
        }
        
        // reset
        retry_connection = false;
        
        debug("Folder %s closed due to error, reestablishing connection to continue monitoring conversations",
            folder.to_string());
        
        schedule_retry();
    }
    
    private async void do_restart_monitoring_async() {
        last_retry_time = get_monotonic_time();
        
        try {
            debug("Restarting conversation monitoring of folder %s, stopping previous monitoring...",
                folder.to_string());
            yield stop_monitoring_internal_async(false, true, null);
        } catch (Error stop_err) {
            debug("Error closing folder %s while reestablishing connection: %s", folder.to_string(),
                stop_err.message);
        }
        
        // TODO: Get smarter about this, especially since this might be an authentication error
        // and not a hard error
        debug("Restarting conversation monitoring of folder %s...", folder.to_string());
        try {
            if (!yield start_monitoring_async(cancellable_monitor))
                debug("Unable to restart monitoring of %s: already monitoring", folder.to_string());
            else
                debug("Reestablished connection to %s, continuing to monitor conversations",
                    folder.to_string());
        } catch (Error start_err) {
            debug("Unable to reestablish connection to %s, retrying in %d seconds: %s", folder.to_string(),
                RETRY_CONNECTION_SEC, start_err.message);
            
            schedule_retry();
        }
    }
    
    // If we've got a pending retry and the folder's account's password is
    // updated, cancel the pending retry and retry now.  This prevents the user
    // waiting while nothing happens after they type in their password.
    private void on_imap_credentials_notified() {
        if (retry_id == 0)
            return;
        unschedule_retry();
        do_restart_monitoring_async.begin();
    }
    
    private void schedule_retry() {
        if (retry_id != 0)
            return;
        
        // Number of us in the future we can schedule a retry, so we have a
        // minimum of RETRY_CONNECTION_SEC s between retries.
        int64 next_retry_time = RETRY_CONNECTION_SEC * 1000000 - (get_monotonic_time() - last_retry_time);
        
        // If it's been enough time since last retry we can retry immediately
        // (note we schedule on ms, translated from us).
        if (next_retry_time <= 0)
            do_restart_monitoring_async.begin();
        else
            retry_id = Timeout.add((uint) (next_retry_time / 1000), on_delayed_retry);
    }
    
    private void unschedule_retry() {
        if (retry_id != 0) {
            Source.remove(retry_id);
            retry_id = 0;
        }
    }
    
    private bool on_delayed_retry() {
        retry_id = 0;
        
        do_restart_monitoring_async.begin();
        
        return false;
    }
    
    /**
     * Attempts to load enough conversations to fill min_window_count.
     */
    private async void fill_window_async() {
        if (!is_monitoring || min_window_count <= conversations.size)
            return;
        
        int initial_message_count = geary_id_map.size;
        
        Geary.EmailIdentifier? low_id = get_lowest_email_id();
        if (low_id != null) {
            // Load at least as many messages as remianing conversations.
            int num_to_load = min_window_count - conversations.size;
            if (num_to_load < WINDOW_FILL_MESSAGE_COUNT)
                num_to_load = WINDOW_FILL_MESSAGE_COUNT;
            
            try {
                yield load_by_id_async(low_id, -num_to_load,
                    Geary.Folder.ListFlags.EXCLUDING_ID, cancellable_monitor);
            } catch(Error e) {
                debug("Error filling conversation window: %s", e.message);
            }
        } else {
            // No existing messages, need to start from scratch.
            try {
                yield load_async(-1, min_window_count, Folder.ListFlags.NONE, cancellable_monitor);
            } catch(Error e) {
                debug("Error filling conversation window: %s", e.message);
            }
        }
        
        // Run again to make sure we're full unless we ran out of messages.
        if (geary_id_map.size != initial_message_count)
            operation_queue.add(new FillWindowOperation(this));
    }
    
}

