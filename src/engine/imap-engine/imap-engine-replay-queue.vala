/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayQueue : Geary.BaseObject {
    private class ReplayClose : ReplayOperation {
        public ReplayClose() {
            // LOCAL_AND_REMOTE to make sure this operation is flushed all the way down the pipe
            base ("Close", ReplayOperation.Scope.LOCAL_AND_REMOTE);
        }
        
        public override async ReplayOperation.Status replay_local_async() throws Error {
            return Status.CONTINUE;
        }
        
        public override bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
            EmailIdentifier id, Imap.EmailFlags? flags) {
            // whatever, no problem, do what you will
            return true;
        }
        
        public override async ReplayOperation.Status replay_remote_async() throws Error {
            return Status.COMPLETED;
        }
        
        public override async void backout_local_async() throws Error {
            // nothing to backout (and should never be called, to boot)
        }
        
        public override string describe_state() {
            return "";
        }
    }
    
    public string name { get; private set; }
    
    public int local_count { get {
        return local_queue.size;
    } }
    
    public int remote_count { get {
        return remote_queue.size;
    } }
    
    private Nonblocking.ReportingSemaphore<bool> remote_reporting_semaphore;
    private Nonblocking.Mailbox<ReplayOperation> local_queue = new Nonblocking.Mailbox<ReplayOperation>();
    private Nonblocking.Mailbox<ReplayOperation> remote_queue = new Nonblocking.Mailbox<ReplayOperation>();
    
    private bool is_closed = false;
    
    public virtual signal void scheduled(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::scheduled: %s %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void locally_executing(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::locally-executing: %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void locally_executed(ReplayOperation op, bool continuing) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::locally-executed: %s continuing=%s",
            to_string(), op.to_string(), continuing.to_string());
    }
    
    public virtual signal void remotely_executing(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::remotely-executing: %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void remotely_executed(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::remotely-executed: %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void backing_out(ReplayOperation op, bool failed, Error? err) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::backout-out: %s failed=%s err=%s",
            to_string(), op.to_string(), failed.to_string(), (err != null) ? err.message : "(null)");
    }
    
    public virtual signal void backed_out(ReplayOperation op, bool failed, Error? err) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::backed-out: %s failed=%s err=%s",
            to_string(), op.to_string(), failed.to_string(), (err != null) ? err.message : "(null)");
    }
    
    public virtual signal void backout_failed(ReplayOperation op, Error? backout_err) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::backout-failed: %s err=%s", to_string(),
            op.to_string(), (backout_err != null) ? backout_err.message : "(null)");
    }
    
    public virtual signal void completed(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::completed: %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void failed(ReplayOperation op) {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::failed: %s", to_string(),
            op.to_string());
    }
    
    public virtual signal void closing() {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::closing", to_string());
    }
    
    public virtual signal void closed() {
        Logging.debug(Logging.Flag.REPLAY, "[%s] ReplayQueue::closed", to_string());
    }
    
    /**
     * ReplayQueue accepts a NonblockingReportingSemaphore<bool> which, when signaled, returns
     * true if the remote folder is ready and open, false if not (closing or closed), and
     * throws an Error if the semaphore has failed.  ReplayQueue will wait on this semaphore for
     * each ReplayOperation waiting to perform a remote operation, cancelling it if the remote
     * folder is not ready.
     */
    public ReplayQueue(string name, Nonblocking.ReportingSemaphore<bool> remote_reporting_semaphore) {
        this.name = name;
        this.remote_reporting_semaphore = remote_reporting_semaphore;
        
        // fire off background queue processors
        do_replay_local_async.begin();
        do_replay_remote_async.begin();
    }
    
    /**
     * Returns false if the operation was not schedule (queue already closed).
     */
    public bool schedule(ReplayOperation op) {
        if (is_closed) {
            debug("Unable to scheduled replay operation %s on %s: replay queue closed", op.to_string(),
                to_string());
            
            return false;
        }
        
        // note that in order for this to work (i.e. for sent and received operations to be handled
        // in order), it's *vital* that even REMOTE_ONLY operations go through the local queue,
        // only being scheduled on the remote queue *after* local operations ahead of it have
        // completed; thus, no need for get_scope() to be called here.
        local_queue.send(op);
        
        scheduled(op);
        
        return true;
    }
    
    /**
     * This is used by the folder normalization routine to handle a situation where replay
     * operations have performed local work (and notified the client of changes) and are enqueued
     * waiting to perform the same operation on the server.  In normalization, the server reports
     * changes that need to be synchronized on the client.  If this change is written before the
     * enqueued replay operations execute, the potential exists to be unsynchronized.
     *
     * This call gives all enqueued remote replay operations a chance to cancel or update their
     * own state due to a writebehind operation.  See
     * ReplayOperation.query_local_writebehind_operation() for more information.
     */
    public bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
        Geary.EmailIdentifier id, Imap.EmailFlags? flags) {
        // Although any replay operation can cancel the writebehind operation, give all a chance to
        // see it as it may affect their internal state
        bool proceed = true;
        foreach (ReplayOperation replay_op in remote_queue.get_all()) {
            if (!replay_op.query_local_writebehind_operation(op, id, flags))
                proceed = false;
        }
        
        return proceed;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (is_closed)
            return;
        
        closing();
        
        // flush a ReplayClose operation down the pipe so all enqueued operations complete
        ReplayClose? close_op = new ReplayClose();
        if (!schedule(close_op))
            close_op = null;
        
        // mark as closed *after* scheduling, otherwise schedule() will fail
        is_closed = true;
        
        if (close_op != null)
            yield close_op.wait_for_ready_async(cancellable);
        
        closed();
    }
    
    private async void do_replay_local_async() {
        bool queue_running = true;
        while (queue_running) {
            ReplayOperation op;
            try {
                op = yield local_queue.recv_async();
            } catch (Error recv_err) {
                debug("Unable to receive next replay operation on local queue %s: %s", to_string(),
                    recv_err.message);
                
                break;
            }
            
            // If this is a Close operation, shut down the queue after processing it
            if (op is ReplayClose)
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
                            op.notify_ready(false, null);
                        break;
                        
                        case ReplayOperation.Status.CONTINUE:
                            // don't touch remote_enqueue; if already false, CONTINUE is treated as
                            // COMPLETED.
                            if (!remote_enqueue)
                                op.notify_ready(false, null);
                        break;
                        
                        case ReplayOperation.Status.FAILED:
                            // done
                            remote_enqueue = false;
                            op.notify_ready(true, null);
                        break;
                        
                        default:
                            assert_not_reached();
                    }
                } catch (Error replay_err) {
                    debug("Replay local error for %s on %s: %s", op.to_string(), to_string(),
                        replay_err.message);
                    
                    op.notify_ready(false, replay_err);
                    remote_enqueue = false;
                }
            }
            
            if (remote_enqueue) {
                remote_queue.send(op);
            } else {
                // all code paths to this point should have notified ready if not enqueuing for
                // next stage
                assert(op.notified);
            }
            
            if (local_execute)
                locally_executed(op, remote_enqueue);
            
            if (!remote_enqueue) {
                if (!op.failed && op.err == null)
                    completed(op);
                else
                    failed(op);
            }
        }
        
        Logging.debug(Logging.Flag.REPLAY, "ReplayQueue.do_replay_local_async %s exiting", to_string());
    }
    
    private async void do_replay_remote_async() {
        bool queue_running = true;
        while (queue_running) {
            // wait for the next operation ... do this *before* waiting for remote
            ReplayOperation op;
            try {
                op = yield remote_queue.recv_async();
            } catch (Error recv_err) {
                debug("Unable to receive next replay operation on remote queue %s: %s", to_string(),
                    recv_err.message);
                
                break;
            }
            
            // ReplayClose means this queue (and the folder) are closing, so handle errors a little
            // differently
            bool is_close_op = op is ReplayClose;
            
            // wait until the remote folder is opened (or returns false, in which case closed)
            bool folder_opened = false;
            try {
                if (yield remote_reporting_semaphore.wait_for_result_async())
                    folder_opened = true;
                else if (!is_close_op)
                    debug("Folder %s closed or failed to open, remote replay queue closing", to_string());
            } catch (Error remote_err) {
                debug("Error for remote queue waiting for remote %s to open, remote queue closing: %s", to_string(),
                    remote_err.message);
                
                // fall through
            }
            
            if (is_close_op)
                queue_running = false;
            
            remotely_executing(op);
            
            ReplayOperation.Status status = ReplayOperation.Status.FAILED;
            Error? remote_err = null;
            if (folder_opened) {
                try {
                    status = yield op.replay_remote_async();
                } catch (Error replay_err) {
                    debug("Replay remote error for %s on %s: %s", op.to_string(), to_string(),
                        replay_err.message);
                    
                    remote_err = replay_err;
                }
            } else if (!is_close_op) {
                remote_err = new EngineError.SERVER_UNAVAILABLE("Folder %s not available", to_string());
            }
            
            bool has_failed = !is_close_op && (status == ReplayOperation.Status.FAILED);
            
            // COMPLETED == CONTINUE, only FAILED or exception of interest here
            if (remote_err != null || has_failed) {
                try {
                    backing_out(op, has_failed, remote_err);
                    
                    yield op.backout_local_async();
                    
                    backed_out(op, has_failed, remote_err);
                } catch (Error backout_err) {
                    backout_failed(op, backout_err);
                }
            }
            
            // use the remote error (not the backout error) for the operation's completion
            // state
            op.notify_ready(has_failed, remote_err);
            
            remotely_executed(op);
            
            if (!op.failed && op.err == null)
                completed(op);
            else
                failed(op);
        }
        
        Logging.debug(Logging.Flag.REPLAY, "ReplayQueue.do_replay_remote_async %s exiting", to_string());
    }
    
    public string to_string() {
        return name;
    }
}

