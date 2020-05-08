/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Allows non-async code to wait for async calls to be completed.
 *
 * To use instances of this class, call an async function or method
 * using the `begin()` form, passing {@link async_completion} as
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
public class ValaUnit.AsyncResultWaiter : GLib.Object {


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
        return (GLib.AsyncResult) result;
    }

}
