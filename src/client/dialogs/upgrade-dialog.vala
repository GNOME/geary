/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class UpgradeDialog : Object {
    public const string PROP_VISIBLE_NAME = "visible";

    // Progress monitor associated with the upgrade.
    public Geary.AggregateProgressMonitor monitor { public get; private set;
        default = new Geary.AggregateProgressMonitor(); }

    // Whether or not this dialog is visible.
    public bool visible { get; set; }

    private weak Application.Client application;

    private Gtk.Dialog? dialog = null;
    private Gee.HashSet<Cancellable> cancellables = new Gee.HashSet<Cancellable>();

    /**
     * Creates and loads the upgrade progress dialog.
     */
    public UpgradeDialog(Application.Client application) {
        this.application = application;

        // Load UI.
        // Hook up signals.
        monitor.start.connect(on_start);
        monitor.finish.connect(on_close);
    }

    private void on_start() {
        Gtk.Builder builder = GioUtil.create_builder("upgrade_dialog.glade");
        this.dialog = (Gtk.Dialog) builder.get_object("dialog");
        this.dialog.set_transient_for(
            this.application.get_active_main_window()
        );
        this.dialog.delete_event.connect(on_delete_event);
        this.dialog.show();
    }

    private bool on_delete_event() {
        // Don't allow window to close until we're finished.
        return !monitor.is_in_progress;
    }

    private void on_close() {
        // If the user quit the dialog before the upgrade completed, cancel everything.
        if (monitor.is_in_progress) {
            foreach(Cancellable c in cancellables)
                c.cancel();
        }

        if (this.dialog != null &&
            this.dialog.visible) {
            this.dialog.hide();
            this.dialog = null;
        }
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

}
