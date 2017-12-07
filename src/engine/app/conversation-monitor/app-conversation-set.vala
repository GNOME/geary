/* Copyright 2016 Software Freedom Conservancy Inc.
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
    
    public Gee.Collection<Geary.EmailIdentifier> get_email_identifiers() {
        return email_id_map.keys;
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

    // Returns a Collection of zero or more Conversations that have Message-IDs associated with
    // the ancestors of the supplied Email ... if more than one, then add_email() should not be
    // called
    private Gee.Set<Conversation> get_associated_conversations(Geary.Email email) {
        Gee.Set<Geary.RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            return Geary.traverse<Geary.RFC822.MessageID>(ancestors)
                .map_nonnull<Conversation>(a => logical_message_id_map.get(a))
                .to_hash_set();
        }
        
        return Gee.Set.empty<Conversation>();
    }

    /**
     * Conditionally adds an email to a conversation.
     *
     * The given email will be added to new conversation if there are
     * not any associated conversations, added to an existing
     * conversation if it does not exist in an associated
     * conversation, otherwise if in an existing conversation,
     * `known_paths` will be merged with the email's paths in that
     * conversation.
     *
     * Returns the conversation the email was strictly added to, else
     * `null` if the conversation was simply merged. The parameter
     * `added_conversation` is set `true` if the returned conversation
     * was created, else it is set to `false`.
     */
    private Conversation? add_email(Geary.Email email,
                                    Folder base_folder,
                                    Gee.Collection<FolderPath>? known_paths,
                                    out bool added_conversation) {
        added_conversation = false;

        Conversation? conversation = email_id_map.get(email.id);
        if (conversation != null) {
            // Exists in a conversation, so re-add it directly to
            // merge its paths
            conversation.add(email, known_paths);
            // Don't give the caller the idea that the email was
            // added
            conversation = null;
        } else {
            Gee.Set<Conversation> associated =
                get_associated_conversations(email);
            conversation = Collection.get_first<Conversation>(associated);
            if (conversation == null) {
                // Not in or related to any existing conversations, so
                // create one
                conversation = new Conversation(base_folder);
                _conversations.add(conversation);
                added_conversation = true;
            }

            // Add it and update the set
            add_email_to_conversation(conversation, email, known_paths);
        }

        return conversation;
    }

    /**
     * Unconditionally adds an email to a conversation.
     */
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

    /**
     * Adds a collection of emails to conversations in this set.
     *
     * This method will create and/or merge conversations as
     * needed. The collection `emails` contains the messages to be
     * added, and for each email in the collection, there should be an
     * entry in `id_to_paths` that indicates the folders each message
     * is known to belong to. The folder `base_folder` is the base
     * folder for the conversation monitor that owns this set.
     *
     * The three collections returned include any conversation that
     * were created, any that had email appended to them (and the
     * messages that were appended), and any that were removed due to
     * being merged into another.
     */
    public async void add_all_emails_async(
        Gee.Collection<Geary.Email> emails,
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? id_to_paths,
        Folder base_folder,
        out Gee.Collection<Conversation> added,
        out Gee.MultiMap<Conversation, Geary.Email> appended,
        out Gee.Collection<Conversation> removed_due_to_merge,
        Cancellable? cancellable)
    throws Error {
        Gee.HashSet<Conversation> _added =
            new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Geary.Email> _appended =
            new Gee.HashMultiMap<Conversation, Geary.Email>();
        Gee.HashSet<Conversation> _removed_due_to_merge =
            new Gee.HashSet<Conversation>();

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
                Conversation dest = yield merge_conversations_async(
                    associated, moved_email, cancellable
                );
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
                email,
                base_folder,
                (id_to_paths != null) ? id_to_paths.get(email.id) : null,
                out added_conversation
            );

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
    private async Conversation
        merge_conversations_async(Gee.Set<Conversation> conversations,
                                  Gee.Set<Geary.Email> moved_email,
                                  Cancellable? cancellable)
        throws Error {
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

        // Collect all emails and their paths from all conversations
        // to be merged, then remove those conversations
        Gee.MultiMap<Geary.EmailIdentifier,Geary.FolderPath>? id_to_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier,Geary.FolderPath>();
        foreach (Conversation conversation in conversations) {
            foreach (EmailIdentifier id in conversation.path_map.get_keys()) {
                moved_email.add(conversation.get_email_by_id(id));
                foreach (FolderPath path in conversation.path_map.get(id)) {
                    id_to_paths.set(id, path);
                }
            }
            remove_conversation(conversation);
        }

        // Now add all that email back to the destination Conversation
        foreach (Geary.Email moved in moved_email) {
            add_email_to_conversation(dest, moved, id_to_paths.get(moved.id));
        }

        return dest;
    }

    /**
     * Removes a conversation from the set.
     */
    private void remove_conversation(Conversation conversation) {
        foreach (Geary.Email conversation_email in conversation.get_emails(Conversation.Ordering.NONE))
            remove_email_from_conversation(conversation, conversation_email);

        if (!_conversations.remove(conversation))
            error("Conversation %s already removed from set", conversation.to_string());
    }

    /**
     * Unconditionally removes an email from a conversation.
     */
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

    /**
     * Conditionally removes an email from a conversation.
     *
     * The given email will only be removed from the conversation if
     * it is associated with a path, i.e. if it is present in more
     * than one folder. Otherwise `source_path` is removed from the
     * email's set of known paths.
     */
    private Conversation? remove_email_by_identifier(FolderPath source_path,
                                                     EmailIdentifier id,
                                                     out Geary.Email? removed_email,
                                                     out bool removed_conversation) {
        removed_email = null;
        removed_conversation = false;

        Conversation? conversation = email_id_map.get(id);
        // This can happen when the conversation monitor only goes back a few
        // emails, but something old gets removed.  It's especially likely when
        // changing search terms in the search folder.
        if (conversation == null)
            return null;

        Geary.Email? email = conversation.get_email_by_id(id);
        switch (conversation.get_folder_count(id)) {
        case 0:
            error("Unable to locate email %s in conversation %s",
                  id.to_string(), conversation.to_string());

        case 1:
            removed_email = email;
            remove_email_from_conversation(conversation, email);
            break;

        default:
            conversation.remove_path(id, source_path);
            break;
        }

        // Evaporate conversations with no more messages.
        if (conversation.get_count() == 0) {
            debug("Removing email %s evaporates conversation %s", id.to_string(), conversation.to_string());
            remove_conversation(conversation);

            removed_conversation = true;
        }

        return conversation;
    }

    /**
     * Removes a number of emails from conversations in this set.
     *
     * This method will remove and/or trim conversations as
     * needed. The collection `emails_ids` contains the identifiers
     * of emails to be removed.
     *
     * The returned collections include any conversations that were
     * removed (if all of their emails were removed), and any that
     * were trimmed and the emails that were trimmed from it,
     * respectively.
     */
    public void remove_all_emails_by_identifier(FolderPath source_path,
                                                Gee.Collection<Geary.EmailIdentifier> ids,
                                                out Gee.Collection<Conversation> removed,
                                                out Gee.MultiMap<Conversation, Geary.Email> trimmed) {
        Gee.HashSet<Conversation> _removed = new Gee.HashSet<Conversation>();
        Gee.HashMultiMap<Conversation, Geary.Email> _trimmed
            = new Gee.HashMultiMap<Conversation, Geary.Email>();

        foreach (Geary.EmailIdentifier id in ids) {
            Geary.Email email;
            bool removed_conversation;
            Conversation? conversation = remove_email_by_identifier(
                source_path, id, out email, out removed_conversation
            );

            if (conversation == null)
                continue;

            if (removed_conversation) {
                if (_trimmed.contains(conversation))
                    _trimmed.remove_all(conversation);
                _removed.add(conversation);
            } else if (!conversation.contains_email_by_id(id)) {
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
    public async Gee.Collection<Conversation> check_conversations_in_folder_async(
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
    
    public async void remove_emails_and_check_in_folder_async(FolderPath source_path,
                                                              Gee.Collection<Geary.EmailIdentifier> ids,
                                                              Account account,
                                                              FolderPath required_folder_path,
                                                              out Gee.Collection<Conversation> removed,
                                                              out Gee.MultiMap<Conversation, Geary.Email> trimmed,
                                                              Cancellable? cancellable) {
        Gee.Collection<Conversation> initial_removed =
            new Gee.HashSet<Conversation>();
        Gee.MultiMap<Conversation, Geary.Email> initial_trimmed =
            new Gee.HashMultiMap<Conversation, Geary.Email>();

        foreach (Geary.EmailIdentifier id in ids) {
            Geary.Email email;
            bool removed_conversation;
            Conversation? conversation = remove_email_by_identifier(
                source_path, id, out email, out removed_conversation);

            if (conversation == null)
                continue;

            if (removed_conversation) {
                if (initial_trimmed.contains(conversation))
                    initial_trimmed.remove_all(conversation);
                initial_removed.add(conversation);
            } else {
                initial_trimmed.set(conversation, email);
            }
        }

        Gee.Collection<Conversation> evaporated = yield check_conversations_in_folder_async(
            initial_trimmed.get_keys(), account, required_folder_path, cancellable);

        Gee.HashSet<Conversation> _removed = new Gee.HashSet<Conversation>();
        _removed.add_all(initial_removed);
        _removed.add_all(evaporated);

        Gee.HashMultiMap<Conversation, Geary.Email> _trimmed =
            new Gee.HashMultiMap<Conversation, Geary.Email>();

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
