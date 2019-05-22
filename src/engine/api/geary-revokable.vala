/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an operation with the Geary Engine that may be revoked (undone) at a later
 * time.
 *
 * The Revokable will do everything it can to commit the operation (if necessary) when its final
 * ref is dropped.  However, since the final ref can be dropped at an indeterminate time, it's
 * advised that callers force the matter by scheduling it with {@link commit_async}.
 */

public abstract class Geary.Revokable : BaseObject {
    public const string PROP_VALID = "valid";
    public const string PROP_IN_PROCESS = "in-process";

    /**
     * Indicates if {@link revoke_async} or {@link commit_async} are valid operations for this
     * {@link Revokable}.
     *
     * Due to later operations or notifications, it's possible for the Revokable to go invalid
     * after being issued to the caller.
     *
     * @see set_invalid
     */
    public bool valid { get; private set; default = true; }

    /**
     * Indicates a {@link revoke_async} or {@link commit_async} operation is underway.
     *
     * Only one operation can occur at a time, and when complete the {@link Revokable} will be
     * invalid.
     *
     * @see valid
     */
    public bool in_process { get; protected set; default = false; }

    private uint commit_timeout_id = 0;

    /**
     * Fired when the {@link Revokable} has been revoked.
     *
     * {@link valid} will still be true when this is fired.
     */
    public signal void revoked();

    /**
     * Fired when the {@link Revokable} has been committed.
     *
     * Some Revokables will offer a new Revokable to allow revoking the committed state.
     *
     * {@link valid} will still be true when this is fired.
     */
    public signal void committed(Geary.Revokable? commit_revokable);

    /**
     * Create a {@link Revokable} with optional parameters.
     *
     * If commit_timeout_sec is nonzero, Revokable will automatically call {@link commit_async}
     * after the timeout expires if it is still {@link valid}.
     */
    protected Revokable(int commit_timeout_sec = 0) {
        if (commit_timeout_sec == 0)
            return;

        // This holds a reference to the Revokable, meaning cancelling the timeout in the dtor is
        // largely symbolic, but so be it
        commit_timeout_id = Timeout.add_seconds(commit_timeout_sec, on_timed_commit);

        // various events that cancel the need for a timed commit; this is important to drop the
        // ref to this object within the event loop
        revoked.connect(cancel_timed_commit);
        committed.connect(cancel_timed_commit);
        notify[PROP_VALID].connect(() => {
            if (!valid)
                cancel_timed_commit();
        });
    }

    ~Revokable() {
        cancel_timed_commit();
    }

    protected virtual void notify_revoked() {
        revoked();
    }

    protected virtual void notify_committed(Geary.Revokable? commit_revokable) {
        committed(commit_revokable);
    }

    /**
     * Mark the {@link Revokable} as invalid.
     *
     * Once invalid, a Revokable may never transit back to a valid state.
     *
     * @see valid
     */
    protected void set_invalid() {
        valid = false;
    }

    /**
     * Revoke (undo) the operation.
     *
     * If the call throws an Error that does not necessarily mean the {@link Revokable} is
     * invalid.  Check {@link valid}.
     *
     * @throws EngineError.ALREADY_OPEN if {@link in_process} is true.  EngineError.ALREADY_CLOSED
     * if {@link valid} is false.
     */
    public virtual async void revoke_async(Cancellable? cancellable = null) throws Error {
        if (in_process)
            throw new EngineError.ALREADY_OPEN("Already revoking or committing operation");

        if (!valid)
            throw new EngineError.ALREADY_CLOSED("Revokable not valid");

        in_process = true;
        try {
            yield internal_revoke_async(cancellable);
        } finally {
            in_process = false;
        }
    }

    /**
     * The child class's implementation of {@link revoke_async}.
     *
     * The default implementation of {@link revoke_async} deals with state issues
     * ({@link in_process}, throwing the appropriate Error, etc.)  Child classes can override this
     * method and only worry about the revoke operation itself.
     *
     * This call *must* set {@link valid} before exiting.  It must also call {@link notify_revoked}
     * if successful.
     */
    protected abstract async void internal_revoke_async(Cancellable? cancellable) throws Error;

    /**
     * Commits (completes) the operation immediately.
     *
     * Some {@link Revokable} operations work by delaying the operation until time has passed or
     * some situation occurs which requires the operation to complete.  This call forces the
     * operation to complete immediately rather than delay it for later.
     *
     * Even if the operation "actually" commits and is not delayed, calling commit_async() will
     * make this Revokable invalid.
     *
     * @throws EngineError.ALREADY_OPEN if {@link in_process} is true.  EngineError.ALREADY_CLOSED
     * if {@link valid} is false.
     */
    public virtual async void commit_async(Cancellable? cancellable = null) throws Error {
        if (in_process)
            throw new EngineError.ALREADY_OPEN("Already revoking or committing operation");

        if (!valid)
            throw new EngineError.ALREADY_CLOSED("Revokable not valid");

        in_process = true;
        try {
            yield internal_commit_async(cancellable);
        } finally {
            in_process = false;
        }
    }

    /**
     * The child class's implementation of {@link commit_async}.
     *
     * The default implementation of {@link commit_async} deals with state issues
     * ({@link in_process}, throwing the appropriate Error, etc.)  Child classes can override this
     * method and only worry about the revoke operation itself.
     *
     * This call *must* set {@link valid} before exiting.  It must also call {@link notify_committed}
     * if successful.
     */
    protected abstract async void internal_commit_async(Cancellable? cancellable) throws Error;

    private bool on_timed_commit() {
        commit_timeout_id = 0;

        if (valid && !in_process)
            commit_async.begin();

        return false;
    }

    private void cancel_timed_commit() {
        if (commit_timeout_id == 0)
            return;

        Source.remove(commit_timeout_id);
        commit_timeout_id = 0;
    }
}

