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
            if (email.message_id.equal_to(other.message_id)) {
                existing = email;
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
    
    /**
     * Add the email (requires Field.REFERENCES) to the mix, creating a new
     * conversation if necessary.  In the event a duplicate email is added (as
     * detected by Message-ID), the email whose EmailIdentifier has the
     * preferred_folder_path will be kept, and the other discarded (note that
     * we always prefer an identifier with a non-null folder path over a null
     * folder path, regardless of what the non-null path is).  Return the
     * conversation the email was added to.  Return in added_conversation
     * whether a new conversation was created.
     */
    public Geary.Conversation add_email(Geary.Email email, ConversationMonitor monitor,
        Geary.FolderPath? preferred_folder_path, out bool added_conversation) {
        added_conversation = false;
        
        // This kind of duplicate is safe to re-add because it's got the same
        // EmailIdentifier, and ImplConversation handles all the necessary
        // juggling.
        ImplConversation? conversation = email_id_map.get(email.id);
        
        if (conversation == null && email.message_id != null) {
            conversation = contained_message_id_map.get(email.message_id);
            // This can happen when we find results in multiple folders.  They
            // won't have the same EmailIdentifier, but (we assume) they're the
            // same message otherwise.  Under some circumstances, we can't
            // re-add the duplicate, because of the different identifiers.
            if (conversation != null &&
                !remove_duplicate_email_by_message_id(conversation, email, preferred_folder_path)) {
                return conversation;
            }
        }
        
        Gee.Set<Geary.RFC822.MessageID>? ancestors = email.get_ancestors();
        if (conversation == null && ancestors != null) {
            foreach (Geary.RFC822.MessageID ancestor in ancestors) {
                conversation = logical_message_id_map.get(ancestor);
                if (conversation != null)
                    break;
            }
        }
        
        if (conversation == null) {
            conversation = new ImplConversation(monitor);
            _conversations.add(conversation);
            
            added_conversation = true;
        }
        
        // It's desired to call add even though the email may be a duplicate,
        // to make sure we always have the "best copy" of the email.
        if (conversation.add(email)) {
            // We could check that nothing we're about to set in these maps
            // is already there, but since we're allowed to re-add emails, that
            // can be complicated.  Instead, we add extra scrutiny to the
            // remove_email_by_identifier method, below.
            email_id_map.set(email.id, conversation);
            
            if (email.message_id == null)
                debug("Adding email %s without Message-ID to conversation set", email.id.to_string());
            else
                contained_message_id_map.set(email.message_id, conversation);
            
            if (ancestors != null) {
                foreach (Geary.RFC822.MessageID ancestor in ancestors)
                    logical_message_id_map.set(ancestor, conversation);
            }
        }
        
        return conversation;
    }
    
    public void add_all_emails(Gee.Collection<Geary.Email> emails,
        ConversationMonitor monitor, Geary.FolderPath? preferred_folder_path,
        out Gee.Collection<Geary.Conversation> added,
        out Gee.MultiMap<Geary.Conversation, Geary.Email> appended) {
        Gee.HashSet<Geary.Conversation> _added = new Gee.HashSet<Geary.Conversation>();
        Gee.HashMultiMap<Geary.Conversation, Geary.Email> _appended
            = new Gee.HashMultiMap<Geary.Conversation, Geary.Email>();
        
        foreach (Geary.Email email in emails) {
            bool added_conversation;
            Geary.Conversation conversation = add_email(
                email, monitor, preferred_folder_path, out added_conversation);
            
            if (added_conversation) {
                _added.add(conversation);
            } else {
                if (!_added.contains(conversation))
                    _appended.set(conversation, email);
            }
        }
        
        added = _added;
        appended = _appended;
    }
    
    public Geary.Conversation? remove_email_by_identifier(Geary.EmailIdentifier id,
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
