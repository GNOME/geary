/* Copyright 2013 Yorba Foundation
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
    
    private Gtk.Dialog dialog;
    private Gee.HashSet<Cancellable> cancellables = new Gee.HashSet<Cancellable>();
    
    /**
     * Creates and loads the upgrade progress dialog.
     */
    public UpgradeDialog() {
        // Load UI.
        Gtk.Builder builder = GearyApplication.instance.create_builder("upgrade_dialog.glade");
        dialog = (Gtk.Dialog) builder.get_object("dialog");
        
        // Hook up signals.
        monitor.start.connect(on_start);
        monitor.finish.connect(on_close);
        dialog.delete_event.connect(on_delete_event);
        
        // Bind visibility flag.
        dialog.bind_property(PROP_VISIBLE_NAME, this, PROP_VISIBLE_NAME, BindingFlags.BIDIRECTIONAL |
            BindingFlags.SYNC_CREATE);
    }
    
    private void on_start() {
        dialog.show();
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
        
        if (dialog.visible)
            dialog.destroy();
    }
    
    /**
     * Add accounts before opening them.
     */
    public void add_account(Geary.Account account, Cancellable? cancellable = null) {
        monitor.add(account.db_upgrade_monitor);
        if (cancellable != null)
            cancellables.add(cancellable);
    }
}

