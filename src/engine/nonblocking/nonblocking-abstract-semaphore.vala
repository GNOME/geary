/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.NonblockingAbstractSemaphore : BaseObject {
    private class Pending {
        public unowned SourceFunc cb;
        public Cancellable? cancellable;
        public bool passed = false;
        public bool scheduled = false;
        
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
        
        public void schedule(bool passed) {
            assert(!scheduled);
            
            this.passed = passed;
            
            Scheduler.on_idle(cb);
            scheduled = true;
        }
    }
    
    private bool broadcast;
    private bool autoreset;
    private Cancellable? cancellable;
    private bool passed = false;
    private Gee.List<Pending> pending_queue = new Gee.LinkedList<Pending>();
    
    public virtual signal void at_reset() {
    }
    
    protected NonblockingAbstractSemaphore(bool broadcast, bool autoreset, Cancellable? cancellable = null) {
        this.broadcast = broadcast;
        this.autoreset = autoreset;
        this.cancellable = cancellable;
        
        if (cancellable != null)
            cancellable.cancelled.connect(on_cancelled);
    }
    
    ~NonblockingAbstractSemaphore() {
        if (pending_queue.size > 0) {
            warning("Nonblocking semaphore destroyed with %d pending callers", pending_queue.size);
            
            foreach (Pending pending in pending_queue)
                pending.cancelled.disconnect(on_pending_cancelled);
        }
        
        if (cancellable != null)
            cancellable.cancelled.disconnect(on_cancelled);
    }
    
    protected virtual void notify_at_reset() {
        at_reset();
    }
    
    private void trigger(bool all) {
        if (pending_queue.size == 0)
            return;
        
        // in both cases, mark the Pending object(s) as passed in case this is an auto-reset
        // semaphore
        if (all) {
            foreach (Pending pending in pending_queue)
                pending.schedule(passed);
            
            pending_queue.clear();
        } else {
            Pending pending = pending_queue.remove_at(0);
            pending.schedule(passed);
        }
    }
    
    public virtual new void notify() throws Error {
        check_cancelled();
        
        passed = true;
        
        trigger(broadcast);
        
        if (autoreset)
            reset();
    }
    
    /**
     * Calls notify() without throwing an Exception, which is merely logged if encountered.
     */
    public void blind_notify() {
        try {
            notify();
        } catch (Error err) {
            message("Error notifying semaphore: %s", err.message);
        }
    }
    
    public virtual async void wait_async(Cancellable? cancellable = null) throws Error {
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
            
            if (pending.passed) {
                check_user_cancelled(cancellable);
                
                return;
            }
        }
    }
    
    public virtual void reset() {
        if (!passed)
            return;
        
        passed = false;
        
        notify_at_reset();
    }
    
    public bool is_passed() {
        return passed;
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
        // if already scheduled, the cancellation will be dealt with when they wake up
        if (pending.scheduled)
            return;
        
        bool removed = pending_queue.remove(pending);
        assert(removed);
        
        Scheduler.on_idle(pending.cb);
    }
    
    private void on_cancelled() {
        trigger(true);
    }
}

