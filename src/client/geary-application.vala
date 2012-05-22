/* Copyright 2011-2012 Yorba Foundation
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
    // TODO: replace static strings with const strings when gettext is integrated properly
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public static string DESCRIPTION = _("Email Client");
    public const string COPYRIGHT = "Copyright 2011-2012 Yorba Foundation";
    public const string WEBSITE = "http://www.yorba.org";
    public static string WEBSITE_LABEL = _("Visit the Yorba web site");
    public const string BUGREPORT = "http://redmine.yorba.org/projects/geary/issues";
    
    public const string VERSION = _VERSION;
    public const string INSTALL_PREFIX = _INSTALL_PREFIX;
    public const string GSETTINGS_DIR = _GSETTINGS_DIR;
    public const string SOURCE_ROOT_DIR = _SOURCE_ROOT_DIR;
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        "Nate Lillich <nate@yorba.org>",
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
    
    static bool log_debug = false;
    static bool log_network = false;
    static bool log_serializer = false;
    static bool log_replay_queue = false;
    static bool log_conversations = false;
    static bool version = false;
    const OptionEntry[] options = {
        { "debug", 0, 0, OptionArg.NONE, ref log_debug, N_("Output debugging information"), null },
        { "log-conversations", 0, 0, OptionArg.NONE, ref log_conversations, N_("Output conversations log"), null },
        { "log-network", 0, 0, OptionArg.NONE, ref log_network, N_("Output network log"), null },
        { "log-replay-queue", 0, 0, OptionArg.NONE, ref log_replay_queue, N_("Output replay queue log"), null },
        { "log-serializer", 0, 0, OptionArg.NONE, ref log_serializer, N_("Output serializer log"), null },
        { "version", 'V', 0, OptionArg.NONE, ref version, N_("Display program version"), null },
        { null }
    };
    
    private int parse_arguments (string[] args) {
        var context = new OptionContext("");
        context.set_help_enabled(true);
        context.add_main_entries(options, null);
        context.add_group(Gtk.get_option_group(false));
        try {
            context.parse(ref args);
        } catch (GLib.Error error) {
            // i18n: Command line arguments are invalid
            GLib.error (_("Failed to parse command line: %s"), error.message);
        }

        if (version) {
            stdout.printf("%s %s\n\n%s\n\n%s\n\t%s\n",
                PRGNAME, VERSION, COPYRIGHT,
                _("Please report comments, suggestions and bugs to:"), BUGREPORT);
            return 1;
        }
        
        if (log_network)
            Geary.Logging.enable_flags(Geary.Logging.Flag.NETWORK);
        
        if (log_serializer)
            Geary.Logging.enable_flags(Geary.Logging.Flag.SERIALIZER);
        
        if (log_replay_queue)
            Geary.Logging.enable_flags(Geary.Logging.Flag.REPLAY);
        
        if (log_conversations)
            Geary.Logging.enable_flags(Geary.Logging.Flag.CONVERSATIONS);
        
        if (log_debug)
            Geary.Logging.log_to(stdout);
        
        return 0;
     }
    
    public override int startup() {
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        Configuration.init(is_installed(), GSETTINGS_DIR);
        
        int result = base.startup();
        result = parse_arguments(args);
        return result;
    }
    
    public override void activate(string[] args) {
        // If Geary is already running, show the main window and return.
        if (controller != null && controller.main_window != null) {
            controller.main_window.present();
            handle_args(args);
            return;
        }

        // Start Geary.
        Geary.Engine.init(get_user_data_directory(), get_resource_directory());
        config = new Configuration();
        controller = new GearyController();
        login();
        handle_args(args);

        return;
    }

    private void login(bool query_keyring = true) {
        // Get saved credentials. If not present, ask user.
        string username = get_username();
        string? password = query_keyring ? keyring_get_password(username) : null;
        string? real_name = null;
        
        Geary.Credentials? cred;
        if (password == null) {
            // No account set up yet.
            Geary.AccountInformation? account_info = null;
            real_name = get_default_real_name();
            cred = request_login(username, ref real_name, ref account_info);
            if (cred == null)
                return;
            
            try {
                account = Geary.Engine.create(cred, account_info);
            } catch (Error err) {
                error("Unable to open mail database for %s: %s", cred.user, err.message);
            }
        } else {
            // Log into existing account.
            cred = new Geary.Credentials(username, password);
            
            try {
                account = Geary.Engine.open(cred);
            } catch (Error err) {
                error("Unable to open mail database for %s: %s", cred.user, err.message);
            }
        }
        
        account.report_problem.connect(on_report_problem);
        controller.start(account);
    }
    
    private string get_username() {
        try {
            Gee.List<string> accounts = Geary.Engine.get_usernames();
            if (accounts.size > 0) {
                return accounts.get(0);
            }
        } catch (Error e) {
            debug("Unable to fetch accounts. Error: %s", e.message);
        }
        
        return "";
    }
    
    private string get_default_real_name() {
        string real_name = Environment.get_real_name();
        return real_name == "Unknown" ? "" : real_name;
    }
    
    // Prompt the user for a username and password, and try to start Geary.
    private Geary.Credentials? request_login(string _username = "", ref string real_name, 
        ref Geary.AccountInformation? account_info) {
        LoginDialog login = new LoginDialog(real_name, _username, "", account_info);
        login.show();
        if (login.get_response() == Gtk.ResponseType.OK) {
            keyring_save_password(login.username, login.password);
            
            account_info = new Geary.AccountInformation();
            account_info.real_name = login.real_name;
            account_info.service_provider = login.provider;
            
            account_info.imap_server_host = login.imap_host;
            account_info.imap_server_port = login.imap_port;
            account_info.imap_server_tls = login.imap_tls;
            account_info.imap_server_pipeline = (login.provider != Geary.ServiceProvider.OTHER);
            account_info.smtp_server_host = login.smtp_host;
            account_info.smtp_server_port = login.smtp_port;
            account_info.smtp_server_tls = login.smtp_tls;
        } else {
            exit(1);
            return null;
        }
        
        return new Geary.Credentials(login.username, login.password);
    }
    
    private void on_report_problem(Geary.Account.Problem problem, Geary.Credentials? credentials,
        Error? err) {
        debug("Reported problem: %s Error: %s", problem.to_string(), err != null ? err.message : "(N/A)");
        switch (problem) {
            case Geary.Account.Problem.DATABASE_FAILURE:
            case Geary.Account.Problem.HOST_UNREACHABLE:
            case Geary.Account.Problem.NETWORK_UNAVAILABLE:
                // TODO
            break;
            
            case Geary.Account.Problem.LOGIN_FAILED:
                debug("Login failed.");
                if (controller != null)
                    controller.stop();
                account.report_problem.disconnect(on_report_problem);
                login(false);
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    public override bool exiting(bool panicked) {
        if (controller.main_window != null)
            controller.main_window.destroy();
            
        return true;
    }
    
    public File get_user_data_directory() {
        return File.new_for_path(Environment.get_user_data_dir()).get_child(Environment.get_prgname());
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

    public bool is_installed() {
        return exec_dir.has_prefix(File.new_for_path(INSTALL_PREFIX));
    }

    // Returns the installation directory, or null if we're running outside of the installation
    // directory.
    public File? get_install_dir() {
        File prefix_dir = File.new_for_path(INSTALL_PREFIX);
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
    
    public Gtk.Window get_main_window() {
        return controller.main_window;
    }

    private void handle_args(string[] args) {
        foreach(string arg in args) {
            if (arg.has_prefix("mailto:")) {
                controller.compose_mailto(arg);
            }
        }
    }
}

