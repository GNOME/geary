/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.ReceiveReplayOperation {
    public string name;
    
    public ReceiveReplayOperation(string name) {
        this.name = name;
    }
    
    public abstract async void replay();
}

private class Geary.ReceiveReplayQueue {
    private class ReplayClose : ReceiveReplayOperation {
        public NonblockingSemaphore semaphore = new NonblockingSemaphore();
        
        public ReplayClose() {
            base ("Close");
        }
        
        public override async void replay() {
            try {
                semaphore.notify();
            } catch (Error err) {
                error("Unable to notify that replay queue is closed: %s", err.message);
            }
        }
    }
    
    private NonblockingMailbox<ReceiveReplayOperation> queue = new
        NonblockingMailbox<ReceiveReplayOperation>();
    private bool closed = false;
    private ReceiveReplayOperation? executing = null;
    
    public ReceiveReplayQueue() {
        do_process_queue.begin();
    }
    
    public void schedule(ReceiveReplayOperation op) {
        try {
            queue.send(op);
        } catch (Error err) {
            error("Unable to schedule operation on replay queue: %s", err.message);
        }
    }
    
    // NOTE: close_async() must not be called within another executing operation; close_async()
    // yields for its own operation to complete, which can never happen while inside another
    public async void close_async() throws EngineError {
        if (executing != null) {
            error("ReceiveReplayQueue.close_async() called from within another operation: %s",
                executing.name);
        }
        
        if (closed)
            throw new EngineError.ALREADY_CLOSED("Closed");
        
        closed = true;
        
        // flush a ReplayClose operation down the pipe so all enqueued operations complete
        ReplayClose replay_close = new ReplayClose();
        schedule(replay_close);
        try {
            yield replay_close.semaphore.wait_async();
        } catch (Error err) {
            error("Error waiting for receive replay queue to close: %s", err.message);
        }
    }
    
    private async void do_process_queue() {
        for (;;) {
            // if queue is empty and the ReplayQueue is closed, bail out; ReplayQueue cannot be
            // restarted
            if (queue.size == 0 && closed)
                break;
            
            try {
                assert(executing == null);
                executing = yield queue.recv_async();
            } catch (Error err) {
                error("Unable to receive next replay operation on queue: %s", err.message);
            }
            
            yield executing.replay();
            executing = null;
        }
    }
}

