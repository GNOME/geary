/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * A NonblockingBatchOperation is an abstract base class used by NonblockingBatch.  It represents
 * a single task of asynchronous work.  NonblockingBatch will execute it one time only.
 */
public abstract class Geary.NonblockingBatchOperation : Object {
    public abstract async Object? execute_async(Cancellable? cancellable) throws Error;
}

/**
 * NonblockingBatch allows for multiple asynchronous tasks to be executed in parallel and for their
 * results to be examined after all have completed.  It's designed specifically with Vala's async
 * keyword in mind.
 *
 * Although the yield keyword allows for async tasks to execute, it only allows them to performed
 * in serial.  In a loop, for example, the next task in the loop won't execute until the current
 * one has completed.  The thread of execution won't block waiting for it, but this can be
 * suboptiminal and certain cases.
 *
 * NonblockingBatch allows for multiple async tasks to be gathered (via the add() method) into a
 * single batch.  Each task must subclass from NonblockingBatchOperation.  It's expected that the
 * subclass will maintain state particular to the operation, although NonblockingBatch does gather
 * two types of a results the task may generate: a result object (which descends from Object) or
 * a thrown exception.  Other results should be stored by the subclass.
 *
 * To use, create a NonblockingBatch and populate it via the add() method.  When all
 * NonblockingBatchOperations have been added, call execute_all_async().  NonblockingBatch will fire off
 * all at once and only complete execute_all_async() when all of them have finished.  As mentioned
 * earlier, it's also gather their returned objects and thrown exceptions while they run.  See
 * get_result() and throw_first_exception() for more information.
 *
 * The caller will want to call *either* get_result() or throw_first_exception() to ensure that
 * errors are propagated.  It's not necessary to call both.
 *
 * After execute_all_async() has completed, the results may be examined.  The NonblockingBatch object
 * can *not* be reused.
 *
 * Currently NonblockingBatch will fire off all operations at once and let them complete.  It does
 * not attempt to stop the others if one throws exception.  Also, there's no algorithm to submit the
 * operations in smaller chunks (to avoid flooding the thread's MainLoop).  These may be added in
 * the future.
 */
public class Geary.NonblockingBatch : Object {
    public const int INVALID_ID = -1;
    
    private const int START_ID = 1;
    
    private class BatchContext {
        public int id;
        public NonblockingBatchOperation op;
        public NonblockingBatch? owner = null;
        public bool completed = false;
        public Object? returned = null;
        public Error? threw = null;
        
        public BatchContext(int id, NonblockingBatchOperation op) {
            this.id = id;
            this.op = op;
        }
        
        public void schedule(NonblockingBatch owner, Cancellable? cancellable) {
            // hold a strong ref to the owner until the operation is completed
            this.owner = owner;
            
            op.execute_async.begin(cancellable, on_op_completed);
        }
        
        private void on_op_completed(Object? source, AsyncResult result) {
            completed = true;
            
            try {
                returned = op.execute_async.end(result);
            } catch (Error err) {
                threw = err;
            }
            
            owner.on_context_completed(this);
            
            // drop the reference to the owner to prevent a reference loop
            owner = null;
        }
    }
    
    /**
     * Returns the number of NonblockingBatchOperations added.
     */
    public int size {
        get { return contexts.size; }
    }
    
    private Gee.HashMap<int, BatchContext> contexts = new Gee.HashMap<int, BatchContext>();
    private NonblockingSemaphore sem = new NonblockingSemaphore();
    private int next_result_id = START_ID;
    private bool locked = false;
    private int completed_ops = 0;
    private Error? first_exception = null;
    
    public signal void added(NonblockingBatchOperation op, int id);
    
    public signal void started(int count);
    
    public signal void operation_completed(NonblockingBatchOperation op, Object? returned,
        Error? threw);
    
    public signal void completed(int count, Error? first_error);
    
    public NonblockingBatch() {
    }
    
    /**
     * Adds a NonblockingBatchOperation to the batch.  INVALID_ID is returned if the batch is
     * executing or has already executed.  Otherwise, returns an ID that can be used to fetch
     * results of this particular NonblockingBatchOperation after execute_all() completes.
     *
     * The returned ID is only good for this NonblockingBatch.  Since each instance uses the
     * same algorithm, different instances will likely return the same ID, so they must be
     * associated with the NonblockingBatch they originated from.
     */
    public int add(NonblockingBatchOperation op) {
        if (locked) {
            warning("NonblockingBatch already executed or executing");
            
            return INVALID_ID;
        }
        
        int id = next_result_id++;
        contexts.set(id, new BatchContext(id, op));
        
        added(op, id);
        
        return id;
    }
    
    /**
     * Executes all the NonblockingBatchOperations added to the batch.  The supplied Cancellable
     * will be passed to each operation.
     *
     * If the batch is executing or already executed, IOError.PENDING will be thrown.  If the
     * Cancellable is already cancelled, IOError.CANCELLED is thrown.  Other errors may be thrown
     * as well; see NonblockingAbstractSemaphore.wait_async().
     *
     * If there are no operations added to the batch, the method quietly exits.
     */
    public async void execute_all_async(Cancellable? cancellable = null) throws Error {
        if (locked)
            throw new IOError.PENDING("NonblockingBatch already executed or executing");
        
        locked = true;
        
        // if empty, quietly exit
        if (contexts.size == 0)
            return;
        
        // if already cancelled, not-so-quietly exit
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("NonblockingBatch cancelled before executing");
        
        started(contexts.size);
        
        // although they should technically be able to execute in any order, fire them off in the
        // order they were submitted; this may hide bugs, but it also makes other bugs reproducible
        int count = 0;
        for (int id = START_ID; id < next_result_id; id++) {
            BatchContext? context = contexts.get(id);
            assert(context != null);
            
            context.schedule(this, cancellable);
            count++;
        }
        
        assert(count == contexts.size);
        
        yield sem.wait_async(cancellable);
    }
    
    /**
     * Returns a Set of IDs for all added NonblockingBatchOperations.
     */
    public Gee.Set<int> get_ids() {
        return contexts.keys;
    }
    
    /**
     * Returns the NonblockingBatchOperation for the supplied ID.  Returns null if the ID is invalid
     * or unknown.
     */
    public NonblockingBatchOperation? get_operation(int id) {
        BatchContext? context = contexts.get(id);
        
        return (context != null) ? context.op : null;
    }
    
    /**
     * Returns the resulting Object from the operation for the supplied ID.  If the ID is invalid
     * or unknown, or the operation returned null, null is returned.
     *
     * If the operation threw an exception, it will be thrown here.  If all the operations' results
     * are examined with this method, there is no need to call throw_first_exception().
     *
     * If the operation has not completed, IOError.BUSY will be thrown.  It *is* legal to query
     * the result of a completed operation while others are executing.
     */
    public Object? get_result(int id) throws Error {
        BatchContext? context = contexts.get(id);
        if (context == null)
            return null;
        
        if (!context.completed)
            throw new IOError.BUSY("NonblockingBatchOperation %d not completed", id);
        
        if (context.threw != null)
            throw context.threw;
        
        return context.returned;
    }
    
    /**
     * If no results are examined via get_result(), this method can be used to manually throw the
     * first seen Error from the operations.
     */
    public void throw_first_exception() throws Error {
        if (first_exception != null)
            throw first_exception;
    }
    
    private void on_context_completed(BatchContext context) {
        if (first_exception == null && context.threw != null)
            first_exception = context.threw;
        
        operation_completed(context.op, context.returned, context.threw);
        
        assert(completed_ops < contexts.size);
        if (++completed_ops == contexts.size) {
            try {
                sem.notify();
            } catch (Error err) {
                debug("Unable to notify NonblockingBatch semaphore: %s", err.message);
            }
            
            completed(completed_ops, first_exception);
        }
    }
}

