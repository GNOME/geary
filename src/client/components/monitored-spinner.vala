/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Adapts a progress spinner to automatically display progress of a Geary.ProgressMonitor.
 */
public class MonitoredSpinner : Gtk.Spinner {
    private Geary.ProgressMonitor? monitor = null;

    public void set_progress_monitor(Geary.ProgressMonitor? monitor) {
        if (monitor != null) {
            this.monitor = monitor;
            monitor.start.connect(on_start);
            monitor.finish.connect(on_stop);
        } else {
            this.monitor = null;
            stop();
            hide();
        }
    }

    public override void show() {
        if (monitor != null && monitor.is_in_progress)
            base.show();
    }

    private void on_start() {
        start();
        show();
    }

    private void on_stop() {
        stop();
        hide();
    }
}

