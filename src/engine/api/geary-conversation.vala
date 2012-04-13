/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.ConversationNode : Object {
    /**
     * Returns the Email represented by this ConversationNode.  If the Email is available
     * in the remote or local Folder and as loaded into the Conversations object either by a manual
     * scan or through monitoring the Folder, then that Email will be returned (with all the fields
     * specified in the Conversation's constructor available).  If, however, the Email was merely
     * referred to by another Email in the Conversation but is unavailable, then this will return
     * null (it's a placeholder).
     */
    public abstract Geary.Email? get_email();
    
    /**
     * Returns the Conversation the ConversationNode is a part of.
     */
    public abstract Geary.Conversation get_conversation();
}

public abstract class Geary.Conversation : Object {
    protected Conversation() {
    }
    
    /**
     * Returns the total number of ConversationNodes in the Conversation, both threaded and orphaned.
     */
    public virtual int get_count() {
        return count_conversation_nodes(false);
    }
    
    /**
     * Returns the total number of ConversationNodes *with email* in the Conversation, both threaded
     * and orphaned.
     */
    public virtual int get_usable_count() {
        return count_conversation_nodes(true);
    }
    
    private int count_conversation_nodes(bool usable) {
        int count = 0;
        
        // start with origin
        ConversationNode? origin = get_origin();
        if (origin != null)
            count += count_nodes(origin, usable);
        
        // add orphans
        Gee.Collection<ConversationNode>? orphans = get_orphans();
        if (orphans != null) {
            foreach (ConversationNode orphan in orphans)
                count += count_nodes(orphan, usable);
        }
        
        return count;
    }
    
    private int count_nodes(ConversationNode current, bool usable) {
        // start with current Node
        int count;
        if (usable)
            count = current.get_email() != null ? 1 : 0;
        else
            count = 1;
        
        // add to it all its children
        Gee.Collection<ConversationNode>? children = get_replies(current);
        if (children != null) {
            foreach (ConversationNode child in children)
                count += count_nodes(child, usable);
        }
        
        return count;
    }
    
    /**
     * Returns a ConversationNode that is the origin of the entire conversation.
     *
     * Returns null if the Conversation has been disconnected from the master Conversations holder
     * (probably due to it being destroyed).
     */
    public abstract Geary.ConversationNode? get_origin();
    
    /**
     * Returns the ConversationNode that the supplied node is in reply to (i.e. its parent).
     *
     * Returns null if the node has no parent (it's the origin), is not part of the conversation,
     * or the conversation has been disconnected (see get_origin()).
     */
    public abstract Geary.ConversationNode? get_in_reply_to(Geary.ConversationNode node);
    
    /**
     * Returns a Collection of ConversationNodes that replied to the supplied node (i.e. its
     * children).
     *
     * Returns null if the node has no replies, is not part of the conversation, or if the
     * conversation has been disconnected (see get_origin()).
     */
    public abstract Gee.Collection<Geary.ConversationNode>? get_replies(Geary.ConversationNode node);
    
    /**
     * Returns a Collection of ConversationNodes that are associated with the Conversation but
     * could not be properly linked into the chain (most likely because it would cause a loop).
     *
     * Returns null if the Conversation has no orphans.
     */
    public abstract Gee.Collection<Geary.ConversationNode>? get_orphans();
    
     /**
     * Returns all emails in the conversation.
     * Only returns nodes that have an e-mail.
     */
    public virtual Gee.Set<Geary.Email>? get_pool() {
        Gee.HashSet<Email> pool = new Gee.HashSet<Email>();
        gather(pool, get_origin());
        add_orphans_to_pool(pool);
        
        return (pool.size > 0) ? pool : null;
    }
    
    /**
     * Returns all emails in the conversation, sorted by compare_func.
     * Only returns nodes that have an e-mail.
     */
    public virtual Gee.SortedSet<Geary.Email>? get_pool_sorted(CompareFunc<Geary.Email>? 
        compare_func = null) {
        Gee.TreeSet<Email> pool = new Gee.TreeSet<Email>(compare_func);
        gather(pool, get_origin());
        add_orphans_to_pool(pool);
        
        return (pool.size > 0) ? pool : null;
    }
    
    private void gather(Gee.Set<Email> pool, ConversationNode? current) {
        if (current == null)
            return;
        
        if (current.get_email() != null)
            pool.add(current.get_email());
        
        Gee.Collection<Geary.ConversationNode>? children = get_replies(current);
        if (children != null) {
            foreach (Geary.ConversationNode child in children)
                gather(pool, child);
        }
    }
    
    private void add_orphans_to_pool(Gee.Set<Email> pool) {
        Gee.Collection<ConversationNode>? orphans = get_orphans();
        if (orphans == null || orphans.size == 0)
            return;
        
        foreach (Geary.ConversationNode orphan in orphans) {
            if (orphan.get_email() != null)
                pool.add(orphan.get_email());
        }
    }
    
    /**
     * Returns true if *any* message in the conversation is unread.
     */
    public virtual bool is_unread() {
        Gee.Set<Geary.Email>? list = get_pool();
        if (list == null)
            return false;

        foreach (Geary.Email email in list) {
            if (email.is_unread().to_boolean(false))
                return true;
        }

        return false;
    }

    /**
     * Returns true if *any* message in the conversation is flagged.
     */
    public virtual bool is_flagged() {
        Gee.Set<Geary.Email>? list = get_pool();
        if (list == null)
            return false;

        foreach (Geary.Email email in list) {
            if (email.is_flagged().to_boolean(false))
                return true;
        }

        return false;
    }
}

