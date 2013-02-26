/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.NonblockingMailbox<G> : Object {
    public int size { get { return queue.size; } }
    public bool allow_duplicates { get; set; default = true; }
    public bool requeue_duplicate { get; set; default = false; }
    
    private Gee.Queue<G> queue;
    private NonblockingSpinlock spinlock = new NonblockingSpinlock();
    
    public NonblockingMailbox(CompareFunc<G>? comparator = null) {
        // can't use ternary here, Vala bug
        if (comparator == null)
            queue = new Gee.LinkedList<G>();
        else
            queue = new Gee.PriorityQueue<G>(comparator);
    }
    
    public bool send(G msg) {
        if (!allow_duplicates && queue.contains(msg)) {
            if (requeue_duplicate)
                queue.remove(msg);
            else
                return false;
        }
        
        if (!queue.offer(msg))
            return false;
        
        spinlock.blind_notify();
        
        return true;
    }
    
    /**
     * Returns true if the message was revoked.
     */
    public bool revoke(G msg) {
        return queue.remove(msg);
    }
    
    /**
     * Returns number of removed items.
     */
    public int clear() {
        int count = queue.size;
        if (count != 0)
            queue.clear();
        
        return count;
    }
    
    public async G recv_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0)
                return queue.poll();
            
            yield spinlock.wait_async(cancellable);
        }
    }
    
    /**
     * Since the queue could potentially alter when the main loop runs, it's important to only
     * examine the queue when not allowing other operations to process.
     *
     * This returns a read-only list in queue-order.  Altering will not affect the queue.  Use
     * revoke() to remove enqueued operations.
     */
    public Gee.Collection<G> get_all() {
        return queue.read_only_view;
    }
}

