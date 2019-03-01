/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ConversationOperationQueue : BaseObject {
    public bool is_processing { get; private set; default = false; }

    /** Tracks progress running operations in this queue. */
    public Geary.ProgressMonitor progress_monitor { get; private set; }

    private Geary.Nonblocking.Queue<ConversationOperation> mailbox
        = new Geary.Nonblocking.Queue<ConversationOperation>.fifo();
    private Geary.Nonblocking.Spinlock processing_done_spinlock
        = new Geary.Nonblocking.Spinlock();

    /** Fired when an error occurs executing an operation. */
    public signal void operation_error(ConversationOperation op, Error err);

    public ConversationOperationQueue(ProgressMonitor progress) {
        this.progress_monitor = progress;
    }

    public void clear() {
        mailbox.clear();
    }

    public void add(ConversationOperation op) {
        bool add_op = true;

        if (!op.allow_duplicates) {
            Type op_type = op.get_type();
            foreach (ConversationOperation other in this.mailbox.get_all()) {
                if (other.get_type() == op_type) {
                    add_op = false;
                    break;
                }
            }
        }

        if (add_op) {
            this.mailbox.send(op);
        }
    }

    public async void stop_processing_async(Cancellable? cancellable)
        throws Error {
        if (this.is_processing) {
            clear();
            add(new TerminateOperation());
            yield processing_done_spinlock.wait_async(cancellable);
        }
    }

    public async void run_process_async() {
        is_processing = true;

        for (;;) {
            ConversationOperation op;
            try {
                op = yield mailbox.receive();
            } catch (Error e) {
                debug("Error processing in conversation operation mailbox: %s", e.message);
                break;
            }
            if (op is TerminateOperation)
                break;

            if (!progress_monitor.is_in_progress)
                progress_monitor.notify_start();

            try {
                yield op.execute_async();
            } catch (Error err) {
                operation_error(op, err);
            }

            if (mailbox.size == 0)
                progress_monitor.notify_finish();
        }

        is_processing = false;
        processing_done_spinlock.blind_notify();
    }
}
