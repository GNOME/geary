/*
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Denotes a dummy object that can be injected into code being tested.
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
public interface ValaUnit.MockObject : GLib.Object, TestAssertions {


    public static GLib.Object box_arg<T>(T value) {
        return new BoxArgument<T>(value);
    }

    public static GLib.Object int_arg(int value) {
        return new IntArgument(value);
    }

    public static GLib.Object uint_arg(uint value) {
        return new UintArgument(value);
    }

    protected abstract Gee.Queue<ExpectedCall> expected { get; set; }


    public ExpectedCall expect_call(string name, GLib.Object?[]? args = null) {
        ExpectedCall expected = new ExpectedCall(name, args);
        this.expected.offer(expected);
        return expected;
    }

    public void assert_expectations() throws GLib.Error {
        assert_true(this.expected.is_empty,
                    "%d expected calls not made".printf(this.expected.size));
        reset_expectations();
    }

    public void reset_expectations() {
        this.expected.clear();
    }

    protected bool boolean_call(string name,
                                GLib.Object?[] args,
                                bool default_return)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        return check_boolean_call(expected, default_return);
    }

    protected async bool boolean_call_async(string name,
                                            GLib.Object?[] args,
                                            bool default_return)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        if (async_call_yield(expected, this.boolean_call_async.callback)) {
            yield;
        }
        return check_boolean_call(expected, default_return);
    }

    protected R object_call<R>(string name,
                               GLib.Object?[] args,
                               R default_return)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        return check_object_call(expected, default_return);
    }

    protected async R object_call_async<R>(string name,
                                           GLib.Object?[] args,
                                           R default_return)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        if (async_call_yield(expected, this.object_call_async.callback)) {
            yield;
        }
        return check_object_call(expected, default_return);
    }

    protected R object_or_throw_call<R>(string name,
                                        GLib.Object?[] args,
                                        GLib.Error default_error)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        return check_object_or_throw_call(expected, default_error);
    }

    protected async R object_or_throw_call_async<R>(string name,
                                                    GLib.Object?[] args,
                                                    GLib.Error default_error)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        if (async_call_yield(expected, this.object_or_throw_call_async.callback)) {
            yield;
        }
        return check_object_or_throw_call(expected, default_error);
    }

    protected void void_call(string name, GLib.Object?[] args)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        check_for_exception(expected);
    }

    protected async void void_call_async(string name, GLib.Object?[] args)
        throws GLib.Error {
        ExpectedCall expected = call_made(name, args);
        if (async_call_yield(expected, this.void_call_async.callback)) {
            yield;
        }
        check_for_exception(expected);
    }

    private ExpectedCall call_made(string name, GLib.Object?[] args)
        throws GLib.Error {
        assert_false(this.expected.is_empty, "Unexpected call: %s".printf(name));

        ExpectedCall expected = (!) this.expected.poll();
        assert_equal(name, expected.name, "Unexpected call");
        if (expected.expected_args != null) {
            assert_args(args, expected.expected_args, "Call %s".printf(name));
        }

        expected.called(args);
        return expected;
    }

    private void assert_args(GLib.Object?[] actual_args,
                             GLib.Object?[] expected_args,
                             string context)
        throws GLib.Error {
        int args = 0;
        foreach (var expected in expected_args) {
            if (args >= actual_args.length) {
                break;
            }

            GLib.Object? actual = actual_args[args];
            string arg_context = "%s, argument #%d".printf(context, args++);

            if (expected is Argument) {
                assert_non_null(actual, arg_context);
                ((Argument) expected).assert((GLib.Object) actual, arg_context);
            } else if (expected != null) {
                var non_null_expected = (GLib.Object) expected;

                assert_non_null(actual, arg_context);
                var non_null_actual = (GLib.Object) actual;

                assert_equal(
                    non_null_expected.get_type(), non_null_actual.get_type(),
                    arg_context
                );
                assert_equal(
                    non_null_actual,
                    non_null_expected,
                    arg_context
                );
            } else {
                assert_null(actual, arg_context);

            }
        }

        assert_equal(
            actual_args.length,
            expected_args.length,
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
            return_value = ((GLib.Variant) expected.return_value).get_boolean();
        }
        return return_value;
    }

    private inline R check_object_call<R>(ExpectedCall expected,
                                          R default_return)
        throws GLib.Error {
        check_for_exception(expected);
        R return_object = default_return;
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
        return (!) expected.return_object;
    }

    private inline void check_for_exception(ExpectedCall expected)
        throws GLib.Error {
        if (expected.throw_error != null) {
            throw expected.throw_error;
        }
    }

}

private interface ValaUnit.Argument {

    public abstract void assert(GLib.Object object, string context)
        throws GLib.Error;

}

private class ValaUnit.BoxArgument<T> : GLib.Object, Argument, TestAssertions {

    private T value;

    internal BoxArgument(T value) {
        this.value = value;
    }

    public new void assert(GLib.Object object, string context)
        throws GLib.Error {
        assert_true(
            object is BoxArgument,
            "%s: Expected %s value".printf(context, this.get_type().name())
        );
        assert_true(this.value == ((BoxArgument<T>) object).value, context);
    }

}

private class ValaUnit.IntArgument : GLib.Object, Argument, TestAssertions {

    private int value;

    internal IntArgument(int value) {
        this.value = value;
    }

    public new void assert(GLib.Object object, string context)
        throws GLib.Error {
        assert_true(
            object is IntArgument, "%s: Expected int value".printf(context)
        );
        assert_equal(((IntArgument) object).value, this.value, context);
    }

}

private class ValaUnit.UintArgument : GLib.Object, Argument, TestAssertions {

    private uint value;

    internal UintArgument(uint value) {
        this.value = value;
    }

    public new void assert(GLib.Object object, string context)
        throws GLib.Error {
        assert_true(
            object is UintArgument, "%s: Expected uint value".printf(context)
        );
        assert_equal(((UintArgument) object).value, this.value, context);
    }

}
