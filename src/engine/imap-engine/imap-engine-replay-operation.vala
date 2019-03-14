/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Base class for folder operations executed by {@link ReplayQueue}.
 */
private abstract class Geary.ImapEngine.ReplayOperation : Geary.BaseObject, Gee.Comparable<ReplayOperation> {

    /**
     * Specifies the call scope (local, remote, both) of an operation.
     *
     * The methods that are called for the operation depends on the
     * returned Scope.
     *
     * * `LOCAL_AND_REMOTE`: replay_local_async() is called.  If that
     * method returns COMPLETED, no further calls are made.  If it
     * returns CONTINUE, replay_remote_async() is called.
     * * `LOCAL_ONLY`: replay_local_async() only.
     * replay_remote_async() will never be called.
     * * `REMOTE_ONLY`: replay_remote_async() only.
     * replay_local_async() will never be called.
     *
     * See the various replay methods for how backout_local_async()
     * may be called depending on this field and those methods' return
     * values.
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
        IGNORE_REMOTE
    }

    public string name { get; set; }
    public int64 submission_number { get; set; default = -1; }
    public Scope scope { get; private set; }
    public OnError on_remote_error { get; protected set; }
    public int remote_retry_count { get; set; default = 0; }
    public Error? err { get; private set; default = null; }
    public bool notified { get { return semaphore.can_pass; } }

    private Nonblocking.Semaphore semaphore = new Nonblocking.Semaphore();

    protected ReplayOperation(string name, Scope scope, OnError on_remote_error = OnError.THROW) {
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
    public virtual void notify_remote_removed_position(Imap.SequenceNumber removed) {
        // noop
    }

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
    public virtual void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // noop
    }

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
    public virtual void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // noop
    }

    /**
     * Executes the local parts of this operation, if any.
     *
     * See Scope for conditions where this method will be called.
     *
     * If an error is thrown, {@link backout_local_async} will
     * *not* be executed.
     *
     * @return {@link Status.COMPLETED} if the operation has completed
     * and no further calls should be made, else {@link
     * Status.CONTINUE} if the local operation has completed and the
     * remote portion must be executed as well. This is treated as
     * `COMPLETED` if get_scope() returns {@link Scope.LOCAL_ONLY}.
     */
    public virtual async Status replay_local_async()
        throws GLib.Error {
        if (this.scope != Scope.REMOTE_ONLY) {
            throw new GLib.IOError.NOT_SUPPORTED("Local operation is not implemented");
        }
        return (this.scope == Scope.LOCAL_ONLY)
            ? Status.COMPLETED : Status.CONTINUE;
    }

    /**
     * Executes the remote parts of this operation, if any.
     *
     * See Scope for conditions where this method will be called.
     *
     * Passed a folder session with the current folder selected.
     *
     * If an error is thrown, {@link backout_local_async} will be
     * executed only if scope is LOCAL_AND_REMOTE.
     */
    public virtual async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        if (this.scope != Scope.LOCAL_ONLY) {
            throw new GLib.IOError.NOT_SUPPORTED("Remote operation is not implemented");
        }
    }

    /**
     * Reverts any local effects of this operation.
     *
     * See {@link Scope}, {@link replay_local_async}, and {@link
     * replay_remote_async} for conditions for this where this will be
     * called.
     */
    public virtual async void backout_local_async() throws Error {
        // noop
    }

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
        assert(!semaphore.can_pass);

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

