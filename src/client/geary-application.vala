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
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public const string DESCRIPTION = _("Email Client");
    public const string COPYRIGHT = _("Copyright 2011-2012 Yorba Foundation");
    public const string WEBSITE = "http://www.yorba.org";
    public const string WEBSITE_LABEL = _("Visit the Yorba web site");
    public const string BUGREPORT = "http://redmine.yorba.org/projects/geary/issues";
    
    public const string VERSION = _VERSION;
    public const string INSTALL_PREFIX = _INSTALL_PREFIX;
    public const string GSETTINGS_DIR = _GSETTINGS_DIR;
    public const string SOURCE_ROOT_DIR = _SOURCE_ROOT_DIR;
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        "Nate Lillich <nate@yorba.org>",
        "Matthew Pirocchi <matthew@yorba.org>",
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
    static bool log_periodic = false;
    static bool log_sql = false;
    static bool log_folder_normalization = false;
    static bool version = false;
    const OptionEntry[] options = {
        { "debug", 'd', 0, OptionArg.NONE, ref log_debug, N_("Output debugging information"), null },
        { "log-conversations", 0, 0, OptionArg.NONE, ref log_conversations, N_("Log conversation monitoring"), null },
        { "log-network", 0, 0, OptionArg.NONE, ref log_network, N_("Log network activity"), null },
        { "log-replay-queue", 0, 0, OptionArg.NONE, ref log_replay_queue, N_("Log IMAP replay queue"), null },
        { "log-serializer", 0, 0, OptionArg.NONE, ref log_serializer, N_("Log network serialization"), null },
        { "log-periodic", 0, 0, OptionArg.NONE, ref log_periodic, N_("Log periodic activity"), null },
        { "log-sql", 0, 0, OptionArg.NONE, ref log_sql, N_("Log database queries (generates lots of messages)"), null },
        { "log-folder-normalization", 0, 0, OptionArg.NONE, ref log_folder_normalization, N_("Log folder normalization"), null },
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
        } catch (OptionError error) {
            // i18n: Command line arguments are invalid
            stdout.printf (_("Failed to parse command line options: %s\n"), error.message);
            stdout.printf("\n%s", context.get_help(true, Gtk.get_option_group(false)));
            return 1;
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
        
        if (log_periodic)
            Geary.Logging.enable_flags(Geary.Logging.Flag.PERIODIC);
        
        if (log_sql)
            Geary.Logging.enable_flags(Geary.Logging.Flag.SQL);
        
        if (log_folder_normalization)
            Geary.Logging.enable_flags(Geary.Logging.Flag.FOLDER_NORMALIZATION);
        
        if (log_debug)
            Geary.Logging.log_to(stdout);
        
        return 0;
    }
    
    public override int startup() {
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        Configuration.init(is_installed(), GSETTINGS_DIR);
        
        base.startup();
        int result = parse_arguments(args);
        return result;
    }
    
    public override void activate(string[] args) {
        // If Geary is already running, show the main window and return.
        if (controller != null && controller.main_window != null) {
            controller.main_window.present_with_time((uint32) TimeVal().tv_sec);
            handle_args(args);
            return;
        }

        // Start Geary.
        Geary.Engine.init(get_user_data_directory(), get_resource_directory());
        config = new Configuration();
        controller = new GearyController();
        initialize_account();
        handle_args(args);

        return;
    }
    
    private void set_account(Geary.EngineAccount? account) {
        if (this.account == account)
            return;
            
        if (this.account != null)
            this.account.report_problem.disconnect(on_report_problem);
        
        this.account = account;
        
        if (this.account != null)
            this.account.report_problem.connect(on_report_problem);
        
        controller.connect_account_async.begin(this.account, null);
    }
    
    private void initialize_account() {
        string? username = get_username();
        if (username == null)
            create_account(username);
        else
            open_account(username);
    }
    
    private void create_account(string? username) {
        Geary.AccountInformation? old_account_information = null;
        if (username != null) {
            Geary.Credentials credentials = new Geary.Credentials(username, null);
            old_account_information = new Geary.AccountInformation(credentials);
            old_account_information.load_info_from_file();
        }
        
        Geary.AccountInformation account_information =
            request_account_information(old_account_information);
        do_validate_until_successful_async.begin(account_information);
    }
    
    private async void do_validate_until_successful_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.AccountInformation? result = account_information;
        do {
            result = yield validate_async(result, cancellable);
        } while (result != null);
    }
    
    // Returns null if we are done validating, or the revised account information if we should retry.
    private async Geary.AccountInformation? validate_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        bool success = false;
        try {
            success = yield account_information.validate_async(cancellable);
        } catch (Geary.EngineError err) {
            debug("Error validating account: %s", err.message);
            success = false;
        }
        
        if (success) {
            account_information.store_async.begin(cancellable);

            try {
                set_account(account_information.get_account());
                debug("Successfully validated account information");
                return null;
            } catch (Geary.EngineError err) {
                debug("Unable to retrieve email account: %s", err.message);
            }
        }

        debug("Validation failed. Prompting user for revised account information");
        Geary.AccountInformation new_account_information =
            request_account_information(account_information);
        
        // If the user refused to enter account information. There is currently no way that we
        // could see this--we exit in request_account_information, and the only way that an
        // exit could be canceled is if there are unsaved composer windows open (which won't
        // happen before an account is created). However, best to include this check for the
        // future.
        if (new_account_information == null) {
            set_account(null);
            return null;
        }
        
        debug("User entered revised account information, retrying validation");
        return new_account_information;
    }
    
    private void open_account(string username, string? old_password = null, Cancellable? cancellable = null) {
        Geary.Credentials credentials = new Geary.Credentials(username, null);
        Geary.AccountInformation account_information = new Geary.AccountInformation(credentials);
        account_information.load_info_from_file();
        
        bool remember_password = account_information.remember_password;
        string? password = get_password(account_information.credentials.user, old_password, ref remember_password);
        // If there was no saved password and the user refused to enter a password.
        if (password == null) {
            set_account(null);
            return;
        }
        
        account_information.remember_password = remember_password;
        account_information.store_async.begin(cancellable);
        
        account_information.credentials.pass = password;
        
        try {
            set_account(account_information.get_account());
        } catch (Geary.EngineError err) {
            // Our service provider is wrong. But we can't change it, because we don't want to
            // change the service provider for an existing account.
            debug("Unable to retrieve email account: %s", err.message);
            set_account(null);
        }
    }
    
    private string? get_username() {
        try {
            Gee.List<string> usernames = Geary.Engine.get_usernames();
            if (usernames.size > 0) {
                string username = usernames.get(0);
                return Geary.String.is_empty(username) ? null : username;
            }
        } catch (Error e) {
            debug("Unable to fetch accounts. Error: %s", e.message);
        }
        
        return null;
    }
    
    private string? get_password(string username, string? old_password, ref bool remember_password) {
        string? password = null;
        if (old_password == null && remember_password)
            password = keyring_get_password(username);
        
        if (Geary.String.is_null_or_whitespace(password))
            password = request_password(username, old_password, out remember_password);
        
        return password;
    }
    
    private string get_default_real_name() {
        string real_name = Environment.get_real_name();
        return real_name == "Unknown" ? "" : real_name;
    }
    
    private string? request_password(string username, string? old_password, out bool remember_password) {
        Geary.Credentials credentials = new Geary.Credentials(username, old_password);
        
        Geary.AccountInformation old_account_information = new Geary.AccountInformation(credentials);
        old_account_information.load_info_from_file();
        
        PasswordDialog password_dialog = new PasswordDialog(old_account_information, old_password == null);
        if (!password_dialog.run()) {
            exit(1);
            remember_password = false;
            return null;
        }
            
        // password_dialog.password should never be null at this point. It will only be null when
        // password_dialog.run() returns false, in which case we have already exited/returned.
        string? password = password_dialog.password;
        remember_password = password_dialog.remember_password;
        
        if (remember_password)
            keyring_save_password(new Geary.Credentials(username, password));
        else
            keyring_delete_password(username);
        
        return password;
    }
    
    // Prompt the user for a service, real name, username, and password, and try to start Geary.
    private Geary.AccountInformation? request_account_information(
        Geary.AccountInformation? old_account_information = null) {
        LoginDialog login_dialog = old_account_information == null ?
            new LoginDialog(get_default_real_name()) :
            new LoginDialog.from_account_information(old_account_information);
        
        if (!login_dialog.show()) {
            debug("User refused to enter account information. Exiting...");
            exit(1);
            return null;
        }
        
        if (login_dialog.account_information.remember_password)
            keyring_save_password(login_dialog.account_information.credentials);
        else
            keyring_delete_password(login_dialog.account_information.credentials.user);
          
        return login_dialog.account_information;  
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
                Geary.Credentials old_credentials = account.settings.credentials;
                account.report_problem.disconnect(on_report_problem);
                open_account(old_credentials.user, old_credentials.pass);
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    public override bool exiting(bool panicked) {
        if (controller.main_window != null)
            controller.main_window.destroy();
        
        controller.disconnect_account_async.begin(null);
        
        return true;
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
        File desktop_file = get_resource_directory().get_child("geary.desktop");
        if (desktop_file.query_exists())
            return desktop_file;
        
        desktop_file = File.new_for_path("/usr/share/applications/geary.desktop");
        if (!desktop_file.query_exists())
            return desktop_file;
        
        return null;
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

