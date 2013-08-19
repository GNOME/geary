/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ConversationSet : BaseObject {
    private Gee.Set<Conversation> _conversations = new Gee.HashSet<Conversation>();
    
    // Maps email ids to conversations.
    private Gee.HashMap<Geary.EmailIdentifier, Conversation> email_id_map
        = new Gee.HashMap<Geary.EmailIdentifier, Conversation>();
    
    // Contains the full set of Message IDs theoretically in each conversation,
    // as determined by the ancestors of all messages in the conversation.
    private Gee.HashMap<Geary.RFC822.MessageID, Conversation> logical_message_id_map
        = new Gee.HashMap<Geary.RFC822.MessageID, Conversation>();
    
    public int size { get { return _conversations.size; } }
    public bool is_empty { get { return _conversations.is_empty; } }
    public Gee.Collection<Conversation> conversations {
        owned get { return _conversations.read_only_view; }
    }
    
    public ConversationSet() {
    }
    
    public int get_email_count() {
        return email_id_map.size;
    }
    
    public bool contains(Conversation conversation) {
        return _conversations.contains(conversation);
    }
    
    public bool has_email_identifier(Geary.EmailIdentifier id) {
        return email_id_map.has_key(id);
    }
    
    /**
     * Return whether the set has the given Message ID.  If logical_set,
     * there's no requirement that any conversation actually contain a message
     * with a matching Message-ID header, and any Message ID matching any
     * ancestor of any message in any conversation will match.
     */
    public bool has_message_id(Geary.RFC822.MessageID message_id) {
        return logical_message_id_map.has_key(message_id);
    }
    
    public Conversation? get_by_email_identifier(Geary.EmailIdentifier id) {
        return email_id_map.get(id);
    }
    
    public void clear_owners() {
        foreach (Conversation conversation in _conversations)
            conversation.clear_owner();
    }
    
    // Returns a Collection of zero or more Conversations that have Message-IDs associated with
    // the ancestors of the supplied Email ... if more than one, then add_email() should not be
    // called
    private Gee.Set<Conversation> get_associated_conversations(Geary.Email email) {
        Gee.Set<Conversation> associated = new Gee.HashSet<Conversation>();
        
        Gee.Set<Geary.RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            foreach (Geary.RFC822.MessageID ancestor in ancestors) {
                Conversation conversation = logical_message_id_map.get(ancestor);
                if (conversation != null)
                    associated.add(conversation);
            }
        }
        
        return associated;
    }
    
    /**
     * Add the email (requires Field.REFERENCES) to the mix, potentially
     * replacing an existing email with the same id, or creating a new
     * conversation if necessary.  In the event of a duplicate (as detected by
     * Message-ID), the email whose EmailIdentifier has the
     * preferred_folder_path will be kept, and the other discarded (note that
     * we always prefer an identifier with a non-null folder path over a null
     * folder path, regardless of what the non-null path is).  Return null if
     * we didn't add the email (e.g. it was a dupe and we preferred the
     * existing email), or the conversation it was added to.  Return in
     * added_conversation whether a new conversation was created.
     *
     * NOTE: Do not call this method if get_associated_conversations() returns a Collection with
     * a size greater than one.  That indicates the Conversations *must* be merged before adding.
     */
    private Conversation? add_email(Geary.Email email, ConversationMonitor monitor,
        Geary.FolderPath? preferred_folder_path, Gee.Collection<Geary.FolderPath>? known_paths,
        out bool added_conversation) {
        added_conversation = false;
        
        if (email_id_map.has_key(email.id))
            return null;
        
        Gee.Set<Conversation> associated = get_associated_conversations(email);
        assert(associated.size <= 1);
        
        Conversation? conversation = null;
        if (associated.size == 1)
            conversation = Collection.get_first<Conversation>(associated);
        
        if (conversation == null) {
            conversation = new Conversation(monitor);
            _conversations.add(conversation);
            
            added_conversation = true;
        }
        
        add_email_to_conversation(conversation, email, known_paths);
        
        return conversation;
    }
    
    private void add_email_to_conversation(Conversation conversation, Geary.Email email,
        Gee.Collection<Geary.FolderPath>? known_paths) {
        if (!conversation.add(email, known_paths)) {
            error("Couldn't add duplicate email %s to conversation %s",
                email.id.to_string(), conversation.to_string());
        }
        
        email_id_map.set(email.id, conversation);
        
        Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            foreach (Geary.RFC822.MessageID ancestor in ancestors)
                logical_message_id_map.set(ancestor, conversation);
        }
    }
    
    public async void add_all_emails_async(Gee.Collection<Geary.Email> emails,
        ConversationMonitor monitor, Geary.FolderPath? preferred_folder_path,
        out Gee.Collection<Conversation> added,
        out Gee.MultiMap<Conversation, Geary.Email> appended,
        out Gee.Collection<Conversation> removed_due_to_merge,
        Cancellable? cancellable) throws Error {
        // Get known paths for all emails
        Gee.Map<Geary.EmailIdentifier, Geary.Email>? id_map = Email.emails_to_map(emails);
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? id_to_paths = null;
        if (id_map != null) {
            id_to_paths = yield monitor.folder.account.get_containing_folders_async(id_map.keys,
                cancellable);
        }
        
        Gee.HashSet<Conversation> _added = new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Geary.Email> _appended
            = new Gee.HashMultiMap<Conversation, Geary.Email>();
        Gee.HashSet<Conversation> _removed_due_to_merge = new Gee.HashSet<Conversation>();
        foreach (Geary.Email email in emails) {
            Gee.Set<Conversation> associated = get_associated_conversations(email);
            if (associated.size > 1) {
                // When multiple conversations hold one or more of the Message-IDs in the email's
                // ancestry, it means a prior email processed here didn't properly list their entire
                // In-Reply-To or References and a split in the conversation appeared ...
                // ConversationSet *requires* each Message-ID is associated with one and only one
                // Conversation
                //
                // By doing this first, it prevents ConversationSet getting itself into a bad state
                // where more than one Conversation thinks it "owns" a Message-ID
                debug("Merging %d conversations due new email associating with all...", associated.size);
                
                // Note that this call will modify the List so it only holds the to-be-axed
                // Conversations
                Gee.Set<Geary.Email> moved_email = new Gee.HashSet<Geary.Email>();
                Conversation dest = yield merge_conversations_async(monitor, associated, moved_email,
                    cancellable);
                assert(!associated.contains(dest));
                
                // remove the remaining conversations from the added/appended Collections
                _added.remove_all(associated);
                foreach (Conversation removed_conversation in associated)
                    _appended.remove_all(removed_conversation);
                
                // but notify caller they were merged away
                _removed_due_to_merge.add_all(associated);
                
                // the dest was always appended to, never created
                if (!_added.contains(dest)) {
                    foreach (Geary.Email moved in moved_email)
                        _appended.set(dest, moved);
                }
                
                // Nasty ol' Email won't cause problems now -- but let's check anyway!
                assert(get_associated_conversations(email).size <= 1);
            }
            
            bool added_conversation;
            Conversation? conversation = add_email(
                email, monitor, preferred_folder_path,
                (id_to_paths != null) ? id_to_paths.get(email.id) : null,
                out added_conversation);
            
            if (conversation == null)
                continue;
            
            if (added_conversation) {
                _added.add(conversation);
            } else {
                if (!_added.contains(conversation))
                    _appended.set(conversation, email);
            }
        }
        
        added = _added;
        appended = _appended;
        removed_due_to_merge = _removed_due_to_merge;
    }
    
    // This method will remove the destination (merged) Conversation from the List and return it
    // as the result, along with a Collection of email that must be merged into it
    private async Conversation merge_conversations_async(ConversationMonitor monitor,
        Gee.Set<Conversation> conversations, Gee.Set<Geary.Email> moved_email,
        Cancellable? cancellable) throws Error {
        assert(conversations.size > 0);
        
        // find the largest conversation and merge the others into it
        Conversation? dest = null;
        foreach (Conversation conversation in conversations) {
            if (dest == null || conversation.get_count() > dest.get_count())
                dest = conversation;
        }
        
        // remove the largest from the list so it's not included in the Collection of source
        // conversations merged into it
        bool removed = conversations.remove(dest);
        assert(removed);
        
        foreach (Conversation conversation in conversations)
            moved_email.add_all(conversation.get_emails(Conversation.Ordering.NONE));
        
        // convert total sum of Emails to move into map of ID -> Email
        Gee.Map<Geary.EmailIdentifier, Geary.Email>? id_map = Geary.Email.emails_to_map(moved_email);
        // there better be some Email here, otherwise things are really hosed
        assert(id_map != null && id_map.size > 0);
        
        // remove using the standard call, to ensure all state is updated
        Gee.MultiMap<Conversation, Geary.Email> trimmed_conversations;
        Gee.Collection<Conversation> removed_conversations;
        remove_all_emails_by_identifier(id_map.keys, out removed_conversations, out trimmed_conversations);
        
        // Conversations should have been removed, not trimmed, and it better have only been the
        // conversations we're merging
        assert(trimmed_conversations.size == 0);
        assert(removed_conversations.size == conversations.size);
        foreach (Conversation conversation in conversations)
            assert(removed_conversations.contains(conversation));
        
        // Get known paths for all emails being moved
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? id_to_paths =
            yield monitor.folder.account.get_containing_folders_async(id_map.keys, cancellable);
        
        // now add all that email back to the destination Conversation
        foreach (Geary.Email moved in moved_email)
            add_email_to_conversation(dest, moved, (id_to_paths != null) ? id_to_paths.get(moved.id) : null);
        
        return dest;
    }
    
    private void remove_email_from_conversation(Conversation conversation, Geary.Email email) {
        // Be very strict about our internal state getting out of whack, since
        // it would indicate a nasty error in our logic that we need to fix.
        if (!email_id_map.unset(email.id))
            error("Email %s already removed from conversation set", email.id.to_string());
        
        Gee.Set<Geary.RFC822.MessageID>? removed_message_ids = conversation.remove(email);
        if (removed_message_ids != null) {
            foreach (Geary.RFC822.MessageID removed_message_id in removed_message_ids) {
                if (!logical_message_id_map.unset(removed_message_id)) {
                    error("Message ID %s already removed from conversation set logical map",
                        removed_message_id.to_string());
                }
            }
        }
    }
    
    private void remove_conversation(Conversation conversation) {
        foreach (Geary.Email conversation_email in conversation.get_emails(Conversation.Ordering.NONE))
            remove_email_from_conversation(conversation, conversation_email);
        
        if (!_conversations.remove(conversation))
            error("Conversation %s already removed from set", conversation.to_string());
        
        conversation.clear_owner();
    }
    
    private Conversation? remove_email_by_identifier(Geary.EmailIdentifier id,
        out Geary.Email? removed_email, out bool removed_conversation) {
        removed_email = null;
        removed_conversation = false;
        
        Conversation? conversation = email_id_map.get(id);
        if (conversation == null) {
            debug("Removed email %s not found in conversation set", id.to_string());
            return null;
        }
        
        Geary.Email? email = conversation.get_email_by_id(id);
        if (email == null)
            error("Unable to locate email %s in conversation %s", id.to_string(), conversation.to_string());
        removed_email = email;
        
        remove_email_from_conversation(conversation, email);
        
        // Evaporate conversations with no more messages.
        if (conversation.get_count() == 0) {
            debug("Removing email %s evaporates conversation %s", id.to_string(), conversation.to_string());
            remove_conversation(conversation);
            
            removed_conversation = true;
        }
        
        return conversation;
    }
    
    public void remove_all_emails_by_identifier(Gee.Collection<Geary.EmailIdentifier> ids,
        out Gee.Collection<Conversation> removed,
        out Gee.MultiMap<Conversation, Geary.Email> trimmed) {
        Gee.HashSet<Conversation> _removed = new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Geary.Email> _trimmed
            = new Gee.HashMultiMap<Conversation, Geary.Email>();
        
        foreach (Geary.EmailIdentifier id in ids) {
            Geary.Email email;
            bool removed_conversation;
            Conversation? conversation = remove_email_by_identifier(
                id, out email, out removed_conversation);
            
            if (conversation == null)
                continue;
            
            if (removed_conversation) {
                if (_trimmed.contains(conversation))
                    _trimmed.remove_all(conversation);
                _removed.add(conversation);
            } else {
                _trimmed.set(conversation, email);
            }
        }
        
        removed = _removed;
        trimmed = _trimmed;
    }
    
    /**
     * Make sure that the conversation has some emails in the given folder, and
     * remove the conversation if not.  Return true if there were emails in the
     * folder, or false if the conversation was removed.
     */
    public async bool check_conversation_in_folder_async(Conversation conversation, Geary.Account account,
        Geary.FolderPath required_folder_path, Cancellable? cancellable) throws Error {
        if ((yield conversation.get_count_in_folder_async(account, required_folder_path, cancellable)) == 0) {
            debug("Evaporating conversation %s because it has no emails in %s",
                conversation.to_string(), required_folder_path.to_string());
            remove_conversation(conversation);
            
            return false;
        }
        
        return true;
    }
    
    /**
     * Check a set of emails using check_conversation_in_folder_async(), return
     * the set of emails that were removed due to not being in the folder.
     */
    public async Gee.Collection<Conversation> check_conversations_in_folder(
        Gee.Collection<Conversation> conversations, Geary.Account account,
        Geary.FolderPath required_folder_path, Cancellable? cancellable) {
        Gee.ArrayList<Conversation> evaporated = new Gee.ArrayList<Conversation>();
        foreach (Geary.App.Conversation conversation in conversations) {
            try {
                if (!(yield check_conversation_in_folder_async(
                    conversation, account, required_folder_path, cancellable))) {
                    evaporated.add(conversation);
                }
            } catch (Error e) {
                debug("Unable to check conversation %s for messages in %s: %s",
                    conversation.to_string(), required_folder_path.to_string(), e.message);
            }
        }
        
        return evaporated;
    }
    
    public async void remove_emails_and_check_in_folder(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Account account,
        Geary.FolderPath required_folder_path, out Gee.Collection<Conversation> removed,
        out Gee.MultiMap<Conversation, Geary.Email> trimmed, Cancellable? cancellable) {
        Gee.HashSet<Conversation> _removed = new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Geary.Email> _trimmed
            = new Gee.HashMultiMap<Conversation, Geary.Email>();
        
        Gee.Collection<Conversation> initial_removed;
        Gee.MultiMap<Conversation, Geary.Email> initial_trimmed;
        remove_all_emails_by_identifier(ids, out initial_removed, out initial_trimmed);
        
        Gee.Collection<Conversation> evaporated = yield check_conversations_in_folder(
            initial_trimmed.get_keys(), account, required_folder_path, cancellable);
        
        _removed.add_all(initial_removed);
        _removed.add_all(evaporated);
        
        foreach (Conversation conversation in initial_trimmed.get_keys()) {
            if (!(conversation in _removed)) {
                Geary.Collection.multi_map_set_all<Conversation, Geary.Email>(
                    _trimmed, conversation, initial_trimmed.get(conversation));
            }
        }
        
        removed = _removed;
        trimmed = _trimmed;
    }
}
