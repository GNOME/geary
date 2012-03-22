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
    
    private class Node : Object, ConversationNode {
        public RFC822.MessageID? node_id { get; private set; }
        public Geary.Email? email;
        public RFC822.MessageID? parent_id { get; set; default = null; }
        public ImplConversation? conversation = null;
        
        private Gee.Set<RFC822.MessageID>? children_ids = null;
        
        public Node(RFC822.MessageID? node_id, Geary.Email? email) {
            this.node_id = node_id;
            this.email = email;
        }
        
        public Node.single(Geary.Email email) {
            node_id = null;
            this.email = email;
        }
        
        public void add_child(RFC822.MessageID child_id) {
            if (children_ids == null) {
                children_ids = new Gee.HashSet<RFC822.MessageID>(Geary.Hashable.hash_func,
                    Geary.Equalable.equal_func);
            }
            
            children_ids.add(child_id);
        }
        
        public Gee.Set<RFC822.MessageID>? get_children() {
            return (children_ids != null) ? children_ids.read_only_view : null;
        }
        
        public Geary.Email? get_email() {
            return email;
        }
        
        public Geary.Conversation get_conversation() {
            // this method should only be called when the Conversation has been set on the Node
            assert(conversation != null);
            
            return conversation;
        }
    }
    
    private class ImplConversation : Conversation {
        public weak Geary.Conversations? owner;
        public RFC822.MessageID? origin;
        public Node? single_node;
        
        private Gee.HashSet<ConversationNode>? orphans = null;
        
        public ImplConversation(Geary.Conversations owner, ConversationNode origin_node) {
            this.owner = owner;
            
            // Rather than keep a reference to the origin node (creating a cross-reference from it
            // to the conversation), keep only the Message-ID, unless it's a SingleConversationNode,
            // which can't be addressed by a Message-ID (it has none)
            origin = ((Node) origin_node).node_id;
            if (origin == null)
                single_node = (Node) origin_node;
        }
        
        // Cannot be used for Conversations with single nodes
        public void set_origin(ConversationNode new_origin_node) {
            assert(single_node == null);
            
            origin = ((Node) new_origin_node).node_id;
            assert(origin != null);
        }
        
        public override Geary.ConversationNode? get_origin() {
            if (owner == null)
                return null;
            
            if (origin == null) {
                assert(single_node != null);
                
                return single_node;
            }
            
            Node? node = owner.get_node(origin);
            if (node == null)
                return null;
            
            // Since the ImplConversation holds the Message-ID of the origin, this should always
            // be true.  Other accessors return null instead because it's possible the caller is
            // passing in ConversationNodes for another Conversation, and would rather warn than
            // assert on that case.
            if (node.conversation != this) {
                debug("Origin of conversation is not queried conversation: (%s vs. %s)",
                    node.conversation.origin.to_string(), this.origin.to_string());
                
                assert(node.conversation == this);
            }
            
            return node;
        }
        
        public override Geary.ConversationNode? get_in_reply_to(Geary.ConversationNode cnode) {
            if (owner == null)
                return null;
            
            Node? node = cnode as Node;
            if (node == null)
                return null;
            
            if (node.conversation != this) {
                warning("Conversation node %s not in conversation", node.node_id.to_string());
                
                return null;
            }
            
            if (node.parent_id == null)
                return null;
            
            Node? parent = owner.get_node(node.parent_id);
            assert(parent != null);
            
            if (parent.conversation != this) {
                warning("Parent of conversation node %s not in conversation", node.node_id.to_string());
                
                return null;
            }
            
            return parent;
        }
        
        public override Gee.Collection<Geary.ConversationNode>? get_replies(
            Geary.ConversationNode cnode) {
            Node? node = cnode as Node;
            if (node == null)
                return null;
            
            if (node.conversation != this) {
                warning("Conversation node %s not in conversation", node.node_id.to_string());
                
                return null;
            }
            
            if (owner == null)
                return null;
            
            Gee.Set<RFC822.MessageID>? children_ids = node.get_children();
            if (children_ids == null || children_ids.size == 0)
                return null;
            
            Gee.Set<Geary.ConversationNode> child_nodes = new Gee.HashSet<Geary.ConversationNode>();
            foreach (RFC822.MessageID child_id in children_ids) {
                Node? child_node = owner.get_node(child_id);
                assert(child_node != null);
                
                // assert on this because the sub-nodes are maintained by the current node
                assert(child_node.conversation == this);
                
                child_nodes.add(child_node);
            }
            
            return child_nodes;
        }
        
        public void add_orphans(Gee.Collection<ConversationNode> add) {
            if (orphans == null)
                orphans = new Gee.HashSet<Node>();
            
            orphans.add_all(add);
        }
        
        public override Gee.Collection<Geary.ConversationNode>? get_orphans() {
            return orphans;
        }
    }
    
    public Geary.Folder folder { get; private set; }
    
    private Geary.Email.Field required_fields;
    private Gee.Map<Geary.RFC822.MessageID, Node> id_map = new Gee.HashMap<Geary.RFC822.MessageID,
        Node>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    private Gee.Map<Geary.EmailIdentifier, Node> geary_id_map = new Gee.HashMap<
        Geary.EmailIdentifier, Node>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    private Gee.Set<ImplConversation> conversations = new Gee.HashSet<ImplConversation>();
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
     * only a single "scan-completed" is fired to indiciate multiple loads have finished.
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
     * "conversations-removed" is fired when all the usable email in a Conversation has been removed.
     * Although the Conversation structure remains intact, there's no usable Email objects in any
     * ConversationNode.  Conversations will then remove the Conversation object.
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
     * "updated-placeholders" is fired when a ConversationNode in a Conversation was earlier
     * detected (i.e. referenced by another Email) but the actual Email was not available.  This
     * signal indicates the Email was discovered (either by loading additional messages or from
     * monitoring) and is now available.
     */
    public virtual signal void updated_placeholders(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
    }
    
    public Conversations(Geary.Folder folder, Geary.Email.Field required_fields) {
        this.folder = folder;
        this.required_fields = required_fields | REQUIRED_FIELDS;
    }
    
    ~Conversations() {
        if (monitor_new) {
            folder.messages_appended.disconnect(on_folder_messages_appended);
            folder.message_removed.disconnect(on_folder_message_removed);
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
    
    protected virtual void notify_updated_placeholders(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        updated_placeholders(conversation, email);
    }
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.read_only_view;
    }
    
    public Geary.Conversation? get_conversation_for_email(Geary.EmailIdentifier email_id) {
        Node? node = geary_id_map.get(email_id);
        
        return (node != null) ? node.conversation : null;
    }
    
    public bool monitor_new_messages(Cancellable? cancellable = null) {
        if (monitor_new)
            return false;
        
        monitor_new = true;
        cancellable_monitor = cancellable;
        folder.messages_appended.connect(on_folder_messages_appended);
        folder.message_removed.connect(on_folder_message_removed);
        
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
        // take each email and toss it into the node pool (also adding its ancestors along the way)
        // and track what signalable events need to be reported: new Conversations, Emails updating
        // placeholders, and Conversation objects having a new Email added to them
        Gee.HashSet<Conversation> new_conversations = new Gee.HashSet<Conversation>();
        Gee.MultiMap<Conversation, Geary.Email> appended_conversations = new Gee.HashMultiMap<
            Conversation, Geary.Email>();
        Gee.MultiMap<Conversation, Geary.Email> updated_placeholders = new Gee.HashMultiMap<
            Conversation, Geary.Email>();
        foreach (Geary.Email email in emails) {
            // Right now, all threading is done with Message-IDs (no parsing of subject lines, etc.)
            // If a message doesn't have a Message-ID, it's treated as its own conversation that
            // cannot be referenced through the node pool (but is available through the
            // conversations list)
            if (email.message_id == null) {
                debug("Email %s: No Message-ID", email.to_string());
                
                Node singleton = new Node.single(email);
                ImplConversation conversation = new ImplConversation(this, singleton);
                singleton.conversation = conversation;
                
                bool added = new_conversations.add(conversation);
                assert(added);
                
                new_email_for_node(singleton);
                
                continue;
            }
            
            // this email is authoritative ... although it might be an old node that's now being
            // filled in with a retrieved email, any other fields that may already be filled in will
            // be replaced by this node
            
            // see if a Node already exists for this email (it's possible that earlier processed
            // emails refer to this one)
            Node? node = get_node(email.message_id);
            if (node != null) {
                // even with duplicates, this new email is considered authoritative
                // (Note that if the node's conversation is null then it's been added this loop,
                // in which case it's not an updated placeholder but part of a new conversation)
                node.email = email;
                new_email_for_node(node);
                
                if (node.conversation != null)
                    updated_placeholders.set(node.conversation, email);
            } else {
                node = add_node(new Node(email.message_id, email));
            }
            
            // build lineage of this email
            Gee.ArrayList<RFC822.MessageID> ancestors = new Gee.ArrayList<RFC822.MessageID>();
            
            // References list the email trail back to its source
            if (email.references != null && email.references.list != null)
                ancestors.add_all(email.references.list);
            
            // RFC822 requires the In-Reply-To Message-ID be prepended to the References list, but
            // this ensures that's the case
            if (email.in_reply_to != null) {
                if (ancestors.size == 0 || !ancestors.last().equals(email.in_reply_to))
                   ancestors.add(email.in_reply_to);
            }
            
            // track whether this email has been reported as appended to a conversation, as the
            // MultiMap will add as many of the same value as you throw at it
            ImplConversation? found_conversation = node.conversation;
            
            // Watch for loops
            Gee.HashSet<RFC822.MessageID> seen = new Gee.HashSet<RFC822.MessageID>(Hashable.hash_func,
                Equalable.equal_func);
            seen.add(node.node_id);
            
            // Walk ancestor IDs, creating nodes if necessary and chaining them together
            // NOTE: References are stored from earliest to latest, but we're walking the opposite
            // direction
            Node current_node = node;
            Node? ancestor_node = null;
            Gee.HashSet<ConversationNode> orphans = new Gee.HashSet<ConversationNode>();
            for (int ctr = ancestors.size - 1; ctr >= 0; ctr--) {
                RFC822.MessageID ancestor_id = ancestors[ctr];
                
                if (seen.contains(ancestor_id)) {
                    message("Loop detected in conversation: %s seen twice", ancestor_id.to_string());
                    
                    continue;
                }
                
                seen.add(ancestor_id);
                
                // create if necessary
                ancestor_node = get_node(ancestor_id);
                if (ancestor_node == null)
                    ancestor_node = add_node(new Node(ancestor_id, null));
                
                // if prior node was orphaned, then all its ancestors are orphaned as well; if any
                // ancestors are already part of a conversation, leave them be
                if (orphans.size > 0) {
                    if (current_node.conversation == null)
                        orphans.add(current_node);
                    
                    current_node = ancestor_node;
                    
                    continue;
                }
                
                // if current_node is in a conversation and its parent_id is null, that means
                // it's the origin of a conversation, in which case making it a child of ancestor
                // is potentially creating a loop
                bool is_origin = (current_node.conversation != null && current_node.parent_id == null);
                
                // This watches for emails with contradictory References paths and new loops;
                // essentially, first email encountered wins when assigning parentage
                if (!is_origin && (current_node.parent_id == null || current_node.parent_id.equals(ancestor_id))) {
                    current_node.parent_id = ancestor_id;
                    ancestor_node.add_child(current_node.node_id);
                    
                    // See if chaining up uncovers an existing conversation
                    if (found_conversation == null)
                        found_conversation = ancestor_node.conversation;
                } else if (!is_origin) {
                    message("Email %s parent already assigned to %s, %s is orphaned in conversation",
                        current_node.node_id.to_string(), current_node.parent_id.to_string(),
                        ancestor_id.to_string());
                    orphans.add(ancestor_node);
                } else {
                    message("Email %s already origin of conversation, %s is now origin",
                        current_node.node_id.to_string(), ancestor_id.to_string());
                    
                    current_node.conversation.set_origin(ancestor_node);
                    current_node.parent_id = ancestor_id;
                    ancestor_node.conversation = current_node.conversation;
                    ancestor_node.add_child(current_node.node_id);
                }
                
                // move up the chain
                current_node = ancestor_node;
            }
            
            // if found a conversation, mark all in chain as part of that conversation and note
            // that this email was appended to the conversation, otherwise create a new one and
            // note that as well
            if (found_conversation != null) {
                appended_conversations.set(found_conversation, email);
            } else {
                found_conversation = new ImplConversation(this, current_node);
                bool added = new_conversations.add(found_conversation);
                assert(added);
            }
            
            assign_conversation(current_node, found_conversation);
            
            // assign orphans and clear set
            if (orphans.size > 0) {
                foreach (ConversationNode orphan in orphans)
                    ((Node) orphan).conversation = found_conversation;
                
                found_conversation.add_orphans(orphans);
                
                orphans.clear();
            }
        }
        
        // Go through all the emails and verify they've all been marked as part of a conversation
        // TODO: Make this optional at compile time (essentially a giant and expensive assertion)
        foreach (Geary.Email email in emails) {
            if (email.message_id == null)
                continue;
            
            Node? node = get_node(email.message_id);
            assert(node != null);
            assert(node.conversation != null);
        }
        
        // Save and signal the new conversations
        if (new_conversations.size > 0) {
            conversations.add_all(new_conversations);
            notify_conversations_added(new_conversations);
        }
        
        // fire signals for other changes
        foreach (Conversation conversation in appended_conversations.get_all_keys())
            notify_conversation_appended(conversation, appended_conversations.get(conversation));
        
        foreach (Conversation conversation in updated_placeholders.get_all_keys())
            notify_updated_placeholders(conversation, updated_placeholders.get(conversation));
    }
    
    private Node add_node(Node node) {
        assert(node.node_id != null);
        
        // add to id_map (all Nodes are referenceable by their Message-ID)
        if (id_map.has_key(node.node_id)) {
            debug("WARNING: Replacing node in conversation model with new node of same Message-ID %s",
                node.node_id.to_string());
        }
        
        id_map.set(node.node_id, node);
        
        new_email_for_node(node);
        
        return node;
    }
    
    private void new_email_for_node(Node node) {
        Geary.Email? email = node.get_email();
        if (email == null)
            return;
        
        // Possible this method will be called multiple times when processing mail (just a fact of
        // life), so be sure before issuing warning
        Node? replacement = geary_id_map.get(email.id);
        if (replacement != null && replacement != node) {
            debug("WARNING: Replacing node in conversation model with new node of same EmailIdentifier %s",
                email.id.to_string());
        }
        
        geary_id_map.set(email.id, node);
    }
    
    private void remove_email(Geary.EmailIdentifier removed_id) {
        // Remove EmailIdentifier from map
        Node node;
        if (!geary_id_map.unset(removed_id, out node)) {
            debug("Removed email %s not found on conversations model", removed_id.to_string());
            
            return;
        }
        
        // Drop email from the Node and signal it's been trimmed from the conversation
        Geary.Email? email = node.email;
        node.email = null;
        
        Conversation conversation = node.get_conversation();
        
        if (email != null)
            notify_conversation_trimmed(conversation, email);
        
        if (conversation.get_usable_count() == 0) {
            // prune all Nodes in the conversation tree
            if (conversation.get_origin() != null)
                prune_nodes((Node) conversation.get_origin());
            
            // prune all orphan Nodes
            Gee.Collection<ConversationNode>? orphans = conversation.get_orphans();
            if (orphans != null) {
                foreach (ConversationNode orphan in orphans)
                    prune_nodes((Node) orphan);
            }
            
            // remove the Conversation from the master list
            bool removed = conversations.remove((ImplConversation) conversation);
            assert(removed);
            
            // done
            notify_conversation_removed(conversation);
        }
    }
    
    private void prune_nodes(Node node) {
        Gee.Set<RFC822.MessageID>? children = node.get_children();
        if (children != null) {
            foreach (RFC822.MessageID child in children) {
                Node? child_node = id_map.get(child);
                if (child_node != null)
                    prune_nodes(child_node);
            }
        }
        
        bool removed = id_map.unset(node.node_id);
        assert(removed);
    }
    
    private inline Node? get_node(RFC822.MessageID node_id) {
        return id_map.get(node_id);
    }
    
    private void assign_conversation(Node node, ImplConversation conversation) {
        if (node.conversation != null && node.conversation != conversation)
            warning("Reassigning node %s to another conversation", node.node_id.to_string());
        
        node.conversation = conversation;
        
        Gee.Collection<RFC822.MessageID>? children = node.get_children();
        if (children != null) {
            foreach (RFC822.MessageID child_id in children) {
                Node? child = get_node(child_id);
                assert(child != null);
                
                assign_conversation(child, conversation);
            }
        }
    }
    
    private void on_folder_messages_appended() {
        // Find highest identifier by ordering
        // TODO: optimize.
        Geary.EmailIdentifier? highest = null;
        foreach (Conversation c in conversations) {
            foreach (Email e in c.get_pool()) {
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
    
    private void on_folder_message_removed(Geary.EmailIdentifier removed_id) {
        remove_email(removed_id);
    }
}

