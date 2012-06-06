/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * A TimerPool accepts items of type G with an associated timeout in seconds (a count of seconds
 * that, in the future, indicates a timeout).  TimerPool checks for timeouts in an Idle task that
 * fires the "timed-out" signal when a late item is detected.
 *
 * Submit items to a TimerPool with start().  If the item can be removed from the TimerPool (its
 * associated work has completed for example), remove it with cancel().  All items can be cancelled
 * with cancel_all(), which effectively clears the queue.
 *
 * It's assumed that the timeout case is not common, and so TimerPool is coded for the efficiency
 * of start() and cancel().
 *
 * While making all attempts for chronological accuracy, due to the nature of the MainLoop, there's
 * no guarantee that the signal will fire precisely the number of seconds later.
 *
 * TODO: Implementation is not the most efficient, especially if the timeout case is considered
 * rare, in which case efficiency should be the goal for start() and cancel().
 */

public class Geary.TimerPool<G> : Object {
    private unowned HashFunc? hash_func;
    private unowned EqualFunc? equal_func;
    private uint timeout_id = 0;
    private DateTime? next_timeout_check = null;
    private Gee.TreeMap<DateTime, Gee.HashSet<G>> timeouts;
    private Gee.HashMap<G, DateTime> timeout_lookup;
    
    public signal void timed_out(G item);
    
    public TimerPool(HashFunc? hash_func, EqualFunc? equal_func) {
        this.hash_func = hash_func;
        this.equal_func = equal_func;
        
        timeouts = new Gee.TreeMap<DateTime, Gee.HashSet<G>>(Comparable.date_time_compare);
        timeout_lookup = new Gee.HashMap<G, DateTime>(hash_func, equal_func, Equalable.date_time_equal);
    }
    
    ~TimerPool() {
        if (timeout_id != 0)
            Source.remove(timeout_id);
    }
    
    /**
     * Note that multiple "equal" items may be added via start().  The timeout will be replaced for
     * that item.
     *
     * If timeout_sec is zero, no timeout is schedule and start() returns false.
     */
    public bool start(G item, uint timeout_sec) {
        if (timeout_sec == 0)
            return false;
        
        DateTime now = new DateTime.now_local();
        DateTime timeout = now.add_seconds(timeout_sec);
        
        // add to cmd_timeouts sorted tree, creating new HashSet to hold all the commands for this
        // timeout if necessary
        Gee.HashSet<G>? pool = timeouts.get(timeout);
        if (pool == null) {
            pool = new Gee.HashSet<G>(hash_func, equal_func);
            timeouts.set(timeout, pool);
        }
        
        pool.add(item);
        
        // add to reverse lookup table
        timeout_lookup.set(item, timeout);
        
        // if no timeout check scheduled or the next timeout is too far in the future, (re)schedule
        if (next_timeout_check == null || timeout.compare(next_timeout_check) < 0) {
            if (timeout_id != 0)
                Source.remove(timeout_id);
            
            timeout_id = Timeout.add_seconds(timeout_sec, on_check_for_timeouts);
            next_timeout_check = timeout;
        }
        
        return true;
    }
    
    /**
     * Returns false if the item is not found.
     */
    public bool cancel(G item) {
        // lookup the timeout on this item, removing it from the lookup table in the process
        DateTime timeout;
        bool removed = timeout_lookup.unset(item, out timeout);
        if (!removed)
            return false;
        
        // fetch the pool of items for this timeout
        Gee.HashSet<G>? pool = timeouts.get(timeout);
        if (pool == null)
            return false;
        
        // remove from the pool
        removed = pool.remove(item);
        if (!removed)
            return false;
        
        // if the pool is empty, remove it from the timeout queue entirely
        if (pool.size == 0)
            timeouts.unset(timeout);
        
        // If no more timeouts, no reason to perform background checking
        if (timeouts.size == 0) {
            assert(timeout_lookup.size == 0);
            
            if (timeout_id != 0) {
                Source.remove(timeout_id);
                timeout_id = 0;
                next_timeout_check = null;
            }
        }
        
        return true;
    }
    
    /**
     * Cancels all outstanding items.
     */
    public void cancel_all() {
        timeouts.clear();
        timeout_lookup.clear();
        
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
            next_timeout_check = null;
        }
    }
    
    private bool on_check_for_timeouts() {
        DateTime now = new DateTime.now_local();
        
        // create a list of times and items that have timed out rather than signal them as they're
        // discovered... this allows for reentrancy inside a signal handlers
        Gee.HashSet<DateTime>? timed_out_times = null;
        next_timeout_check = null;
        foreach (DateTime timeout in timeouts.keys) {
            // cmd_timeouts is sorted, so stop as soon as timeout is hit that's in the future
            if (timeout.compare(now) > 0) {
                next_timeout_check = timeout;
                
                break;
            }
            
            if (timed_out_times == null) {
                timed_out_times = new Gee.HashSet<DateTime>(Hashable.date_time_hash,
                    Equalable.date_time_equal);
            }
            
            timed_out_times.add(timeout);
        }
        
        // remove everything that's timed out from the queue
        if (timed_out_times != null) {
            Gee.HashSet<G>? timed_out_items = new Gee.HashSet<G>(hash_func, equal_func);
            foreach (DateTime timeout in timed_out_times) {
                Gee.HashSet<G> pool;
                bool removed = timeouts.unset(timeout, out pool);
                assert(removed);
                
                timed_out_items.add_all(pool);
            }
            
            // report all the timed out items
            if (timed_out_items != null) {
                foreach (G item in timed_out_items)
                    timed_out(item);
            }
        }
        
        // one-shot; exit this method but reschedule for next timeout, if one is present
        if (next_timeout_check != null) {
            TimeSpan diff = next_timeout_check.difference(now);
            // TimeSpan is in microseconds ... min. of 1 because, if got here, there's at least
            // one item on the timeout queue and don't want it to be left there
            uint diff_sec = (uint) (diff / 1000000);
            if (diff_sec == 0)
                diff_sec = 1;
            
            timeout_id = Timeout.add_seconds(diff_sec, on_check_for_timeouts);
        } else {
            timeout_id = 0;
        }
        
        return false;
    }
}

