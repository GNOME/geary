/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A task primitive for creating critical sections inside of asynchronous code.
 *
 * Like other primitives in {@link Nonblocking}, Mutex is ''not'' designed for a threaded
 * environment.
 */

public class Geary.Nonblocking.Mutex : BaseObject {
    public const int INVALID_TOKEN = -1;
    
    private Spinlock spinlock = new Spinlock();
    private bool locked = false;
    private int next_token = INVALID_TOKEN + 1;
    private int locked_token = INVALID_TOKEN;
    
    public Mutex() {
    }
    
    /**
     * Returns true if the {@link Mutex} has been claimed by a task.
     */
    public bool is_locked() {
        return locked;
    }
    
    /**
     * Claim (i.e. lock) the {@link Mutex} and begin execution inside a critical section.
     *
     * claim_async will block asynchronously waiting for the Mutex to be released, if it's already
     * claimed.
     *
     * @return A token which must be used to {@link release} the Mutex.
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
     * Release (i.e. unlock) the {@link Mutex} and end execution inside a critical section.
     *
     * The token returned by {@link claim_async} must be supplied as a parameter.  It will be
     * modified by this call so it can't be reused.
     *
     * Throws IOError.INVALID_ARGUMENT if the token was not the one returned by claim_async.
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

