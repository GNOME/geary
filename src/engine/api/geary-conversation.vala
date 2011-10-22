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
     * Returns all ConversationNodes in the conversation, which can then be sorted by the caller's
     * own requirements.
     *
     */
    public virtual Gee.Collection<Geary.ConversationNode>? get_pool() {
        Gee.HashSet<ConversationNode> pool = new Gee.HashSet<ConversationNode>();
        gather(pool, get_origin());
        
        return (pool.size > 0) ? pool : null;
    }
    
    private void gather(Gee.Set<ConversationNode> pool, ConversationNode? current) {
        if (current == null)
            return;
        
        pool.add(current);
        
        Gee.Collection<Geary.ConversationNode>? children = get_replies(current);
        if (children != null) {
            foreach (Geary.ConversationNode child in children)
                gather(pool, child);
        }
    }
}

