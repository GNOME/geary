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
        Geary.Email.Field.PROPERTIES;
    
    private class ImplConversation : Conversation {
        public weak Geary.Conversations? owner;
        public Gee.HashMap<EmailIdentifier, Email> emails = new Gee.HashMap<EmailIdentifier, Email>(
            Hashable.hash_func, Equalable.equal_func);
        
        public ImplConversation(Geary.Conversations owner) {
            this.owner = owner;
        }
        
        public override int get_count() {
            return emails.size;
        }
        
        public override Gee.Collection<Geary.Email> get_email() {
            return emails.values.read_only_view;
        }
        
        public void add(Email email) {
            emails.set(email.id, email);
        }
        
        public void remove(Email email) {
            emails.unset(email.id);
        }
    }
    
    public Geary.Folder folder { get; private set; }
    
    private Geary.Email.Field required_fields;
    private Gee.Set<ImplConversation> conversations = new Gee.HashSet<ImplConversation>();
    private Gee.HashMap<RFC822.MessageID, ImplConversation> message_id_map = new Gee.HashMap<
        RFC822.MessageID, ImplConversation>(Hashable.hash_func, Equalable.equal_func);
    private Gee.HashMap<Geary.EmailIdentifier, ImplConversation> geary_id_map = new Gee.HashMap<
        Geary.EmailIdentifier, ImplConversation>(Hashable.hash_func, Equalable.equal_func);
    private bool monitor_new = false;
    private Cancellable? cancellable_monitor = null;
    
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
    
    public Conversations(Geary.Folder folder, Geary.Email.Field required_fields) {
        this.folder = folder;
        this.required_fields = required_fields | REQUIRED_FIELDS;
    }
    
    ~Conversations() {
        if (monitor_new) {
            folder.email_appended.disconnect(on_folder_email_appended);
            folder.email_removed.disconnect(on_folder_email_removed);
        }
        
        // Manually detach all the weak refs in the Conversation objects
        foreach (ImplConversation conversation in conversations)
            conversation.owner = null;
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
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.read_only_view;
    }
    
    public Geary.Conversation? get_conversation_for_email(Geary.EmailIdentifier email_id) {
        return geary_id_map.get(email_id);
    }
    
    public bool monitor_new_messages(Cancellable? cancellable = null) {
        if (monitor_new)
            return false;
        
        monitor_new = true;
        cancellable_monitor = cancellable;
        folder.email_appended.connect(on_folder_email_appended);
        folder.email_removed.connect(on_folder_email_removed);
        
        return true;
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
        
        Geary.Email? found = conversation.emails.get(removed_id);
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
        // TODO: optimize.
        Geary.EmailIdentifier? highest = null;
        foreach (Conversation c in conversations) {
            foreach (Email e in c.get_email()) {
                if (highest == null || (e.id.compare(highest) > 0))
                    highest = e.id;
            }
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
}

