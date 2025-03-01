/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** Manages progress when upgrading and rebuilding account databases. */
internal class Application.DatabaseManager : Geary.BaseObject {


    /* Progress monitor for database operations. */
    public Geary.AggregateProgressMonitor monitor {
        public get; private set;
        default = new Geary.AggregateProgressMonitor();
    }

    /** Determines whether or not the database dialog is visible. */
    public bool visible { get; set; }

    private weak Application.Client application;

    private Gtk.Dialog? dialog = null;
    private Gee.Set<GLib.Cancellable> cancellables =
        new Gee.HashSet<GLib.Cancellable>();

    /**
     * Creates a new manager for the given application.
     */
    public DatabaseManager(Application.Client application) {
        this.application = application;

        this.monitor.start.connect(on_start);
        this.monitor.finish.connect(on_close);
    }

    /**
     * Adds an account to be monitored for upgrades by the dialog.
     *
     * Accounts should be added before being opened.
     */
    public void add_account(Geary.Account account,
                            GLib.Cancellable? cancellable = null) {
        monitor.add(account.db_upgrade_monitor);
        monitor.add(account.db_vacuum_monitor);
        if (cancellable != null) {
            cancellables.add(cancellable);
        }
    }

    /**
     * Stops an account from being monitored.
     */
    public void remove_account(Geary.Account account) {
        monitor.remove(account.db_upgrade_monitor);
        monitor.remove(account.db_vacuum_monitor);
    }

    private void on_start() {
        // Disable main windows
        foreach (Application.MainWindow window in this.application.get_main_windows()) {
            window.sensitive = false;
        }

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        box.append(new Adw.Spinner());
        /// Translators: Label for account database upgrade dialog
        box.append(new Gtk.Label(_("Account update in progress")));

        this.dialog = new Gtk.Dialog.with_buttons(
            /// Translators: Window title for account database upgrade
            /// dialog
            _("Account update"),
            this.application.get_active_main_window(),
            MODAL
        );
        this.dialog.add_css_class("geary-upgrade");
        this.dialog.get_content_area().append(box);
        this.dialog.deletable = false;
        this.dialog.close_request.connect(on_close_request);
        this.dialog.close.connect(this.on_close);
        this.dialog.present();
    }

    private bool on_close_request() {
        // Don't allow window to close until we're finished.
        return !this.monitor.is_in_progress;
    }

    private void on_close() {
        // If the user quit the dialog before the upgrade completed, cancel everything.
        if (this.monitor.is_in_progress) {
            foreach (var c in cancellables) {
                c.cancel();
            }
        }

        if (this.dialog != null &&
            this.dialog.visible) {
            this.dialog.hide();
            this.dialog.destroy();
            this.dialog = null;
        }

        // Enable main windows
        foreach (Application.MainWindow window in this.application.get_main_windows()) {
            window.sensitive = true;
        }
    }

}
