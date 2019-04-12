/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/*
 * Manages desktop files in the autostart.
 */
public class Application.StartupManager : GLib.Object {

    private const string AUTOSTART_FOLDER = "autostart";
    private const string AUTOSTART_DESKTOP_FILE = "geary-autostart.desktop";

    private Configuration config;
    private GLib.File? install_dir;
    private GLib.File startup_file; // Startup '.desktop' file

    public StartupManager(Configuration config, GLib.File? install_dir) {
        this.config = config;
        this.install_dir = install_dir;
        this.startup_file = GLib.File.new_for_path(
            GLib.Environment.get_user_config_dir()
        ).get_child(AUTOSTART_FOLDER)
        .get_child(AUTOSTART_DESKTOP_FILE);

        // Connect startup-notifications option callback
        config.settings.changed[Configuration.STARTUP_NOTIFICATIONS_KEY].connect(
            on_startup_notification_change
        );
    }

    /**
     * Returns the system-wide autostart desktop file
     */
    public GLib.File? get_autostart_desktop_file() {
        GLib.File? parent = null;
        if (this.install_dir != null) {
            // Running from the installation directory
            parent = (
                this.install_dir
                .get_child("share")
                .get_child("applications")
            );
        } else {
            // Running from the source build directory
            parent = (
                GLib.File.new_for_path(GearyApplication.SOURCE_ROOT_DIR)
                .get_child("build")
                .get_child("desktop")
            );
        }

        GLib.File desktop_file = parent.get_child(AUTOSTART_DESKTOP_FILE);
        return desktop_file.query_exists() ? desktop_file : null;
    }

    /**
     * Copies the autostart desktop file to the autostart directory.
     */
    public void install_startup_file() throws GLib.Error {
        if (!this.startup_file.query_exists()) {
            GLib.File autostart_dir = this.startup_file.get_parent();
            if (!autostart_dir.query_exists()) {
                autostart_dir.make_directory_with_parents();
            }
            GLib.File? autostart = get_autostart_desktop_file();
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
    public void delete_startup_file() throws GLib.Error {
        try {
            this.startup_file.delete();
        } catch (GLib.IOError.NOT_FOUND err) {
            // All good
        }
    }

    /*
     * Synchronises the config with the actual state of the autostart file.
     *
     * Ensures it's not misleading (i.e. the option is checked while
     * the file doesn't exist).
     */
    public void sync_with_config() {
        this.config.startup_notifications = this.startup_file.query_exists();
    }

    private void on_startup_notification_change() {
        try {
            if (this.config.startup_notifications) {
                install_startup_file();
            } else {
                delete_startup_file();
            }
        } catch (GLib.Error err) {
            warning("Failed to update autostart desktop file: %s", err.message);
        }
    }

}
