/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A broadcasting, manually-resetting asynchronous lock.
 *
 * This lock type will notify all waiting asynchronous tasks when
 * marked as being safe to pass, and requires a call to {@link
 * Lock.reset} to be marked as unsafe again.
 *
 * This class is ''not'' thread safe and should only be used by
 * asynchronous tasks.
 *
 * @see Lock
 */
public class Geary.Nonblocking.Semaphore : Geary.Nonblocking.Lock {

    /**
     * Constructs a new semaphore lock.
     *
     * The new lock is initially not able to be passed.
     */
    public Semaphore(Cancellable? cancellable = null) {
        base (true, false, cancellable);
    }

}

/**
 * A broadcasting, automatically-resetting asynchronous lock.
 *
 * This lock type will notify all waiting asynchronous tasks when
 * marked as being safe to pass, and will automatically reset as being
 * unsafe to pass after doing so.
 *
 * This class is ''not'' thread safe and should only be used by
 * asynchronous tasks.
 *
 * @see Lock
 */
public class Geary.Nonblocking.Event : Geary.Nonblocking.Lock {

    /**
     * Constructs a new event lock.
     *
     * The new lock is initially not able to be passed.
     */
    public Event(Cancellable? cancellable = null) {
        base (true, true, cancellable);
    }

}

/**
 * A single-task-notifying, automatically-resetting asynchronous lock.
 *
 * This lock type will the first asynchronous task waiting when marked
 * as being safe to pass, and will automatically reset as being unsafe
 * to pass after doing so.
 *
 * This class is ''not'' thread safe and should only be used by
 * asynchronous tasks.
 *
 * @see Lock
 */
public class Geary.Nonblocking.Spinlock : Geary.Nonblocking.Lock {

    /**
     * Constructs a new spin lock.
     *
     * The new lock is initially not able to be passed.
     */
    public Spinlock(Cancellable? cancellable = null) {
        base (false, true, cancellable);
    }

}
