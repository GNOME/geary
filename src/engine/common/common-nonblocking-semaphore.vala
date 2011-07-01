/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Common.NonblockingSemaphore {
    private class Pending {
        public SourceFunc cb;
        public Cancellable? cancellable;
        
        public signal void cancelled();
        
        public Pending(SourceFunc cb, Cancellable? cancellable) {
            this.cb = cb;
            this.cancellable = cancellable;
            
            if (cancellable != null)
                cancellable.cancelled.connect(on_cancelled);
        }
        
        ~Pending() {
            if (cancellable != null)
                cancellable.cancelled.disconnect(on_cancelled);
        }
        
        private void on_cancelled() {
            cancelled();
        }
    }
    
    private bool broadcast;
    private Cancellable? cancellable;
    private bool passed = false;
    private Gee.List<Pending> pending_queue = new Gee.LinkedList<Pending>();
    
    public NonblockingSemaphore(bool broadcast, Cancellable? cancellable = null) {
        this.broadcast = broadcast;
        this.cancellable = cancellable;
        
        if (cancellable != null)
            cancellable.cancelled.connect(on_cancelled);
    }
    
    ~NonblockingSemaphore() {
        if (pending_queue.size > 0)
            warning("Nonblocking semaphore destroyed with %d pending callers", pending_queue.size);
    }
    
    private void trigger(bool all) {
        if (pending_queue.size == 0)
            return;
        
        if (all) {
            foreach (Pending pending in pending_queue)
                Idle.add(pending.cb);
            
            pending_queue.clear();
        } else {
            Pending pending = pending_queue.remove_at(0);
            Idle.add(pending.cb);
        }
    }
    
    public void notify() throws Error {
        check_cancelled();
        
        passed = true;
        
        trigger(broadcast);
    }
    
    // TODO: Allow the caller to pass their own cancellable in if they want to be able to cancel
    // this particular wait (and not all waiting threads of execution)
    public async void wait_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            check_user_cancelled(cancellable);
            check_cancelled();
            
            if (passed)
                return;
            
            Pending pending = new Pending(wait_async.callback, cancellable);
            pending.cancelled.connect(on_pending_cancelled);
            
            pending_queue.add(pending);
            yield;
            
            pending.cancelled.disconnect(on_pending_cancelled);
        }
    }
    
    public void reset() {
        passed = false;
    }
    
    public bool is_cancelled() {
        return (cancellable != null) ? cancellable.is_cancelled() : false;
    }
    
    private void check_cancelled() throws Error {
        if (is_cancelled())
            throw new IOError.CANCELLED("Semaphore cancelled");
    }
    
    private static void check_user_cancelled(Cancellable? cancellable) throws Error {
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("User cancelled operation");
    }
    
    private void on_pending_cancelled(Pending pending) {
        bool removed = pending_queue.remove(pending);
        assert(removed);
        
        Idle.add(pending.cb);
    }
    
    private void on_cancelled() {
        trigger(true);
    }
}

