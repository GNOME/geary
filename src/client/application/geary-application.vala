/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _INSTALL_PREFIX;
extern const string _GSETTINGS_DIR;
extern const string _WEB_EXTENSIONS_DIR;
extern const string _SOURCE_ROOT_DIR;
extern const string _BUILD_ROOT_DIR;
extern const string GETTEXT_PACKAGE;

/**
 * The interface between Geary and the desktop environment.
 */
public class GearyApplication : Gtk.Application {

    public const string NAME = "Geary";
    public const string APP_ID = "org.gnome.Geary";
    public const string DESCRIPTION = _("Send and receive email");
    public const string COPYRIGHT_1 = _("Copyright 2016 Software Freedom Conservancy Inc.");
    public const string COPYRIGHT_2 = _("Copyright 2016-2019 Geary Development Team.");
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
        "Michael Gratton <mike@vee.net>",
        null
    };

    // Common window actions
    public const string ACTION_CLOSE = "close";
    public const string ACTION_COPY = "copy";
    public const string ACTION_HELP_OVERLAY = "show-help-overlay";
    public const string ACTION_REDO = "redo";
    public const string ACTION_UNDO = "undo";

    // App-wide actions
    public const string ACTION_ABOUT = "about";
    public const string ACTION_ACCOUNTS = "accounts";
    public const string ACTION_COMPOSE = "compose";
    public const string ACTION_INSPECT = "inspect";
    public const string ACTION_HELP = "help";
    public const string ACTION_MAILTO = "mailto";
    public const string ACTION_PREFERENCES = "preferences";
    public const string ACTION_QUIT = "quit";

    // Local-only command line options
    private const string OPTION_VERSION = "version";

    // Local command line options
    private const string OPTION_DEBUG = "debug";
    private const string OPTION_INSPECTOR = "inspector";
    private const string OPTION_LOG_CONVERSATIONS = "log-conversations";
    private const string OPTION_LOG_DESERIALIZER = "log-deserializer";
    private const string OPTION_LOG_FOLDER_NORM = "log-folder-normalization";
    private const string OPTION_LOG_NETWORK = "log-network";
    private const string OPTION_LOG_PERIODIC = "log-periodic";
    private const string OPTION_LOG_REPLAY_QUEUE = "log-replay-queue";
    private const string OPTION_LOG_SERIALIZER = "log-serializer";
    private const string OPTION_LOG_SQL = "log-sql";
    private const string OPTION_QUIT = "quit";
    private const string OPTION_REVOKE_CERTS = "revoke-certs";

    private const ActionEntry[] action_entries = {
        {ACTION_ABOUT, on_activate_about},
        {ACTION_ACCOUNTS, on_activate_accounts},
        {ACTION_COMPOSE, on_activate_compose},
        {ACTION_INSPECT, on_activate_inspect},
        {ACTION_HELP, on_activate_help},
        {ACTION_MAILTO, on_activate_mailto, "s"},
        {ACTION_PREFERENCES, on_activate_preferences},
        {ACTION_QUIT, on_activate_quit},
    };

    // This is also the order in which they are presented to the user,
    // so it's probably best to keep them alphabetical
    public const GLib.OptionEntry[] OPTION_ENTRIES = {
        { OPTION_DEBUG, 'd', 0, GLib.OptionArg.NONE, null,
          N_("Print debug logging"), null },
        { OPTION_INSPECTOR, 'i', 0, GLib.OptionArg.NONE, null,
          N_("Enable WebKitGTK Inspector in web views"), null },
        { OPTION_LOG_CONVERSATIONS, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log conversation monitoring"), null },
        { OPTION_LOG_DESERIALIZER, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log IMAP network deserialization"), null },
        /// "Normalization" can also be called "synchronization"
        { OPTION_LOG_FOLDER_NORM, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log folder normalization"), null },
        { OPTION_LOG_NETWORK, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log network activity"), null },
        { OPTION_LOG_PERIODIC, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log periodic activity"), null },
        /// The IMAP replay queue is how changes on the server are
        /// replicated on the client.  It could also be called the
        /// IMAP events queue.
        { OPTION_LOG_REPLAY_QUEUE, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log IMAP replay queue"), null },
        /// Serialization is how commands and responses are converted
        /// into a stream of bytes for network transmission
        { OPTION_LOG_SERIALIZER, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log IMAP network serialization"), null },
        { OPTION_LOG_SQL, 0, 0, GLib.OptionArg.NONE, null,
          N_("Log database queries (generates lots of messages)"), null },
        { OPTION_QUIT, 'q', 0, GLib.OptionArg.NONE, null,
          N_("Perform a graceful quit"), null },
        { OPTION_REVOKE_CERTS, 0, 0, GLib.OptionArg.NONE, null,
          N_("Revoke all pinned TLS server certificates"), null },
        { OPTION_VERSION, 'v', 0, GLib.OptionArg.NONE, null,
          N_("Display program version"), null },
        /// Use this to specify arguments in the help section
        { "", 0, 0, GLib.OptionArg.NONE, null, null, "[mailto:[...]]" },
        { null }
    };

    private const int64 USEC_PER_SEC = 1000000;
    private const int64 FORCE_SHUTDOWN_USEC = 5 * USEC_PER_SEC;


    /** Object returned by {@link get_runtime_information}. */
    public struct RuntimeDetail {

        public string name;
        public string value;

    }

    [Version (deprecated = true)]
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
     * closed, instead of exiting as usual.
     */
    public bool is_background_service {
        get { return (this.flags & ApplicationFlags.IS_SERVICE) != 0; }
    }

    private string bin;
    private File exec_dir;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private bool is_destroyed = false;
    private Components.Inspector? inspector = null;


    /**
     * Returns name/value pairs of application information.
     *
     * This includes Geary library version information, the current
     * desktop, and so on.
     */
    public Gee.Collection<RuntimeDetail?> get_runtime_information() {
        Gee.LinkedList<RuntimeDetail?> info =
            new Gee.LinkedList<RuntimeDetail?>();

        /// Application runtime information label
        info.add({ _("Geary version"), VERSION });
        /// Application runtime information label
        info.add({ _("GTK version"),
                    "%u.%u.%u".printf(
                        Gtk.get_major_version(),
                        Gtk.get_minor_version(),
                        Gtk.get_micro_version()
                    )});
        /// Applciation runtime information label
        info.add({ _("GLib version"),
                    "%u.%u.%u".printf(
                        GLib.Version.major,
                        GLib.Version.minor,
                        GLib.Version.micro
                    )});
        /// Application runtime information label
        info.add({ _("WebKitGTK version"),
                    "%u.%u.%u".printf(
                        WebKit.get_major_version(),
                        WebKit.get_minor_version(),
                        WebKit.get_micro_version()
                    )});
        /// Application runtime information label
        info.add({ _("Desktop environment"),
                    Environment.get_variable("XDG_CURRENT_DESKTOP") ??
                    _("Unknown")
            });

        // Distro name and version using LSB util

        GLib.SubprocessLauncher launcher = new GLib.SubprocessLauncher(
            GLib.SubprocessFlags.STDOUT_PIPE |
            GLib.SubprocessFlags.STDERR_SILENCE
        );
        // Reset lang vars so we can guess the strings below
        launcher.setenv("LANGUAGE", "C", true);
        launcher.setenv("LANG", "C", true);
        launcher.setenv("LC_ALL", "C", true);

        string lsb_output = "";
        try {
            GLib.Subprocess lsb_release = launcher.spawnv(
                { "lsb_release", "-ir" }
            );
            lsb_release.communicate_utf8(null, null, out lsb_output, null);
        } catch (GLib.Error err) {
            warning("Failed to exec lsb_release: %s", err.message);
        }
        if (lsb_output != "") {
            foreach (string line in lsb_output.split("\n")) {
                string[] parts = line.split(":", 2);
                if (parts.length > 1) {
                    if (parts[0].has_prefix("Distributor ID")) {
                        /// Application runtime information label
                        info.add(
                            { _("Distribution name"), parts[1].strip() }
                        );
                    } else if (parts[0].has_prefix("Release")) {
                        /// Application runtime information label
                        info.add(
                            { _("Distribution release"), parts[1].strip() }
                        );
                    }
                }
            }
        }

        /// Application runtime information label
        info.add({ _("Installation prefix"), INSTALL_PREFIX });

        return info;
    }

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
            application_id: APP_ID,
            flags: ApplicationFlags.HANDLES_COMMAND_LINE
        );
        this.add_main_option_entries(OPTION_ENTRIES);
        _instance = this;
    }

    public override bool local_command_line(ref unowned string[] args,
                                            out int exit_status) {
        this.bin = args[0];
        string current_path = Posix.realpath(Environment.find_program_in_path(this.bin));
        this.exec_dir = File.new_for_path(current_path).get_parent();

        return base.local_command_line(ref args, out exit_status);
    }

    public override int handle_local_options(GLib.VariantDict options) {
        if (options.contains(OPTION_VERSION)) {
            GLib.stdout.printf(
                "%s: %s\n", this.bin, GearyApplication.VERSION
            );
            return 0;
        }

        return -1;
    }

    public override void startup() {
        Environment.set_application_name(NAME);
        International.init(GETTEXT_PACKAGE, this.bin);

        Configuration.init(is_installed(), GSETTINGS_DIR);
        Geary.Logging.init();
        Geary.Logging.log_to(stderr);
        GLib.Log.set_default_handler(Geary.Logging.default_handler);

        Util.Date.init();

        // Calls Gtk.init(), amongst other things
        base.startup();

        // Ensure all geary windows have an icon
        Gtk.Window.set_default_icon_name(APP_ID);

        this.config = new Configuration(APP_ID);

        add_action_entries(action_entries, this);

        if (this.is_background_service) {
            // Since command_line won't be called below if running as
            // a DBus service, disable logging spew and start the
            // controller running.
            Geary.Logging.log_to(null);
            this.create_async.begin();
        }
    }

    public override int command_line(ApplicationCommandLine command_line) {
        int exit_value = handle_general_options(this.config, command_line.get_options_dict());
        if (exit_value != -1)
            return exit_value;

        exit_value = handle_arguments(this, command_line.get_arguments());
        if (exit_value != -1)
            return exit_value;

        activate();

        return -1;
    }

    public override void activate() {
        base.activate();

        if (!present())
            create_async.begin();
    }

    public bool present() {
        if (controller == null || controller.main_window == null)
            return false;

        // Use present_with_time and a synthesised time so the present
        // actually works, as a work around for Bug 766284
        // <https://bugzilla.gnome.org/show_bug.cgi?id=766284>.
        // Subtract 1000ms from the current time to avoid the main
        // window stealing the focus when presented just before
        // showing a dialog (issue #43, bgo 726282).
        this.controller.main_window.present_with_time(
            (uint32) (get_monotonic_time() / 1000) - 1000
        );

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

        // Application accels
        add_app_accelerators(ACTION_COMPOSE, { "<Ctrl>N" });
        add_app_accelerators(ACTION_HELP, { "F1" });
        add_app_accelerators(ACTION_INSPECT, { "<Alt><Shift>I" });
        add_app_accelerators(ACTION_QUIT, { "<Ctrl>Q" });

        // Common window accels
        add_window_accelerators(ACTION_CLOSE, { "<Ctrl>W" });
        add_window_accelerators(ACTION_COPY, { "<Ctrl>C" });
        add_window_accelerators(ACTION_HELP_OVERLAY, { "<Ctrl>F1", "<Ctrl>question" });
        add_window_accelerators(ACTION_REDO, { "<Ctrl><Shift>Z" });
        add_window_accelerators(ACTION_UNDO, { "<Ctrl>Z" });

        ComposerWidget.add_window_accelerators(this);
        Components.Inspector.add_window_accelerators(this);

        yield this.controller.open_async(null);

        release();
    }

    private async void destroy_async() {
        // see create_async() for reasoning hold/release is used
        hold();

        if (this.controller != null && this.controller.is_open) {
            yield this.controller.close_async();
        }

        release();
        this.is_destroyed = true;
    }

    public void add_window_accelerators(string action,
                                        string[] accelerators,
                                        Variant? param = null) {
        string name = "win." + action;
        string[] all_accel = get_accels_for_action(name);
        foreach (string accel in accelerators) {
            all_accel += accel;
        }
        set_accels_for_action(name, all_accel);
    }

    public void show_accounts() {
        activate();

        Accounts.Editor editor = new Accounts.Editor(this, get_active_window());
        editor.run();
        editor.destroy();
        this.controller.expunge_accounts.begin();
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
     * When running from the installation prefix, this will be based
     * on the Meson `libdir` option, and can be set by invoking `meson
     * configure` as appropriate.
     */
    public File get_web_extensions_dir() {
        return (get_install_dir() != null)
            ? File.new_for_path(_WEB_EXTENSIONS_DIR)
            : File.new_for_path(BUILD_ROOT_DIR).get_child("src");
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
     * Displays a URI on the current active window, if any.
     */
    public void show_uri(string uri) throws Error {
        bool success = Gtk.show_uri_on_window(
            get_active_window(), uri, Gdk.CURRENT_TIME
        );
        if (!success) {
            throw new IOError.FAILED("gtk_show_uri() returned false");
        }
    }

    // This call will fire "exiting" only if it's not already been fired.
    public void exit(int exitcode = 0) {
        if (this.exiting_fired)
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
                Posix.exit(2);
            }
        }

        quit();
        Util.Date.terminate();
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

    public void add_app_accelerators(string action,
                                     string[] accelerators,
                                     Variant? param = null) {
        set_accels_for_action("app." + action, accelerators);
    }

    public int handle_general_options(Configuration config,
                                      GLib.VariantDict options) {
        if (options.contains(OPTION_QUIT)) {
            exit();
            return 0;
        }

        bool enable_debug = options.contains(OPTION_DEBUG);
        // Will be logging to stderr until this point
        if (enable_debug) {
            Geary.Logging.log_to(GLib.stdout);
        } else {
            Geary.Logging.log_to(null);
        }

        // Logging flags
        if (options.contains(OPTION_LOG_NETWORK))
            Geary.Logging.enable_flags(Geary.Logging.Flag.NETWORK);
        if (options.contains(OPTION_LOG_SERIALIZER))
            Geary.Logging.enable_flags(Geary.Logging.Flag.SERIALIZER);
        if (options.contains(OPTION_LOG_REPLAY_QUEUE))
            Geary.Logging.enable_flags(Geary.Logging.Flag.REPLAY);
        if (options.contains(OPTION_LOG_CONVERSATIONS))
            Geary.Logging.enable_flags(Geary.Logging.Flag.CONVERSATIONS);
        if (options.contains(OPTION_LOG_PERIODIC))
            Geary.Logging.enable_flags(Geary.Logging.Flag.PERIODIC);
        if (options.contains(OPTION_LOG_SQL))
            Geary.Logging.enable_flags(Geary.Logging.Flag.SQL);
        if (options.contains(OPTION_LOG_FOLDER_NORM))
            Geary.Logging.enable_flags(Geary.Logging.Flag.FOLDER_NORMALIZATION);
        if (options.contains(OPTION_LOG_DESERIALIZER))
            Geary.Logging.enable_flags(Geary.Logging.Flag.DESERIALIZER);

        config.enable_debug = enable_debug;
        config.enable_inspector = options.contains(OPTION_INSPECTOR);
        config.revoke_certs = options.contains(OPTION_REVOKE_CERTS);

        return -1;
    }

    /**
     * Handles the actual arguments of the application.
     */
    public int handle_arguments(GearyApplication app, string[] args) {
        for (int ctr = 1; ctr < args.length; ctr++) {
            string arg = args[ctr];

            // the only acceptable arguments are mailto:'s
            if (arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                if (arg == Geary.ComposedEmail.MAILTO_SCHEME)
                    app.activate_action(GearyApplication.ACTION_COMPOSE, null);
                else
                    app.activate_action(GearyApplication.ACTION_MAILTO, new Variant.string(arg));
            } else {
                stdout.printf(_("Unrecognized argument: “%s”\n").printf(arg));
                stdout.printf(_("Geary only accepts mailto-links as arguments.\n"));

                return 1;
            }
        }

        return -1;
    }

    private void on_activate_about() {
        Gtk.show_about_dialog(get_active_window(),
            "program-name", NAME,
            "comments", DESCRIPTION,
            "authors", AUTHORS,
            "copyright", string.join("\n", COPYRIGHT_1, COPYRIGHT_2),
            "license-type", Gtk.License.LGPL_2_1,
            "logo-icon-name", APP_ID,
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
        show_accounts();
    }

    private void on_activate_compose() {
        if (this.controller != null) {
            this.controller.compose();
        }
    }

    private void on_activate_inspect() {
        if (this.inspector == null) {
            this.inspector = new Components.Inspector(this);
            this.inspector.destroy.connect(() => {
                    this.inspector = null;
                });
            this.inspector.show();
        } else {
            this.inspector.present();
        }
    }

    private void on_activate_mailto(SimpleAction action, Variant? param) {
        if (this.controller != null && param != null) {
            this.controller.compose(param.get_string());
        }
    }

    private void on_activate_preferences() {
        PreferencesDialog dialog = new PreferencesDialog(get_active_window(), this);
        dialog.run();
    }

    private void on_activate_quit() {
        exit();
    }

    private void on_activate_help() {
        try {
            if (is_installed()) {
                show_uri("help:geary");
            } else {
                Pid pid;
                File exec_dir = get_exec_dir();
                string[] argv = new string[3];
                argv[0] = "yelp";
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
