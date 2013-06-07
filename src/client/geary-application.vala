/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _VERSION;
extern const string _INSTALL_PREFIX;
extern const string _GSETTINGS_DIR;
extern const string _SOURCE_ROOT_DIR;

public class GearyApplication : YorbaApplication {
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public const string DESCRIPTION = DESKTOP_GENERIC_NAME;
    public const string COPYRIGHT = _("Copyright 2011-2013 Yorba Foundation");
    public const string WEBSITE = "http://www.yorba.org";
    public const string WEBSITE_LABEL = _("Visit the Yorba web site");
    public const string BUGREPORT = "http://redmine.yorba.org/projects/geary/issues";
    
    // These strings must match corresponding strings in desktop/geary.desktop *exactly* and be
    // internationalizable
    public const string DESKTOP_NAME = _("Geary Mail");
    public const string DESKTOP_GENERIC_NAME = _("Mail Client");
    public const string DESKTOP_COMMENT = _("Send and receive email");
    public const string DESKTOP_KEYWORDS = _("Email;E-mail;Mail;");
    public const string DESKTOP_COMPOSE_NAME = _("Compose Message");
    
    public const string VERSION = _VERSION;
    public const string INSTALL_PREFIX = _INSTALL_PREFIX;
    public const string GSETTINGS_DIR = _GSETTINGS_DIR;
    public const string SOURCE_ROOT_DIR = _SOURCE_ROOT_DIR;
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        "Nate Lillich <nate@yorba.org>",
        "Matthew Pirocchi <matthew@yorba.org>",
        "Charles Lindsay <chaz@yorba.org>",
        "Robert Schroll <rschroll@gmail.com>",
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
    
    public GearyController controller { get; private set; default = new GearyController(); }
    
    public Gtk.ActionGroup actions {
        get; private set; default = new Gtk.ActionGroup("GearyActionGroup");
    }
    
    public Gtk.UIManager ui_manager {
        get; private set; default = new Gtk.UIManager();
    }
    
    public Configuration config { get; private set; }
    
    /**
     * Fired when the current account in the UI has changed.
     * TODO: This signal really belongs in the controller.  See #7032 for the refactoring ticket.
     */
    public signal void current_account_changed(Geary.Account? account);
    
    private static GearyApplication _instance = null;
    
    private File exec_dir;
    
    public GearyApplication() {
        base (NAME, PRGNAME, "org.yorba.geary");
        
        _instance = this;
    }
    
    public override int startup() {
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        
        Geary.Logging.init();
        Configuration.init(is_installed(), GSETTINGS_DIR);
        Date.init();
        WebKit.set_cache_model(WebKit.CacheModel.DOCUMENT_BROWSER);
        
        int ec = base.startup();
        if (ec != 0)
            return ec;
        
        return Args.parse(args);
    }
    
    public override bool exiting(bool panicked) {
        controller.close();
        Date.terminate();
        
        return true;
    }
    
    public override void activate(string[] args) {
        do_activate_async.begin(args);
    }

    // Without owned on the args parameter, vala won't bother to keep the array
    // around until the open_async() call completes, leading to crashes.  This
    // way, this method gets its own long-lived copy.
    private async void do_activate_async(owned string[] args) {
        // If Geary is already running, show the main window and return.
        if (controller != null && controller.main_window != null) {
            controller.main_window.present();
            handle_args(args);
            return;
        }
        
        // do *after* parsing args, as they dicate where logging is sent to, if anywhere, and only
        // after activate (which means this is only logged for the one user-visible instance, not
        // the other instances called when sending commands to the app via the command-line)
        message("%s %s prefix=%s exec_dir=%s is_installed=%s", NAME, VERSION, INSTALL_PREFIX,
            exec_dir.get_path(), is_installed().to_string());
        
        config = new Configuration();
        yield controller.open_async();
        
        handle_args(args);
    }
    
    // NOTE: This assert()'s if the Gtk.Action is not present in the default action group
    public Gtk.Action get_action(string name) {
        Gtk.Action? action = actions.get_action(name);
        assert(action != null);
        
        return action;
    }
    
    public File get_user_data_directory() {
        return File.new_for_path(Environment.get_user_data_dir()).get_child("geary");
    }
    
    public File get_user_config_directory() {
        return File.new_for_path(Environment.get_user_config_dir()).get_child("geary");
    }
    
    /**
     * Returns the base directory that the application's various resource files are stored.  If the
     * application is running from its installed directory, this will point to
     * $(BASEDIR)/share/<program name>.  If it's running from the build directory, this points to
     * that.
     */
    public File get_resource_directory() {
        if (get_install_dir() != null)
            return get_install_dir().get_child("share").get_child("geary");
        else
            return File.new_for_path(SOURCE_ROOT_DIR);
    }
    
    // Returns the directory the application is currently executing from.
    public File get_exec_dir() {
        return exec_dir;
    }
    
    public File? get_desktop_file() {
        File? install_dir = get_install_dir();
        File desktop_file = (install_dir != null)
            ? install_dir.get_child("share").get_child("applications").get_child("geary.desktop")
            : File.new_for_path(SOURCE_ROOT_DIR).get_child("build").get_child("desktop").get_child("geary.desktop");
        
        return desktop_file.query_exists() ? desktop_file : null;
    }
    
    public bool is_installed() {
        return exec_dir.has_prefix(get_install_prefix_dir());
    }
    
    // Returns the configure installation prefix directory, which does not imply Geary is installed
    // or that it's running from this directory.
    public File get_install_prefix_dir() {
        return File.new_for_path(INSTALL_PREFIX);
    }
    
    // Returns the installation directory, or null if we're running outside of the installation
    // directory.
    public File? get_install_dir() {
        File prefix_dir = get_install_prefix_dir();
        
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

    public string? read_theme_file(string filename) {
        try {
            File file = get_resource_directory().get_child("theming").get_child(filename);
            DataInputStream data_input_stream = new DataInputStream(file.read());
            
            size_t length;
            return data_input_stream.read_upto("\0", 1, out length);
        } catch(Error error) {
            debug("Unable to load text from theme file: %s", error.message);
            return null;
        }
    }
    
    // Loads a UI file (in the ui directory) into the specified UI manager.
    public void load_ui_file_for_manager(Gtk.UIManager ui, string ui_filename) {
        try {
            ui.add_ui_from_file(get_resource_directory().get_child("ui").get_child(
                ui_filename).get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.UIManager: %s".printf(error.message));
        }
    }
    
    // Loads a UI file (in the ui directory) into the UI manager.
    public void load_ui_file(string ui_filename) {
        load_ui_file_for_manager(ui_manager, ui_filename);
    }
    
    private void handle_args(string[] args) {
        foreach(string arg in args) {
            if (arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                controller.compose_mailto(arg);
            }
        }
    }
}

