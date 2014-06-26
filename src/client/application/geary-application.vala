/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _VERSION;
extern const string _INSTALL_PREFIX;
extern const string _GSETTINGS_DIR;
extern const string _SOURCE_ROOT_DIR;
extern const string GETTEXT_PACKAGE;

public class GearyApplication : Gtk.Application {
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public const string APP_ID = "org.yorba.geary";
    public const string DESCRIPTION = _("Mail Client");
    public const string COPYRIGHT = _("Copyright 2011-2014 Yorba Foundation");
    public const string WEBSITE = "http://www.yorba.org";
    public const string WEBSITE_LABEL = _("Visit the Yorba web site");
    public const string BUGREPORT = "https://wiki.gnome.org/Apps/Geary/ReportingABug";
    public const string DONATE = "http://www.yorba.org/about/donate";
    
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
    
    private static const string ACTION_ENTRY_COMPOSE = "compose";
    
    public static const ActionEntry[] action_entries = {
        {ACTION_ENTRY_COMPOSE, activate_compose, "s"},
    };
    
    public static GearyApplication instance {
        get { return _instance; }
        private set {
            // Ensure singleton behavior.
            assert (_instance == null);
            _instance = value;
        }
    }
    
    /**
     * Signal that is activated when 'exit' is called, but before the application actually exits.
     *
     * To cancel an exit, a callback should return GearyApplication.cancel_exit(). To procede with
     * an exit, a callback should return true.
     */
    public virtual signal bool exiting(bool panicked) {
        controller.close();
        Date.terminate();
        
        return true;
    }
    
    public GearyController controller { get; private set; default = new GearyController(); }
    
    public Gtk.ActionGroup actions {
        get; private set; default = new Gtk.ActionGroup("GearyActionGroup");
    }
    public Gee.Collection<Geary.ActionAdapter> action_adapters {
        get; private set; default = new Gee.ArrayList<Geary.ActionAdapter>();
    }
    
    public Gtk.UIManager ui_manager {
        get; private set; default = new Gtk.UIManager();
    }
    
    public Configuration config { get; private set; }
    
    private static GearyApplication _instance = null;
    
    private string bin;
    private File exec_dir;
    
    private bool exiting_fired = false;
    private int exitcode = 0;
    
    public GearyApplication() {
        Object(application_id: APP_ID);
        
        _instance = this;
    }
    
    // Application.run() calls this as an entry point.
    public override bool local_command_line(ref unowned string[] args, out int exit_status) {
        bin = args[0];
        exec_dir = (File.new_for_path(Posix.realpath(Environment.find_program_in_path(bin)))).get_parent();
        
        try {
            register();
        } catch (Error e) {
            error("Error registering GearyApplication: %s", e.message);
        }
        
        if (!Args.parse(args)) {
            exit_status = 1;
            return true;
        }
        
        activate();
        foreach (unowned string arg in args) {
            if (arg != null && arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME))
                activate_action(ACTION_ENTRY_COMPOSE, new Variant.string(arg));
        }
        
        exit_status = 0;
        return true;
    }
    
    public override void startup() {
        Configuration.init(is_installed(), GSETTINGS_DIR);
        
        Environment.set_application_name(NAME);
        Environment.set_prgname(PRGNAME);
        International.init(GETTEXT_PACKAGE, bin);
        
        Geary.Logging.init();
        Date.init();
        WebKit.set_cache_model(WebKit.CacheModel.DOCUMENT_BROWSER);
        
        base.startup();
        
        add_action_entries(action_entries, this);
    }
    
    public override void activate() {
        base.activate();
        
        if (!present())
            create_async.begin();
    }
    
    public void activate_compose(SimpleAction action, Variant? param) {
        if (param == null)
            return;
        
        compose(param.get_string());
    }
    
    public bool present() {
        if (controller == null || controller.main_window == null)
            return false;
        
        if (!controller.main_window.get_realized())
            controller.main_window.show_all();
        else
            controller.main_window.present();
        
        return true;
    }
    
    private async void create_async() {
        // Manually keep the main loop around for the duration of this call.
        // Without this, the main loop will exit as soon as we hit the yield
        // below, before we create the main window.
        hold();
        
        // do *after* parsing args, as they dicate where logging is sent to, if anywhere, and only
        // after activate (which means this is only logged for the one user-visible instance, not
        // the other instances called when sending commands to the app via the command-line)
        message("%s %s prefix=%s exec_dir=%s is_installed=%s", NAME, VERSION, INSTALL_PREFIX,
            exec_dir.get_path(), is_installed().to_string());
        
        config = new Configuration(APP_ID);
        yield controller.open_async();
        
        release();
    }
    
    public bool compose(string mailto) {
        if (controller == null)
            return false;
        
        controller.compose_mailto(mailto);
        return true;
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
    
    public File get_ui_file(string filename) {
        return get_resource_directory().get_child("ui").get_child(filename);
    }
    
    // Loads a UI file (in the ui directory) into the specified UI manager.
    public void load_ui_file_for_manager(Gtk.UIManager ui, string ui_filename) {
        try {
            ui.add_ui_from_file(get_ui_file(ui_filename).get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.UIManager: %s".printf(error.message));
        }
    }
    
    // Loads a UI file (in the ui directory) into the UI manager.
    public void load_ui_file(string ui_filename) {
        load_ui_file_for_manager(ui_manager, ui_filename);
    }
    
    // This call will fire "exiting" only if it's not already been fired.
    public void exit(int exitcode = 0) {
        if (exiting_fired)
            return;
        
        this.exitcode = exitcode;
        
        exiting_fired = true;
        if (!exiting(false)) {
            exiting_fired = false;
            this.exitcode = 0;
            
            return;
        }
        
        if (Gtk.main_level() > 0)
            Gtk.main_quit();
        else
            Posix.exit(exitcode);
    }
    
    /**
     * A callback for GearyApplication.exiting should return cancel_exit() to prevent the
     * application from exiting.
     */
    public bool cancel_exit() {
        Signal.stop_emission_by_name(this, "exiting");
        return false;
    }
    
    // This call will fire "exiting" only if it's not already been fired and halt the application
    // in its tracks.
    public void panic() {
        if (!exiting_fired) {
            exiting_fired = true;
            exiting(true);
        }
        
        Posix.exit(1);
    }
}

