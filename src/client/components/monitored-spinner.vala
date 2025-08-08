/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Adapts a progress spinner to automatically display progress of a Geary.ProgressMonitor.
 */
public class MonitoredSpinner : Adw.Bin {
    private Geary.ProgressMonitor? monitor = null;

    private Adw.Spinner spinner;

    construct {
        this.spinner = new Adw.Spinner();
        this.child = spinner;
    }

    public void set_progress_monitor(Geary.ProgressMonitor? monitor) {
        if (monitor != null) {
            this.monitor = monitor;
            monitor.start.connect(on_start);
            monitor.finish.connect(on_stop);
        } else {
            this.monitor = null;
            this.spinner.visible = false;
        }
    }

    public override void show() {
        if (monitor != null && monitor.is_in_progress)
            base.show();
    }

    private void on_start() {
        this.spinner.visible = true;
    }

    private void on_stop() {
        this.spinner.visible = false;
    }
}

