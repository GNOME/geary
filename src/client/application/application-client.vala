/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
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
 * The client application's main point of entry and desktop integration.
 */
public class Application.Client : Gtk.Application {

    public const string NAME = "Geary" + _NAME_SUFFIX;
    public const string APP_ID = _APP_ID;
    public const string SCHEMA_ID = "org.gnome.Geary";
    public const string DESCRIPTION = _("Send and receive email");
    public const string COPYRIGHT_1 = _("Copyright 2016 Software Freedom Conservancy Inc.");
    public const string COPYRIGHT_2 = _("Copyright 2016-2020 Geary Development Team.");
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

    /** Default size of avatar images, in virtual pixels */
    public const int AVATAR_SIZE_PIXELS = 48;

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
    private const string OPTION_NEW_WINDOW = "new-window";
    private const string OPTION_QUIT = "quit";
    private const string OPTION_REVOKE_CERTS = "revoke-certs";

    private const ActionEntry[] ACTION_ENTRIES = {
        { Action.Application.ABOUT, on_activate_about},
        { Action.Application.ACCOUNTS, on_activate_accounts},
        { Action.Application.COMPOSE, on_activate_compose},
        { Action.Application.HELP, on_activate_help},
        { Action.Application.INSPECT, on_activate_inspect},
        { Action.Application.MAILTO, on_activate_mailto, "s"},
        { Action.Application.NEW_WINDOW, on_activate_new_window },
        { Action.Application.PREFERENCES, on_activate_preferences},
        { Action.Application.QUIT, on_activate_quit},
        { Action.Application.SHOW_EMAIL, on_activate_show_email, "(vv)"},
        { Action.Application.SHOW_FOLDER, on_activate_show_folder, "(v)"}
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
        { OPTION_NEW_WINDOW, 'n', 0, GLib.OptionArg.NONE, null,
          N_("Open a new window"), null },
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

    /**
     * The global email subsystem controller for this app instance.
     */
    public Geary.Engine? engine {
        get; private set; default = null;
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
     * The last active main window.
     *
     * This will be null if no main windows exist, see {@link
     * get_active_main_window} if you want to be guaranteed an
     * instance.
     */
    public MainWindow? last_active_main_window {
        get; private set; default = null;
    }

    /**
     * Manages the autostart desktop file.
     *
     * This will be null until {@link startup} has been called, and
     * hence will only ever become non-null for the primary instance.
     */
    public StartupManager? autostart {
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
     * The global controller for this application instance.
     *
     * This will be non-null in the primary application instance, only
     * after initial activation, or after startup if {@link
     * is_background_service} is true.
     */
    internal Controller? controller {
        get; private set; default = null;
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
    private Gtk.CssProvider single_key_shortcuts = new Gtk.CssProvider();
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


    public Client() {
        Object(
            application_id: APP_ID,
            flags: (
                GLib.ApplicationFlags.HANDLES_OPEN |
                GLib.ApplicationFlags.HANDLES_COMMAND_LINE
            )
        );
        this.add_main_option_entries(OPTION_ENTRIES);
        this.window_removed.connect_after(on_window_removed);
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
        int ret = -1;
        if (options.contains(OPTION_DEBUG)) {
            Geary.Logging.log_to(GLib.stdout);
        }
        if (options.contains(OPTION_VERSION)) {
            GLib.stdout.printf(
                "%s: %s\n", this.binary, Client.VERSION
            );
            ret = 0;
        }
        return ret;
    }

    public override void startup() {
        Environment.set_application_name(NAME);
        Util.International.init(GETTEXT_PACKAGE, this.binary);
        Util.Date.init();

        Configuration.init(this.is_installed, GSETTINGS_DIR);

        // Add application's actions before chaining up so they are
        // present when the application is first registered on the
        // session bus.
        add_action_entries(ACTION_ENTRIES, this);

        // Calls Gtk.init(), amongst other things
        base.startup();

        this.engine = new Geary.Engine(get_resource_directory());
        this.config = new Configuration(SCHEMA_ID);
        this.autostart = new StartupManager(
            this.config, this.get_desktop_directory()
        );

        // Ensure all geary windows have an icon
        Gtk.Window.set_default_icon_name(APP_ID);

        // Application accels
        add_app_accelerators(Action.Application.COMPOSE, { "<Ctrl>N" });
        add_app_accelerators(Action.Application.HELP, { "F1" });
        add_app_accelerators(Action.Application.INSPECT, { "<Alt><Shift>I" });
        add_app_accelerators(Action.Application.NEW_WINDOW, { "<Ctrl><Shift>N" });
        add_app_accelerators(Action.Application.QUIT, { "<Ctrl>Q" });

        // Common window accels
        add_window_accelerators(Action.Window.CLOSE, { "<Ctrl>W" });
        add_window_accelerators(
            Action.Window.SHORTCUT_HELP, { "<Ctrl>F1", "<Ctrl>question" }
        );

        // Common edit accels
        add_edit_accelerators(Action.Edit.COPY, { "<Ctrl>C" });
        add_edit_accelerators(Action.Edit.REDO, { "<Ctrl><Shift>Z" });
        add_edit_accelerators(Action.Edit.UNDO, { "<Ctrl>Z" });

        // Load Geary GTK CSS
        var provider = new Gtk.CssProvider();
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Display.get_default().get_default_screen(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        load_css(provider,
                 "resource:///org/gnome/Geary/geary.css");
        load_css(this.single_key_shortcuts,
                 "resource:///org/gnome/Geary/single-key-shortcuts.css");
        update_single_key_shortcuts();
        this.config.notify[Configuration.SINGLE_KEY_SHORTCUTS].connect(
            on_single_key_shortcuts_toggled
        );

        MainWindow.add_accelerators(this);
        Composer.Widget.add_accelerators(this);
        Components.Inspector.add_accelerators(this);
        Components.PreferencesWindow.add_accelerators(this);
        Dialogs.ProblemDetailsDialog.add_accelerators(this);

        // Manually place a hold on the application otherwise the
        // application will exit when the async call to
        // ::create_controller next returns without having yet created
        // a window.
        hold();

        // Finally, start the controller.
        this.create_controller.begin();
    }

    public override int command_line(GLib.ApplicationCommandLine command_line) {
        int exit_value = handle_general_options(command_line);
        if (exit_value != -1)
            return exit_value;

        return -1;
    }

    public override void shutdown() {
        bool controller_closed = false;
        this.destroy_controller.begin((obj, res) => {
                this.destroy_controller.end(res);
                controller_closed = true;
            });

        // GApplication will stop the main loop, so we need to keep
        // pumping here to allow destroy_controller() to exit. To
        // avoid bug(s) where Geary hangs at exit, shut the whole
        // thing down if it takes too long to complete
        int64 start_usec = get_monotonic_time();
        while (!controller_closed) {
            Gtk.main_iteration();

            int64 delta_usec = get_monotonic_time() - start_usec;
            if (delta_usec >= FORCE_SHUTDOWN_USEC) {
                // Use a warning here so a) it's usually logged
                // and b) we can run under gdb with
                // G_DEBUG=fatal-warnings and have it break when
                // this happens, and maybe debug it.
                warning("Forcing shutdown of Geary, %ss passed...",
                        (delta_usec / USEC_PER_SEC).to_string());
                Posix.exit(2);
            }
        }

        this.engine = null;
        this.config = null;
        this.autostart = null;

        Util.Date.terminate();
        Geary.Logging.clear();

        base.shutdown();
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

    /**
     * Returns a collection of open main windows.
     */
    public Gee.Collection<MainWindow> get_main_windows() {
        var windows = new Gee.LinkedList<MainWindow>();
        foreach (Gtk.Window window in get_windows()) {
            MainWindow? main = window as MainWindow;
            if (main != null) {
                windows.add(main);
            }
        }
        return windows;
    }

    /**
     * Returns the mostly recently active main window or a new instance.
     *
     * This returns the value of {@link last_active_main_window} if
     * not null, else it constructs a new MainWindow instance and
     * shows it.
     */
    public MainWindow get_active_main_window() {
        if (this.last_active_main_window == null) {
            this.last_active_main_window = new_main_window(true);
        }
        return last_active_main_window;
    }

    public void add_window_accelerators(string action,
                                        string[] accelerators,
                                        Variant? param = null) {
        string name = Action.Window.prefix(action);
        string[] all_accel = get_accels_for_action(name);
        foreach (string accel in accelerators) {
            all_accel += accel;
        }
        set_accels_for_action(name, all_accel);
    }

    public void add_edit_accelerators(string action,
                                      string[] accelerators,
                                      Variant? param = null) {
        string name = Action.Edit.prefix(action);
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

        Accounts.Editor editor = new Accounts.Editor(
            this, get_active_main_window()
        );
        editor.run();
        editor.destroy();
        this.controller.expunge_accounts.begin();
    }

    public async void show_email(Geary.Folder folder,
                                 Geary.EmailIdentifier id) {
        MainWindow main = yield this.present();
        main.show_email.begin(folder, Geary.Collection.single(id), true);
    }

    public async void show_folder(Geary.Folder folder) {
        MainWindow main = yield this.present();
        yield main.select_folder(folder, true);
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

        Components.PreferencesWindow prefs = new Components.PreferencesWindow(
            get_active_main_window(),
            this.controller.plugins
        );
        prefs.show();
    }

    public async void new_composer(string? mailto) {
        yield this.present();

        this.controller.compose(mailto);
    }

    public async void new_window(Geary.Folder? select_folder,
                                 Gee.Collection<Geary.App.Conversation>? select_conversations) {
        yield create_controller();

        bool do_select = (
            select_folder != null &&
            select_conversations != null &&
            !select_conversations.is_empty
        );

        MainWindow main = new_main_window(!do_select);
        main.present();

        if (do_select) {
            if (select_conversations == null || select_conversations.is_empty) {
                main.select_folder.begin(select_folder, true);
            } else {
                main.show_conversations.begin(
                    select_folder,
                    select_conversations,
                    true
                );
            }
        }
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

    /**
     * Closes the controller and all open windows, exiting if possible.
     *
     * Any open composers with unsaved or un-savable changes will be
     * prompted about and if cancelled, will cancel shut-down here.
     */
    public new void quit() {
        if (this.controller == null ||
            this.controller.check_open_composers()) {
            this.last_active_main_window = null;
            base.quit();
        }
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
            new GLib.ThemedIcon("%s-symbolic".printf(Client.APP_ID))
        );
        send_notification(ERROR_NOTIFICATION_ID, error);
        this.error_notification = error;
    }

    internal void clear_error_notification() {
        this.error_notification = null;
        withdraw_notification(ERROR_NOTIFICATION_ID);
    }

    // Presents a main window, opening the controller and window if
    // needed.
    private async MainWindow present() {
        yield create_controller();
        MainWindow main = get_active_main_window();
        main.present();
        return main;
    }

    private MainWindow new_main_window(bool select_first_inbox) {
        MainWindow window = new MainWindow(this);
        this.controller.register_window(window);
        window.focus_in_event.connect(on_main_window_focus_in);
        if (select_first_inbox) {
            if (!window.select_first_inbox(true)) {
                // The first inbox wasn't selected, so the account is
                // likely still loading folders after being
                // opened. Add a listener to try again later.
                try {
                    Geary.Account? first = Geary.Collection.first<Geary.Account>(
                        this.engine.get_accounts()
                    );
                    if (first != null) {
                        first.folders_available_unavailable.connect_after(
                            on_folders_first_available
                        );
                    }
                } catch (GLib.Error error) {
                    debug("Error getting Inbox for first account");
                }
            }
        }
        return window;
    }

    // Opens the controller
    private async void create_controller() {
        bool first_run = false;
        bool open_failed = false;
        int mutex_token = Geary.Nonblocking.Mutex.INVALID_TOKEN;
        try {
            mutex_token = yield this.controller_mutex.claim_async();
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

                this.controller = yield new Controller(
                    this, this.controller_cancellable
                );
                first_run = !this.engine.has_accounts;
            }
        } catch (Error err) {
            open_failed = true;
            warning("Error creating controller: %s", err.message);
            var dialog = new Dialogs.ProblemDetailsDialog(
                null,
                this,
                new Geary.ProblemReport(err)
            );
            dialog.run();
        }

        if (mutex_token != Geary.Nonblocking.Mutex.INVALID_TOKEN) {
            try {
                this.controller_mutex.release(ref mutex_token);
            } catch (GLib.Error error) {
                warning("Failed to release controller mutex: %s",
                        error.message);
            }
        }

        if (open_failed) {
            quit();
        }

        if (first_run) {
            yield show_accounts();
            if (!this.engine.has_accounts) {
                // No accounts were added after showing the accounts
                // editor, so nothing else to do but exit.
                quit();
            }
        }
    }

    // Closes the controller, if running
    private async void destroy_controller() {
        try {
            int mutex_token = yield this.controller_mutex.claim_async();
            if (this.controller != null) {
                yield this.controller.close();
                this.controller = null;
            }
            this.controller_mutex.release(ref mutex_token);
        } catch (GLib.Error err) {
            warning("Error destroying controller: %s", err.message);
        }

        try {
            this.engine.close();
        } catch (GLib.Error error) {
            warning("Error shutting down the engine: %s", error.message);
        }
    }

    private int handle_general_options(GLib.ApplicationCommandLine command_line) {
        GLib.VariantDict options = command_line.get_options_dict();
        if (options.contains(OPTION_QUIT)) {
            quit();
            return 0;
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
        if (options.contains(OPTION_NEW_WINDOW)) {
            activate_action(Action.Application.NEW_WINDOW, null);
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
                    activate_action(Action.Application.COMPOSE, null);
                    activated = true;
                } else if (arg.down().has_prefix(MAILTO_URI_SCHEME_PREFIX)) {
                    activate_action(Action.Application.MAILTO, new GLib.Variant.string(arg));
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

        this.config.enable_debug = options.contains(OPTION_DEBUG);
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

    private void update_single_key_shortcuts() {
        if (this.config.single_key_shortcuts) {
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Display.get_default().get_default_screen(),
                this.single_key_shortcuts,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } else {
            Gtk.StyleContext.remove_provider_for_screen(
                Gdk.Display.get_default().get_default_screen(),
                this.single_key_shortcuts
            );
        }
    }

    private Geary.Folder? get_folder_from_action_target(GLib.Variant target) {
        Geary.Folder? folder = null;
        GLib.Variant param = target.get_child_value(0).get_variant();
        string id = (string) param.get_child_value(0);
        try {
            Geary.Account account = this.engine.get_account_for_id(id);
            Geary.FolderPath? path =
                account.to_folder_path(
                    param.get_child_value(1).get_variant()
                );
            folder = account.get_folder(path);
        } catch (GLib.Error err) {
            debug("Could not find account/folder %s", err.message);
        }
        return folder;
    }

    private void load_css(Gtk.CssProvider provider, string resource_uri) {
        provider.parsing_error.connect(on_css_parse_error);
        try {
            var file = GLib.File.new_for_uri(resource_uri);
            provider.load_from_file(file);
        } catch (GLib.Error error) {
            warning("Could not load CSS: %s", error.message);
        }
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

    private void on_activate_new_window() {
        // If there was an existing active main, select the same
        // account/folder/conversation.
        MainWindow? current = this.last_active_main_window;
        this.new_window.begin(
            current.selected_folder,
            current.conversation_list_view.copy_selected()
        );
    }

    private void on_activate_preferences() {
        this.show_preferences.begin();
    }

    private void on_activate_quit() {
        quit();
    }

    private void on_activate_show_email(GLib.SimpleAction action,
                                        GLib.Variant? target) {
        if (target != null) {
            Geary.Folder? folder = get_folder_from_action_target(target);
            Geary.EmailIdentifier? email_id = null;
            if (folder != null) {
                try {
                    email_id = folder.account.to_email_identifier(
                        target.get_child_value(1).get_variant()
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
                argv[1] = Client.SOURCE_ROOT_DIR + "/help/C/";
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

    private void on_folders_first_available(Geary.Account account,
        Gee.BidirSortedSet<Geary.Folder>? available,
        Gee.BidirSortedSet<Geary.Folder>? unavailable
    ) {
        if (get_active_main_window().select_first_inbox(true)) {
            // The handler has done its job, so disconnect it
            account.folders_available_unavailable.disconnect(
                on_folders_first_available
            );
        }
    }

    private bool on_main_window_focus_in(Gtk.Widget widget,
                                         Gdk.EventFocus event) {
        MainWindow? main = widget as MainWindow;
        if (main != null) {
            this.last_active_main_window = main;
        }
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_window_removed(Gtk.Window window) {
        MainWindow? main = window as MainWindow;
        if (main != null) {
            this.controller.unregister_window(main);
            if (this.last_active_main_window == main) {
                this.last_active_main_window = Geary.Collection.first(
                    get_main_windows()
                );
            }
        }

        // Since ::startup above took out a manual hold on the
        // application, manually work out if the application should
        // quit here.
        if (!this.is_background_service && get_windows().length() == 0) {
            quit();
        }
    }

    private void on_single_key_shortcuts_toggled() {
        update_single_key_shortcuts();
    }

    private void on_css_parse_error(Gtk.CssSection section, GLib.Error error) {
        uint start = section.get_start_line();
        uint end = section.get_end_line();
        if (start == end) {
            warning(
                "Error parsing %s:%u: %s",
                section.get_file().get_uri(), start, error.message
            );
        } else {
            warning(
                "Error parsing %s:%u-%u: %s",
                section.get_file().get_uri(), start, end, error.message
            );
        }
    }
}
