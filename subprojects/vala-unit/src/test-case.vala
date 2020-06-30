/*
 * Copyright © 2009 Julien Peeters
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 *
 * Author(s):
 *  Julien Peeters <contact@julienpeeters.fr>
 *  Michael Gratton <mike@vee.net>
 */


/**
 * The primary class for creating unit tests.
 *
 * A test case is a collection of related test methods.
 *
 * To create and run tests, extend this class with one or more test
 * methods that implement {@link TestMethod} and call {@link add_test}
 * for each. These may then be added to the root {@link
 * GLib.TestSuite} or a child test suite of the root, then executed by
 * calling {@link GLib.Test.run}.
 *
 * To make test assertions in test methods, call the `assert` methods
 * on this class instead of those defined by GLib.
 */
public abstract class ValaUnit.TestCase : GLib.Object, TestAssertions {


    /** The delegate that test methods must implement. */
    public delegate void TestMethod() throws GLib.Error;


    private class SignalWaiter : Object {

        public bool was_fired = false;

        public void @callback(Object source) {
            was_fired = true;
        }
    }


    /** The name of this test case. */
    public string name { get; private set; }

    /** The collection of GLib tests defined by this test case. */
    public GLib.TestSuite suite { get; private set; }

    /** Main loop context for this test case. */
    protected GLib.MainContext main_loop {
        get; private set; default = GLib.MainContext.default();
    }

    private TestAdaptor[] adaptors = new TestAdaptor[0];
    private AsyncResultWaiter async_waiter;


    /**
     * Constructs a new named test case.
     *
     * The given name is used as the name of the GLib test suite that
     * collects all tests.
     */
	protected TestCase(string name) {
        this.name = name;
        this.suite = new GLib.TestSuite(name);
        this.async_waiter = new AsyncResultWaiter(this.main_loop);
    }

    /**
     * Test case fixture set-up method.
     *
     * This method is called prior to running a test method.
     *
     * Test cases should override this method when they require test
     * fixtures to be initialised before a test is run.
     */
    public virtual void set_up() throws GLib.Error {
        // no-op
    }

    /**
     * Test case fixture set-up method.
     *
     * This method is called after a test method is successfully run.
     *
     * Test cases should override this method when they require test
     * fixtures to be destroyed after a test is run.
     */
    public virtual void tear_down() throws GLib.Error {
        // no-op
    }

    /**
     * Adds a test method to be executed as part of this test case.
     *
     * Adding a test method add it to {@link suite} with the given
     * name, ensuring the {@link set_up}, test, and {@link tear_down}
     * methods are executed when the test suite is run.
     */
    protected void add_test(string name, owned TestMethod test) {
        var adaptor = new TestAdaptor(name, (owned) test, this);
        this.adaptors += adaptor;

        this.suite.add(
            new GLib.TestCase(
                adaptor.name,
                adaptor.set_up,
                adaptor.run,
                adaptor.tear_down
            )
        );
    }

    /**
     * Calls the same method on the test case's default async waiter.
     *
     * @see AsyncResultWaiter.async_result
     */
    protected AsyncResult async_result() {
        return this.async_waiter.async_result();
    }

    /**
     * Calls the same method on the test case's default async waiter.
     *
     * @see AsyncResultWaiter.async_completion
     */
    protected void async_completion(GLib.Object? object,
                                    AsyncResult result) {
        this.async_waiter.async_completion(object, result);
    }

    /**
     * Waits for a mock object's call to be completed.
     *
     * This method busy waits on the test's main loop until either
     * until {@link ExpectedCall.was_called} is true, or until the
     * given timeout in seconds has occurred.
     *
     * Returns //true// if the call was made, or //false// if the
     * timeout was reached.
     */
    protected bool wait_for_call(ExpectedCall call, double timeout = 1.0) {
        GLib.Timer timer = new GLib.Timer();
        timer.start();
        while (!call.was_called && timer.elapsed() < timeout) {
            this.main_loop.iteration(false);
        }
        return call.was_called;
    }

    /**
     * Waits for an object's signal to be fired.
     *
     * This method busy waits on the test's main loop until either
     * until the object emits the named signal, or until the given
     * timeout in seconds has occurred.
     *
     * Returns //true// if the signal was fired, or //false// if the
     * timeout was reached.
     */
    protected bool wait_for_signal(GLib.Object source,
                                   string name,
                                   double timeout = 0.5) {
        SignalWaiter handler = new SignalWaiter();
        ulong id = GLib.Signal.connect_swapped(
            source, name, (GLib.Callback) handler.callback, handler
        );

        GLib.Timer timer = new GLib.Timer();
        timer.start();
        while (!handler.was_fired && timer.elapsed() < timeout) {
            this.main_loop.iteration(false);
        }

        source.disconnect(id);
        return handler.was_fired;
    }

    /**
     * Immediately causes the current test to fail.
     *
     * Throws a {@link TestError.FAILED} with the given reason,
     * terminating the test.
     */
    protected void fail(string? message = null) throws TestError.FAILED {
        throw new TestError.FAILED(
            message != null ? (string) message : "Test failed"
        );
    }

    /**
     * Immediately skips the rest of the current test.
     *
     * Throws a {@link TestError.SKIPPED} with the given reason,
     * terminating the test.
     */
    protected void skip(string? message = null) throws TestError.SKIPPED {
        throw new TestError.SKIPPED(
            message != null ? (string) message : "Test skipped"
        );
    }

}
