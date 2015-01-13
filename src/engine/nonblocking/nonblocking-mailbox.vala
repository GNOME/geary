/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Nonblocking.Mailbox<G> : BaseObject {
    public int size { get { return queue.size; } }
    
    public bool allow_duplicates { get; set; default = true; }
    
    public bool requeue_duplicate { get; set; default = false; }
    
    private bool _is_paused = false;
    public bool is_paused {
        get { return _is_paused; }
        
        set {
            // if no longer paused, wake up any waiting recipients
            if (_is_paused && !value)
                spinlock.blind_notify();
            
            _is_paused = value;
        }
    }
    
    private Gee.Queue<G> queue;
    private Nonblocking.Spinlock spinlock = new Nonblocking.Spinlock();
    
    public Mailbox(owned CompareDataFunc<G>? comparator = null) {
        // can't use ternary here, Vala bug
        if (comparator == null)
            queue = new Gee.LinkedList<G>();
        else
            queue = new Gee.PriorityQueue<G>((owned) comparator);
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
        
        if (!is_paused)
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
    
    /**
     * Remove messages matching the given predicate.  Return the removed messages.
     */
    public Gee.Collection<G> revoke_matching(owned Gee.Predicate<G> predicate) {
        Gee.ArrayList<G> removed = new Gee.ArrayList<G>();
        // Iterate over a copy so we can modify the original.
        foreach (G msg in queue.to_array()) {
            if (predicate(msg)) {
                queue.remove(msg);
                removed.add(msg);
            }
        }
        
        return removed;
    }
    
    public async G recv_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0 && !is_paused)
                return queue.poll();
            
            yield spinlock.wait_async(cancellable);
        }
    }
    
    /**
     * Returns a read-only version of the mailbox queue that can be iterated in queue-order.
     *
     * Since the queue could potentially alter when the main loop runs, it's important to only
     * examine the queue when not allowing other operations to process.
     *
     * Altering will not affect the actual queue.  Use {@link revoke} to remove enqueued operations.
     */
    public Gee.Collection<G> get_all() {
        return queue.read_only_view;
    }
}

