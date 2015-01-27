/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.ReplayOperation : Geary.BaseObject, Gee.Comparable<ReplayOperation> {
    /**
     * Scope specifies what type of operations (remote, local, or both) are needed by this operation.
     *
     * What methods are made on the operation depends on the returned Scope:
     *
     * LOCAL_AND_REMOTE: replay_local_async() is called.  If that method returns COMPLETED,
     *   no further calls are made.  If it returns CONTINUE, replay_remote_async() is called.
     * LOCAL_ONLY: replay_local_async() only.  replay_remote_async() will never be called.
     * REMOTE_ONLY: replay_remote_async() only.  replay_local_async() will never be called.
     *
     * See the various replay methods for how backout_local_async() may be called depending on
     * this field and those methods' return values.
     */
    public enum Scope {
        LOCAL_AND_REMOTE,
        LOCAL_ONLY,
        REMOTE_ONLY
    }
    
    public enum Status {
        COMPLETED,
        CONTINUE
    }
    
    public enum OnError {
        THROW,
        RETRY,
        IGNORE
    }
    
    public string name { get; set; }
    public int64 submission_number { get; set; default = -1; }
    public Scope scope { get; private set; }
    public OnError on_remote_error { get; protected set; }
    public int remote_retry_count { get; set; default = 0; }
    public Error? err { get; private set; default = null; }
    public bool notified { get { return semaphore.is_passed(); } }
    
    private Nonblocking.Semaphore semaphore = new Nonblocking.Semaphore();
    
    public ReplayOperation(string name, Scope scope, OnError on_remote_error = OnError.THROW) {
        this.name = name;
        this.scope = scope;
        this.on_remote_error = on_remote_error;
    }
    
    /**
     * Notify the operation that a message has been removed by position (SequenceNumber).
     *
     * This notification can be invoked any time before replay_remote_async() is called.
     *
     * Since the unsolicited server notification is positionally addressed, this only applies to
     * operations that use positional addressing.  Use Imap.SequenceNumber.shift_for_removed() for
     * foolproof adjustment.
     *
     * This won't be called while replay_local_async() or replay_remote_async() are executing.
     */
    public abstract void notify_remote_removed_position(Imap.SequenceNumber removed);
    
    /**
     * Notify the operation that a message has been removed by UID (EmailIdentifier).
     *
     * This method is called only when the ReplayOperation is blocked waiting to execute and it's
     * discovered that the supplied email(s) are no longer on the server.
     *
     * This happens during folder normalization (initial synchronization with the server
     * when a folder is opened) where ReplayOperations are allowed to execute locally and enqueue
     * for remote operation in preparation for the folder to fully open.
     *
     * The ReplayOperation should remove any reference to the emails so not to attempt operation
     * on the server.  If it's discovered in replay_remote_async() that there are no more operations
     * to perform, it should simply exit without contacting the server.
     *
     * This won't be called while replay_local_async() or replay_remote_async() are executing.
     */
    public abstract void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids);
    
    /**
     * Add to the Collection EmailIdentifiers that will be removed in replay_remote_async().
     *
     * This is called when the ReplayOperation is still waiting to run replay_remote_async().
     * If it has any EmailIdentifiers it plans on removing from the server's folder, it should
     * add them to the supplied Collection.
     *
     * This is called during folder normalization when it's necessary to know which remove markers
     * in the local folder are set due to current user interaction or were left over from the last
     * invocation (i.e. the Folder closed before the server could notify the engine that they were
     * removed).
     */
    public abstract void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids);
    
    /**
     * See Scope for conditions where this method will be called.
     *
     * Returns:
     *   COMPLETED: the operation has completed and no further calls should be made.
     *   CONTINUE: The local operation has completed and the remote portion must be executed as
     *      well.  This is treated as COMPLETED if get_scope() returns LOCAL_ONLY.
     *
     * If Error thrown:
     *   backout_local_async() will *not* be executed.
     */
    public abstract async Status replay_local_async() throws Error;
    
    /**
     * See Scope for conditions where this method will be called.
     *
     * Returns:
     *   COMPLETED: the operation has completed and no further calls should be made.
     *   CONTINUE: Treated as COMPLETED.
     *
     * If Error thrown:
     *   backout_local_async() will be executed only if scope is LOCAL_AND_REMOTE.
     */
    public abstract async Status replay_remote_async() throws Error;
    
    /**
     * See Scope, replay_local_async(), and replay_remote_async() for conditions for this where this
     * will be called.
     */
    public abstract async void backout_local_async() throws Error;
    
    /**
     * Completes when the operation has completed execution.  If the operation threw an error
     * during execution, it will be thrown here.
     */
    public async void wait_for_ready_async(Cancellable? cancellable = null) throws Error {
        yield semaphore.wait_async(cancellable);
        
        if (err != null)
            throw err;
    }
    
    // Can only be called once
    internal void notify_ready(Error? err) {
        assert(!semaphore.is_passed());
        
        this.err = err;
        
        try {
            semaphore.notify();
        } catch (Error notify_err) {
            debug("Unable to notify replay operation as ready: [%s] %s", name, notify_err.message);
        }
    }
    
    public abstract string describe_state();
    
    // The Comparable interface is merely to ensure the ReplayQueue sorts operations by their
    // submission order, ensuring that retry operations are retried in order of submissions
    public int compare_to(ReplayOperation other) {
        assert(submission_number >= 0);
        assert(other.submission_number >= 0);
        
        return (int) (submission_number - other.submission_number).clamp(-1, 1);
    }
    
    public string to_string() {
        string state = describe_state();
        
        return String.is_empty(state)
            ? "[%s] %s remote_retry_count=%d".printf(submission_number.to_string(), name, remote_retry_count)
            : "[%s] %s: %s remote_retry_count=%d".printf(submission_number.to_string(), name, state,
                remote_retry_count);
    }
}

