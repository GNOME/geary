/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private interface Argument {

    public abstract void assert(Object object) throws Error;

}

private class BoxArgument<T> : Object, Argument {

    private T value;

    internal BoxArgument(T value) {
        this.value = value;
    }

    public new void assert(Object object) throws Error {
        assert_true(
            object is BoxArgument,
            "Expected %s value".printf(this.get_type().name())
        );
        assert_true(this.value == ((BoxArgument<T>) object).value);
    }

        }

private class IntArgument : Object, Argument {

    private int value;

    internal IntArgument(int value) {
        this.value = value;
    }

    public new void assert(Object object) throws Error {
        assert_true(object is IntArgument, "Expected int value");
        assert_int(this.value, ((IntArgument) object).value);
    }

}

private class UintArgument : Object, Argument {

    private uint value;

    internal UintArgument(uint value) {
        this.value = value;
    }

    public new void assert(Object object) throws Error {
        assert_true(object is UintArgument, "Expected uint value");
        assert_uint(this.value, ((UintArgument) object).value);
    }

}

/**
 * Represents an expected method call on a mock object.
 *
 * An instance of this object is returned when calling {@link
 * Mock.Object.expect_call}, and may be used to further specify
 * expectations, such that the mock method should throw a specific
 * error or return a specific value or object.
 */
public class ExpectedCall : GLib.Object {


    /** Options for handling async calls. */
    public enum AsyncCallOptions {

        /** Check and return from the expected call immediately. */
        CONTINUE,

        /**
         * Check and return from the expected call when idle.
         *
         * This will yield when the call is made, being resuming when
         * idle.
         */
        CONTINUE_AT_IDLE,

        /**
         * Check and return from the expected call when requested.
         *
         * This will yield when the call is made, resuming when {@link
         * ExpectedCall.async_resume} is called.
         */
        PAUSE;

    }


    /** The name of the expected call. */
    public string name { get; private set; }

    /** Determines how async calls are handled. */
    public AsyncCallOptions async_behaviour {
        get; private set; default = CONTINUE;
    }

    /** The error to be thrown by the call, if any. */
    public GLib.Error? throw_error { get; private set; default = null; }

    /** An object to be returned by the call, if any. */
    public GLib.Object? return_object { get; private set; default = null; }

    /** A value to be returned by the call, if any. */
    public GLib.Variant? return_value { get; private set; default = null; }

    /** Determines if the call has been made or not. */
    public bool was_called { get; private set; default = false; }

    /** Determines if an async call has been resumed or not. */
    public bool async_resumed { get; private set; default = false; }

    // XXX Arrays can't be GObject properties :(
    internal GLib.Object[]? expected_args = null;
    private GLib.Object[]? called_args = null;

    internal unowned GLib.SourceFunc? async_callback = null;


    internal ExpectedCall(string name, Object[]? args) {
        this.name = name;
        this.expected_args = args;
    }

    /** Sets the behaviour for an async call. */
    public ExpectedCall async_call(AsyncCallOptions behaviour) {
        this.async_behaviour = behaviour;
        return this;
    }

    /** Sets an object that the call should return. */
    public ExpectedCall returns_object(Object value) {
        this.return_object = value;
        return this;
    }

    /** Sets a bool value that the call should return. */
    public ExpectedCall returns_boolean(bool value) {
        this.return_value = new GLib.Variant.boolean(value);
        return this;
    }

    /** Sets an error that the cal should throw. */
    public ExpectedCall @throws(GLib.Error err) {
        this.throw_error = err;
        return this;
    }

    /**
     * Resumes an async call that has been paused.
     *
     * Throws an assertion error if the call has not yet been called
     * or has not been paused.
     */
    public void async_resume() throws GLib.Error {
        assert_true(
            this.async_callback != null,
            "Async call not called, could not resume"
        );
        assert_false(
            this.async_resumed,
            "Async call already resumed"
        );
        this.async_resumed = true;
        this.async_callback();
    }

    /** Determines if an argument was given in the specific position. */
    public T called_arg<T>(int pos) throws GLib.Error {
        assert_true(
            this.called_args != null && this.called_args.length >= (pos + 1),
            "%s call argument %u, type %s, not present".printf(
                this.name, pos, typeof(T).name()
            )
        );
        assert_true(
            this.called_args[pos] is T,
            "%s call argument %u not of type %s".printf(
                this.name, pos, typeof(T).name()
            )
        );
        return (T) this.called_args[pos];
    }

    internal void called(Object[]? args) {
        this.was_called = true;
        this.called_args = args;
    }

}


/**
 * Denotes a class that is injected into code being tested.
 *
 * Mock objects are unit testing fixtures that are used to provide
 * instances of specific classes or interfaces which are required by
 * the code being tested. For example, if an object being tested
 * requires certain objects to be passed in via its constructor or as
 * arguments of method calls and uses these to implement its
 * behaviour, mock objects that fulfill these requirements can be used.
 *
 * Mock objects provide a means of both ensuring code being tested
 * makes expected method calls with expected arguments on its
 * dependencies, and a means of orchestrating the return value and
 * exceptions raised when these methods are called, if any.
 *
 * To specify a specific method should be called on a mock object,
 * call {@link expect_call} with the name of the method and optionally
 * the arguments that are expected. The returned {@link ExpectedCall}
 * object can be used to specify any exception or return values for
 * the method. After executing the code being tested, call {@link
 * assert_expectations} to ensure that the actual calls made matched
 * those expected.
 */
public interface MockObject : GLib.Object {


    public static Object box_arg<T>(T value) {
        return new BoxArgument<T>(value);
    }

    public static Object int_arg(int value) {
        return new IntArgument(value);
    }

    public static Object uint_arg(uint value) {
        return new UintArgument(value);
    }

    protected abstract Gee.Queue<ExpectedCall> expected { get; set; }


    public ExpectedCall expect_call(string name, Object[]? args = null) {
        ExpectedCall expected = new ExpectedCall(name, args);
        this.expected.offer(expected);
        return expected;
    }

    public void assert_expectations() throws Error {
        assert_true(this.expected.is_empty,
                    "%d expected calls not made".printf(this.expected.size));
        reset_expectations();
    }

    public void reset_expectations() {
        this.expected.clear();
    }

    protected bool boolean_call(string name, Object[] args, bool default_return)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        return check_boolean_call(expected, default_return);
    }

    protected async bool boolean_call_async(string name,
                                            Object[] args,
                                            bool default_return)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        if (async_call_yield(expected, this.boolean_call_async.callback)) {
            yield;
        }
        return check_boolean_call(expected, default_return);
    }

    protected R object_call<R>(string name, Object[] args, R default_return)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        return check_object_call(expected, default_return);
    }

    protected async R object_call_async<R>(string name,
                                           Object[] args,
                                           R default_return)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        if (async_call_yield(expected, this.object_call_async.callback)) {
            yield;
        }
        return check_object_call(expected, default_return);
    }

    protected R object_or_throw_call<R>(string name,
                                        Object[] args,
                                        GLib.Error default_error)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        return check_object_or_throw_call(expected, default_error);
    }

    protected async R object_or_throw_call_async<R>(string name,
                                                    Object[] args,
                                                    GLib.Error default_error)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        if (async_call_yield(expected, this.object_or_throw_call_async.callback)) {
            yield;
        }
        return check_object_or_throw_call(expected, default_error);
    }

    protected void void_call(string name, Object[] args) throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        check_for_exception(expected);
    }

    protected async void void_call_async(string name, Object[] args)
        throws GLib.Error {
        ExpectedCall? expected = call_made(name, args);
        if (async_call_yield(expected, this.void_call_async.callback)) {
            yield;
        }
        check_for_exception(expected);
    }

    private ExpectedCall? call_made(string name, Object[] args) throws Error {
        assert_false(this.expected.is_empty, "Unexpected call: %s".printf(name));

        ExpectedCall expected = this.expected.poll();
        assert_string(expected.name, name, "Unexpected call");
        if (expected.expected_args != null) {
            assert_args(expected.expected_args, args, "Call %s".printf(name));
        }

        expected.called(args);
        return expected;
    }

    private void assert_args(Object[]? expected_args, Object[]? actual_args, string context)
        throws Error {
        int args = 0;
        foreach (Object expected in expected_args) {
            if (args >= actual_args.length) {
                break;
            }

            Object actual = actual_args[args];
            string arg_context = "%s, argument #%d".printf(context, args++);

            if (expected is Argument) {
                ((Argument) expected).assert(actual);
            } else if (expected != null) {
                assert_true(
                    actual != null,
                    "%s: Expected %s, actual is null".printf(
                        arg_context, expected.get_type().name()
                    )
                );
                assert_true(
                    expected.get_type() == actual.get_type(),
                    "%s: Expected %s, actual: %s".printf(
                        arg_context,
                        expected.get_type().name(),
                        actual.get_type().name()
                    )
                );
                assert_equal(
                    expected, actual,
                    "%s: object value".printf(arg_context)
                );
            } else {

            }
        }

        assert_int(
            expected_args.length, actual_args.length,
            "%s: argument list length".printf(context)
        );
    }

    private bool async_call_yield(ExpectedCall expected,
                                  GLib.SourceFunc @callback) {
        var @yield = false;
        if (expected.async_behaviour != CONTINUE) {
            expected.async_callback = @callback;
            if (expected.async_behaviour == CONTINUE_AT_IDLE) {
                GLib.Idle.add(() => {
                        try {
                            expected.async_resume();
                        } catch (GLib.Error err) {
                            critical(
                                "Async call already resumed: %s", err.message
                            );
                        }
                        return GLib.Source.REMOVE;
                    });
            }
            @yield = true;
        }
        return @yield;
    }

    private inline bool check_boolean_call(ExpectedCall expected,
                                           bool default_return)
        throws GLib.Error {
        check_for_exception(expected);
        bool return_value = default_return;
        if (expected.return_value != null) {
            return_value = expected.return_value.get_boolean();
        }
        return return_value;
    }

    private inline R check_object_call<R>(ExpectedCall expected,
                                          R default_return)
        throws GLib.Error {
        check_for_exception(expected);
        R? return_object = default_return;
        if (expected.return_object != null) {
            return_object = (R) expected.return_object;
        }
        return return_object;
    }

    private inline R check_object_or_throw_call<R>(ExpectedCall expected,
                                                   GLib.Error default_error)
        throws GLib.Error {
        check_for_exception(expected);
        if (expected.return_object == null) {
            throw default_error;
        }
        return expected.return_object;
    }

    private inline void check_for_exception(ExpectedCall expected)
        throws GLib.Error {
        if (expected.throw_error != null) {
            throw expected.throw_error;
        }
    }

}
