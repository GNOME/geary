/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Adapts a progress bar to automatically display progress of a Geary.ProgressMonitor.
 */
public class MonitoredProgressBar : Adw.Bin {
    private Geary.ProgressMonitor? monitor = null;

    private Gtk.ProgressBar progress_bar;

    construct {
        this.progress_bar = new Gtk.ProgressBar();
        this.child = this.progress_bar;
    }

    public void set_progress_monitor(Geary.ProgressMonitor monitor) {
        this.monitor = monitor;
        monitor.start.connect(on_start);
        monitor.finish.connect(on_finish);
        monitor.update.connect(on_update);

        this.progress_bar.fraction = monitor.progress;
    }

    private void on_start() {
        this.progress_bar.fraction = 0.0;
    }

    private void on_update(double total_progress, double change, Geary.ProgressMonitor monitor) {
        this.progress_bar.fraction = total_progress;
    }

    private void on_finish() {
        this.progress_bar.fraction = 1.0;
    }
}

