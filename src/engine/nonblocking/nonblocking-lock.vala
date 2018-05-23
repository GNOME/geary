/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic asynchronous lock data type.
 *
 * This class provides an asynchronous, queue-based lock
 * implementation to allow implementing safe access to resources that
 * are shared by asynchronous tasks. An asynchronous task may call
 * {@link wait_async} to wait for the lock to be marked as safe to
 * pass. Another asynchronous task may call {@link notify} to mark the
 * lock as being safe, notifying waiting tasks. Once marked as being
 * safe to pass, a lock may be reset to being unsafe by calling {@link
 * reset}. The lock cannot be passed initially, if this is desired
 * call notify after constructing it.
 *
 * See the specialised sub-classes for concrete implementations,
 * which vary based on two features:
 *
 * //Broadcasting//: Whether all waiting tasks are notified when the
 * lock may be passed, or just the next earliest waiting task.
 *
 * //Autoreset//: Whether the lock is automatically reset after
 * notifying all waiting tasks, or if it must be manually reset by
 * calling {@link reset}.
 *
 * This class is ''not'' thread safe and should only be used by
 * asynchronous tasks.
 */
public abstract class Geary.Nonblocking.Lock : BaseObject {

    private class Pending : BaseObject {
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

    /** Determines if this lock is marked as safe to pass. */
    public bool can_pass { get { return this.passed; } }

    /** Determines if this lock has been cancelled. */
    public bool is_cancelled {
        get {
            return this.cancellable != null && this.cancellable.is_cancelled();
        }
    }

    private bool broadcast;
    private bool autoreset;
    private Cancellable? cancellable;
    private bool passed = false;
    private Gee.List<Pending> pending_queue = new Gee.LinkedList<Pending>();

    /**
     * Constructs a new lock that is initially not able to be passed.
     */
    protected Lock(bool broadcast, bool autoreset, Cancellable? cancellable = null) {
        this.broadcast = broadcast;
        this.autoreset = autoreset;
        this.cancellable = cancellable;

        if (cancellable != null)
            cancellable.cancelled.connect(on_cancelled);
    }

    ~Lock() {
        if (pending_queue.size > 0) {
            warning("Nonblocking lock destroyed with %d pending callers", pending_queue.size);

            foreach (Pending pending in pending_queue)
                pending.cancelled.disconnect(on_pending_cancelled);
        }

        if (cancellable != null)
            cancellable.cancelled.disconnect(on_cancelled);
    }

    private void trigger(bool all) {
        if (pending_queue.size == 0)
            return;

        // in both cases, mark the Pending object(s) as passed in case
        // this is an auto-reset lock
        if (all) {
            foreach (Pending pending in pending_queue)
                pending.schedule(passed);

            pending_queue.clear();
        } else {
            Pending pending = pending_queue.remove_at(0);
            pending.schedule(passed);
        }
    }

    /**
     * Marks the lock as being safe to pass.
     *
     * Asynchronous tasks waiting on this lock via a call to {@link
     * wait_async} are resumed when this method is called. If this
     * lock is broadcasting then all pending tasks are released,
     * otherwise only the first in the queue is released.
     *
     * @throws GLib.IOError.CANCELLED if either the lock is cancelled
     * or the caller's `cancellable` argument is cancelled.
     */
    public virtual new void notify() throws Error {
        check_cancelled();

        passed = true;

        trigger(broadcast);

        if (autoreset)
            reset();
    }

    /**
     * Calls {@link notify} without throwing an exception.
     *
     * If an error is thrown, it is logged but otherwise ignored.
     */
    public void blind_notify() {
        try {
            notify();
        } catch (Error err) {
            message("Error notifying lock: %s", err.message);
        }
    }

    /**
     * Waits for the lock to be marked as being safe to pass.
     *
     * If the lock is already marked as being safe to pass, then this
     * method will return immediately. If not, the call to this method
     * will yield and not resume until the lock as been marked as safe
     * by a call to {@link notify}.
     *
     * @throws GLib.IOError.CANCELLED if either the lock is cancelled or
     * the caller's `cancellable` argument is cancelled.
     */
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

    /**
     * Marks this lock as being unsafe to pass.
     */
    public virtual void reset() {
        passed = false;
    }

    private void check_cancelled() throws Error {
        if (this.is_cancelled)
            throw new IOError.CANCELLED("Lock was cancelled");
    }

    private static void check_user_cancelled(Cancellable? cancellable) throws Error {
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("User cancelled lock operation");
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
