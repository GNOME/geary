/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Interleaves IMAP operations to maintain consistent sequence numbering.
 *
 * The replay queue manages and executes operations originating both
 * locally and from the server for a specific IMAP mailbox so as to
 * ensure the execution of the operations maintains consistent.
 */
private class Geary.ImapEngine.ReplayQueue : BaseObject, Logging.Source {


    // Maximum number of times a retry-able operation should be
    // retried before failing. It's set to 1 since we only attempt to
    // retry if there's some transient error, so if it doesn't work
    // second time around, it probably won't work at all.
    private const int MAX_OP_RETRIES = 1;

    // This value is high because delays between back-to-back
    // unsolicited notifications have been see as high as 250ms
    private const int NOTIFICATION_QUEUE_WAIT_MSEC = 1000;


    private enum State {
        OPEN,
        CLOSING,
        CLOSED
    }

    private class CloseReplayQueue : ReplayOperation {

        bool local_closed = false;
        bool remote_closed = false;

        public CloseReplayQueue() {
            // LOCAL_AND_REMOTE to make sure this operation is flushed all the way down the pipe
            base ("CloseReplayQueue", ReplayOperation.Scope.LOCAL_AND_REMOTE, OnError.IGNORE_REMOTE);
        }

        public override async ReplayOperation.Status replay_local_async()
            throws GLib.Error {
            this.local_closed = true;
            return Status.CONTINUE;
        }

        // This doesn't actually get executed, but it's here for
        // completeness
        public override async void replay_remote_async(Imap.FolderSession remote)
            throws GLib.Error {
            this.remote_closed = true;
        }

        public override string describe_state() {
            return "local_closed: %s, remote_closed: %s".printf(
                this.local_closed.to_string(), this.remote_closed.to_string()
            );
        }
    }


    private class WaitOperation : ReplayOperation {

        public WaitOperation() {
            // LOCAL_AND_REMOTE to make sure this operation is flushed
            // all the way down the pipe
            base("Wait", LOCAL_AND_REMOTE, OnError.IGNORE_REMOTE);
        }

        public override async ReplayOperation.Status replay_local_async()
            throws GLib.Error {
            return Status.CONTINUE;
        }

        public override async void replay_remote_async(Imap.FolderSession remote)
            throws GLib.Error {
            // Noop
        }

        public override string describe_state() {
            return "";
        }

    }


    public int local_count { get {
        return local_queue.size;
    } }

    public int remote_count { get {
        return remote_queue.size;
    } }

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return Imap.ClientService.REPLAY_QUEUE_LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent {
        get { return this.owner; }
    }

    private weak MinimalFolder owner;
    private Nonblocking.Queue<ReplayOperation> local_queue =
        new Nonblocking.Queue<ReplayOperation>.fifo();
    private Nonblocking.Queue<ReplayOperation> remote_queue =
        new Nonblocking.Queue<ReplayOperation>.fifo();
    private ReplayOperation? local_op_active = null;
    private ReplayOperation? remote_op_active = null;
    private Gee.ArrayList<ReplayOperation> notification_queue = new Gee.ArrayList<ReplayOperation>();
    private Scheduler.Scheduled? notification_timer = null;
    private int64 next_submission_number = 0;
    private State state = State.OPEN;
    private Cancellable remote_wait_cancellable = new Cancellable();

    public virtual signal void scheduled(ReplayOperation op) {
        debug("Scheduled: %s", op.to_string());
    }

    public virtual signal void locally_executing(ReplayOperation op) {
        debug("Locally-executing: %s", op.to_string());
    }

    public virtual signal void locally_executed(ReplayOperation op, bool continuing) {
        debug("Locally-executed: %s continuing=%s",
              op.to_string(), continuing.to_string());
    }

    public virtual signal void remotely_executing(ReplayOperation op) {
        debug("Remotely-executing: %s", op.to_string());
    }

    public virtual signal void remotely_executed(ReplayOperation op) {
        debug("Remotely-executed: %s", op.to_string());
    }

    public virtual signal void backing_out(ReplayOperation op, Error? err) {
        debug("Backout-out: %s err=%s",
              op.to_string(), (err != null) ? err.message : "(null)");
    }

    public virtual signal void backed_out(ReplayOperation op, Error? err) {
        debug("Backed-out: %s err=%s",
              op.to_string(), (err != null) ? err.message : "(null)");
    }

    public virtual signal void backout_failed(ReplayOperation op, Error? backout_err) {
        debug("Backout-failed: %s err=%s",
              op.to_string(), (backout_err != null) ? backout_err.message : "(null)");
    }

    public virtual signal void completed(ReplayOperation op) {
        debug("Completed: %s", op.to_string());
    }

    public virtual signal void failed(ReplayOperation op) {
        debug("Failed: %s", op.to_string());
    }

    public virtual signal void closing() {
        debug("Closing");
    }

    public virtual signal void closed() {
        debug("Closed");
    }

    /**
     * ReplayQueue accepts a NonblockingReportingSemaphore<bool> which, when signaled, returns
     * true if the remote folder is ready and open, false if not (closing or closed), and
     * throws an Error if the semaphore has failed.  ReplayQueue will wait on this semaphore for
     * each ReplayOperation waiting to perform a remote operation, cancelling it if the remote
     * folder is not ready.
     */
    public ReplayQueue(MinimalFolder owner) {
        this.owner = owner;

        // fire off background queue processors
        do_replay_local_async.begin();
        do_replay_remote_async.begin();
    }

    ~ReplayQueue() {
        if (notification_timer != null)
            notification_timer.cancel();
    }

    /**
     * Returns false if the operation was not schedule (queue already closed).
     */
    public bool schedule(ReplayOperation op) {
        // ReplayClose is allowed past the velvet ropes even as the hoi palloi is turned away
        if (state != State.OPEN && !(op is CloseReplayQueue)) {
            debug("Unable to schedule replay operation %s on %s: replay queue closed", op.to_string(),
                to_string());

            return false;
        }

        // assign a submission number to operation ... this *must* happen before it's submitted to
        // any Mailbox
        op.submission_number = next_submission_number++;

        // note that in order for this to work (i.e. for sent and received operations to be handled
        // in order), it's *vital* that even REMOTE_ONLY operations go through the local queue,
        // only being scheduled on the remote queue *after* local operations ahead of it have
        // completed; thus, no need for get_scope() to be called here.
        bool is_scheduled = local_queue.send(op);
        if (is_scheduled)
            scheduled(op);

        return is_scheduled;
    }

    /**
     * Schedules a ReplayOperation created due to a server notification.
     *
     * All unsolicited server data uses positional addressing, so it's possible for an EXISTS
     * (append) to arrive followed by one or more EXPUNGEs (removes), meaning that the first
     * append's position has shifted downward.  Without a pause, Geary will immediately issue a
     * FETCH on that position, which no longer exists on the server.
     *
     * There is no signal in IMAP for the server to say "no more notifications arriving", hence a
     * timer must be used.
     *
     * Server notifications can arrive with significant time lapses between then (i.e.
     * up to 250ms) and back-to-back EXPUNGEs and EXISTs have serious affects on positional
     * addressing, ReplayQueue will store them for a period of time without adding them to the
     * queues.  When they stop arriving, it will enqueue them in order for processing.
     *
     * In particular, notify_remote_removed_position() should be called ''before'' adding the
     * ReplayRemoval operation, otherwise its own notification method will be called (making it
     * look like it was removed twice).
     *
     * Returns false if the operation was not schedule (queue already closed).
     */
    public bool schedule_server_notification(ReplayOperation op) {
        if (state != State.OPEN) {
            debug("Unable to schedule notification operation %s on %s: replay queue closed",
                  op.to_string(), to_string());
            return false;
        }

        notification_queue.add(op);

        // reschedule timeout every time new operation is added
        if (notification_timer != null)
            notification_timer.cancel();

        notification_timer = Scheduler.after_msec(NOTIFICATION_QUEUE_WAIT_MSEC, on_notification_timeout);

        return true;
    }

    /** Waits until all pending operations have been processed. */
    public async void checkpoint(GLib.Cancellable? cancellable)
        throws GLib.Error {
        WaitOperation wait_op = new WaitOperation();
        if (schedule(wait_op)) {
            yield wait_op.wait_for_ready_async(cancellable);
        } else {
            debug("Unable to schedule checkpoint op on %s", to_string());
        }
    }

    /** Queues for any pending server notifications to be processed. */
    public void flush_notifications() {
        if (this.notification_queue.size > 0) {
            debug("%s: Scheduling %d held server notification operations",
                  this.owner.to_string(),
                  this.notification_queue.size);

            // no new operations in timeout span, add them all to the
            // "real" queue
            foreach (ReplayOperation notification_op in this.notification_queue) {
                if (!schedule(notification_op)) {
                    debug("Unable to schedule notification operation %s on %s",
                          notification_op.to_string(),
                          to_string());
                }
            }
            this.notification_queue.clear();
        }
    }

    private bool on_notification_timeout() {
        flush_notifications();
        return false;
    }

    /**
     * This call gives all enqueued remote replay operations a chance to update their own state
     * due to a message being removed due to an unsolicited notification from the server)
     *
     * @see ReplayOperation.notify_remote_removed_position
     */
    public void notify_remote_removed_position(Imap.SequenceNumber pos) {
        notify_remote_removed_position_collection(notification_queue, null, pos);
        notify_remote_removed_position_collection(local_queue.get_all(), local_op_active, pos);
        notify_remote_removed_position_collection(remote_queue.get_all(), remote_op_active, pos);
    }

    private void notify_remote_removed_position_collection(Gee.Collection<ReplayOperation> replay_ops,
        ReplayOperation? active, Imap.SequenceNumber pos) {
        foreach (ReplayOperation replay_op in replay_ops)
            replay_op.notify_remote_removed_position(pos);

        if (active != null)
            active.notify_remote_removed_position(pos);
    }

    /**
     * This call gives all enqueued remote replay operations a chance to update their own state
     * due to a message being removed (either during normalization or an unsolicited notification
     * from the server)
     *
     * @see ReplayOperation.notify_remote_removed_ids
     */
    public void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        notify_remote_removed_ids_collection(notification_queue, null, ids);
        notify_remote_removed_ids_collection(local_queue.get_all(), local_op_active, ids);
        notify_remote_removed_ids_collection(remote_queue.get_all(), remote_op_active, ids);
    }

    private void notify_remote_removed_ids_collection(Gee.Collection<ReplayOperation> replay_ops,
        ReplayOperation? active, Gee.Collection<ImapDB.EmailIdentifier> ids) {
        foreach (ReplayOperation replay_op in replay_ops)
            replay_op.notify_remote_removed_ids(ids);

        if (active != null)
            active.notify_remote_removed_ids(ids);
    }

    /**
     * Returns all ImapDb.EmailIdentifiers for enqueued ReplayOperations waiting for
     * replay_remote_async() that are planning to be removed on the server.
     */
    public void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        foreach (ReplayOperation replay_op in remote_queue.get_all())
            replay_op.get_ids_to_be_remote_removed(ids);

        if (remote_op_active != null)
            remote_op_active.get_ids_to_be_remote_removed(ids);
    }

    /**
     * Closes the {@link ReplayQueue}.
     *
     * If flush_pending is false, outstanding operations are cancelled.  If a {@link ReplayOperation}
     * has executed locally and is waiting to execute remotely, it will be backed out.
     *
     * Otherwise, all outstanding operations are permitted to execute, but no new ones may be
     * scheduled.
     *
     * A ReplayQueue cannot be re-opened.
     */
    public async void close_async(bool flush_pending, Cancellable? cancellable = null) throws Error {
        if (state != State.OPEN)
            return;

        // cancel notification queue timeout
        if (notification_timer != null)
            notification_timer.cancel();

        // piggyback on the notification timer callback to flush notification operations
        if (flush_pending)
            on_notification_timeout();

        // mark as closed now to prevent further scheduling ... ReplayClose gets special
        // consideration in schedule()
        state = State.CLOSING;
        closing();

        // if not flushing pending, stop waiting for a remote session
        // and clear out all waiting operations, backing out any that
        // need to be backed out
        if (!flush_pending) {
            this.remote_wait_cancellable.cancel();
            yield clear_pending_async(cancellable);
        }

        // flush a ReplayClose operation down the pipe so all working operations complete
        CloseReplayQueue close_op = new CloseReplayQueue();
        bool is_scheduled = schedule(close_op);
        assert(is_scheduled);

        yield close_op.wait_for_ready_async(cancellable);

        state = State.CLOSED;
        closed();
    }

    /**
     * Get pending unread change.
     */
    public int pending_unread_change() {
        int unread_change = 0;
        Gee.Collection<ReplayOperation> replay_ops = traverse(
            remote_queue.get_all()
        ).to_array_list();
        replay_ops.add(this.remote_op_active);
        foreach (ReplayOperation op in replay_ops) {
            if (op is ImapEngine.MarkEmail) {
                ImapEngine.MarkEmail mark_email = op as ImapEngine.MarkEmail;
                unread_change += mark_email.unread_change;
            }
        }
        return unread_change;
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "notification=%d local=%d local_active=%s remote=%d remote_active=%s",
            this.notification_queue.size,
            this.local_queue.size,
            (this.local_op_active != null).to_string(),
            this.remote_queue.size,
            (this.remote_op_active != null).to_string()
        );
    }

    private async void clear_pending_async(Cancellable? cancellable) {
        // note that this merely clears the queue; disabling the timer is performed in close_async
        notification_queue.clear();

        // clear the local queue; nothing more to do there
        local_queue.clear();

        // have to backout elements that have executed locally but not remotely
        // clear the remote queue before backing out, otherwise the queue might proceed while
        // yielding
        Gee.List<ReplayOperation> remote_list = new Gee.ArrayList<ReplayOperation>();
        remote_list.add_all(remote_queue.get_all());

        remote_queue.clear();

        foreach (ReplayOperation op in remote_list) {
            try {
                yield op.backout_local_async();
            } catch (Error err) {
                debug("Error backing out operation %s: %s", op.to_string(), err.message);
            }
        }
    }

    private async void do_replay_local_async() {
        bool queue_running = true;
        while (queue_running) {
            ReplayOperation op;
            try {
                op = yield local_queue.receive();
            } catch (Error recv_err) {
                debug("Unable to receive next replay operation on local queue %s: %s", to_string(),
                    recv_err.message);

                break;
            }

            this.local_op_active = op;

            // If this is a Close operation, shut down the queue after processing it
            if (op is CloseReplayQueue)
                queue_running = false;

            bool local_execute = false;
            bool remote_enqueue = false;
            switch (op.scope) {
                case ReplayOperation.Scope.LOCAL_AND_REMOTE:
                    local_execute = true;
                    remote_enqueue = true;
                break;

                case ReplayOperation.Scope.LOCAL_ONLY:
                    local_execute = true;
                    remote_enqueue = false;
                break;

                case ReplayOperation.Scope.REMOTE_ONLY:
                    local_execute = false;
                    remote_enqueue = true;
                break;

                default:
                    assert_not_reached();
            }

            if (local_execute) {
                locally_executing(op);

                try {
                    switch (yield op.replay_local_async()) {
                        case ReplayOperation.Status.COMPLETED:
                            // done
                            remote_enqueue = false;
                            op.notify_ready(null);
                        break;

                        case ReplayOperation.Status.CONTINUE:
                            // don't touch remote_enqueue; if already false, CONTINUE is treated as
                            // COMPLETED.
                            if (!remote_enqueue)
                                op.notify_ready(null);
                        break;

                        default:
                            assert_not_reached();
                    }
                } catch (Error replay_err) {
                    debug("Replay local error for %s on %s: %s", op.to_string(), to_string(),
                        replay_err.message);

                    op.notify_ready(replay_err);
                    remote_enqueue = false;
                }
            }

            if (remote_enqueue) {
                if (!remote_queue.send(op)) {
                    debug("Unable to enqueue operation %s for %s remote operation", op.to_string(),
                        to_string());
                }
            } else {
                // all code paths to this point should have notified ready if not enqueuing for
                // next stage
                assert(op.notified);
            }

            if (local_execute)
                locally_executed(op, remote_enqueue);

            if (!remote_enqueue) {
                if (op.err == null)
                    completed(op);
                else
                    failed(op);
            }

            this.local_op_active = null;
        }

        debug("ReplayQueue.do_replay_local_async %s exiting", to_string());
    }

    private async void do_replay_remote_async() {
        bool folder_opened = true;
        bool queue_running = true;
        while (queue_running) {
            // wait for the next operation ... do this *before* waiting for remote
            ReplayOperation op;
            try {
                op = yield remote_queue.receive();
            } catch (Error recv_err) {
                debug("Unable to receive next replay operation on remote queue %s: %s", to_string(),
                    recv_err.message);

                break;
            }

            this.remote_op_active = op;

            // ReplayClose means this queue (and the folder) are closing, so handle errors a little
            // differently
            bool is_close_op = op is CloseReplayQueue;
            if (is_close_op)
                queue_running = false;

            // wait until the remote folder is opened (or throws an exception, in which case closed)
            Imap.FolderSession? remote = null;
            try {
                if (!is_close_op && folder_opened && state != State.CLOSED) {
                    remote = yield owner.claim_remote_session(
                        this.remote_wait_cancellable
                    );
                }
            } catch (Error remote_err) {
                debug("Folder %s closed or failed to open, remote replay queue closing: %s",
                      to_string(), remote_err.message);

                // not open
                folder_opened = false;

                // fall through
            }

            remotely_executing(op);

            Error? remote_err = null;
            if (remote != null) {
                if (op.remote_retry_count > 0)
                    debug("Retrying op %s on %s", op.to_string(), to_string());

                try {
                    yield op.replay_remote_async(remote);
                } catch (Error replay_err) {
                    debug("Replay remote error for %s on %s: %s (%s)", op.to_string(), to_string(),
                        replay_err.message, op.on_remote_error.to_string());

                    // If a recoverable failure and operation allows
                    // remote replay and not closing, re-schedule now
                    if (op.on_remote_error == RETRY &&
                        op.remote_retry_count <= MAX_OP_RETRIES &&
                        is_recoverable_failure(replay_err) &&
                        state == State.OPEN) {
                        debug("Schedule op retry %s on %s", op.to_string(), to_string());

                        // the Folder will disconnect and reconnect due to the hard error and
                        // wait_for_open_async() will block this command until reconnected and
                        // normalized
                        op.remote_retry_count++;
                        remote_queue.send(op);

                        continue;
                    } else if (op.on_remote_error == IGNORE_REMOTE &&
                               is_remote_error(replay_err)) {
                        // ignoring error, simply notify as completed and continue
                        debug("Ignoring remote error op %s on %s", op.to_string(), to_string());
                    } else {
                        debug("Throwing error for op %s on %s: %s", op.to_string(), to_string(),
                            replay_err.message);

                        // store for notification
                        remote_err = replay_err;
                    }
                }
            } else if (!is_close_op) {
                remote_err = new EngineError.SERVER_UNAVAILABLE("Folder %s not available", owner.to_string());
            }

            // COMPLETED == CONTINUE, only exception of interest here if not closing
            if (remote_err != null && !is_close_op) {
                try {
                    backing_out(op, remote_err);

                    yield op.backout_local_async();

                    backed_out(op, remote_err);
                } catch (Error backout_err) {
                    backout_failed(op, backout_err);
                }
            }

            // use the remote error (not the backout error) for the operation's completion
            // state
            op.notify_ready(remote_err);

            remotely_executed(op);

            if (op.err == null)
                completed(op);
            else
                failed(op);

            this.remote_op_active = null;
        }

        debug("ReplayQueue.do_replay_remote_async %s exiting", to_string());
    }

}
