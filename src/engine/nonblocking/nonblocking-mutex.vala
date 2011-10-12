/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.NonblockingMutex {
    public const int INVALID_TOKEN = -1;
    
    private NonblockingSpinlock spinlock = new NonblockingSpinlock();
    private bool locked = false;
    private int next_token = INVALID_TOKEN + 1;
    private int locked_token = INVALID_TOKEN;
    
    public NonblockingMutex() {
    }
    
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
    
    public void release(ref int token) throws Error {
        if (token != locked_token || token == INVALID_TOKEN)
            throw new IOError.INVALID_ARGUMENT("Token %d is not the lock token", token);
        
        locked = false;
        token = INVALID_TOKEN;
        locked_token = INVALID_TOKEN;
        
        spinlock.notify();
    }
}

