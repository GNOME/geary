/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.NonblockingMailbox<G> : Object {
    public int size { get { return queue.size; } }
    
    private Gee.List<G> queue;
    private NonblockingSpinlock spinlock = new NonblockingSpinlock();
    
    public NonblockingMailbox() {
        queue = new Gee.LinkedList<G>();
    }
    
    public void send(G msg) throws Error {
        queue.add(msg);
        spinlock.notify();
    }
    
    /**
     * Returns true if the message was revoked.
     */
    public bool revoke(G msg) throws Error {
        return queue.remove(msg);
    }
    
    public async G recv_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0)
                return queue.remove_at(0);
            
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
    public Gee.List<G> get_all() {
        return queue.read_only_view;
    }
}

