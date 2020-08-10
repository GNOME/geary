/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

errordomain AccountProcessorTestError {
    TEST;
}

public class Geary.ImapEngine.AccountProcessorTest : TestCase {


    public class TestOperation : AccountOperation {

        public bool throw_error = false;
        public bool wait_for_cancel = false;
        public bool execute_called = false;

        private Nonblocking.Spinlock spinlock = new Nonblocking.Spinlock();

        internal TestOperation(Geary.Account account) {
            base(account);
        }

        public override async void execute(Cancellable cancellable)
            throws Error {
            this.execute_called = true;
            if (this.wait_for_cancel) {
                yield this.spinlock.wait_async(cancellable);
            }
            if (this.throw_error) {
                throw new AccountProcessorTestError.TEST("Failed");
            }
        }

    }


    public class OtherOperation : TestOperation {

        internal OtherOperation(Geary.Account account) {
            base(account);
        }

    }


    private AccountProcessor? processor = null;
    private Geary.Account? account = null;
    private Geary.AccountInformation? info = null;
    private uint succeeded;
    private uint failed;
    private uint completed;


    public AccountProcessorTest() {
        base("Geary.ImapEngine.AccountProcessorTest");
        add_test("success", success);
        add_test("failure", failure);
        add_test("duplicate", duplicate);
        add_test("stop", stop);
    }

    public override void set_up() {
        this.info = new Geary.AccountInformation(
            "test-info",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
        this.account = new Mock.Account(this.info);
        this.processor = new AccountProcessor();

        this.succeeded = 0;
        this.failed = 0;
        this.completed = 0;
    }

    public override void tear_down() {
        this.processor.stop();
        this.processor = null;

        this.account = null;
        this.info = null;

        this.succeeded = 0;
        this.failed = 0;
        this.completed = 0;
    }

    public void success() throws Error {
        TestOperation op = setup_operation(new TestOperation(this.account));

        this.processor.enqueue(op);
        assert(this.processor.waiting == 1);

        execute_all();

        assert(op.execute_called);
        assert(this.succeeded == 1);
        assert(this.failed == 0);
        assert(this.completed == 1);
    }

    public void failure() throws Error {
        TestOperation op = setup_operation(new TestOperation(this.account));
        op.throw_error = true;

        AccountOperation? error_op = null;
        Error? error = null;
        this.processor.operation_error.connect((proc, op, err) => {
                error_op = op;
                error = err;
            });

        this.processor.enqueue(op);
        execute_all();

        assert(this.succeeded == 0);
        assert(this.failed == 1);
        assert(this.completed == 1);
        assert(error_op == op);
        assert(error is AccountProcessorTestError.TEST);
    }

    public void duplicate() throws Error {
        TestOperation op1 = setup_operation(new TestOperation(this.account));
        TestOperation op2 = setup_operation(new TestOperation(this.account));
        TestOperation op3 = setup_operation(new OtherOperation(this.account));

        this.processor.enqueue(op1);
        this.processor.enqueue(op2);
        assert(this.processor.waiting == 1);

        this.processor.enqueue(op3);
        assert(this.processor.waiting == 2);
    }

    public void stop() throws Error {
        TestOperation op1 = setup_operation(new TestOperation(this.account));
        op1.wait_for_cancel = true;
        TestOperation op2 = setup_operation(new OtherOperation(this.account));

        this.processor.enqueue(op1);
        this.processor.enqueue(op2);

        while (!this.processor.is_executing) {
            this.main_loop.iteration(true);
        }

        this.processor.stop();

        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        assert(!this.processor.is_executing);
        assert(this.processor.waiting == 0);
        assert(this.succeeded == 0);
        assert(this.failed == 1);
        assert(this.completed == 1);
    }

    private TestOperation setup_operation(TestOperation op) {
        op.succeeded.connect(() => {
                this.succeeded++;
            });
        op.failed.connect(() => {
                this.failed++;
            });
        op.completed.connect(() => {
                this.completed++;
            });
        return op;
    }

    private void execute_all() {
        while (this.processor.is_executing || this.processor.waiting > 0) {
            this.main_loop.iteration(true);
        }
    }
}
