/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Conversations : Object {
    /**
     * These are the fields Conversations require to thread emails together.  These fields will
     * be retrieved irregardless of the Field parameter passed to the constructor.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = Geary.Email.Field.REFERENCES;
    
    private class Node : Object, ConversationNode {
        public RFC822.MessageID? node_id { get; private set; }
        public Geary.Email? email { get; set; }
        public RFC822.MessageID? parent_id { get; set; default = null; }
        public ImplConversation? conversation { get; set; default = null; }
        
        private Gee.Set<RFC822.MessageID>? children_ids = null;
        
        public Node(RFC822.MessageID? node_id, Geary.Email? email) {
            this.node_id = node_id;
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
    }
    
    private class SingleConversationNode : Object, ConversationNode {
        public Geary.Email email;
        
        public SingleConversationNode(Geary.Email email) {
            this.email = email;
        }
        
        public Geary.Email? get_email() {
            return email;
        }
    }
    
    private class ImplConversation : Conversation {
        public weak Geary.Conversations? owner;
        public RFC822.MessageID? origin;
        public SingleConversationNode? single_node;
        
        private Gee.HashSet<ConversationNode>? orphans = null;
        
        public ImplConversation(Geary.Conversations owner, ConversationNode origin_node) {
            this.owner = owner;
            
            // Rather than keep a reference to the origin node (creating a cross-reference from it
            // to the conversation), keep only the Message-ID, unless it's a SingleConversationNode,
            // which can't be addressed by a Message-ID (it has none)
            single_node = origin_node as SingleConversationNode;
            if (single_node != null) {
                origin = null;
            } else {
                origin = ((Node) origin_node).node_id;
                assert(origin != null);
            }
        }
        
        // Cannot be used for SingleConversationNodes.
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
            assert(node.conversation == this);
            
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
    private Gee.Set<ImplConversation> conversations = new Gee.HashSet<ImplConversation>();
    private bool monitor_new = false;
    private Cancellable? cancellable_monitor = null;
    
    public virtual signal void scan_started(int low, int count) {
    }
    
    public virtual signal void scan_error(Error err) {
    }
    
    public virtual signal void scan_completed() {
    }
    
    public virtual signal void conversations_added(Gee.Collection<Conversation> conversations) {
    }
    
    public virtual signal void conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
    }
    
    public virtual signal void updated_placeholders(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
    }
    
    public Conversations(Geary.Folder folder, Geary.Email.Field required_fields) {
        this.folder = folder;
        this.required_fields = required_fields | REQUIRED_FIELDS;
    }
    
    ~Conversations() {
        // Manually detach all the weak refs in the Conversation objects
        foreach (ImplConversation conversation in conversations)
            conversation.owner = null;
        
        if (monitor_new)
            folder.messages_appended.disconnect(on_folder_messages_appended);
    }
    
    protected virtual void notify_scan_started(int low, int count) {
        scan_started(low, count);
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
    
    protected virtual void notify_conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        conversation_appended(conversation, email);
    }
    
    protected virtual void notify_updated_placeholders(Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        updated_placeholders(conversation, email);
    }
    
    public Gee.Collection<Conversation> get_conversations() {
        return conversations.read_only_view;
    }
    
    public async void load_async(int low, int count, Geary.Folder.ListFlags flags,
        Cancellable? cancellable) throws Error {
        notify_scan_started(low, count);
        try {
            Gee.List<Email>? list = yield folder.list_email_async(low, count, required_fields, flags);
            on_email_listed(list, null);
            if (list != null)
                on_email_listed(null, null);
        } catch (Error err) {
            on_email_listed(null, err);
        }
    }
    
    public void lazy_load(int low, int count, Geary.Folder.ListFlags flags, Cancellable? cancellable)
        throws Error {
        notify_scan_started(low, count);
        folder.lazy_list_email(low, count, required_fields, flags, on_email_listed, cancellable);
    }
    
    public bool monitor_new_messages(Cancellable? cancellable = null) {
        if (monitor_new)
            return false;
        
        monitor_new = true;
        cancellable_monitor = cancellable;
        folder.messages_appended.connect(on_folder_messages_appended);
        return true;
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
                
                bool added = new_conversations.add(
                    new ImplConversation(this, new SingleConversationNode(email)));
                assert(added);
                
                continue;
            }
            
            // this email is authoritative ... although it might be an old node that's now being
            // filled in with a retrieved email, any other fields that may already be filled in will
            // be replaced by this node
            
            // see if a Node already exists for this email (it's possible that earlier processed
            // emails refer to this one)
            Node? node = get_node(email.message_id);
            if (node != null) {
                if (node.email != null) {
                    message("Duplicate email found while threading: %s vs. %s", node.email.to_string(),
                        email.to_string());
                }
                
                // even with duplicates, this new email is considered authoritative
                // (Note that if the node's conversation is null then it's been added this loop,
                // in which case it's not an updated placeholder but part of a new conversation)
                node.email = email;
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
        
        return node;
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
        // Find highest position.
        // TODO: optimize.
        int high = -1;
        foreach (Conversation c in conversations)
            foreach (Email e in c.get_pool())
                if (e.location.position > high)
                    high = e.location.position;
        
        if (high < 0) {
            debug("Unable to find highest message position in %s", folder.to_string());
            
            return;
        }
        
        debug("Message(s) appended to %s, fetching email at %d and above", folder.to_string(),
            high + 1);
        
        // Want to get the one *after* the highest position in the list
        try {
            lazy_load(high + 1, -1, Folder.ListFlags.NONE, cancellable_monitor);
        } catch (Error e) {
            warning("Error getting new mail: %s", e.message);
        }
    }
}

