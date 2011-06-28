/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Common.NonblockingSemaphore {
    private class Pending {
        public SourceFunc cb;
        
        public Pending(SourceFunc cb) {
            this.cb = cb;
        }
    }
    
    private Cancellable? cancellable;
    private bool passed = false;
    private Gee.List<Pending> pending_queue = new Gee.LinkedList<Pending>();
    
    public NonblockingSemaphore(Cancellable? cancellable = null) {
        this.cancellable = cancellable;
        
        if (cancellable != null)
            cancellable.cancelled.connect(on_cancelled);
    }
    
    ~NonblockingSemaphore() {
        if (pending_queue.size > 0)
            warning("Nonblocking semaphore destroyed with %d pending callers", pending_queue.size);
    }
    
    private void trigger_all() {
        foreach (Pending pending in pending_queue)
            Idle.add(pending.cb);
        
        pending_queue.clear();
    }
    
    public void notify() throws Error {
        check_cancelled();
        
        passed = true;
        trigger_all();
    }
    
    // TODO: Allow the caller to pass their own cancellable in if they want to be able to cancel
    // this particular wait (and not all waiting threads of execution)
    public async void wait_async() throws Error {
        for (;;) {
            check_cancelled();
            
            if (passed)
                return;
            
            pending_queue.add(new Pending(wait_async.callback));
            yield;
        }
    }
    
    public bool is_cancelled() {
        return (cancellable != null) ? cancellable.is_cancelled() : false;
    }
    
    private void check_cancelled() throws Error {
        if (is_cancelled())
            throw new IOError.CANCELLED("Semaphore cancelled");
    }
    
    private void on_cancelled() {
        trigger_all();
    }
}

