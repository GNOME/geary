/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Manages execution of a function on the main loop.
 *
 * This class is a convenience API for the GLib main loop and source
 * infrastructure, automatically performing cleanup when destroyed.
 *
 * Note this class is not thread safe and should only be invoked from
 * the main loop.
 */
public class Geary.IdleManager : BaseObject {


    /** Specifies the priority the idle function should be given. */
    public enum Priority {
        HIGH = GLib.Priority.HIGH,
        DEFAULT = GLib.Priority.DEFAULT,
        HIGH_IDLE = GLib.Priority.HIGH_IDLE,
        DEFAULT_IDLE = GLib.Priority.DEFAULT_IDLE,
        LOW = GLib.Priority.LOW;
    }

    /** Specifies if the idle function should run once or be continuously. */
    public enum Repeat { ONCE, FOREVER; }

    /** The idle callback function prototype. */
    public delegate void IdleFunc(IdleManager manager);

    /** Determines if the function will be re-scheduled after being run. */
    public Repeat repetition = Repeat.ONCE;

    /** Determines the priority the function will receive on the main loop. */
    public Priority priority = Priority.DEFAULT;

    /** Determines if the function is waiting to fire or not. */
    public bool is_running {
        get { return this.source_id >= 0; }
    }

    private IdleFunc callback;
    private int source_id = -1;


    /**
     * Constructs a new idle manager with an interval in seconds.
     *
     * The idle function will be by default not running, and hence
     * needs to be started by a call to {@link schedule}.
     */
    public IdleManager(owned IdleFunc callback) {
        this.callback = (owned) callback;
    }

    ~IdleManager() {
        reset();
    }

    /**
     * Schedules the idle function to run on the main loop.
     *
     * If the function is already waiting to run, it will first be reset.
     */
    public void schedule() {
        reset();
        this.source_id = (int) GLib.Idle.add_full(this.priority, on_trigger);
    }

    /**
     * Prevents the idle function from being run.
     *
     * @return `true` if function was already scheduled, else `false`
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
