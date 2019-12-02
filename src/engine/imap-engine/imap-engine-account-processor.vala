/*
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
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
 * `problem_report` signal. Normally if an operation throws an error
 * it will not be re-queued, however if a network connection error
 * occurs the error will be suppressed and it will be re-attempted
 * once, to allow for the network dropping out mid-execution.
 */
internal class Geary.ImapEngine.AccountProcessor :
    Geary.BaseObject, Logging.Source {


    // Retry ops after network failures at least once before giving up
    private const int MAX_NETWORK_ERRORS = 1;


    private static bool op_equal(AccountOperation a, AccountOperation b) {
        return a.equal_to(b);
    }

    /** Determines an operation is currently being executed. */
    public bool is_executing { get { return this.current_op != null; } }

    /** Returns the number of operations currently waiting in the queue. */
    public uint waiting { get { return this.queue.size; } }


    /** Fired when an error occurs processing an operation. */
    public signal void operation_error(AccountOperation op, Error error);

    /** {@inheritDoc} */
    public Logging.Flag logging_flags {
        get; protected set; default = Logging.Flag.ALL;
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;


    private bool is_running;

    private Nonblocking.Queue<AccountOperation> queue =
        new Nonblocking.Queue<AccountOperation>.fifo(op_equal);

    private AccountOperation? current_op = null;
    private GLib.Cancellable? op_cancellable = null;


    public AccountProcessor() {
        this.queue.allow_duplicates = false;
        this.is_running = true;
        this.run.begin();
    }

    public void enqueue(AccountOperation op) {
        if (this.current_op == null || !op.equal_to(this.current_op)) {
            this.queue.send(op);
        }
    }

    public void stop() {
        this.is_running = false;
        if (this.op_cancellable != null) {
            this.op_cancellable.cancel();
            this.op_cancellable = null;
        }
        this.queue.clear();
    }

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "queued: %d",
            this.queue.size
        );
    }

    /** Sets the processor's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    private async void run() {
        while (this.is_running) {
            this.op_cancellable = new GLib.Cancellable();

            AccountOperation? op = null;
            try {
                op = yield this.queue.receive(this.op_cancellable);
            } catch (Error err) {
                // we've been cancelled, so bail out
                return;
            }

            if (op != null) {
                debug("Executing operation: %s", op.to_string());
                this.current_op = op;

                Error? op_error = null;
                int network_errors = 0;
                while (op_error == null) {
                    try {
                        yield op.execute(this.op_cancellable);
                        op.succeeded();
                        break;
                    } catch (ImapError err) {
                        if (err is ImapError.NOT_CONNECTED &&
                            ++network_errors <= MAX_NETWORK_ERRORS) {
                            debug(
                                "Retrying operation due to network error: %s",
                                err.message
                            );
                        } else {
                            op_error = err;
                        }
                    } catch (Error err) {
                        op_error = err;
                    }
                }

                if (op_error != null) {
                    op.failed(op_error);
                    operation_error(op, op_error);
                }
                op.completed();

                this.current_op = null;
                this.op_cancellable = null;
            }
        }
    }

}
