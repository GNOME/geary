/* Copyright 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Handle maintenance window for Dozed daemon
 */
public class Geary.App.Maintenance : BaseObject {

    private const string LOGIND_DBUS_NAME = "org.freedesktop.login1";
    private const string LOGIND_DBUS_PATH = "/org/freedesktop/login1";
    private const string LOGIND_DBUS_INTERFACE = "org.freedesktop.login1.Manager";

    private const string DOZED_DBUS_NAME = "org.freedesktop.Dozed";
    private const string DOZED_DBUS_PATH = "/org/freedesktop/Dozed";
    private const string DOZED_DBUS_INTERFACE = "org.freedesktop.Dozed";

    private Geary.AggregateProgressMonitor monitor = new Geary.AggregateProgressMonitor();

    private Gee.Set<Geary.Account> accounts = new Gee.HashSet<Geary.Account>();

    private DBusProxy? dozed_proxy = null;
    private DBusProxy logind_proxy;

    private GLib.Cancellable cancellable = null;

    private int progress_count = 0;

    private int64 maintenance_window_id = 0;

    public Maintenance() {
        this.monitor.start.connect(on_start);
        this.monitor.finish.connect(on_finish);

        try {
            this.logind_proxy = new DBusProxy.for_bus_sync(
                BusType.SYSTEM,
                DBusProxyFlags.NONE,
                null,
                LOGIND_DBUS_NAME,
                LOGIND_DBUS_PATH,
                LOGIND_DBUS_INTERFACE,
                null
            );
            this.logind_proxy.g_signal.connect(this.on_logind_signal);
        } catch (GLib.Error err) {
            debug("Failed to connect logind bus: %s", err.message);
        }

        try {
            this.dozed_proxy = new DBusProxy.for_bus_sync(
                BusType.SYSTEM,
                DBusProxyFlags.NONE,
                null,
                DOZED_DBUS_NAME,
                DOZED_DBUS_PATH,
                DOZED_DBUS_INTERFACE,
                null
            );
        } catch (GLib.Error err) {
            debug("Failed to connect dozed bus: %s", err.message);
        }
    }

    public void add_account(Geary.Account to_add) {
        if (!this.accounts.contains(to_add)) {
            this.accounts.add(to_add);
            this.monitor.add(to_add.background_progress);
        }
    }

    public void remove_account(Geary.Account to_remove) {
        if (this.accounts.contains(to_remove)) {
            this.accounts.remove(to_remove);
            this.monitor.remove(to_remove.background_progress);
        }
    }

    private async void register_maintenance_window() {
        if (this.dozed_proxy == null) {
            return;
        }

        GLib.Variant[] args = {};
        args += new GLib.Variant.string(
            GLib.Application.get_default().application_id
        );
        args += new GLib.Variant.boolean(
            true
        );
        var parameters = new GLib.Variant.tuple(args);
        try {
            var res = yield this.dozed_proxy.call(
                        "RegisterMaintenanceWindow",
                        parameters,
                        DBusCallFlags.NONE,
                        -1,
                        null
            );
            this.maintenance_window_id = res.get_child_value(0).get_int64();
        } catch (GLib.Error err) {
            debug("Failed to register a new maintenance window: %s", err.message);
            this.maintenance_window_id = 0;
        }
    }

    private async void release_maintenance_window() {
        if (this.dozed_proxy == null) {
            return;
        }

        GLib.Variant[] args = {};
        args += new GLib.Variant.string(
            GLib.Application.get_default().application_id
        );
        args += new GLib.Variant.int64(
            this.maintenance_window_id
        );
        var parameters = new GLib.Variant.tuple(args);
        try {
            yield this.dozed_proxy.call(
                        "ReleaseMaintenanceWindow",
                        parameters,
                        DBusCallFlags.NONE,
                        -1,
                        null
            );
        } catch (GLib.Error err) {
            debug("Failed to release maintenance window: %s", err.message);
        }
        this.maintenance_window_id = 0;
    }

    private void on_start() {
        if (this.maintenance_window_id != 0) {
            this.progress_count++;
        }
    }

    private void on_finish() {
        if (this.maintenance_window_id != 0) {
            this.progress_count--;
            if (this.progress_count == 0) {
                this.release_maintenance_window.begin();
            }
        }
    }

    private void on_logind_signal(DBusProxy logind_proxy, string? sender_name,
                                  string signal_name, Variant parameters)  {
        if (signal_name != "PrepareForSleep") {
            return;
        }

        bool about_to_suspend = parameters.get_child_value(0).get_boolean();

        if (!about_to_suspend) {
            this.register_maintenance_window.begin();
        }

        this.cancellable.cancel();
        this.cancellable = new GLib.Cancellable();
        foreach (var account in this.accounts) {
            if (about_to_suspend) {
                account.incoming.stop.begin(this.cancellable);
                account.outgoing.stop.begin(this.cancellable);
            } else {

                account.incoming.start.begin(this.cancellable);
                account.outgoing.start.begin(this.cancellable);
            }
        }
    }
}
