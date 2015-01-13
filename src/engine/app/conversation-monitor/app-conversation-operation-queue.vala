/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ConversationOperationQueue : BaseObject {
    public bool is_processing { get; private set; default = false; }
    public Geary.SimpleProgressMonitor progress_monitor { get; private set; default = 
        new Geary.SimpleProgressMonitor(Geary.ProgressType.ACTIVITY); }
    
    private Geary.Nonblocking.Mailbox<ConversationOperation> mailbox
        = new Geary.Nonblocking.Mailbox<ConversationOperation>();
    private Geary.Nonblocking.Spinlock processing_done_spinlock
        = new Geary.Nonblocking.Spinlock();
    
    public void clear() {
        mailbox.clear();
    }
    
    public void add(ConversationOperation op) {
        // There should only ever be one FillWindowOperation at a time.
        FillWindowOperation? fill_op = op as FillWindowOperation;
        if (fill_op != null) {
            Gee.Collection<ConversationOperation> removed
                = mailbox.revoke_matching(o => o is FillWindowOperation);
            
            // If there were any "insert" fill window ops, preserve that flag,
            // as otherwise we might miss some data.
            if (!fill_op.is_insert) {
                foreach (ConversationOperation removed_op in removed) {
                    FillWindowOperation? removed_fill = removed_op as FillWindowOperation;
                    assert(removed_fill != null);
                    
                    if (removed_fill.is_insert) {
                        fill_op.is_insert = true;
                        break;
                    }
                }
            }
        }
        
        mailbox.send(op);
    }
    
    public async void stop_processing_async(Cancellable? cancellable) {
        clear();
        add(new TerminateOperation());
        
        try {
            yield processing_done_spinlock.wait_async(cancellable);
        } catch (Error e) {
            debug("Error waiting for conversation operation queue to finish processing: %s",
                e.message);
        }
    }
    
    public async void run_process_async() {
        is_processing = true;
        
        for (;;) {
            ConversationOperation op;
            try {
                op = yield mailbox.recv_async();
            } catch (Error e) {
                debug("Error processing in conversation operation mailbox: %s", e.message);
                break;
            }
            if (op is TerminateOperation)
                break;
            
            if (!progress_monitor.is_in_progress)
                progress_monitor.notify_start();
            
            yield op.execute_async();
            
            if (mailbox.size == 0)
                progress_monitor.notify_finish();
        }
        
        is_processing = false;
        processing_done_spinlock.blind_notify();
    }
}
