/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _INSTALL_PREFIX;
extern const string _GSETTINGS_DIR;
extern const string _WEB_EXTENSIONS_DIR;
extern const string _PLUGINS_DIR;
extern const string _SOURCE_ROOT_DIR;
extern const string _BUILD_ROOT_DIR;
extern const string GETTEXT_PACKAGE;
extern const string _APP_ID;
extern const string _NAME_SUFFIX;
extern const string _PROFILE;
extern const string _VERSION;
extern const string _REVNO;

/**
 * The interface between Geary and the desktop environment.
 */
public class GearyApplication : Gtk.Application {

    public const string NAME = "Geary" + _NAME_SUFFIX;
    public const string APP_ID = _APP_ID;
    public const string SCHEMA_ID = "org.gnome.Geary";
    public const string DESCRIPTION = _("Send and receive email");
    public const string COPYRIGHT_1 = _("Copyright 2016 Software Freedom Conservancy Inc.");
    public const string COPYRIGHT_2 = _("Copyright 2016-2019 Geary Development Team.");
    public const string WEBSITE = "https://wiki.gnome.org/Apps/Geary";
    public const string WEBSITE_LABEL = _("Visit the Geary web site");
    public const string BUGREPORT = "https://wiki.gnome.org/Apps/Geary/ReportingABug";

    public const string VERSION = _VERSION;
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
    public const string ACTION_SHOW_EMAIL = "show-email";
    public const string ACTION_SHOW_FOLDER = "show-folder";
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
    private const string OPTION_HIDDEN = "hidden";
    private const string OPTION_QUIT = "quit";
    private const string OPTION_REVOKE_CERTS = "revoke-certs";

    private const ActionEntry[] ACTION_ENTRIES = {
        {ACTION_ABOUT, on_activate_about},
        {ACTION_ACCOUNTS, on_activate_accounts},
        {ACTION_COMPOSE, on_activate_compose},
        {ACTION_HELP, on_activate_help},
        {ACTION_INSPECT, on_activate_inspect},
        {ACTION_MAILTO, on_activate_mailto, "s"},
        {ACTION_PREFERENCES, on_activate_preferences},
        {ACTION_QUIT, on_activate_quit},
        {ACTION_SHOW_EMAIL, on_activate_show_email, "(svv)"},
        {ACTION_SHOW_FOLDER, on_activate_show_folder, "(sv)"}
    };

    // This is also the order in which they are presented to the user,
    // so it's probably best to keep them alphabetical
    private const GLib.OptionEntry[] OPTION_ENTRIES = {
        { OPTION_DEBUG, 'd', 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Print debug logging"), null },
        { OPTION_HIDDEN, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Start with the main window hidden (deprecated)"), null },
        { OPTION_INSPECTOR, 'i', 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Enable WebKitGTK Inspector in web views"), null },
        { OPTION_LOG_CONVERSATIONS, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Log conversation monitoring"), null },
        { OPTION_LOG_DESERIALIZER, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Log IMAP network deserialization"), null },
        { OPTION_LOG_FOLDER_NORM, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option. "Normalization" can also be called
          /// "synchronization".
          N_("Log folder normalization"), null },
        { OPTION_LOG_NETWORK, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Log network activity"), null },
        { OPTION_LOG_PERIODIC, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Log periodic activity"), null },
        { OPTION_LOG_REPLAY_QUEUE, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option. The IMAP replay queue is how changes
          /// on the server are replicated on the client.  It could
          /// also be called the IMAP events queue.
          N_("Log IMAP replay queue"), null },
        { OPTION_LOG_SERIALIZER, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option. Serialization is how commands and
          /// responses are converted into a stream of bytes for
          /// network transmission
          N_("Log IMAP network serialization"), null },
        { OPTION_LOG_SQL, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Log database queries (generates lots of messages)"), null },
        { OPTION_QUIT, 'q', 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Perform a graceful quit"), null },
        { OPTION_REVOKE_CERTS, 0, 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Revoke all pinned TLS server certificates"), null },
        { OPTION_VERSION, 'v', 0, GLib.OptionArg.NONE, null,
          /// Command line option
          N_("Display program version"), null },
          // Use this to specify arguments in the help section
        { GLib.OPTION_REMAINING, 0, 0, GLib.OptionArg.STRING_ARRAY, null, null,
          "[mailto:[...]]" },
        { null }
    };

    private const string MAILTO_URI_SCHEME_PREFIX = "mailto:";
    private const int64 USEC_PER_SEC = 1000000;
    private const int64 FORCE_SHUTDOWN_USEC = 5 * USEC_PER_SEC;

    private const string ERROR_NOTIFICATION_ID = "error";



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
     * The global controller for this application instance.
     *
     * This will be non-null in the primary application instance, only
     * after initial activation, or after startup if {@link
     * is_background_service} is true.
     */
    public Application.Controller? controller {
        get; private set; default = null;
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
     * The user's desktop settings for the application.
     *
     * This will be null until {@link startup} has been called, and
     * hence will only ever become non-null for the primary instance.
     */
    public Configuration? config {
        get; private set; default = null;
    }

    /**
     * Manages the autostart desktop file.
     *
     * This will be null until {@link startup} has been called, and
     * hence will only ever become non-null for the primary instance.
     */
    public Application.StartupManager? autostart {
        get; private set; default = null;
    }

    /**
     * Determines if Geary configured to run as as a background service.
     *
     * If this returns `true`, then the primary application instance
     * will continue to run in the background after the last window is
     * closed, instead of exiting as usual.
     */
    public bool is_background_service {
        get {
            return (
                (this.flags & ApplicationFlags.IS_SERVICE) != 0 ||
                this.start_hidden
            );
        }
    }

    /**
     * Determines if this instance is running from the install directory.
     */
    internal bool is_installed {
        get {
            return this.exec_dir.has_prefix(this.install_prefix);
        }
    }

    /** Returns the compile-time configured installation directory. */
    internal GLib.File install_prefix {
        get; private set; default = GLib.File.new_for_path(INSTALL_PREFIX);
    }


    private File exec_dir;
    private string binary;
    private bool start_hidden = false;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private bool is_destroyed = false;
    private GLib.Cancellable controller_cancellable = new GLib.Cancellable();
    private Components.Inspector? inspector = null;
    private Geary.Nonblocking.Mutex controller_mutex = new Geary.Nonblocking.Mutex();
    private GLib.Notification? error_notification = null;


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
        info.add({ _("Geary revision"), _REVNO });
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
     * To cancel an exit, a callback should return GearyApplication.cancel_exit(). To proceed with
     * an exit, a callback should return true.
     */
    public virtual signal bool exiting(bool panicked) {
        return true;
    }


    public GearyApplication() {
        Object(
            application_id: APP_ID,
            flags: (
                GLib.ApplicationFlags.HANDLES_OPEN |
                GLib.ApplicationFlags.HANDLES_COMMAND_LINE
            )
        );
        this.add_main_option_entries(OPTION_ENTRIES);
        _instance = this;
    }

    public override bool local_command_line(ref unowned string[] args,
                                            out int exit_status) {
        this.binary = args[0];
        string? current_path = Posix.realpath(
            GLib.Environment.find_program_in_path(this.binary)
        );
        if (current_path == null) {
            // Couldn't find the path, are being run as a unit test?
            // Probably should deal with the null either way though.
            current_path = this.binary;
        }
        this.exec_dir = GLib.File.new_for_path(current_path).get_parent();

        return base.local_command_line(ref args, out exit_status);
    }

    public override int handle_local_options(GLib.VariantDict options) {
        if (options.contains(OPTION_VERSION)) {
            GLib.stdout.printf(
                "%s: %s\n", this.binary, GearyApplication.VERSION
            );
            return 0;
        }
        return -1;
    }

    public override void startup() {
        Environment.set_application_name(NAME);
        Util.International.init(GETTEXT_PACKAGE, this.binary);

        Configuration.init(this.is_installed, GSETTINGS_DIR);
        Geary.Logging.init();
        Geary.Logging.log_to(stderr);
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);

        Util.Date.init();

        // Add application's actions before chaining up so they are
        // present when the application is first registered on the
        // session bus.
        add_action_entries(ACTION_ENTRIES, this);

        // Calls Gtk.init(), amongst other things
        base.startup();

        this.config = new Configuration(SCHEMA_ID);
        this.autostart = new Application.StartupManager(
            this.config, this.get_desktop_directory()
        );

        // Ensure all geary windows have an icon
        Gtk.Window.set_default_icon_name(APP_ID);

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

        MainWindow.add_window_accelerators(this);
        ComposerWidget.add_window_accelerators(this);
        Components.Inspector.add_window_accelerators(this);

        if (this.is_background_service) {
            // Since command_line won't be called below if running as
            // a DBus service, disable logging spew and start the
            // controller running.
            Geary.Logging.log_to(null);
            this.create_controller.begin();
        }
    }

    public override int command_line(GLib.ApplicationCommandLine command_line) {
        int exit_value = handle_general_options(command_line);
        if (exit_value != -1)
            return exit_value;

        return -1;
    }

    public override void activate() {
        base.activate();
        this.present.begin();
    }

    public override void open(GLib.File[] targets, string hint) {
        foreach (GLib.File target in targets) {
            if (target.get_uri_scheme() == "mailto") {
                string mailto = target.get_uri();
                // Due to GNOME/glib#1886, the email address may be
                // prefixed by a '///'. If so, remove it.
                const string B0RKED_GLIB_MAILTO_PREFIX = "mailto:///";
                if (mailto.has_prefix(B0RKED_GLIB_MAILTO_PREFIX)) {
                    mailto = (
                        MAILTO_URI_SCHEME_PREFIX +
                        mailto.substring(B0RKED_GLIB_MAILTO_PREFIX.length)
                    );
                }
                this.new_composer.begin(mailto);
            }
        }
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

    public async void show_about() {
        yield this.present();

        Gtk.show_about_dialog(get_active_window(),
            "program-name", NAME,
            "comments", DESCRIPTION,
            "authors", AUTHORS,
            "copyright", string.join("\n", COPYRIGHT_1, COPYRIGHT_2),
            "license-type", Gtk.License.LGPL_2_1,
            "logo-icon-name", APP_ID,
            "version", _REVNO == "" ? VERSION : "%s (%s)".printf(VERSION, _REVNO),
            "website", WEBSITE,
            "website-label", WEBSITE_LABEL,
            "title", _("About %s").printf(NAME),
            // Translators: add your name and email address to receive
            // credit in the About dialog For example: Yamada Taro
            // <yamada.taro@example.com>
            "translator-credits", _("translator-credits")
        );
    }

    public async void show_accounts() {
        yield this.present();

        Accounts.Editor editor = new Accounts.Editor(this, get_active_window());
        editor.run();
        editor.destroy();
        this.controller.expunge_accounts.begin();
    }

    public async void show_email(Geary.Folder? folder,
                                 Geary.EmailIdentifier id) {
        yield this.present();

        this.controller.main_window.show_email(folder, id);
    }

    public async void show_folder(Geary.Folder? folder) {
        yield this.present();

        this.controller.main_window.show_folder(folder);
    }

    public async void show_inspector() {
        yield this.present();

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

    public async void show_preferences() {
        yield this.present();

        PreferencesDialog dialog = new PreferencesDialog(
            get_active_window(), this
        );
        dialog.run();
    }

    public async void new_composer(string? mailto) {
        yield this.present();

        this.controller.compose(mailto);
    }

    /** Returns the application's base user configuration directory. */
    public GLib.File get_user_config_directory() {
        return GLib.File.new_for_path(
            Environment.get_user_config_dir()
        ).get_child("geary");
    }

    /** Returns the application's base user cache directory. */
    public GLib.File get_user_cache_directory() {
        return GLib.File.new_for_path(
            GLib.Environment.get_user_cache_dir()
        ).get_child("geary");
    }

    /** Returns the application's base user data directory. */
    public GLib.File get_user_data_directory() {
        return GLib.File.new_for_path(
            GLib.Environment.get_user_data_dir()
        ).get_child("geary");
    }

    /** Returns the application's base static resources directory. */
    public GLib.File get_resource_directory() {
        return (is_installed)
            ? this.install_prefix.get_child("share").get_child("geary")
            : GLib.File.new_for_path(SOURCE_ROOT_DIR);
    }

    /** Returns the location of the application's desktop files. */
    public GLib.File get_desktop_directory() {
        return (is_installed)
            ? this.install_prefix.get_child("share").get_child("applications")
            : GLib.File.new_for_path(BUILD_ROOT_DIR).get_child("desktop");
    }

    /**
     * Returns the directory containing the application's WebExtension libs.
     *
     * When running from the installation prefix, this will be based
     * on the Meson `libdir` option, and can be set by invoking `meson
     * configure` as appropriate.
     */
    public GLib.File get_web_extensions_dir() {
        return (is_installed)
            ? GLib.File.new_for_path(_WEB_EXTENSIONS_DIR)
            : GLib.File.new_for_path(BUILD_ROOT_DIR).get_child("src");
    }

    /**
     * Returns the directory containing the application's plugins.
     *
     * When running from the installation prefix, this will be based
     * on the Meson `libdir` option, and can be set by invoking `meson
     * configure` as appropriate.
     */
    public GLib.File get_app_plugins_dir() {
        return (is_installed)
            ? GLib.File.new_for_path(_PLUGINS_DIR)
            : GLib.File.new_for_path(BUILD_ROOT_DIR)
                  .get_child("src").get_child("client").get_child("plugin");
    }

    /** Displays a URI on the current active window, if any. */
    public async void show_uri(string uri) {
        yield create_controller();

        if (uri.down().has_prefix(MAILTO_URI_SCHEME_PREFIX)) {
            yield this.new_composer(uri);
        } else {
            string uri_ = uri;
            // Support web URLs that omit the protocol.
            if (!uri.contains(":")) {
                uri_ = "http://" + uri;
            }

            try {
                Gtk.show_uri_on_window(
                    get_active_window(), uri_, Gdk.CURRENT_TIME
                );
            } catch (GLib.Error err) {
                this.controller.report_problem(new Geary.ProblemReport(err));
            }
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

        this.controller_cancellable.cancel();

        // Give asynchronous destroy_controller() a chance to
        // complete, but to avoid bug(s) where Geary hangs at exit,
        // shut the whole thing down if destroy_controller() takes too
        // long to complete
        int64 start_usec = get_monotonic_time();
        destroy_controller.begin();
        while (!is_destroyed || Gtk.events_pending()) {
            Gtk.main_iteration();

            int64 delta_usec = get_monotonic_time() - start_usec;
            if (delta_usec >= FORCE_SHUTDOWN_USEC) {
                debug("Forcing shutdown of Geary, %ss passed...", (delta_usec / USEC_PER_SEC).to_string());
                Posix.exit(2);
            }
        }

        quit();

        Geary.Logging.clear();
        Util.Date.terminate();
    }

    /**
     * A callback for GearyApplication.exiting should return
     * cancel_exit() to prevent the application from exiting.
     */
    public bool cancel_exit() {
        Signal.stop_emission_by_name(this, "exiting");
        return false;
    }

    /**
     * Causes the application to exit immediately.
     *
     * This call will fire "exiting" only if it's not already been
     * fired and halt the application in its tracks
     */
    public void panic() {
        if (!exiting_fired) {
            exiting_fired = true;
            exiting(true);
        }

        Posix.exit(1);
    }

    /**
     * Displays an error notification.
     *
     * Use _very_ sparingly.
     */
    internal void send_error_notification(string summary, string body) {
        if (this.error_notification != null) {
            clear_error_notification();
        }

        GLib.Notification error = new GLib.Notification(summary);
        error.set_body(body);
        error.set_icon(
            new GLib.ThemedIcon("%s-symbolic".printf(GearyApplication.APP_ID))
        );
        send_notification(ERROR_NOTIFICATION_ID, error);
        this.error_notification = error;
    }

    internal void clear_error_notification() {
        this.error_notification = null;
        withdraw_notification(ERROR_NOTIFICATION_ID);
    }

    // Presents a main window. If the controller is not open, opens it
    // first.
    private async void present() {
        yield create_controller();
        this.controller.main_window.present();
    }

    // Opens the controller
    private async void create_controller() {
        // Manually keep the main loop around for the duration of this
        // call. Without this, the main loop will exit as soon as we
        // hit the yield below, before we create the main window.
        hold();

        bool first_run = false;
        try {
            int mutex_token = yield this.controller_mutex.claim_async();
            if (this.controller == null) {
                message(
                    "%s %s%s prefix=%s exec_dir=%s is_installed=%s",
                    NAME,
                    VERSION,
                    _REVNO != "" ? " (%s)".printf(_REVNO) : "",
                    INSTALL_PREFIX,
                    exec_dir.get_path(),
                    this.is_installed.to_string()
                );

                this.controller = yield new Application.Controller(
                    this, this.controller_cancellable
                );
                first_run = !this.engine.has_accounts;
            }
            this.controller_mutex.release(ref mutex_token);
        } catch (Error err) {
            error("Error creating controller: %s", err.message);
        }

        if (first_run) {
            yield show_accounts();
            if (!this.engine.has_accounts) {
                // No accounts were added after showing the accounts
                // editor, so nothing else to do but exit.
                quit();
            }
        }

        release();
    }

    // Closes the controller, if running
    private async void destroy_controller() {
        // see create_controller() for reasoning hold/release is used
        hold();

        try {
            int mutex_token = yield this.controller_mutex.claim_async();
            if (this.controller != null) {
                yield this.controller.close_async();
                this.controller = null;
            }
            this.controller_mutex.release(ref mutex_token);
        } catch (Error err) {
            debug("Error destroying controller: %s", err.message);
        }

        release();
        this.is_destroyed = true;
    }

    private int handle_general_options(GLib.ApplicationCommandLine command_line) {
        GLib.VariantDict options = command_line.get_options_dict();
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

        bool activated = false;

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
        if (options.contains(OPTION_HIDDEN)) {
            warning(
                /// Warning printed to the console when a deprecated
                /// command line option is used.
                _("The `--hidden` option is deprecated and will be removed in the future.")
            );
            this.start_hidden = true;
            // Update the autostart file so that it stops using the
            // --hidden option.
            this.update_autostart_file.begin();
            // Then manually start the controller
            this.create_controller.begin();
            activated = true;
        }

        if (options.contains(GLib.OPTION_REMAINING)) {
            string[] args = options.lookup_value(
                GLib.OPTION_REMAINING,
                GLib.VariantType.STRING_ARRAY
            ).get_strv();
            foreach (string arg in args) {
                // the only acceptable arguments are mailto:'s
                if (arg == MAILTO_URI_SCHEME_PREFIX) {
                    activate_action(GearyApplication.ACTION_COMPOSE, null);
                    activated = true;
                } else if (arg.down().has_prefix(MAILTO_URI_SCHEME_PREFIX)) {
                    activate_action(
                        GearyApplication.ACTION_MAILTO,
                        new GLib.Variant.string(arg)
                    );
                    activated = true;
                } else {
                    command_line.printerr("%s: ", this.binary);
                    command_line.printerr(
                        /// Command line warning, string substitution
                        /// is the given argument
                        _("Unrecognised program argument: “%s”"), arg
                    );
                    command_line.printerr("\n");
                    return 1;
                }
            }
        }

        this.config.enable_debug = enable_debug;
        this.config.enable_inspector = options.contains(OPTION_INSPECTOR);
        this.config.revoke_certs = options.contains(OPTION_REVOKE_CERTS);

        if (!activated) {
            activate();
        }

        return -1;
    }

    /** Removes and re-adds the autostart file if needed. */
    private async void update_autostart_file() {
        try {
            this.autostart.delete_startup_file();
            if (this.config.startup_notifications) {
                this.autostart.install_startup_file();
            }
        } catch (GLib.Error err) {
            warning("Could not update autostart file");
        }
    }

    private void add_app_accelerators(string action,
                                      string[] accelerators,
                                      GLib.Variant? param = null) {
        set_accels_for_action("app." + action, accelerators);
    }

    private Geary.Folder? get_folder_from_action_target(GLib.Variant target) {
        Geary.Folder? folder = null;
        string account_id = (string) target.get_child_value(0);
        try {
            Geary.AccountInformation? account_config =
                this.engine.get_account(account_id);
            Geary.Account? account =
                this.engine.get_account_instance(account_config);
            Geary.FolderPath? path =
                account.to_folder_path(
                    target.get_child_value(1).get_variant()
                );
            folder = account.get_folder(path);
        } catch (GLib.Error err) {
            debug("Could not find account/folder %s", err.message);
        }
        return folder;
    }

    private void on_activate_about() {
        this.show_about.begin();
    }

    private void on_activate_accounts() {
        this.show_accounts.begin();
    }

    private void on_activate_compose() {
        this.new_composer.begin(null);
    }

    private void on_activate_inspect() {
        this.show_inspector.begin();
    }

    private void on_activate_mailto(SimpleAction action, Variant? param) {
        if (param != null) {
            this.new_composer.begin(param.get_string());
        }
    }

    private void on_activate_preferences() {
        this.show_preferences.begin();
    }

    private void on_activate_quit() {
        exit();
    }

    private void on_activate_show_email(GLib.SimpleAction action,
                                        GLib.Variant? target) {
        if (target != null) {
            // Target is a (account_id,folder_path,email_id) tuple
            Geary.Folder? folder = get_folder_from_action_target(target);
            Geary.EmailIdentifier? email_id = null;
            if (folder != null) {
                try {
                    email_id = folder.account.to_email_identifier(
                        target.get_child_value(2).get_variant()
                    );
                } catch (GLib.Error err) {
                    debug("Could not find email id: %s", err.message);
                }

                if (email_id != null) {
                    this.show_email.begin(folder, email_id);
                }
            }
        }
    }

    private void on_activate_show_folder(GLib.SimpleAction action,
                                        GLib.Variant? target) {
        if (target != null) {
            // Target is a (account_id,folder_path) tuple
            Geary.Folder? folder = get_folder_from_action_target(target);
            if (folder != null) {
                this.show_folder.begin(folder);
            }
        }
    }

    private void on_activate_help() {
        try {
            if (this.is_installed) {
                this.show_uri.begin("help:geary");
            } else {
                Pid pid;
                File exec_dir = this.exec_dir;
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
