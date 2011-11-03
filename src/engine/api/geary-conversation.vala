/* Copyright 2011 Yorba Foundation
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
}

public abstract class Geary.Conversation : Object {
    protected Conversation() {
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
}

