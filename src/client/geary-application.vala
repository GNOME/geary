/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Defined by wscript
extern const string _PREFIX;

public class GearyApplication : YorbaApplication {
    // TODO: replace static strings with const strings when gettext is integrated properly
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public static string DESCRIPTION = _("Email Client");
    public const string VERSION = "0.0.0+trunk";
    public const string COPYRIGHT = "Copyright 2011 Yorba Foundation";
    public const string WEBSITE = "http://www.yorba.org";
    public static string WEBSITE_LABEL = _("Visit the Yorba web site");
    
    public const string PREFIX = _PREFIX;
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        null
    };
    
    public const string LICENSE = """
Geary is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

Geary is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with Geary; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";
    
    public static GearyApplication instance { 
        get { return _instance; }
        private set { 
            // Ensure singleton behavior.
            assert (_instance == null);
            _instance = value;
        }
    }
    
    public Gtk.ActionGroup actions {
        get; private set; default = new Gtk.ActionGroup("GearyActionGroup");
    }
    
    public Gtk.UIManager ui_manager {
        get; private set; default = new Gtk.UIManager();
    }
    
    public Configuration config { get; private set; }
    
    private static GearyApplication _instance = null;
    
    private GearyController? controller = null;
    private Geary.EngineAccount? account = null;
    
    private File exec_dir;
    
    public GearyApplication() {
        base (NAME, PRGNAME, "org.yorba.geary");
        
        _instance = this;
    }
    
    public override int startup() {
        int result = base.startup();
        
        // TODO: Use OptionArg to properly parse the command line
        for (int ctr = 1; ctr < args.length; ctr++) {
            switch (args[ctr].down()) {
                case "--log-network":
                    Geary.Logging.enable_flags(Geary.Logging.Flag.NETWORK);
                break;
                
                default:
                    // ignore
                break;
            }
        }
        
        return result;
    }
    
    public override void activate() {
        // If Geary is already running, show the main window and return.
        if (controller != null && controller.main_window != null) {
            controller.main_window.present();
            return;
        }
        
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        
        // Start Geary.
        config = new Configuration(GearyApplication.instance.get_install_dir() != null,
            GearyApplication.instance.get_exec_dir().get_child("build/src/client").get_path());
        
        // Get saved credentials. If not present, ask user.
        string username = "";
        string? password = null;
        try {
            Gee.List<string> accounts = Geary.Engine.get_usernames(get_user_data_directory());
            if (accounts.size > 0) {
                username = accounts.get(0);
                password = keyring_get_password(username);
            }
        } catch (Error e) {
            debug("Unable to fetch accounts. Error: %s", e.message);
        }
        
        if (password == null) {
            LoginDialog login = new LoginDialog(username);
            login.show();
            if (login.get_response() == Gtk.ResponseType.OK) {
                username = login.username;
                password = login.password;
                
                // TODO: check credentials before saving password in keyring.
                keyring_save_password(username, password);
            } else {
                exit(1);
            }
        }
        
        Geary.Credentials cred = new Geary.Credentials(username, password);
        
        try {
            account = Geary.Engine.open(cred, get_user_data_directory(), get_resource_directory());
        } catch (Error err) {
            error("Unable to open mail database for %s: %s", cred.user, err.message);
        }
        
        controller = new GearyController();
        controller.start(account);
        
        return;
    }
    
    public override void exiting(bool panicked) {
        if (controller.main_window != null)
            controller.main_window.destroy();
    }
    
    public File get_user_data_directory() {
        return File.new_for_path(Environment.get_user_data_dir()).get_child(Environment.get_prgname());
    }
    
    /**
     * Returns the base directory that the application's various resource files are stored.  If the
     * application is running from its installed directory, this will point to
     * $(BASEDIR)/share/<program name>.  If it's running from the build directory, this points to
     * that.
     *
     * TODO: Implement.  This is placeholder code for build environments and assumes you're running
     * the program in the build directory.
     */
    public File get_resource_directory() {
        return File.new_for_path(Environment.get_current_dir());
    }
    
    // Returns the directory the application is currently executing from.
    public File get_exec_dir() {
        return exec_dir;
    }
    
    // Returns the installation directory, or null if we're running outside of the installation
    // directory.
    public File? get_install_dir() {
        File prefix_dir = File.new_for_path(PREFIX);
        return exec_dir.has_prefix(prefix_dir) ? prefix_dir : null;
    }
    
    // Creates a GTK builder given the filename of a UI file in the ui directory.
    public Gtk.Builder create_builder(string ui_filename) {
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_file(get_resource_directory().get_child("ui").get_child(
                ui_filename).get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.Builder: %s".printf(error.message));
        }
        
        return builder;
    }
    
    // Loads a UI file (in the ui directory) into the UI manager.
    public void load_ui_file(string ui_filename) {
        try {
            ui_manager.add_ui_from_file(get_resource_directory().get_child("ui").get_child(
                ui_filename).get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.UIManager: %s".printf(error.message));
        }
    }
    
    public Gtk.Window get_main_window() {
        return controller.main_window;
    }
}

