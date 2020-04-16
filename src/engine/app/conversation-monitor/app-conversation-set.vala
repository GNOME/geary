/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Creates and maintains set of conversations by adding and removing email.
 */
private class Geary.App.ConversationSet : BaseObject, Logging.Source {


    /** The base folder for this set of conversations. */
    public Folder base_folder { get; private set; }

    /** Determines the number of conversations in the set. */
    public int size { get { return _conversations.size; } }

    /** Determines the set contains no conversations.  */
    public bool is_empty { get { return _conversations.is_empty; } }

    /** Returns a read-only view of conversations in the set.  */
    public Gee.Set<Conversation> read_only_view {
        owned get { return _conversations.read_only_view; }
    }

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return ConversationMonitor.LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent {
        get { return this.base_folder; }
    }


    private Gee.Set<Conversation> _conversations = new Gee.HashSet<Conversation>();

    // Maps email ids to conversations.
    private Gee.HashMap<Geary.EmailIdentifier, Conversation> email_id_map
        = new Gee.HashMap<Geary.EmailIdentifier, Conversation>();

    // Contains the full set of Message IDs theoretically in each conversation,
    // as determined by the ancestors of all messages in the conversation.
    private Gee.HashMap<Geary.RFC822.MessageID, Conversation> logical_message_id_map
        = new Gee.HashMap<Geary.RFC822.MessageID, Conversation>();


    /**
     * Constructs a new conversation set.
     *
     * The `base_folder` argument is the base folder for the
     * conversation monitor that owns this set.
     */
    public ConversationSet(Folder base_folder) {
        this.base_folder = base_folder;
    }

    public int get_email_count() {
        return email_id_map.size;
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

    /**
     * Adds a collection of emails to conversations in this set.
     *
     * This method will create and/or merge conversations as
     * needed. The collection `emails` contains the messages to be
     * added, and for each email in the collection, there should be an
     * entry in `id_to_paths` that indicates the folders each message
     * is known to belong to.
     *
     * The three collections returned include any conversation that
     * were created, any that had email appended to them (and the
     * messages that were appended), and any that were removed due to
     * being merged into another.
     */
    public void add_all_emails(Gee.Collection<Email> emails,
                               Gee.MultiMap<EmailIdentifier, FolderPath> id_to_paths,
                               out Gee.Collection<Conversation> added,
                               out Gee.MultiMap<Conversation, Email> appended,
                               out Gee.Collection<Conversation> removed_due_to_merge) {
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
                Conversation dest = merge_conversations(
                    associated, moved_email
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
            }

            Conversation? conversation = null;
            bool added_conversation = false;
            Gee.Collection<Geary.FolderPath>? known_paths = id_to_paths.get(email.id);
            if (known_paths != null) {
                // Don't add an email with no known paths - it may
                // have been removed after being listed for adding.
                conversation = add_email(
                    email, known_paths, out added_conversation
                );
            }

            if (conversation != null) {
                if (added_conversation) {
                    _added.add(conversation);
                } else {
                    if (!_added.contains(conversation))
                        _appended.set(conversation, email);
                }
            }
        }

        added = _added;
        appended = _appended;
        removed_due_to_merge = _removed_due_to_merge;
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
                                                Gee.Collection<EmailIdentifier> ids,
                                                Gee.Collection<Conversation> removed,
                                                Gee.MultiMap<Conversation,Email> trimmed) {
        Gee.Set<Conversation> remaining = new Gee.HashSet<Conversation>();

        foreach (Geary.EmailIdentifier id in ids) {
            Conversation? conversation = email_id_map.get(id);
            // The conversation could be null if the conversation
            // monitor only goes back a few emails, but something old
            // gets removed.  It's especially likely when changing
            // search terms in the search folder.
            if (conversation != null) {
                // Conditionally remove email from its conversation
                Geary.Email? email = conversation.get_email_by_id(id);
                if (email != null) {
                    switch (conversation.get_folder_count(id)) {
                    case 0:
                        warning("Email %s conversation %s not in any folders",
                                id.to_string(), conversation.to_string());
                        break;

                    case 1:
                        remove_email_from_conversation(conversation, email);
                        trimmed.set(conversation, email);
                        break;

                    default:
                        conversation.remove_path(id, source_path);
                        break;
                    }
                }

                if (conversation.get_count() == 0) {
                    debug(
                        "Conversation %s evaporated: No messages remains",
                        conversation.to_string()
                    );
                    removed.add(conversation);
                    remaining.remove(conversation);
                    trimmed.remove_all(conversation);
                    remove_conversation(conversation);
                } else {
                    remaining.add(conversation);
                }
            }
        }

        if (source_path.equal_to(this.base_folder.path)) {
            // Now that all email have been processed, check reach
            // remaining conversation to ensure it has at least one
            // email in the base folder. It might not if remaining
            // email in the conversation also exists in another
            // folder, and so is especially likely for servers that
            // have an All Email folder, since email will likely be in
            // two different folders.
            foreach (Conversation conversation in remaining) {
                if (conversation.get_count_in_folder(source_path) == 0) {
                    debug(
                        "Conversation %s dropped: No messages in base folder remain",
                        conversation.to_string()
                    );
                    removed.add(conversation);
                    trimmed.remove_all(conversation);
                    remove_conversation(conversation);
                }
            }
        }
    }

    /**
     * Removes a conversation from the set.
     */
    public void remove_conversation(Conversation conversation) {
        Gee.Collection<Email> conversation_emails = conversation.get_emails(
            Conversation.Ordering.NONE,     // ordering
            Conversation.Location.ANYWHERE, // location
            null,                           // blacklist
            false                           // filter deleted (false, so we remove emails that are flagged for deletion too)
        );

        foreach (Geary.Email conversation_email in conversation_emails)
            remove_email_from_conversation(conversation, conversation_email);

        if (!_conversations.remove(conversation))
            error("Conversation %s already removed from set", conversation.to_string());
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return new Logging.State(this, "size=%d", this.size);
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
            conversation = Collection.first(associated);
            if (conversation == null) {
                // Not in or related to any existing conversations, so
                // create one
                conversation = new Conversation(this.base_folder);
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

    // This method will remove the destination (merged) Conversation from the List and return it
    // as the result, along with a Collection of email that must be merged into it
    private Conversation merge_conversations(Gee.Set<Conversation> conversations,
                                             Gee.Set<Email> moved_email) {
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
     * Unconditionally removes an email from a conversation.
     */
    private void remove_email_from_conversation(Conversation conversation, Geary.Email email) {
        if (!this.email_id_map.unset(email.id)) {
            warning("Email %s already removed from conversation set",
                    email.id.to_string());
        }

        Gee.Set<Geary.RFC822.MessageID>? removed_message_ids = conversation.remove(email);
        debug("Removed %d messages from conversation", removed_message_ids != null ? removed_message_ids.size : 0);
        if (removed_message_ids != null) {
            foreach (Geary.RFC822.MessageID removed_message_id in removed_message_ids) {
                if (!logical_message_id_map.unset(removed_message_id)) {
                    error("Message ID %s already removed from conversation set logical map",
                        removed_message_id.to_string());
                }
            }
        }
    }

}
