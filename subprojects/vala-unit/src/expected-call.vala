/*
 * Copyright 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Represents an expected method call on a mock object.
 *
 * An instance of this object is returned when calling {@link
 * MockObject.expect_call}, and may be used to further specify
 * expectations, such that the mock method should throw a specific
 * error or return a specific value or object.
 */
public class ValaUnit.ExpectedCall : GLib.Object {


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
    internal GLib.Object?[]? expected_args = null;
    private GLib.Object?[]? called_args = null;

    internal unowned GLib.SourceFunc? async_callback = null;


    internal ExpectedCall(string name, GLib.Object?[]? args) {
        this.name = name;
        this.expected_args = args;
    }

    /** Sets the behaviour for an async call. */
    public ExpectedCall async_call(AsyncCallOptions behaviour) {
        this.async_behaviour = behaviour;
        return this;
    }

    /** Sets an object that the call should return. */
    public ExpectedCall returns_object(GLib.Object value) {
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
    public void async_resume() throws TestError {
        if (this.async_callback == null) {
            throw new TestError.FAILED(
                "Async call not called, could not resume"
            );
        }
        if (this.async_resumed) {
            throw new TestError.FAILED(
                "Async call already resumed"
            );
        }
        this.async_resumed = true;
        this.async_callback();
    }

    /** Determines if an argument was given in the specific position. */
    public T called_arg<T>(int pos) throws TestError {
        if (this.called_args == null || this.called_args.length < (pos + 1)) {
            throw new TestError.FAILED(
                "%s call argument %u, type %s, not present".printf(
                    this.name, pos, typeof(T).name()
                )
            );
        }
        if (!(this.called_args[pos] is T)) {
            throw new TestError.FAILED(
                "%s call argument %u not of type %s".printf(
                    this.name, pos, typeof(T).name()
                )
            );
        }
        return (T) this.called_args[pos];
    }

    internal void called(GLib.Object?[]? args) {
        this.was_called = true;
        this.called_args = args;
    }

}
