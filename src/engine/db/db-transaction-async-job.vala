/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.Db.TransactionAsyncJob : BaseObject {
    private TransactionType type;
    private unowned TransactionMethod cb;
    private Cancellable cancellable;
    private NonblockingEvent completed;
    private TransactionOutcome outcome = TransactionOutcome.ROLLBACK;
    private Error? caught_err = null;
    
    protected TransactionAsyncJob(TransactionType type, TransactionMethod cb, Cancellable? cancellable) {
        this.type = type;
        this.cb = cb;
        this.cancellable = cancellable ?? new Cancellable();
        
        completed = new NonblockingEvent();
    }
    
    public void cancel() {
        cancellable.cancel();
    }
    
    public bool is_cancelled() {
        return cancellable.is_cancelled();
    }
    
    // Called in background thread context
    internal void execute(Connection cx) {
        // execute transaction
        try {
            // possible was cancelled during interim of scheduling and execution
            if (is_cancelled())
                throw new IOError.CANCELLED("Async transaction cancelled");
            
            outcome = cx.exec_transaction(type, cb, cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("AsyncJob: transaction completed with error: %s", err.message);
            
            caught_err = err;
        }
        
        schedule_completion();
    }
    
    // Called in background thread context
    internal void failed(Error err) {
        // store as a caught thread to report to original caller
        caught_err = err;
        
        schedule_completion();
    }
    
    private void schedule_completion() {
        // notify foreground thread of completion
        // because Idle doesn't hold a ref, manually keep this object alive
        ref();
        
        // NonblockingSemaphore and its brethren are not thread-safe, so need to signal notification
        // of completion in the main thread
        Idle.add(on_notify_completed);
    }
    
    private bool on_notify_completed() {
        try {
            completed.notify();
        } catch (Error err) {
            if (caught_err != null && !(caught_err is IOError.CANCELLED)) {
                debug("Unable to notify AsyncTransaction has completed w/ err %s: %s",
                    caught_err.message, err.message);
            } else {
                debug("Unable to notify AsyncTransaction has completed w/o err: %s", err.message);
            }
        }
        
        // manually unref; do NOT touch "this" once unref() returns, as this object may be freed
        unref();
        
        return false;
    }
    
    // No way to cancel this because the callback thread *must* finish before
    // we move on here.  Any I/O the thread is doing can still be cancelled
    // using our cancel() above.
    public async TransactionOutcome wait_for_completion_async()
        throws Error {
        yield completed.wait_async();
        if (caught_err != null)
            throw caught_err;
        
        return outcome;
    }
}

