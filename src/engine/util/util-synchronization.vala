/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Synchronization {

/**
 * A synchronization primitive that spins waiting for a completion state to be reached.
 *
 * SpinWaiter allows for the caller to specify work to be performed periodically in a callback
 * while waiting for another thread to notify completion.
 */

public class SpinWaiter : BaseObject {
    public delegate bool PollService();

    private int poll_msec;
    private PollService cb;
    private Mutex mutex = Mutex();
    private Cond cond = Cond();
    private bool notified = false;

    /**
     * Create a {@link SpinWaiter}.
     *
     * poll_msec indicates how long to delay while spinning before interrupting and allowing
     * the {@link PollService} to execute.  If poll_msec is zero or less, PollService will be
     * called constantly.
     */
    public SpinWaiter(int poll_msec, owned PollService cb) {
        this.poll_msec = poll_msec;
        this.cb = (owned) cb;
    }

    /**
     * Spins waiting for a completion state to be reached.
     *
     * There's two ways the completion state can be reached: (1) PollService returns false,
     * indicating an abort state, (2) {@link notify} is called, indicating a success state, or
     * (3) the Cancellable was cancelled, causing an IOError.CANCELLED exception to be thrown.
     *
     * {@link PollService} will be called from within the calling thread context.
     *
     * Although this is thread-safe, it's not designed to be invoked by multiple callers.  That
     * could cause the PollService callback to be called more often than specified in the
     * constructor.
     */
    public bool wait(Cancellable? cancellable = null) throws Error {
        // normalize poll_msec; negative values are zeroed
        int64 actual_poll_msec = Numeric.int64_floor(0, poll_msec);

        bool result;

        mutex.lock();

        while (!notified) {
            if (cancellable != null && cancellable.is_cancelled())
                break;

            int64 end_time = get_monotonic_time() + (actual_poll_msec * TimeSpan.MILLISECOND);
            if (!cond.wait_until(mutex, end_time)) {
                // timeout passed, allow the callback to run
                mutex.unlock();
                if (!cb()) {
                    // PollService returned false, abort
                    mutex.lock();

                    break;
                }
                mutex.lock();
            }
        }

        result = notified;

        mutex.unlock();

        if (cancellable.is_cancelled())
            throw new IOError.CANCELLED("SpinWaiter.wait cancelled");

        return result;
    }

    /**
     * Signals a completion state to a thread calling {@link wait}.
     *
     * This call is thread-safe.  However, once a {@link SpinWaiter} has been signalled to stop,
     * it cannot be restarted.
     */
    public new void notify() {
        mutex.lock();

        notified = true;
        cond.broadcast();

        mutex.unlock();
    }

    /**
     * Indicates if the {@link SpinWaiter} has been notified.
     *
     * Other completion states (PollService returning false, Cancellable being cancelled in
     * {@link wait}) are not recorded here.
     *
     * This method is thread-safe.
     *
     * @see notify
     */
    public bool is_notified() {
        bool result;

        mutex.lock();

        result = notified;

        mutex.unlock();

        return result;
    }
}

}
