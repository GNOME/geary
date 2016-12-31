/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _INSTALL_PREFIX;
extern const string _GSETTINGS_DIR;
extern const string _SOURCE_ROOT_DIR;
extern const string _BUILD_ROOT_DIR;
extern const string GETTEXT_PACKAGE;

/**
 * The interface between Geary and the desktop environment.
 */
public class GearyApplication : Gtk.Application {
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public const string APP_ID = "org.gnome.Geary";
    public const string DESCRIPTION = _("Mail Client");
    public const string COPYRIGHT = _("Copyright 2016 Software Freedom Conservancy Inc.");
    public const string WEBSITE = "https://wiki.gnome.org/Apps/Geary";
    public const string WEBSITE_LABEL = _("Visit the Geary web site");
    public const string BUGREPORT = "https://wiki.gnome.org/Apps/Geary/ReportingABug";

    public const string VERSION = Geary.Version.GEARY_VERSION;
    public const string INSTALL_PREFIX = _INSTALL_PREFIX;
    public const string GSETTINGS_DIR = _GSETTINGS_DIR;
    public const string SOURCE_ROOT_DIR = _SOURCE_ROOT_DIR;
    public const string BUILD_ROOT_DIR = _BUILD_ROOT_DIR;

    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        "Nate Lillich <nate@yorba.org>",
        "Matthew Pirocchi <matthew@yorba.org>",
        "Charles Lindsay <chaz@yorba.org>",
        "Robert Schroll <rschroll@gmail.com>",
        null
    };

    private const string ACTION_ABOUT = "about";
    private const string ACTION_ACCOUNTS = "accounts";
    private const string ACTION_COMPOSE = "compose";
    private const string ACTION_MAILTO = "mailto";
    private const string ACTION_HELP = "help";
    private const string ACTION_PREFERENCES = "preferences";
    private const string ACTION_QUIT = "quit";

    private const ActionEntry[] action_entries = {
        {ACTION_ABOUT, on_activate_about},
        {ACTION_ACCOUNTS, on_activate_accounts},
        {ACTION_COMPOSE, on_activate_compose},
        {ACTION_MAILTO, on_activate_mailto, "s"},
        {ACTION_HELP, on_activate_help},
        {ACTION_PREFERENCES, on_activate_preferences},
        {ACTION_QUIT, on_activate_quit},
    };

    private const int64 USEC_PER_SEC = 1000000;
    private const int64 FORCE_SHUTDOWN_USEC = 5 * USEC_PER_SEC;


    [Version(deprecated = true)]
    public static GearyApplication instance {
        get { return _instance; }
        private set {
            // Ensure singleton behavior.
            assert (_instance == null);
            _instance = value;
        }
    }
    private static GearyApplication _instance = null;


    /**
     * The global UI controller for this app instance.
     */
    public GearyController controller {
        get;
        private set;
        default = new GearyController(this);
    }

    /**
     * The global email subsystem controller for this app instance.
     */
    public Geary.Engine engine {
        get {
            // XXX We should be managing the engine's lifecycle here,
            // but until that happens provide this property to
            // encourage access via the application anyway
            return Geary.Engine.instance;
        }
    }

    /**
     * The user's desktop-wide settings for the application.
     */
    public Configuration config { get; private set; }

    /**
     * Determines if Geary configured to run as as a background service.
     *
     * If this returns `true`, then the primary application instance
     * will continue to run in the background after the last window is
     * closed, instead of existing as usual.
     */
    public bool is_background_service {
        get { return Args.hidden_startup || this.config.startup_notifications; }
    }

    public Gtk.ActionGroup actions {
        get; private set; default = new Gtk.ActionGroup("GearyActionGroup");
    }

    public Gtk.UIManager ui_manager {
        get; private set; default = new Gtk.UIManager();
    }

    private string bin;
    private File exec_dir;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private bool is_destroyed = false;


    /**
     * Signal that is activated when 'exit' is called, but before the application actually exits.
     *
     * To cancel an exit, a callback should return GearyApplication.cancel_exit(). To procede with
     * an exit, a callback should return true.
     */
    public virtual signal bool exiting(bool panicked) {
        return true;
    }


    public GearyApplication() {
        Object(
            application_id: APP_ID
        );
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

        if (!Args.quit) {
            // Normal application startup or activation
            activate();
            foreach (unowned string arg in args) {
                if (arg != null) {
                    if (arg == Geary.ComposedEmail.MAILTO_SCHEME)
                        activate_action(ACTION_COMPOSE, null);
                    else if (arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME))
                        activate_action(ACTION_MAILTO, new Variant.string(arg));
                }
            }
        } else {
            // User requested quit, only try to if we aren't running
            // already.
            if (this.is_remote) {
                activate_action(ACTION_QUIT, null);
            }
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

        base.startup();

        add_action_entries(action_entries, this);
    }
    
    public override void activate() {
        base.activate();
        
        if (!present())
            create_async.begin();
    }
    
    public bool present() {
        if (controller == null)
            return false;
        
        // if LoginDialog (i.e. the opening dialog for creating the initial account) is present
        // and visible, bring that to top (to prevent opening the hidden main window, which is
        // empty)
        if (controller.login_dialog != null && controller.login_dialog.visible) {
            controller.login_dialog.present_with_time(Gdk.CURRENT_TIME);
            
            return true;
        }
        
        if (controller.main_window == null)
            return false;

        // When the app is started hidden, show_all() never gets
        // called, do so here to prevent an empty window appearing.
        controller.main_window.show_all();
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
    
    private async void destroy_async() {
        // see create_async() for reasoning hold/release is used
        hold();
        
        yield controller.close_async();
        
        release();
        
        is_destroyed = true;
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

    public File get_user_cache_directory() {
        return File.new_for_path(Environment.get_user_cache_dir()).get_child("geary");
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

    /** Returns the directory the application is currently executing from. */
    public File get_exec_dir() {
        return this.exec_dir;
    }

    /**
     * Returns the directory containing the application's WebExtension libs.
     *
     * If the application is installed, this will be
     * `$INSTALL_PREFIX/lib/geary/web-extension`, else it will be
     */
    public File get_web_extensions_dir() {
        File? dir = get_install_dir();
        if (dir != null)
            dir = dir.get_child("lib").get_child("geary").get_child("web-extensions");
        else
            dir = File.new_for_path(BUILD_ROOT_DIR).get_child("src");
        return dir;
    }

    public File? get_desktop_file() {
        File? install_dir = get_install_dir();
        File desktop_file = (install_dir != null)
            ? install_dir.get_child("share").get_child("applications").get_child("org.gnome.Geary.desktop")
            : File.new_for_path(SOURCE_ROOT_DIR).get_child("build").get_child("desktop").get_child("org.gnome.Geary.desktop");
        
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

    /**
     * Creates a GTK builder given the name of a GResource.
     *
     * @deprecated Use {@link GioUtil.create_builder} instead.
     */
    [Version (deprecated = true)]
    public Gtk.Builder create_builder(string name) {
        return GioUtil.create_builder(name);
    }

    /**
     * Loads a GResource as a string.
     *
     * @deprecated Use {@link GioUtil.read_resource} instead.
     */
    [Version (deprecated = true)]
    public string read_resource(string name) throws Error {
        return GioUtil.read_resource(name);
    }

    /**
     * Loads a UI GResource into the UI manager.
     */
    [Version (deprecated = true)]
    public void load_ui_resource(string name) {
        try {
            this.ui_manager.add_ui_from_resource("/org/gnome/Geary/" + name);
        } catch(GLib.Error error) {
            critical("Unable to load \"%s\" for Gtk.UIManager: %s".printf(
                name, error.message
            ));
        }
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
        
        // Give asynchronous destroy_async() a chance to complete, but to avoid bug(s) where
        // Geary hangs at exit, shut the whole thing down if destroy_async() takes too long to
        // complete
        int64 start_usec = get_monotonic_time();
        destroy_async.begin();
        while (!is_destroyed || Gtk.events_pending()) {
            Gtk.main_iteration();
            
            int64 delta_usec = get_monotonic_time() - start_usec;
            if (delta_usec >= FORCE_SHUTDOWN_USEC) {
                debug("Forcing shutdown of Geary, %ss passed...", (delta_usec / USEC_PER_SEC).to_string());
                
                break;
            }
        }
        
        if (Gtk.main_level() > 0)
            Gtk.main_quit();
        else
            Posix.exit(exitcode);
        
        Date.terminate();
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

    private void on_activate_about() {
        Gtk.show_about_dialog(get_active_window(),
            "program-name", NAME,
            "comments", DESCRIPTION,
            "authors", AUTHORS,
            "copyright", COPYRIGHT,
            "license-type", Gtk.License.LGPL_2_1,
            "logo-icon-name", "geary",
            "version", VERSION,
            "website", WEBSITE,
            "website-label", WEBSITE_LABEL,
            "title", _("About %s").printf(NAME),
            // Translators: add your name and email address to receive
            // credit in the About dialog For example: Yamada Taro
            // <yamada.taro@example.com>
            "translator-credits", _("translator-credits")
        );
    }

    private void on_activate_accounts() {
        AccountDialog dialog = new AccountDialog(get_active_window());
        dialog.show_all();
        dialog.run();
        dialog.destroy();
    }

    private void on_activate_compose() {
        if (this.controller != null) {
            this.controller.compose();
        }
    }

    private void on_activate_mailto(SimpleAction action, Variant? param) {
        if (this.controller != null && param != null) {
            this.controller.compose_mailto(param.get_string());
        }
    }

    private void on_activate_preferences() {
        PreferencesDialog dialog = new PreferencesDialog(get_active_window());
        dialog.run();
    }

    private void on_activate_quit() {
        exit();
    }

    private void on_activate_help() {
        try {
            if (is_installed()) {
                Gtk.show_uri(null, "ghelp:geary", Gdk.CURRENT_TIME);
            } else {
                Pid pid;
                File exec_dir = get_exec_dir();
                string[] argv = new string[3];
                argv[0] = "gnome-help";
                argv[1] = GearyApplication.SOURCE_ROOT_DIR + "/help/C/";
                argv[2] = null;
                if (!Process.spawn_async(
                        exec_dir.get_path(),
                        argv,
                        null,
                        SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
                        null,
                        out pid)) {
                    debug("Failed to launch help locally.");
                }
            }
        } catch (Error error) {
            debug("Error showing help: %s", error.message);
            Gtk.Dialog dialog = new Gtk.Dialog.with_buttons(
                "Error",
                get_active_window(),
                Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Stock._CLOSE, Gtk.ResponseType.CLOSE, null);
            dialog.response.connect(() => { dialog.destroy(); });
            dialog.get_content_area().add(
                new Gtk.Label("Error showing help: %s".printf(error.message))
            );
            dialog.show_all();
            dialog.run();
        }
    }

}
