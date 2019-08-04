/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Schedule an asynchronous operation (a {@link ConcurrentCallback} to run in a background thread.
 *
 * Useful to perform blocking I/O or CPU-bound tasks where the result must be ready before
 * other work can proceed.
 */

public class Geary.Nonblocking.Concurrent : BaseObject {
    public const int DEFAULT_MAX_THREADS = 4;

    /**
     * A callback invoked from a {@link Concurrent} background thread.
     *
     * The Cancellable passed to the callback is the same Cancellable the caller supplied to
     * {@link schedule_async}.
     *
     * Note that this callback may throw an Error.  If it does, Concurrent will throw it to the
     * foreground caller on behalf of the callback.
     */
    public delegate void ConcurrentCallback(Cancellable? cancellable) throws Error;

    private class ConcurrentOperation : BaseObject {
        private unowned ConcurrentCallback cb;
        private Cancellable? cancellable;
        private Error? caught_err = null;
        private Event event = new Event();

        public ConcurrentOperation(ConcurrentCallback cb, Cancellable? cancellable) {
            this.cb = cb;
            this.cancellable = cancellable;
        }

        // Called from the foreground thread to wait for the background to complete.
        //
        // Can't cancel here because we *must* wait for the operation to be executed by the
        // thread and complete
        public async void wait_async() throws Error {
            yield event.wait_async();

            if (caught_err != null)
                throw caught_err;

            // now deal with cancellation
            if (cancellable != null && cancellable.is_cancelled())
                throw new IOError.CANCELLED("Geary.Nonblocking.Concurrent cancelled");
        }

        // Called from a background thread
        public void execute() {
            // only execute if not already cancelled
            if (cancellable == null || !cancellable.is_cancelled()) {
                try {
                    cb(cancellable);
                } catch (Error err) {
                    caught_err = err;
                }
            }

            // can't notify event here, Nonblocking.Event is not thread safe
            //
            // artificially increment the ref count of this object, schedule a completion callback
            // on the foreground thread, and signal there
            ref();

            Idle.add(on_notify_completed);
        }

        // Called in the context of the Event loop in the foreground thread
        private bool on_notify_completed() {
            // alert waiters
            event.blind_notify();

            // unref; do not touch "self" from here on, it's possibly deallocated
            unref();

            return false;
        }
    }

    private static Concurrent? _global = null;
    /**
     * Returns the global instance of a {@link Concurrent} scheduler.
     *
     * Note that this call is ''not'' thread-safe and should only be called from the foreground
     * thread.
     */
    public static Concurrent global {
        get {
            return (_global != null) ? _global : _global = new Concurrent();
        }
    }

    private ThreadPool<ConcurrentOperation>? thread_pool = null;
    private ThreadError? init_err = null;

    /**
     * Creates a new Concurrent pool for scheduling background work.
     *
     * A caller may create their own pool, or they may use the default one available with
     * {link instance}.
     */
    public Concurrent(int max_threads = DEFAULT_MAX_THREADS) {
        try {
            thread_pool = new ThreadPool<ConcurrentOperation>.with_owned_data(on_work_ready,
                max_threads, false);
        } catch (ThreadError err) {
            init_err = err;

            warning("Unable to create Geary.Nonblocking.Concurrent: %s", err.message);
        }
    }

    /**
     * Schedule a callback to be invoked in a background thread.
     *
     * The caller should take care that the callback's state is available until
     * {@link schedule_async} completes.
     *
     * This method is thread-safe.
     */
    public async void schedule_async(ConcurrentCallback cb, Cancellable? cancellable = null)
        throws Error {
        if (init_err != null)
            throw init_err;

        // hold ConcurrentOperation ref until thread completes
        ConcurrentOperation op = new ConcurrentOperation(cb, cancellable);
        thread_pool.add(op);

        yield op.wait_async();
    }

    private void on_work_ready(owned ConcurrentOperation op) {
        op.execute();
    }
}

