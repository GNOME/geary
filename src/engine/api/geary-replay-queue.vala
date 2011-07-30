/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.ReplayOperation {
    private string name;
    
    public ReplayOperation(string name) {
        this.name = name;
    }
    
    public abstract async void replay();
}

private class Geary.ReplayQueue {
    private class ReplayClose : ReplayOperation {
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
    
    private NonblockingMailbox<ReplayOperation> queue = new NonblockingMailbox<ReplayOperation>();
    private bool closed = false;
    
    public ReplayQueue() {
        do_process_queue.begin();
    }
    
    public void schedule(ReplayOperation op) {
        try {
            queue.send(op);
        } catch (Error err) {
            error("Unable to schedule operation on replay queue: %s", err.message);
        }
    }
    
    public async void close_async() throws EngineError {
        if (closed)
            throw new EngineError.CLOSED("Closed");
        
        closed = true;
        
        // flush a ReplayClose operation down the pipe so all enqueued operations complete
        ReplayClose replay_close = new ReplayClose();
        schedule(replay_close);
        try {
            yield replay_close.semaphore.wait_async();
        } catch (Error err) {
            error("Error waiting for replay queue to close: %s", err.message);
        }
    }
    
    private async void do_process_queue() {
        for (;;) {
            // if queue is empty and the ReplayQueue is closed, bail out; ReplayQueue cannot be
            // restarted
            if (queue.size == 0 && closed)
                break;
            
            ReplayOperation op;
            try {
                op = yield queue.recv_async();
            } catch (Error err) {
                error("Unable to receive next replay operation on queue: %s", err.message);
            }
            
            yield op.replay();
        }
    }
}

