/*
 * Copyright (C) 2009 Julien Peeters
 * Copyright (C) 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 *  Julien Peeters <contact@julienpeeters.fr>
 *  Michael Gratton <mike@vee.net>
 */


public void assert_null(Object? actual, string? context = null)
    throws Error {
    if (actual != null) {
        print_assert(context ?? "Object is non-null", null);
        assert_not_reached();
    }
}

public void assert_non_null(Object? actual, string? context = null)
    throws Error {
    if (actual == null) {
        print_assert(context ?? "Object is null", null);
        assert_not_reached();
    }
}

public void assert_equal(Object expected, Object? actual, string? context = null)
    throws Error {
    if (expected != actual) {
        print_assert(context ?? "Objects are not equal", null);
        assert_not_reached();
    }
}

public void assert_string(string expected, string? actual, string? context = null)
    throws Error {
    if (expected != actual) {
        string a = expected;
        if (a.length > 32) {
            a = a[0:32] + "…";
        }
        string? b = actual;
        if (b != null) {
            if (b.length > 32) {
                b = b[0:32] + "…";
            }
        }
        if (b != null) {
            print_assert("Expected: \"%s\", was: \"%s\"".printf(a, b), context);
        } else {
            print_assert("Expected: \"%s\", was null".printf(a), context);
        }
        assert_not_reached();
    }
}

public void assert_null_string(string? actual, string? context = null)
    throws Error {
    if (actual != null) {
        string a = actual;
        if (a.length > 70) {
            a = a[0:70] + "…";
        }
        print_assert("Expected: null, was: \"%s\"".printf(a), context);
        assert_not_reached();
    }
}

public void assert_int(int expected, int actual, string? context = null)
    throws Error {
    if (expected != actual) {
        print_assert("Expected: %d, was: %d".printf(expected, actual), context);
        assert_not_reached();
    }
}

public void assert_int64(int64 expected, int64 actual, string? context = null)
    throws Error {
    if (expected != actual) {
        print_assert("Expected: %lld, was: %lld".printf(expected, actual), context);
        assert_not_reached();
    }
}

public void assert_double(double actual, double expected, double epsilon) {
    assert(actual + epsilon >= expected && actual - epsilon <= expected);
}

public void assert_uint(uint expected, uint actual, string? context = null)
    throws GLib.Error {
    if (expected != actual) {
        print_assert("Expected: %u, was: %u".printf(expected, actual), context);
        assert_not_reached();
    }
}

public void assert_true(bool condition, string? context = null)
    throws Error {
    if (!condition) {
        print_assert(context ?? "Expected true", null);
        assert_not_reached();
    }
}

public void assert_false(bool condition, string? context = null)
    throws Error {
    if (condition) {
        print_assert(context ?? "Expected false", null);
        assert_not_reached();
    }
}

public void assert_error(Error expected, Error? actual, string? context = null) {
    bool failed = false;
    if (actual == null) {
        print_assert(
            "Expected error: %s %i, was null".printf(
                expected.domain.to_string(), expected.code
            ),
            context
        );
        failed = true;
    } else if (expected.domain != actual.domain ||
               expected.code != actual.code) {
        print_assert(
            "Expected error: %s %i, was actually %s %i: %s".printf(
                expected.domain.to_string(),
                expected.code,
                actual.domain.to_string(),
                actual.code,
                actual.message
            ),
            context
        );
        failed = true;
    }

    if (failed) {
        assert_not_reached();
    }
}

// XXX this shadows GLib.assert_no_error since that doesn't work
public void assert_no_error(Error? err, string? context = null) {
    if (err != null) {
        print_assert(
            "Unexpected error: %s %i: %s".printf(
                err.domain.to_string(),
                err.code,
                err.message
            ),
            context
        );
        assert_not_reached();
    }
}

private inline void print_assert(string message, string? context) {
    string output = message;
    if (context != null) {
        output = "%s: %s".printf(context, output);
    }
    GLib.stderr.puts(output);
    GLib.stderr.putc('\n');
}

public void delete_file(File parent) throws GLib.Error {
    FileInfo info = parent.query_info(
        "standard::*",
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS
    );

    if (info.get_file_type () == FileType.DIRECTORY) {
        FileEnumerator enumerator = parent.enumerate_children(
            "standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS
        );

        info = null;
        while (((info = enumerator.next_file()) != null)) {
            delete_file(parent.get_child(info.get_name()));
        }
    }

    parent.delete();
}


/**
 * Allows non-async code to wait for async calls to be completed.
 *
 * To use instances of this class, call an async function or method
 * using the `begin()` form, passing {@link async_complete} as
 * completion argument (that is, the last argument):
 *
 * {{{
 *     var waiter = new AsyncResultWaiter();
 *     my_async_call.begin("foo", waiter.async_completion);
 * }}}
 *
 * Then, when you want to ensure the call is complete, pass the result
 * of calling {@link async_result} to its `end()` form:
 *
 * {{{
 *     my_async_call.end(waiter.async_result());
 * }}}
 *
 * This will block until the async call has completed.
 *
 * Note that {@link TestCase} exposes the same interface, so it is
 * usually easier to just call those when testing a single async call,
 * or multiple, non-interleaved async calls.
 *
 * This class is implemented as a FIFO queue of {@link
 * GLib.AsyncResult} instances, and thus can be used for waiting for
 * multiple calls. Note however the ordering depends on the order in
 * which the async calls being invoked are executed and are
 * completed. Thus if testing multiple interleaved async calls, you
 * should probably use an instance of this class per call.
 */
public class AsyncResultWaiter : GLib.Object {


    /** The main loop that is executed when waiting for async results. */
    public GLib.MainContext main_loop { get; construct set; }

    private GLib.AsyncQueue<GLib.AsyncResult> results =
        new GLib.AsyncQueue<GLib.AsyncResult>();


    /**
     * Constructs a new waiter.
     *
     * @param main_loop a main loop context to execute when waiting
     * for an async result
     */
    public AsyncResultWaiter(GLib.MainContext main_loop) {
        Object(main_loop: main_loop);
    }

    /**
     * The last argument of an async call to be tested.
     *
     * Records the given {@link GLib.AsyncResult}, adding it to the
     * internal FIFO queue. This method should be called as the
     * completion of an async call to be tested.
     *
     * To use it, pass as the last argument to the `begin()` form of
     * the async call:
     *
     * {{{
     *     var waiter = new AsyncResultWaiter();
     *     my_async_call.begin("foo", waiter.async_completion);
     * }}}
     */
    public void async_completion(GLib.Object? object,
                                 GLib.AsyncResult result) {
        this.results.push(result);
        // Notify the loop so that if async_result() has already been
        // called, that method won't block.
        this.main_loop.wakeup();
    }

    /**
     * Waits for async calls to complete, returning the most recent one.
     *
     * This returns the first {@link GLib.AsyncResult} from the
     * internal FIFO queue that has been provided by {@link
     * async_completion}. If none are available, it will pump the main
     * loop, blocking until one becomes available.
     *
     * To use it, pass its return value as the argument to the `end()`
     * call:
     *
     * {{{
     *     my_async_call.end(waiter.async_result());
     * }}}
     */
    public GLib.AsyncResult async_result() {
        GLib.AsyncResult? result = this.results.try_pop();
        while (result == null) {
            this.main_loop.iteration(true);
            result = this.results.try_pop();
        }
        return result;
    }

}

public abstract class TestCase : GLib.Object {


    /** GLib.File URI for resources in test/data. */
    public const string RESOURCE_URI = "resource:///org/gnome/GearyTest";


    private class SignalWaiter : Object {

        public bool was_fired = false;

        public void @callback(Object source) {
            was_fired = true;
        }
    }


    protected MainContext main_loop = MainContext.default();

    private GLib.TestSuite suite;
    private Adaptor[] adaptors = new Adaptor[0];
    private AsyncResultWaiter async_waiter;

    public delegate void TestMethod() throws Error;

	protected TestCase(string name) {
        this.suite = new GLib.TestSuite(name);
        this.async_waiter = new AsyncResultWaiter(this.main_loop);
    }

    public void add_test(string name, owned TestMethod test) {
        var adaptor = new Adaptor(name, (owned) test, this);
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

    public virtual void set_up() throws Error {
    }

    public virtual void tear_down() throws Error {
    }

    public GLib.TestSuite get_suite() {
        return this.suite;
    }

    /**
     * Calls the same method on the test case's default async waiter.
     *
     * @see AsyncResultWaiter.async_completion
     */
    protected void async_complete(AsyncResult result) {
        this.async_waiter.async_completion(null, result);
    }

    /**
     * Calls the same method on the test case's default async waiter.
     *
     * @see AsyncResultWaiter.async_completion
     */
    protected void async_complete_full(GLib.Object? object,
                                       AsyncResult result) {
        this.async_waiter.async_completion(object, result);
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
    protected bool wait_for_signal(Object source, string name, double timeout = 0.5) {
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

    private class Adaptor {

        public string name { get; private set; }
        private TestMethod test;
        private TestCase test_case;

        public Adaptor(string name,
                       owned TestMethod test,
                       TestCase test_case) {
            this.name = name;
            this.test = (owned) test;
            this.test_case = test_case;
        }

        public void set_up(void* fixture) {
            try {
                this.test_case.set_up();
            } catch (Error err) {
                assert_no_error(err);
            }
        }

        public void run(void* fixture) {
            try {
                this.test();
            } catch (Error err) {
                assert_no_error(err);
            }
        }

        public void tear_down(void* fixture) {
            try {
                this.test_case.tear_down();
            } catch (Error err) {
                assert_no_error(err);
            }
        }

    }

}
