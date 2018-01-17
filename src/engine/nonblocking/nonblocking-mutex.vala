/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A primitive for creating critical sections inside of asynchronous tasks.
 *
 * Two methods can be used for executing code protected by this
 * mutex. The easiest is to create a {@link CriticalSection} delegate
 * and pass it to {@link execute_locked}. This will manage acquiring
 * the lock as needed. The lower-level method is to call {@link
 * claim_async}, execute the critical section, then ensure {@link
 * release} is always called afterwards.
 *
 * This class is ''not'' thread safe and should only be used by
 * asynchronous tasks.
 */
public class Geary.Nonblocking.Mutex : BaseObject {

    public const int INVALID_TOKEN = -1;

    /** A delegate that can be executed by this lock. */
    public delegate void CriticalSection() throws GLib.Error;

    private Spinlock spinlock = new Spinlock();
    private bool locked = false;
    private int next_token = INVALID_TOKEN + 1;
    private int locked_token = INVALID_TOKEN;


    /**
     * Returns true if the {@link Mutex} has been claimed by a task.
     */
    public bool is_locked() {
        return locked;
    }

    /**
     * Executes a critical section while protected by this mutex.
     *
     * This high-level method takes care of claiming, executing, then
     * releasing the mutex, without requiring the caller to manage any
     * this.
     *
     * @throws GLib.IOError.CANCELLED thrown if the caller's
     * cancellable is cancelled before execution is completed
     * @throws GLib.Error if an error occurred during execution of
     * //target//.
     */
    public async void execute_locked(Mutex.CriticalSection target,
                                     Cancellable? cancellable = null)
        throws Error {
        int token = yield claim_async(cancellable);
        try {
            target();
        } finally {
            try {
                release(ref token);
            } catch (Error err) {
                debug("Mutex error releasing token: %s", err.message);
            }
        }
    }

    /**
     * Locks the mutex for execution inside a critical section.
     *
     * If already claimed, this call will block asynchronously waiting
     * for the mutex to be released.
     *
     * @return A token which must be passed to {@link release} when
     * the critical section has completed executing.
     */
    public async int claim_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (!locked) {
                locked = true;
                do {
                    locked_token = next_token++;
                } while (locked_token == INVALID_TOKEN);

                return locked_token;
            }

            yield spinlock.wait_async(cancellable);
        }
    }

    /**
     * Releases the lock at the end of executing a critical section.
     *
     * The token returned by {@link claim_async} must be supplied as a
     * parameter.  It will be modified by this call so it can't be
     * reused.
     *
     * Throws IOError.INVALID_ARGUMENT if the token was not the one
     * returned by claim_async.
     */
    public void release(ref int token) throws Error {
        if (token != locked_token || token == INVALID_TOKEN)
            throw new IOError.INVALID_ARGUMENT("Token %d is not the lock token", token);

        locked = false;
        token = INVALID_TOKEN;
        locked_token = INVALID_TOKEN;

        spinlock.notify();
    }

}
