/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.SendReplayOperation {
    public Error? error { get; private set; default = null; }
    
    private NonblockingSemaphore semaphore = new NonblockingSemaphore();
    private string name;
    
    public SendReplayOperation(string name) {
        this.name = name;
    }
    
    // Used by grandchild classes that can't call c'tor directly.
    public void set_name(string name) {
        this.name = name;
    }
    
    /**
     * Runs the local operation.
     * Returns true if the operation is complete, or false if a call to
     * replay_remote() is also needed.
     */
    public abstract async bool replay_local() throws Error;
    
    /**
     * Runs the remote operation.
     * Returns true if the operation is complete, or false if the remote operation
     * didn't complete successfully; in that case, backout_local() will be called.
     */
    public abstract async bool replay_remote() throws Error;
    
    /**
     * Backs out the local operation.
     * This is effectively an "undo" for when the remote operation failed.
     */
    public virtual async void backout_local() throws Error {}
    
    /**
     * Waits until the operation is ready.
     * On a read, this should wait until the entire operation completes.
     * On a write, this should wait until the local operation completes.
     *
     * To trigger this, call set_ready() with either a null or an Error.  Either will
     * trigger completion, if an error is passed in this function will throw that error.
     */
    public async void wait_for_ready() throws Error {
        yield semaphore.wait_async();
        if (error != null)
            throw error;
    }
    
    // See the comments on wait_for_ready() on how to use this function.
    internal void set_ready(Error? error) {
        this.error = error;
        try {
            semaphore.notify();
        } catch (Error e) {
            debug("Unable to compelte send replay queue operation [%s] error: %s", name, e.message);
        }
    }
}

private class Geary.SendReplayQueue {
    private class ReplayClose: Geary.SendReplayOperation {
        public ReplayClose() {
            base ("Close");
        }
        
        public override async bool replay_local() throws Error {
            return false;
        }
        
        public override async bool replay_remote() throws Error {
            return true;
        }
        
        public override async void backout_local() {}
    }
    
    private NonblockingMailbox<SendReplayOperation> local_queue = new
        NonblockingMailbox<SendReplayOperation>();
    private NonblockingMailbox<SendReplayOperation> remote_queue = new
        NonblockingMailbox<SendReplayOperation>();
    
    private bool closed = false;
    
    // Signals an operation has failedand the failure was non-recoverable.
    public signal void replay_failed(SendReplayOperation op, Error? fatal_error);
    
    public SendReplayQueue() {
        do_process_local_queue.begin();
        do_process_remote_queue.begin();
    }
    
    public void schedule(SendReplayOperation op) {
        try {
            local_queue.send(op);
        } catch (Error err) {
            error("Unable to schedule operation on replay queue: %s", err.message);
        }
    }
    
    public async void close_async() throws EngineError {
        if (closed)
            throw new EngineError.ALREADY_CLOSED("Closed");
        
        closed = true;
        
        // flush a ReplayClose operation down the pipe so all enqueued operations complete
        ReplayClose replay_close = new ReplayClose();
        schedule(replay_close);
        try {
            yield replay_close.wait_for_ready();
        } catch (Error err) {
            error("Error waiting for replay queue to close: %s", err.message);
        }
    }
    
    private async void do_process_local_queue() {
        for (;;) {
            if (local_queue.size == 0 && closed)
                break;
            
            SendReplayOperation op;
            try {
                op = yield local_queue.recv_async();
            } catch (Error err) {
                error("Unable to receive next replay operation on queue: %s", err.message);
            }
            
            bool completed = false;
            try {
                completed = yield op.replay_local();
            } catch (Error e) {
                debug("Replay local error: %s", e.message);
                op.set_ready(e);
                
                continue;
            }
            
            if (!completed) {
                try {
                    remote_queue.send(op);
                } catch (Error err) {
                    error("Unable to schedule operation on remote replay queue: %s", err.message);
                }
            } else {
                op.set_ready(null);
            }
        }
    }
    
    private async void do_process_remote_queue() {
        for (;;) {
            if (remote_queue.size == 0 && closed)
                break;
            
            SendReplayOperation op;
            try {
                op = yield remote_queue.recv_async();
            } catch (Error err) {
                error("Unable to receive next replay operation on queue: %s", err.message);
            }
            
            bool completed = false;
            Error? remote_error = null;
            try {
                completed = yield op.replay_remote();
            } catch (Error e) {
                debug("Error: could not replay remote");
                remote_error = e;
            }
            
            if (op.error != null || !completed) {
                try {
                    yield op.backout_local();
                } catch (Error e) {
                    replay_failed(op, e);
                    op.set_ready(remote_error);
                    
                    continue;
                }
                
                // Signal that a recovery happened.
                replay_failed(op, null);
            }
            
            op.set_ready(null);
        }
    }
}

