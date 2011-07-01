/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Common.NonblockingMutex {
    private NonblockingSemaphore spinlock = new NonblockingSemaphore(false);
    private bool locked = false;
    private int next_token = 0;
    private int locked_token = -1;
    
    public NonblockingMutex() {
    }
    
    public async int claim_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (!locked) {
                locked = true;
                locked_token = next_token++;
                
                return locked_token;
            }
            
            yield spinlock.wait_async(cancellable);
        }
    }
    
    public void release(int token) throws Error {
        if (token != locked_token)
            throw new IOError.INVALID_ARGUMENT("Token %d is not the lock token", token);
        
        locked = false;
        locked_token = -1;
        
        spinlock.notify();
    }
}

