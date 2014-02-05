/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Type of progress monitor.
 */
public enum Geary.ProgressType {
    AGGREGATED,
    ACTIVITY,
    DB_UPGRADE,
    SEARCH_INDEX
}

/**
 * Base class for progress monitoring.
 */
public abstract class Geary.ProgressMonitor : BaseObject {
    public const double MIN = 0.0;
    public const double MAX = 1.0;
    
    public double progress { get; protected set; default = MIN; }
    public bool is_in_progress { get; protected set; default = false; }
    public Geary.ProgressType progress_type { get; protected set; }
    
    /**
     * The start signal is fired just before progress begins.  It will not fire again until after
     * {@link finish} has fired.
     */
    public signal void start();
    
    /**
     * Notifies the user of existing progress.  Note that monitor refers to the monitor that
     * invoked this update, which may not be the same as this object.
     */
    public signal void update(double total_progress, double change, Geary.ProgressMonitor monitor);
    
    /**
     * Finish is fired when progress has completed.
     */
    public signal void finish();
    
    /**
     * Users must call this before calling update.
     *
     * Must not be called again until {@link ProgressMonitor.notify_finish} has been called.
     */ 
    public virtual void notify_start() {
        assert(!is_in_progress);
        progress = MIN;
        is_in_progress = true;
        
        start();
    }
    
    /**
     * Users must call this when progress has completed.
     *
     * Must only be called after {@link ProgressMonitor.notify_start}.
     */
    public virtual void notify_finish() {
        assert(is_in_progress);
        is_in_progress = false;
        
        finish();
    }
}

/**
 * Captures the progress of a single action.
 */
public class Geary.SimpleProgressMonitor : Geary.ProgressMonitor {
    /**
     * Creates a new progress monitor of the given type.
     */
    public SimpleProgressMonitor(ProgressType type) {
        this.progress_type = type;
    }
    
    /**
     * Updates the progress by the given value.  Must be between {@link ProgressMonitor.MIN} and
     * {@link ProgressMonitor.MAX}.
     *
     * Must only be called after {@link ProgressMonitor.notify_start} and before
     * {@link ProgressMonitor.notify_finish}.
     */
    public void increment(double value) {
        assert(value > 0);
        assert(is_in_progress);
        
        if (progress + value > MAX)
            value = MAX - progress;
        
        progress += value;
        update(progress, value, this);
    }
}

/**
 * Monitors the progress of a countable interval.  Note that min and max are inclusive.
 */
public class Geary.IntervalProgressMonitor : Geary.ProgressMonitor {
    private int min_interval;
    private int max_interval;
    private int current = 0;
    
    /**
     * Creates a new progress monitor with the given interval range.
     */
    public IntervalProgressMonitor(ProgressType type, int min, int max) {
        this.progress_type = type;
        this.min_interval = min;
        this.max_interval = max;
    }
    
    /**
     * Sets a new interval.  Must not be done while in progress.
     */
    public void set_interval(int min, int max) {
        assert(!is_in_progress);
        this.min_interval = min;
        this.max_interval = max;
    }
    
    public override void notify_start() {
        current = 0;
        base.notify_start();
    }
    
    /**
     * Incrememts the progress 
     */
    public void increment(int count = 1) {
        assert(is_in_progress);
        assert(count + progress >= min_interval);
        assert(count + progress <= max_interval);
        
        current += count;
        
        double new_progress = (1.0 * current - min_interval) / (1.0 * max_interval - min_interval);
        double change = new_progress - progress;
        progress = new_progress;
        
        update(progress, change, this);
    }
}

/**
 * Captures progress of multiple actions by composing
 * many progress monitors into one.
 */
public class Geary.AggregateProgressMonitor : Geary.ProgressMonitor {
    private Gee.HashSet<Geary.ProgressMonitor> monitors = new Gee.HashSet<Geary.ProgressMonitor>();
    
    /**
     * Creates an aggregate progress monitor.
     */
    public AggregateProgressMonitor() {
        this.progress_type = Geary.ProgressType.AGGREGATED;
    }
    
    /**
     * Adds a new progress monitor to this aggregate.
     */
    public void add(Geary.ProgressMonitor pm) {
        // TODO: Handle the case where we add a new monitor during progress.
        monitors.add(pm);
        pm.start.connect(on_start);
        pm.update.connect(on_update);
        pm.finish.connect(on_finish);
    }
    
    public void remove(Geary.ProgressMonitor pm) {
        // TODO: Handle the case where we remove a new monitor during progress.
        monitors.remove(pm);
        pm.start.disconnect(on_start);
        pm.update.disconnect(on_update);
        pm.finish.disconnect(on_finish);
        
        if (pm.is_in_progress) {
            // If no other PMs are in progress, we must issue a finish signal.
            bool issue_signal = true;
            foreach(ProgressMonitor p in monitors) {
                if (p.is_in_progress) {
                    issue_signal = false;
                    break;
                }
            }
            
            if (issue_signal)
                notify_finish();
        }
    }
    
    private void on_start() {
        if (!is_in_progress)
            notify_start();
    }
    
    private void on_update(double total_progress, double change, ProgressMonitor monitor) {
        assert(is_in_progress);
        
        double updated_progress = MIN;
        foreach(Geary.ProgressMonitor pm in monitors)
            updated_progress += pm.progress;
        
        updated_progress /= monitors.size;
        
        double aggregated_change = updated_progress - progress;
        if (aggregated_change < 0)
            aggregated_change = 0;
        
        progress += updated_progress;
        
        if (progress > MAX)
            progress = MAX;
        
        update(progress, aggregated_change, monitor);
    }
    
    private void on_finish() {
        // Only signal completion once all progress monitors are complete.
        foreach(Geary.ProgressMonitor pm in monitors) {
            if (pm.is_in_progress)
                return;
        }
        
        notify_finish();
    }
}

