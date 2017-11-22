/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Queues and asynchronously executes {@link AccountOperation} instances.
 *
 * Operations that are equal to any currently executing or currently
 * in the queue will not be re-queued.
 *
 * Errors thrown are reported to the user via the account's
 * `problem_report` signal.
 */
internal class Geary.ImapEngine.AccountProcessor : Geary.BaseObject {


    private static bool op_equal(AccountOperation a, AccountOperation b) {
        return a.equal_to(b);
    }

    /** Determines an operation is currently being executed. */
    public bool is_executing { get { return this.current_op != null; } }

    /** Returns the number of operations currently waiting in the queue. */
    public uint waiting { get { return this.queue.size; } }


    /** Fired when an error occurs processing an operation. */
    public signal void operation_error(AccountOperation op, Error error);


    private string id;

    private Nonblocking.Queue<AccountOperation> queue =
        new Nonblocking.Queue<AccountOperation>.fifo(op_equal);

    private AccountOperation? current_op = null;

    private Cancellable cancellable = new Cancellable();


    public AccountProcessor(string id) {
        this.id = id;
        this.queue.allow_duplicates = false;
        this.run.begin();
    }

    public void enqueue(AccountOperation op) {
        if (this.current_op == null || !op.equal_to(this.current_op)) {
            this.queue.send(op);
        }
    }

    public void stop() {
        this.cancellable.cancel();
        this.queue.clear();
    }

    private async void run() {
        while (!this.cancellable.is_cancelled()) {
            AccountOperation? op = null;
            try {
                op = yield this.queue.receive(this.cancellable);
            } catch (Error err) {
                // we've been cancelled, so bail out
                return;
            }

            if (op != null) {
                debug("%s: Executing operation: %s", id, op.to_string());
                this.current_op = op;
                try {
                    yield op.execute(this.cancellable);
                    op.succeeded();
                } catch (Error err) {
                    op.failed(err);
                    operation_error(op, err);
                }
                op.completed();
                this.current_op = null;
            }
        }
    }

}
