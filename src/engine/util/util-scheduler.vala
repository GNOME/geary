/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Scheduler provides a mechanism for submitting unowned SourceFunc delegates to the Idle and
 * Timeout event queues.  The returned Scheduled object can be used to cancel the callback, or
 * can be simply dropped (ignored) and the callback will be called at the scheduled time.
 */

namespace Geary.Scheduler {

private Gee.HashSet<ScheduledInstance>? scheduled_map = null;

private class ScheduledInstance : BaseObject, Geary.ReferenceSemantics {
    protected int manual_ref_count { get; protected set; }

    private unowned SourceFunc? cb;
    private uint sched_id;

    // Can't rely on ReferenceSemantic's "freed" signal because it's possible all the SmartReferences
    // have been dropped but the callback is still pending.  This signal is fired when all references
    // are dropped and the callback is not pending or has been cancelled.
    public signal void dead();

    public ScheduledInstance.on_idle(SourceFunc cb, int priority) {
        this.cb = cb;
        sched_id = Idle.add(on_callback, priority);

        freed.connect(on_freed);
    }

    public ScheduledInstance.after_msec(uint msec, SourceFunc cb, int priority) {
        this.cb = cb;
        sched_id = Timeout.add(msec, on_callback, priority);

        freed.connect(on_freed);
    }

    public ScheduledInstance.after_sec(uint sec, SourceFunc cb, int priority) {
        this.cb = cb;
        sched_id = Timeout.add_seconds(sec, on_callback, priority);

        freed.connect(on_freed);
    }

    public void cancel() {
        if (sched_id == 0)
            return;

        // cancel callback
        Source.remove(sched_id);

        // mark as cancelled
        cb = null;
        sched_id = 0;

        // tell SmartReferences to drop their refs
        // (this in turn will call "freed", firing the "dead" signal)
        release_now();
    }

    private bool on_callback() {
        bool again = (cb != null) ? cb() : false;

        if (!again) {
            // mark as cancelled
            cb = null;
            sched_id = 0;

            // tell the SmartReferences to drop their refs
            // (this in turn will call "freed", firing the "dead" signal, unless all refs were
            // released earlier and the callback was pending, so fire "dead" now)
            if (is_freed())
                dead();
            else
                release_now();
        }

        return again;
    }

    private void on_freed() {
        // only fire "dead" if marked as cancelled, otherwise wait until callback completes
        if (sched_id == 0)
            dead();
    }
}

public class Scheduled : Geary.SmartReference {
    internal Scheduled(ScheduledInstance instance) {
        base (instance);
    }

    public void cancel() {
        ScheduledInstance? instance = get_reference() as ScheduledInstance;
        if (instance != null)
            instance.cancel();
    }
}

public Scheduled on_idle(SourceFunc cb, int priority = GLib.Priority.DEFAULT_IDLE) {
    return schedule_instance(new ScheduledInstance.on_idle(cb, priority));
}

public Scheduled after_msec(uint msec, SourceFunc cb, int priority = GLib.Priority.DEFAULT) {
    return schedule_instance(new ScheduledInstance.after_msec(msec, cb, priority));
}

public Scheduled after_sec(uint sec, SourceFunc cb, int priority = GLib.Priority.DEFAULT) {
    return schedule_instance(new ScheduledInstance.after_sec(sec, cb, priority));
}

private Scheduled schedule_instance(ScheduledInstance inst) {
    inst.dead.connect(on_scheduled_dead);

    if (scheduled_map == null)
        scheduled_map = new Gee.HashSet<ScheduledInstance>();

    scheduled_map.add(inst);

    return new Scheduled(inst);
}

private void on_scheduled_dead(ScheduledInstance inst) {
    inst.dead.disconnect(on_scheduled_dead);

    bool removed = scheduled_map.remove(inst);
    assert(removed);
}

// Sleeps for the specified number of seconds.
public async void sleep_async(uint seconds) {
    uint id = Timeout.add_seconds(seconds, sleep_async.callback);
    yield;
    Source.remove(id);
}

/// Sleeps for the specified number of milliseconds.
public async void sleep_ms_async(uint milliseconds) {
    uint id = Timeout.add(milliseconds, sleep_ms_async.callback);
    yield;
    Source.remove(id);
}

}

