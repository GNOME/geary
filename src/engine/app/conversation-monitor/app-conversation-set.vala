/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ConversationSet : BaseObject {
    private Gee.Set<ImplConversation> _conversations = new Gee.HashSet<ImplConversation>();
    
    // Maps email ids to conversations.
    private Gee.HashMap<Geary.EmailIdentifier, ImplConversation> email_id_map
        = new Gee.HashMap<Geary.EmailIdentifier, ImplConversation>();
    
    // Only contains the Message-ID headers of emails actually in
    // conversations.
    private Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> contained_message_id_map
        = new Gee.HashMap<Geary.RFC822.MessageID, ImplConversation>();
    
    // Contains the full set of Message IDs theoretically in each conversation,
    // as determined by the ancestors of all messages in the conversation.
    private Gee.HashMap<Geary.RFC822.MessageID, ImplConversation> logical_message_id_map
        = new Gee.HashMap<Geary.RFC822.MessageID, ImplConversation>();
    
    public int size { get { return _conversations.size; } }
    public bool is_empty { get { return _conversations.is_empty; } }
    public Gee.Collection<Geary.Conversation> conversations {
        owned get { return _conversations.read_only_view; }
    }
    
    public ConversationSet() {
    }
    
    public int get_email_count(bool folder_email_ids_only = false) {
        if (!folder_email_ids_only)
            return email_id_map.size;
        
        int count = 0;
        foreach (ImplConversation conversation in _conversations)
            count += conversation.get_count(folder_email_ids_only);
        return count;
    }
    
    public bool contains(Geary.Conversation conversation) {
        if (!(conversation is ImplConversation))
            return false;
        return _conversations.contains((ImplConversation) conversation);
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
    public bool has_message_id(Geary.RFC822.MessageID message_id, bool logical_set = false) {
        return (logical_set ? logical_message_id_map : contained_message_id_map).has_key(message_id);
    }
    
    public Geary.Conversation? get_by_email_identifier(Geary.EmailIdentifier id) {
        return email_id_map.get(id);
    }
    
    /**
     * Return the conversation the given Message ID belongs to.  If
     * logical_set, the Message ID may match any ancestor of any message in any
     * conversation; else it must match the Message-ID header of an email in
     * any conversation.  Return null if not found.
     */
    public Geary.Conversation? get_by_message_id(Geary.RFC822.MessageID message_id,
        bool logical_set = false) {
        return (logical_set ? logical_message_id_map : contained_message_id_map).get(message_id);
    }
    
    public void clear_owners() {
        foreach (ImplConversation conversation in _conversations)
            conversation.clear_owner();
    }
    
    private void remove_email_from_conversation(ImplConversation conversation, Geary.Email email) {
        // Be very strict about our internal state getting out of whack, since
        // it would indicate a nasty error in our logic that we need to fix.
        if (!email_id_map.unset(email.id))
            error("Email %s already removed from conversation set", email.id.to_string());
        
        if (email.message_id != null) {
            if (!contained_message_id_map.unset(email.message_id))
                error("Message-ID %s already removed from conversation set", email.message_id.to_string());
        }
        
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
    
    private bool remove_duplicate_email_by_message_id(ImplConversation conversation,
        Geary.Email email, Geary.FolderPath? preferred_folder_path) {
        Email? existing = null;
        foreach (Geary.Email other in conversation.get_emails(Geary.Conversation.Ordering.NONE)) {
            if (other.message_id != null && email.message_id.equal_to(other.message_id)) {
                existing = other;
                break;
            }
        }
        if (existing == null) {
            error("Email with Message-ID %s not found in conversation %s",
                email.message_id.to_string(), conversation.to_string());
        }
        
        bool basic_upgrade = (existing.id.folder_path == null && email.id.folder_path != null);
        bool preferred_folder_upgrade = (preferred_folder_path != null &&
            email.id.folder_path != null &&
            existing.id.folder_path != null &&
            preferred_folder_path.equal_to(email.id.folder_path) &&
            !preferred_folder_path.equal_to(existing.id.folder_path));
        if (basic_upgrade || preferred_folder_upgrade) {
            remove_email_from_conversation(conversation, existing);
            return true;
        }
        
        return false;
    }
    
    // Returns a Collection of zero or more Conversations that have Message-IDs associated with
    // the ancestors of the supplied Email ... if more than one, then add_email() should not be
    // called
    private Gee.Set<ImplConversation> get_associated_conversations(Geary.Email email) {
        Gee.Set<ImplConversation> associated = new Gee.HashSet<ImplConversation>();
        
        Gee.Set<Geary.RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            foreach (Geary.RFC822.MessageID ancestor in ancestors) {
                ImplConversation conversation = logical_message_id_map.get(ancestor);
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
    private Geary.Conversation? add_email(Geary.Email email, ConversationMonitor monitor,
        Geary.FolderPath? preferred_folder_path, out bool added_conversation) {
        added_conversation = false;
        
        if (email_id_map.has_key(email.id))
            return null;
        
        ImplConversation? conversation = null;
        if (email.message_id != null) {
            conversation = contained_message_id_map.get(email.message_id);
            // This can happen when we find results in multiple folders or a
            // message gets moved into the current folder after we found it
            // through "full conversations".  They won't have the same
            // EmailIdentifier, but (we assume) they're the same message
            // otherwise.
            if (conversation != null &&
                !remove_duplicate_email_by_message_id(conversation, email, preferred_folder_path)) {
                return null;
            }
        }
        
        if (conversation == null) {
            Gee.Set<ImplConversation> associated = get_associated_conversations(email);
            assert(associated.size <= 1);
            
            if (associated.size == 1)
                conversation = Collection.get_first<ImplConversation>(associated);
        }
        
        if (conversation == null) {
            conversation = new ImplConversation(monitor);
            _conversations.add(conversation);
            
            added_conversation = true;
        }
        
        add_email_to_conversation(conversation, email);
        
        return conversation;
    }
    
    private void add_email_to_conversation(ImplConversation conversation, Geary.Email email) {
        if (!conversation.add(email)) {
            error("Couldn't add duplicate email %s to conversation %s",
                email.id.to_string(), conversation.to_string());
        }
        
        email_id_map.set(email.id, conversation);
        
        if (email.message_id == null)
            debug("Adding email %s without Message-ID to conversation set", email.id.to_string());
        else
            contained_message_id_map.set(email.message_id, conversation);
        
        Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            foreach (Geary.RFC822.MessageID ancestor in ancestors)
                logical_message_id_map.set(ancestor, conversation);
        }
    }
    
    public void add_all_emails(Gee.Collection<Geary.Email> emails,
        ConversationMonitor monitor, Geary.FolderPath? preferred_folder_path,
        out Gee.Collection<Geary.Conversation> added,
        out Gee.MultiMap<Geary.Conversation, Geary.Email> appended,
        out Gee.Collection<Geary.Conversation> removed_due_to_merge) {
        Gee.HashSet<Geary.Conversation> _added = new Gee.HashSet<Geary.Conversation>();
        Gee.HashMultiMap<Geary.Conversation, Geary.Email> _appended
            = new Gee.HashMultiMap<Geary.Conversation, Geary.Email>();
        Gee.HashSet<Geary.Conversation> _removed_due_to_merge = new Gee.HashSet<Geary.Conversation>();
        foreach (Geary.Email email in emails) {
            Gee.Set<ImplConversation> associated = get_associated_conversations(email);
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
                ImplConversation dest = merge_conversations(associated, moved_email);
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
            Geary.Conversation? conversation = add_email(
                email, monitor, preferred_folder_path, out added_conversation);
            
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
    private ImplConversation merge_conversations(Gee.Set<ImplConversation> conversations,
        Gee.Set<Geary.Email> moved_email) {
        assert(conversations.size > 0);
        
        // find the largest conversation and merge the others into it
        ImplConversation? dest = null;
        foreach (ImplConversation conversation in conversations) {
            if (dest == null || conversation.get_count() > dest.get_count())
                dest = conversation;
        }
        
        // remove the largest from the list so it's not included in the Collection of source
        // conversations merged into it
        bool removed = conversations.remove(dest);
        assert(removed);
        
        foreach (ImplConversation conversation in conversations)
            moved_email.add_all(conversation.get_emails(Conversation.Ordering.NONE));
        
        // convert total sum of Emails to move into map of ID -> Email
        Gee.Map<Geary.EmailIdentifier, Geary.Email>? id_map = Geary.Email.emails_to_map(moved_email);
        // there better be some Email here, otherwise things are really hosed
        assert(id_map != null && id_map.size > 0);
        
        // remove using the standard call, to ensure all state is updated
        Gee.MultiMap<Geary.Conversation, Geary.Email> trimmed_conversations;
        Gee.Collection<Geary.Conversation> removed_conversations;
        remove_all_emails_by_identifier(id_map.keys, out removed_conversations, out trimmed_conversations);
        
        // Conversations should have been removed, not trimmed, and it better have only been the
        // conversations we're merging
        assert(trimmed_conversations.size == 0);
        assert(removed_conversations.size == conversations.size);
        foreach (ImplConversation conversation in conversations)
            assert(removed_conversations.contains(conversation));
        
        // now add all that email back to the destination Conversation
        foreach (Geary.Email moved in moved_email)
            add_email_to_conversation(dest, moved);
        
        return dest;
    }
    
    private Geary.Conversation? remove_email_by_identifier(Geary.EmailIdentifier id,
        out Geary.Email? removed_email, out bool removed_conversation) {
        removed_email = null;
        removed_conversation = false;
        
        ImplConversation? conversation = email_id_map.get(id);
        if (conversation == null) {
            debug("Removed email %s not found in conversation set", id.to_string());
            return null;
        }
        
        Geary.Email? email = conversation.get_email_by_id(id);
        if (email == null)
            error("Unable to locate email %s in conversation %s", id.to_string(), conversation.to_string());
        removed_email = email;
        
        remove_email_from_conversation(conversation, email);
        
        // Evaporate conversations with no more messages in the folder.
        if (conversation.get_count(true) == 0) {
            foreach (Geary.Email conversation_email in conversation.get_emails(Geary.Conversation.Ordering.NONE))
                remove_email_from_conversation(conversation, conversation_email);
            
            if (!_conversations.remove(conversation))
                error("Conversation %s already removed from set", conversation.to_string());
            debug("Removing email %s evaporates conversation %s", id.to_string(), conversation.to_string());
            
            conversation.clear_owner();
            
            removed_conversation = true;
        }
        
        return conversation;
    }
    
    public void remove_all_emails_by_identifier(Gee.Collection<Geary.EmailIdentifier> ids,
        out Gee.Collection<Geary.Conversation> removed,
        out Gee.MultiMap<Geary.Conversation, Geary.Email> trimmed) {
        Gee.HashSet<Geary.Conversation> _removed = new Gee.HashSet<Geary.Conversation>();
        Gee.HashMultiMap<Geary.Conversation, Geary.Email> _trimmed
            = new Gee.HashMultiMap<Geary.Conversation, Geary.Email>();
        
        foreach (Geary.EmailIdentifier id in ids) {
            Geary.Email email;
            bool removed_conversation;
            Geary.Conversation? conversation = remove_email_by_identifier(
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
}
