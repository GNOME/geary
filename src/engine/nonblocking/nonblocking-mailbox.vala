/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.NonblockingMailbox<G> : Object {
    public int size { get { return queue.size; } }
    
    private Gee.List<G> queue;
    private NonblockingSemaphore spinlock = new NonblockingSemaphore(false);
    
    public NonblockingMailbox() {
        queue = new Gee.LinkedList<G>();
    }
    
    public void send(G msg) throws Error {
        queue.add(msg);
        spinlock.notify();
    }
    
    public async G recv_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0)
                return queue.remove_at(0);
            
            yield spinlock.wait_async(cancellable);
        }
    }
}

