/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/*
 * A simple class for manipulating autostarting Geary as a hidden application through a simple
 * desktop file at $HOME/.config/autostart/geary.desktop
 */
public class AutostartManager : Object {
    private const string AUTOSTART_FOLDER = "autostart";
    private const string AUTOSTART_DESKTOP_FILE = "geary-autostart.desktop";

    private File startup_file; // Startup '.desktop' file

    public AutostartManager() {
        startup_file = File.new_for_path(Environment.get_user_config_dir()).get_child(AUTOSTART_FOLDER)
            .get_child(AUTOSTART_DESKTOP_FILE);
        
        // Connect startup-notifications option callback
        GearyApplication.instance.config.settings.changed[Configuration.STARTUP_NOTIFICATIONS_KEY].connect(
            on_startup_notification_change);
    }

    /**
     * Returns the system-wide autostart desktop file
     */
    public File? get_autostart_desktop_file() {
        File? install_dir = GearyApplication.instance.get_install_dir();
        File desktop_file = (install_dir != null)
            ? install_dir.get_child("share").get_child("applications").get_child(AUTOSTART_DESKTOP_FILE)
            : File.new_for_path(GearyApplication.SOURCE_ROOT_DIR).get_child("build").get_child("desktop").get_child(AUTOSTART_DESKTOP_FILE);
        
        return desktop_file.query_exists() ? desktop_file : null;
    }

    /**
     * Deletes the desktop file from autostart directory.
     */
    public void delete_startup_file() {
        if (startup_file.query_exists()) {
            try {
                startup_file.delete();
            } catch (Error err) {
                message("Failed to delete startup file: %s", err.message);
            }
        }
    }

    /**
     * Creates .desktop file in autostart directory (usually '$HOME/.config/autostart/') if no one exists.
     */
    public void create_startup_file() {
        if (startup_file.query_exists())
            return;
        
        try {
            File autostart_dir = startup_file.get_parent();
            if (!autostart_dir.query_exists())
                autostart_dir.make_directory_with_parents();
            File? autostart = get_autostart_desktop_file();
            if (autostart == null) {
                message("Autostart file is not installed!");
            } else {
                autostart.copy(startup_file, 0);
            }
        } catch (Error err) {
            message("Failed to create startup file: %s", err.message);
        }
    }
   
    /**
     * Callback for startup notification option changes.
     */
    public void on_startup_notification_change() {
        if (GearyApplication.instance.config.startup_notifications)
            create_startup_file();
        else
            delete_startup_file();
    }
    
    /*
     * A convenience method. The purpose of this method is to synchronize the state of startup notifications setting
     * with the actual state of the file, so it's not misleading for the user (the option is checked while the file doesn't exist)
     */
    public void sync_with_config() {
        GearyApplication.instance.config.startup_notifications = startup_file.query_exists(); 
    }
}
