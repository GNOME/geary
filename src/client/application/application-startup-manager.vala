/*
 * Copyright 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Background portal
namespace portal {
    [DBus(name = "org.freedesktop.portal.Request")]
    public interface Request : GLib.Object {
        [DBus(name = "Response")]
        public signal void response(
            uint response,
            GLib.HashTable<string, GLib.Variant> results);
    }

    [DBus(name = "org.freedesktop.portal.Background")]
    public interface Background : GLib.Object {
        [DBus(name = "RequestBackground")]
        public abstract GLib.ObjectPath request_background(
            string parent_window,
            GLib.HashTable<string, GLib.Variant> options)
        throws DBusError, IOError;
    }
}

/*
 * Manages desktop files in the autostart.
 */
public class Application.StartupManager : GLib.Object {

    private const string AUTOSTART_FOLDER = "autostart";
    private const string AUTOSTART_DESKTOP_FILE = "geary-autostart.desktop";
    private const string BUS_NAME = "org.freedesktop.portal.Desktop";
    private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";


    private Application.Client app;
    private GLib.File installed_file;
    private GLib.File startup_file;

    public StartupManager(Application.Client app) {
        GLib.File desktop_dir = app.get_desktop_directory();
        this.app = app;
        this.installed_file = desktop_dir.get_child(AUTOSTART_DESKTOP_FILE);
        this.startup_file = GLib.File.new_for_path(
            GLib.Environment.get_user_config_dir()
        ).get_child(AUTOSTART_FOLDER)
        .get_child(AUTOSTART_DESKTOP_FILE);

        // Connect run-in-background option callback
        app.config.settings.changed[Configuration.RUN_IN_BACKGROUND_KEY].connect(
            on_run_in_background_change
        );
    }

    /**
     * Returns the system-wide autostart desktop file if it exists.
     */
    private GLib.File? get_installed_desktop_file() {
        return this.installed_file.query_exists() ? this.installed_file : null;
    }

    /**
     * Request background mode using Background portal
     */
    private async void request_background(bool autostart) {
        try {
            GLib.DBusConnection bus = yield Bus.get(BusType.SESSION);
            string[] cmdline = {"geary", "--gapplication-service"};
            var background = yield bus.get_proxy<portal.Background>(
                BUS_NAME, OBJECT_PATH);
            var options = new GLib.HashTable<string, GLib.Variant>(
                str_hash, str_equal);
            options.insert("reason", new GLib.Variant(
                "s", _("Geary wants to run in background")));
            options.insert("autostart", new GLib.Variant(
                "b", autostart));
            options.insert("commandline", new GLib.Variant.strv(cmdline));
            var handle = background.request_background(_APP_ID, options);
            yield bus.get_proxy<portal.Request>(BUS_NAME, handle);
        } catch (GLib.Error error) {
            warning("Failed to request to run in background: %s", error.message);
        }
    }

    /**
     * Handle autostart file installation
     */
    private async void handle_autostart(bool install) {
       try {
            if (install) {
                install_startup_file();
            } else {
                delete_startup_file();
            }
        } catch (GLib.Error err) {
            warning("Failed to update autostart desktop file: %s", err.message);
        }
    }

    /**
     * Copies the autostart desktop file to the autostart directory.
     */
    private void install_startup_file() throws GLib.Error {
        if (!this.startup_file.query_exists()) {
            GLib.File autostart_dir = this.startup_file.get_parent();
            if (!autostart_dir.query_exists()) {
                autostart_dir.make_directory_with_parents();
            }
            GLib.File? autostart = get_installed_desktop_file();
            if (autostart == null) {
                warning("Autostart file is not installed!");
            } else {
                autostart.copy(this.startup_file, 0);
            }
        }
    }

    /**
     * Deletes the desktop file from autostart directory.
     */
    private void delete_startup_file() throws GLib.Error {
        try {
            this.startup_file.delete();
        } catch (GLib.IOError.NOT_FOUND err) {
            // All good
        }
    }

    /**
     * Install background/autostart support depending on current
     * execution environment
     */
    private void on_run_in_background_change() {
        if (this.app.is_flatpak_sandboxed) {
            request_background.begin(this.app.config.run_in_background);
        } else {
            handle_autostart.begin(this.app.config.run_in_background);
        }
    }

}
