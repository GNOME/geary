/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An abstract base class representing a single task of asynchronous work.
 */
public abstract class Geary.Nonblocking.BatchOperation : BaseObject {
    /**
     * Called by {@link Nonblocking.Batch} when execution should start.
     *
     * This will be called once and only once by Nonblocking.Batch.
     *
     * @return An optional Object.  This will be referenced and stored by Nonblocking.Batch.
     */
    public abstract async Object? execute_async(Cancellable? cancellable) throws Error;
}

/**
 * Allows for multiple asynchronous tasks to be executed in parallel and for their results to be
 * examined after all have completed.
 *
 * Nonblocking.Batch is designed specifically with Vala's async keyword in mind.
 * Although the yield keyword allows for async tasks to execute, it only allows them to performed
 * in serial.  In a loop, for example, the next task in the loop won't execute until the current
 * one has completed.  The thread of execution won't block waiting for it, but this can be
 * suboptiminal and certain cases.
 *
 * Nonblocking.Batch allows for multiple async tasks to be gathered (via the {@link add} method)
 * into a single batch.  Each task must subclass from {@link BatchOperation}.  It's expected that
 * the subclass will maintain state particular to the operation, although Nonblocking.Batch does
 * gather two types of a results the task may generate: a result object (which descends from Object)
 * or a thrown exception.  Other results should be stored by the subclass.
 *
 * To use, create a Nonblocking.Batch and populate it via the add() method.  When all
 * {@link BatchOperation}s have been added, call {@link execute_all_async}.  NonblockingBatch will
 * execute all BatchOperations at once and only complete their execute_all_async when all have
 * finished.  As mentioned earlier, it's also gather their returned objects and thrown exceptions
 * while they run.  See {@link get_result} and {@link throw_first_exception} for more information.
 *
 * The caller will want to call either get_result or throw_first_exception to ensure that
 * errors are propagated.  It's not necessary to call both.
 *
 * After execute_all_async has completed, the results may be examined.  The Nonblocking.Batch
 * object can ''not'' be reused.
 *
 * Nonblocking.Batch will fire off all operations at once and let them complete.  It does
 * not attempt to stop the others if one throws exception.  Also, there's no algorithm to submit the
 * operations in smaller chunks (to avoid flooding the thread's MainLoop).  These may be added in
 * the future.
 */
public class Geary.Nonblocking.Batch : BaseObject {
    /**
     * An invalid {@link BatchOperation} identifier.
     */
    public const int INVALID_ID = -1;

    private const int START_ID = 1;

    private class BatchContext : BaseObject {
        public int id;
        public Nonblocking.BatchOperation op;
        public Nonblocking.Batch? owner = null;
        public bool completed = false;
        public Object? returned = null;
        public Error? threw = null;

        public BatchContext(int id, Nonblocking.BatchOperation op) {
            this.id = id;
            this.op = op;
        }

        public void schedule(Nonblocking.Batch owner, Cancellable? cancellable) {
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
     * Returns the number of {@link BatchOperation}s added to the batch.
     */
    public int size {
        get { return contexts.size; }
    }

    /**
     * Returns the first exception encountered after completing {@link execute_all_async}.
     */
    public Error? first_exception { get; private set; default = null; }

    private Gee.HashMap<int, BatchContext> contexts = new Gee.HashMap<int, BatchContext>();
    private Nonblocking.Semaphore sem = new Nonblocking.Semaphore();
    private int next_result_id = START_ID;
    private bool locked = false;
    private int completed_ops = 0;

    /**
     * Fired when a {@link BatchOperation} is added to the batch.
     */
    public signal void added(Nonblocking.BatchOperation op, int id);

    /**
     * Fired when batch execution has started.
     */
    public signal void started(int count);

    /**
     * Fired when a {@link BatchOperation} has completed.
     */
    public signal void operation_completed(Nonblocking.BatchOperation op, Object? returned,
        Error? threw);

    /**
     * Fired when all {@link BatchOperation}s have completed.
     */
    public signal void completed(int count, Error? first_error);

    public Batch() {
    }

    /**
     * Adds a {@link BatchOperation} for later execution.
     *
     * {@link INVALID_ID} is returned if the batch is executing or has already executed.  Otherwise,
     * returns an ID that can be used to fetch results of this particular BatchOperation after
     * {@link execute_all_async} completes.
     *
     * The returned ID is only good for this {@link Batch}.  Since each instance uses the
     * same algorithm, different instances will likely return the same ID, so they must be
     * associated with the Batch they originated from.
     */
    public int add(Nonblocking.BatchOperation op) {
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
     * Executes all the {@link BatchOperation}s added to the batch.
     *
     * The supplied Cancellable will be passed to each {@link BatchOperation.execute_async}.
     *
     * If the batch is executing or already executed, IOError.PENDING will be thrown.  If the
     * Cancellable is already cancelled, IOError.CANCELLED is thrown.  Other errors may be thrown
     * as well; see {@link Lock.wait_async}.
     *
     * Batch will launch each BatchOperation in the order added.  Depending on the BatchOperation,
     * this does not guarantee that they'll complete in any particular order.
     *
     * If there are no operations added to the batch, the method quietly exits.
     */
    public async void execute_all_async(Cancellable? cancellable = null) throws Error {
        if (locked)
            throw new IOError.PENDING("NonblockingBatch already executed or executing");

        locked = true;

        // if empty, quietly exit (leaving the object locked; NonblockingBatch is a one-shot deal)
        if (contexts.size == 0)
            return;

        // if already cancelled, not-so-quietly exit
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("NonblockingBatch cancelled before executing");

        started(contexts.size);

        // fire them off in order they were submitted; this may hide bugs, but it also makes other
        // bugs reproducible
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
     * Returns a Set of identifiers for all added {@link BatchOperation}s.
     */
    public Gee.Set<int> get_ids() {
        return contexts.keys;
    }

    /**
     * Returns the NonblockingBatchOperation for the supplied identifier.
     *
     * @return null if the identifier is invalid or unknown.
     */
    public Nonblocking.BatchOperation? get_operation(int id) {
        BatchContext? context = contexts.get(id);

        return (context != null) ? context.op : null;
    }

    /**
     * Returns the resulting Object from the operation for the supplied identifier.
     *
     * If the operation threw an exception, it will be thrown here.  If all the operations' results
     * are examined with this method, there is no need to call throw_first_exception().
     *
     * If the operation has not completed, IOError.BUSY will be thrown.  It is legal to query
     * the result of a completed operation while others are executing.
     *
     * @return The resulting Object for the executed {@link BatchOperation}, which may be null.
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
     * If no results are examined via {@link get_result}, this method can be used to manually throw
     * the first seen Error from the operations.
     */
    public void throw_first_exception() throws Error {
        if (first_exception != null)
            throw first_exception;
    }

    /**
     * Returns the Error message if an exception was encountered, null otherwise.
     */
    public string? get_first_exception_message() {
        return (first_exception != null) ? first_exception.message : null;
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

