/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.Db.TransactionAsyncJob : BaseObject {

    internal DatabaseConnection? default_cx { get; private set; }
    internal Cancellable cancellable { get; private set; }

    private TransactionType type;
    private unowned TransactionMethod cb;
    private Nonblocking.Event completed;
    private TransactionOutcome outcome = TransactionOutcome.ROLLBACK;
    private Error? caught_err = null;


    public TransactionAsyncJob(DatabaseConnection? default_cx,
                               TransactionType type,
                               TransactionMethod cb,
                               Cancellable? cancellable) {
        this.default_cx = default_cx;
        this.type = type;
        this.cb = cb;
        this.cancellable = cancellable ?? new Cancellable();

        this.completed = new Nonblocking.Event();
    }

    public bool is_cancelled() {
        return cancellable.is_cancelled();
    }

    // Called in background thread context
    internal void execute(DatabaseConnection cx) {
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
    // using the job's cancellable.
    public async TransactionOutcome wait_for_completion_async()
        throws Error {
        yield this.completed.wait_async();
        if (this.caught_err != null)
            throw this.caught_err;

        return this.outcome;
    }
}
