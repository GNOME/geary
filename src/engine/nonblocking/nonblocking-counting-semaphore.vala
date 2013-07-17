/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A nonblocking semaphore which allows for any number of tasks to run, but only signalling
 * completion when all have finished.
 *
 * Unlike the other {@link AbstractSemaphore} variants, a task must {@link acquire} before it
 * can {@link notify}.  The number of acquired tasks is kept in the {@link count} property.
 */
public class Geary.Nonblocking.CountingSemaphore : Geary.Nonblocking.AbstractSemaphore {
    /**
     * The number of tasks which have {@link acquire} the semaphore.
     */
    public int count { get; private set; default = 0; }
    
    /**
     * Indicates that the {@link count} has changed due to either {@link acquire} or
     * {@link notify} being invoked.
     */
    public signal void count_changed(int count);
    
    public CountingSemaphore(Cancellable? cancellable) {
        base (true, true, cancellable);
    }
    
    /**
     * Called by a task to acquire (and, hence, lock) the semaphore.
     *
     * @return Number of acquired tasks, including the one that made this call.
     */
    public int acquire() {
        count++;
        
        // store on stack in case of reentrancy from signal handler; also note that Vala doesn't
        // deal well with properties, pre/post-inc, and assignment on same line
        int new_count = count;
        count_changed(new_count);
        
        return new_count;
    }
    
    /**
     * Called by a task which has previously {@link acquire}d the semaphore.
     *
     * When the number of acquired tasks reaches zero, the semaphore is unlocked and all waiting
     * tasks will resume.
     *
     * @see wait_async
     * @throws NonblockingError.INVALID if called when {@link count} is zero.
     */
    public override void notify() throws Error {
        if (count == 0)
            throw new NonblockingError.INVALID("notify() on a zeroed CountingSemaphore");
        
        count--;
        
        // store on stack in case of reentrancy from signal handler; also note that Vala doesn't
        // deal well with properties, pre/post-inc, and assignment on same line
        int new_count = count;
        count_changed(new_count);
        
        if (new_count == 0)
            base.notify();
    }
    
    /**
     * Wait for all tasks which have {@link acquire}d this semaphore to release it.
     *
     * If no tasks have acquired the semaphore, this call will complete immediately.
     */
    public async override void wait_async(Cancellable? cancellable = null) throws Error {
        if (count != 0)
            yield base.wait_async(cancellable);
    }
}

