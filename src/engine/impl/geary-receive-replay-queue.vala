/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.ReceiveReplayOperation {
    private string name;
    
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
    
    public async void close_async() throws EngineError {
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
            
            ReceiveReplayOperation op;
            try {
                op = yield queue.recv_async();
            } catch (Error err) {
                error("Unable to receive next replay operation on queue: %s", err.message);
            }
            
            yield op.replay();
        }
    }
}

