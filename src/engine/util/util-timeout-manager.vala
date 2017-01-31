/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Executes a function after a certain period of time has elapsed.
 *
 * This class is a convenience API for the GLib main loop and source
 * infrastructure, automatically performing cleanup when destroyed.
 *
 * Note this class is not thread safe and should only be invoked from
 * the main loop.
 */
public class Geary.TimeoutManager : BaseObject {


    /** Specifies the priority the timeout should be given. */
    public enum Priority {
        HIGH = GLib.Priority.HIGH,
        DEFAULT = GLib.Priority.DEFAULT,
        HIGH_IDLE = GLib.Priority.HIGH_IDLE,
        DEFAULT_IDLE = GLib.Priority.DEFAULT_IDLE,
        LOW = GLib.Priority.LOW;
    }

    /** Specifies if the timeout should fire once or continuously. */
    public enum Repeat { ONCE, FOREVER; }

    /** The timeout callback function prototype. */
    public delegate void TimeoutFunc(TimeoutManager manager);


    /** Determines if {@link interval} represent seconds. */
    public bool use_seconds;

    /** The interval after which the timeout is fired, in seconds or milliseconds */
    public uint interval;

    /** Determines if this timeout will continue to fire after the first time. */
    public Repeat repetition = Repeat.ONCE;

    /** Determines the priority this timeout will receive on the main loop. */
    public Priority priority = Priority.DEFAULT;

    /** Determines if the timeout is waiting to fire or not. */
    public bool is_running {
        get { return this.source_id >= 0; }
    }

    private TimeoutFunc callback;
    private int source_id = -1;


    /**
     * Constructs a new timeout with an interval in seconds.
     *
     * The timeout will be by default not running, and hence needs to be
     * started by a call to {@link start}.
     */
    public TimeoutManager.seconds(uint interval, TimeoutFunc callback) {
        this.use_seconds = true;
        this.interval = interval;
        this.callback = callback;
    }

    /**
     * Constructs a new timeout with an interval in milliseconds.
     *
     * The timeout will be by default not running, and hence needs to be
     * started by a call to {@link start}.
     */
    public TimeoutManager.milliseconds(uint interval, TimeoutFunc callback) {
        this.use_seconds = false;
        this.interval = interval;
        this.callback = callback;
    }

    ~TimeoutManager() {
        reset();
    }

    /**
     * Schedules the timeout to fire after the given interval.
     *
     * If the timeout is already running, it will first be reset.
     */
    public void start() {
        reset();
        this.source_id = (int) (
            (this.use_seconds)
            ? GLib.Timeout.add_seconds(this.interval, on_trigger, this.priority)
            : GLib.Timeout.add(this.interval, on_trigger, this.priority)
        );
    }

    /**
     * Prevents the timeout from firing.
     *
     * After a call to this timeout will not fire again, regardless of
     * the specified repetition for the timeout.
     *
     * @return `true` if the timeout was already running, else `false`
     */
    public bool reset() {
        bool is_running = this.is_running;
        if (is_running) {
            Source.remove(this.source_id);
            this.source_id = -1;
        }
        return is_running;
    }

    private bool on_trigger() {
        bool ret = Source.CONTINUE;
        // If running only once, reset the source id now in case the
        // callback resets the timer while it is executing, so we
        // avoid removing the source just before it would be removed
        // after this call anyway
        if (this.repetition == Repeat.ONCE) {
            this.source_id = -1;
            ret = Source.REMOVE;
        }
        callback(this);
        return ret;
    }

}
