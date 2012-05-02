/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Conversations : Object {
    /**
     * These are the fields Conversations require to thread emails together.  These fields will
     * be retrieved irregardless of the Field parameter passed to the constructor.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = Geary.Email.Field.REFERENCES | 
        Geary.Email.Field.PROPERTIES | Geary.Email.Field.DATE;
    
    private const int RETRY_CONNECTION_SEC = 15;
    
    private class ImplConversation : Conversation {
        private weak Geary.Conversations? owner;
        private Gee.HashMap<EmailIdentifier, Email> emails = new Gee.HashMap<EmailIdentifier, Email>(
            Hashable.hash_func, Equalable.equal_func);
        
        // this isn't ideal but the cost of adding an email to multiple sorted sets once versus
        // the number of times they're accessed makes it worth it
        private Gee.SortedSet<Email> date_ascending = new Gee.TreeSet<Email>(
            (CompareFunc) compare_date_ascending);
        private Gee.SortedSet<Email> date_descending = new Gee.TreeSet<Email>(
            (CompareFunc) compare_date_descending);
        private Gee.SortedSet<Email> id_ascending = new Gee.TreeSet<Email>(
            (CompareFunc) compare_id_ascending);
        private Gee.SortedSet<Email> id_descending = new Gee.TreeSet<Email>(
            (CompareFunc) compare_id_descending);
        
        public ImplConversation(Geary.Conversations owner) {
            this.owner = owner;
        }
        
        public void clear_owner() {
            owner = null;
        }
        
        public override int get_count() {
            return emails.size;
        }
        
        public override Gee.List<Geary.Email> get_email(Conversation.Ordering ordering) {
            switch (ordering) {
                case Conversation.Ordering.DATE_ASCENDING:
                    return Collection.to_array_list<Email>(date_ascending);
                
                case Conversation.Ordering.ID_ASCENDING:
                    return Collection.to_array_list<Email>(id_ascending);
                
                case Conversation.Ordering.ID_DESCENDING:
                    return Collection.to_array_list<Email>(id_descending);
                
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
        
        public override Gee.Collection<Geary.EmailIdentifier> get_email_ids() {
            return emails.keys;
        }
        
        public void add(Email email) {
            // since Email is mutable (and Conversations itself mutates them, and callers might as
            // well), don't replace known email with new
            if (emails.has_key(email.id))
                return;
            
            emails.set(email.id, email);
            date_ascending.add(email);
            date_descending.add(email);
            id_ascending.add(email);
            id_descending.add(email);
        }
        
        public void remove(Email email) {
            emails.unset(email.id);
            date_ascending.remove(email);
            date_descending.remove(email);
            id_ascending.remove(email);
            id_descending.remove(email);
        }
        
        private static int compare_date_ascending(Email a, Email b) {
            int diff = a.date.value.compare(b.date.value);
            
            // stabilize the sort if the same date
            return (diff != 0) ? diff : compare_id_ascending(a, b);
        }
        
        private static int compare_date_descending(Email a, Email b) {
            return compare_date_ascending(b, a);
        }
        
        private static int compare_id_ascending(Email a, Email b) {
            int64 diff = a.id.ordering - b.id.ordering;
            if (diff < 0)
                return -1;
            else if (diff > 0)
                return 1;
            else
                return 0;
        }
        
        private static int compare_id_descending(Email a, Email b) {
            return compare_id_ascending(b, a);
        }
    }
    
    public Geary.Folder folder { get; private set; }
    public bool reestablish_connections { get; set; default = true; }
    public bool monitoring { get; private set; default = false; }
    
    private Geary.Email.Field required_fields;
    private Gee.Set<ImplConversation> conversations = new Gee.HashSet<ImplConversation>();
    private Gee.HashMap<RFC822.MessageID, ImplConversation> message_id_map = new Gee.HashMap<
        RFC822.MessageID, ImplConversation>(Hashable.hash_func, Equalable.equal_func);
    private Gee.HashMap<Geary.EmailIdentifier, ImplConversation> geary_id_map = new Gee.HashMap<
        Geary.EmailIdentifier, ImplConversation>(Hashable.hash_func, Equalable.equal_func);
    private Cancellable? cancellable_monitor = null;
    private bool retry_connection = false;
    private uint retry_id = 0;
    
    /**
     * "monitoring-started" is fired when the Conversations folder has been opened for monitoring.
     * This may be called multiple times if a connection is being reestablished.
     */
    public virtual signal void monitoring_started() {
    }
    
    /**
     * "monitoring-stopped" is fired when the Geary.Folder object has closed (either due to error
     * or user) and the Conversations object is therefore unable to continue monitoring.
     *
     * retrying is set to true if the Conversations object will, in the background, attempt to
     * reestablish a connection to the Folder and continue operating.
     */
    public virtual signal void monitoring_stopped(bool retrying) {
    }
    
    /**
     * "scan-started" is fired whenever beginning to load messages into the Conversations object.
     * If id is not null, then the scan is starting at an identifier and progressing according to
     * count (see Geary.Folder.list_email_by_id_async()).  Otherwise, the scan is using positional
     * addressing and low is a valid one-based position (see Geary.Folder.list_email_async()).
     *
     * Note that more than one load can be initiated, due to Conversations being completely
     * asynchronous.  "scan-started", "scan-error", and "scan-completed" will be fired (as
     * appropriate) for each individual load request; that is, there is no internal counter to ensure
     * only a single "scan-completed" is fired to indicate multiple loads have finished.
     */
    public virtual signal void scan_started(Geary.EmailIdentifier? id, int low, int count) {
    }
    
    /**
     * "scan-error" is fired when an Error is encounted while loading messages.  It will be followed
     * by a "scan-completed" signal.
     */
    public virtual signal void scan_error(Error err) {
    }
    
    /**
     * "scan-completed" is fired when the scan of the email has finished.
     */
    public virtual signal void scan_completed() {
    }
    
    /**
     * "conversations-added" indicates that one or more new Conversations have been detected while
     * processing email, either due to a user-initiated load request or due to monitoring.
     */
    public virtual signal void conversations_added(Gee.Collection<Conversation> conversations) {
    }
    
    /**
     * "conversations-removed" is fired when all the email in a Conversation has been removed.
     *
     * Note that this can only occur when monitoring is enabled.  There is (currently) no
     * user call to manually remove email from Conversations.
     */
    public virtual signal void conversation_removed(Conversation conversation) {
    }
    
    /**
     * "conversation-appended" is fired when one or more Email objects have been added to the
     * specified Conversation.  This can happen due to a user-initiated load or while monitoring
     * the Folder.
     */
    public virtual signal void conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
    }
    
    /**
     * "conversation-trimmed" is fired when an Email has been removed from the Folder, and therefore
     * from the specified Conversation.  If the trimmed Email is the last usable Email in the
     * Conversation, this signal will be followed by "conversation-removed".
     *
     * There is (currently) no user-specified call to manually remove Email from Conversations.
     * This is only called when monitoring is enabled.
     */
    public virtual signal void conversation_trimmed(Conversation conversation, Geary.Email email) {
    }
    
    /**
     * "email-flags-changed" is fired when the flags of an email in a conversation have changed,
     * as reported by the monitored folder.  The local copy of the Email is updated and this
     * signal is fired.
     *
     * Note that if the flags of an email not captured by the Conversations object, no signal
     * is fired.  To know of all changes to flags, subscribe to the Geary.Folder's
     * "email-flags-changed" signal.
     */
    public virtual signal void email_flags_changed(Conversation conversation, Geary.Email email) {
    }
    
    public Conversations(Geary.Folder folder, Geary.Email.Field required_fields) {
        this.folder = folder;
        this.required_fields = required_fields | REQUIRED_FIELDS;
    }
    
    ~Conversations() {
        if (monitoring)
            debug("Warning: Conversations object destroyed without stopping monitoring");
        
        // Manually detach all the weak refs in the Conversation objects
        foreach (ImplConversation conversation in conversations)
            conversation.clear_owner();
    }
    
    protected virtual void notify_monitoring_started() {
        monitoring_started();
    }
    
    protected virtual void notify_monitoring_stopped(bool retrying) {
        monitoring_stopped(retrying);
    }
    
    protected virtual void notify_scan_started(Geary.EmailIdentifier? id, int low, int count) {
        scan_started(id, low, count);
    }
    
    protected virtual void notify_scan_error(Error err) {
        scan_error(err);
    }
    
    protected virtual void notify_scan_completed() {
        scan_completed();
    }
    
    protected virtual void notify_conversations_added(Gee.Collection<Conversation> conversations) {
        conversations_added(conversations);
    }
    
    protected virtual void notify_conversation_removed(Conversation conversation) {
        conversation_removed(conversation);
    }
    
    protected virtual void notify_conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        conversation_appended(conversation, email);
    }
    
    protected virtual void notify_conversation_trimmed(Conversation conversation, Geary.Email email) {
        conversation_trimmed(conversation, email);
    }
    
    protected virtual void notify_email_flags_changed(Conversation conversation, Geary.Email email) {
        email_flags_changed(conversation, email);
    }
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.read_only_view;
    }
    
    public Geary.Conversation? get_conversation_for_email(Geary.EmailIdentifier email_id) {
        return geary_id_map.get(email_id);
    }
    
    public async bool start_monitoring_async(Cancellable? cancellable = null) throws Error {
        if (monitoring)
            return false;
        
        // set before yield to guard against reentrancy
        monitoring = true;
        
        if (folder.get_open_state() == Geary.Folder.OpenState.CLOSED) {
            try {
                yield folder.open_async(false, cancellable);
            } catch (Error err) {
                monitoring = false;
                
                throw err;
            }
        }
        
        cancellable_monitor = cancellable;
        folder.email_appended.connect(on_folder_email_appended);
        folder.email_removed.connect(on_folder_email_removed);
        folder.email_flags_changed.connect(on_folder_email_flags_changed);
        folder.closed.connect(on_folder_closed);
        
        notify_monitoring_started();
        
        return true;
    }
    
    public async void stop_monitoring_async(bool close_folder, Cancellable? cancellable = null) throws Error {
        yield stop_monitoring_internal_async(close_folder, false, cancellable);
    }
    
    private async void stop_monitoring_internal_async(bool close_folder, bool retrying,
        Cancellable? cancellable) throws Error {
        // always unschedule, as Timeout will hold a reference to this object
        unschedule_retry();
        
        if (!monitoring)
            return;
        
        // set now to prevent reentrancy during yield or signal
        monitoring = false;
        
        folder.email_appended.disconnect(on_folder_email_appended);
        folder.email_removed.disconnect(on_folder_email_removed);
        folder.email_flags_changed.disconnect(on_folder_email_flags_changed);
        folder.closed.disconnect(on_folder_closed);
        
        Error? close_err = null;
        if (close_folder) {
            try {
                yield folder.close_async(cancellable ?? cancellable_monitor);
            } catch (Error err) {
                // throw, but only after cleaning up (which is to say, if close_async() fails,
                // then the Folder is still treated as closed, which is the best that can be
                // expected; it definitely shouldn't still be considered open).
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
    public async void load_async(int low, int count, Geary.Folder.ListFlags flags,
        Cancellable? cancellable) throws Error {
        notify_scan_started(null, low, count);
        try {
            Gee.List<Email>? list = yield folder.list_email_async(low, count, required_fields, flags,
                cancellable);
            on_email_listed(list, null);
            if (list != null)
                on_email_listed(null, null);
        } catch (Error err) {
            on_email_listed(null, err);
        }
    }
    
    /**
     * See Geary.Folder.lazy_list_email_async() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    public void lazy_load(int low, int count, Geary.Folder.ListFlags flags, Cancellable? cancellable) {
        notify_scan_started(null, low, count);
        folder.lazy_list_email(low, count, required_fields, flags, on_email_listed, cancellable);
    }
    
    /**
     * See Geary.Folder.list_email_by_id_async() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    public async void load_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Folder.ListFlags flags, Cancellable? cancellable) throws Error {
        notify_scan_started(initial_id, -1, count);
        try {
            Gee.List<Email>? list = yield folder.list_email_by_id_async(initial_id, count,
                required_fields, flags, cancellable);
            on_email_listed(list, null);
            if (list != null)
                on_email_listed(null, null);
        } catch (Error err) {
            on_email_listed(null, err);
            throw err;
        }
    }
    
    /**
     * See Geary.Folder.lazy_list_email_by_id() for details of how these parameters operate.  Instead
     * of returning emails, this method will load the Conversations object with them sorted into
     * Conversation objects.
     */
    public void lazy_load_by_id(Geary.EmailIdentifier initial_id, int count, Geary.Folder.ListFlags flags,
        Cancellable? cancellable) {
        notify_scan_started(initial_id, -1, count);
        folder.lazy_list_email_by_id(initial_id, count, required_fields, flags, on_email_listed,
            cancellable);
    }
    
    private void on_email_listed(Gee.List<Geary.Email>? emails, Error? err) {
        if (err != null)
            notify_scan_error(err);
        
        // check for completion
        if (emails == null) {
            notify_scan_completed();
            
            return;
        }
        
        process_email(emails);
    }
    
    private void process_email(Gee.List<Geary.Email> emails) {
        Gee.HashSet<RFC822.MessageID> ancestors = new Gee.HashSet<RFC822.MessageID>(
            Hashable.hash_func, Equalable.equal_func);
        Gee.HashSet<Conversation> new_conversations = new Gee.HashSet<Conversation>();
        Gee.MultiMap<Conversation, Geary.Email> appended_conversations = new Gee.HashMultiMap<
            Conversation, Geary.Email>();
        foreach (Geary.Email email in emails) {
            // Right now, all threading is done with Message-IDs (no parsing of subject lines, etc.)
            // If a message doesn't have a Message-ID, it's treated as its own conversation
            
            // build lineage of this email
            ancestors.clear();
            
            // the email's Message-ID counts as its lineage
            if (email.message_id != null)
                ancestors.add(email.message_id);
            
            // References list the email trail back to its source
            if (email.references != null && email.references.list != null)
                ancestors.add_all(email.references.list);
            
            // RFC822 requires the In-Reply-To Message-ID be prepended to the References list, but
            // this ensures that's the case
            if (email.in_reply_to != null)
               ancestors.add(email.in_reply_to);
            
            // see if any of these ancestor IDs maps to an existing conversation
            ImplConversation? conversation = null;
            foreach (RFC822.MessageID ancestor_id in ancestors) {
                conversation = message_id_map.get(ancestor_id);
                if (conversation != null)
                    break;
            }
            
            // create new conversation if not seen before
            if (conversation == null) {
                conversation = new ImplConversation(this);
                new_conversations.add(conversation);
            } else {
                appended_conversations.set(conversation, email);
            }
            
            // add this email to the conversation
            conversation.add(email);
            
            // map email identifier to email (for later removal)
            geary_id_map.set(email.id, conversation);
            
            // map all ancestors to this conversation
            foreach (RFC822.MessageID ancestor_id in ancestors) {
                ImplConversation? current = message_id_map.get(ancestor_id);
                if (current != null && current != conversation)
                    debug("WARNING: Alternate conversation found when assigning ancestors");
                else
                    message_id_map.set(ancestor_id, conversation);
            }
        }
        
        // Save and signal the new conversations
        if (new_conversations.size > 0) {
            conversations.add_all(new_conversations);
            notify_conversations_added(new_conversations);
        }
        
        // fire signals for other changes
        foreach (Conversation conversation in appended_conversations.get_all_keys())
            notify_conversation_appended(conversation, appended_conversations.get(conversation));
    }
    
    private void remove_email(Geary.EmailIdentifier removed_id) {
        // Remove EmailIdentifier from map
        ImplConversation conversation;
        if (!geary_id_map.unset(removed_id, out conversation)) {
            debug("Removed email %s not found on conversations model", removed_id.to_string());
            
            return;
        }
        
        Geary.Email? found = conversation.get_email_by_id(removed_id);
        if (found == null) {
            debug("WARNING: Unable to locate email ID %s in conversation", removed_id.to_string());
            
            return;
        }
        
        conversation.remove(found);
        if (found.message_id != null)
            message_id_map.unset(found.message_id);
        
        notify_conversation_trimmed(conversation, found);
        
        if (conversation.get_count() == 0) {
            // remove the Conversation from the master list
            bool removed = conversations.remove((ImplConversation) conversation);
            assert(removed);
            
            // done
            notify_conversation_removed(conversation);
        }
    }
    
    private void on_folder_email_appended() {
        // Find highest identifier by ordering
        Geary.EmailIdentifier? highest = null;
        foreach (Conversation c in conversations) {
            Geary.Email head = c.get_email(Conversation.Ordering.ID_DESCENDING).first();
            if (highest == null || (head.id.compare(highest) > 0))
                highest = head.id;
        }
        
        if (highest == null) {
            debug("Unable to find highest message position in %s", folder.to_string());
            
            return;
        }
        
        debug("Message(s) appended to %s, fetching email above %s", folder.to_string(),
            highest.to_string());
        
        // Want to get the one *after* the highest position in the list
        lazy_load_by_id(highest, int.MAX, Folder.ListFlags.EXCLUDING_ID, cancellable_monitor);
    }
    
    private void on_folder_email_removed(Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        foreach (Geary.EmailIdentifier id in removed_ids)
            remove_email(id);
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
    
    private void on_folder_closed(Folder.CloseReason reason) {
        // watch for errors; these indicate a retry should occur
        if (reason == Folder.CloseReason.LOCAL_ERROR || reason == Folder.CloseReason.REMOTE_ERROR) {
            // only retry if configured to do so
            if (reestablish_connections)
                retry_connection = true;
            
            return;
        }
        
        // wait for the folder to be completely closed before retrying
        if (reason != Folder.CloseReason.FOLDER_CLOSED)
            return;
        
        if (!retry_connection) {
            stop_monitoring_internal_async.begin(false, false, null);
            
            return;
        }
        
        // reset
        retry_connection = false;
        
        debug("Folder %s closed, restablishing connection to continue monitoring conversations",
            folder.to_string());
        
        // First retry is immediate; thereafter, a delay
        do_restart_monitoring_async.begin();
    }
    
    private async void do_restart_monitoring_async() {
        try {
            yield stop_monitoring_internal_async(false, true, cancellable_monitor);
        } catch (Error stop_err) {
            debug("Error closing folder %s while reestablishing connection: %s", folder.to_string(),
                stop_err.message);
        }
        
        // TODO: Get smarter about this, especially since this might be an authentication error
        // and not a hard error
        try {
            yield start_monitoring_async(cancellable_monitor);
            debug("Reestablished connection to %s, continuing to monitor conversations",
                folder.to_string());
        } catch (Error start_err) {
            debug("Unable to restablish connection to %s, retrying in %d seconds: %s", folder.to_string(),
                RETRY_CONNECTION_SEC, start_err.message);
            
            schedule_retry(true);
        }
    }
    
    // TODO: A back-off algorithm would make tons of sense here; the reschedule flag can assist
    // in that calculation
    private void schedule_retry(bool reschedule) {
        if (reschedule)
            unschedule_retry();
        else if (retry_id != 0)
            return;
        
        Timeout.add_seconds(RETRY_CONNECTION_SEC, on_delayed_retry);
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
}

