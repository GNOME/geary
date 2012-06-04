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
    static bool log_periodic = false;
    static bool version = false;
    const OptionEntry[] options = {
        { "debug", 0, 0, OptionArg.NONE, ref log_debug, N_("Output debugging information"), null },
        { "log-conversations", 0, 0, OptionArg.NONE, ref log_conversations, N_("Output conversations log"), null },
        { "log-network", 0, 0, OptionArg.NONE, ref log_network, N_("Output network log"), null },
        { "log-replay-queue", 0, 0, OptionArg.NONE, ref log_replay_queue, N_("Output replay queue log"), null },
        { "log-serializer", 0, 0, OptionArg.NONE, ref log_serializer, N_("Output serializer log"), null },
        { "log-periodic", 0, 0, OptionArg.NONE, ref log_periodic, N_("Output periodic activity"), null },
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
        
        if (log_periodic)
            Geary.Logging.enable_flags(Geary.Logging.Flag.PERIODIC);
        
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
        initialize_account();
        handle_args(args);

        return;
    }
    
    private void initialize_account(bool replace_existing_data = false) {
        string? username = get_username();
        if (username == null || replace_existing_data)
            create_account(username);
        else
            open_account(username);
    }
    
    private void create_account(string? username) {
        Geary.AccountInformation? old_account_information = null;
        if (username != null) {
            Geary.Credentials credentials = new Geary.Credentials(username, null);
            old_account_information = new Geary.AccountInformation(credentials);
            try {
                old_account_information.load_info_from_file();
            } catch (Error err) {
                debug("Problem loading account information: %s", err.message);
                old_account_information = null;
            }
        }
        
        Geary.AccountInformation account_information =
            request_account_information(old_account_information);
        do_validate_until_successful_async.begin(account_information, null,
            on_do_validate_until_successful_async_finished);
    }
    
    private void on_do_validate_until_successful_async_finished(Object? source, AsyncResult result) {
        try {
            do_validate_until_successful_async.end(result);
        } catch (IOError err) {
            debug("Caught validation error: %s", err.message);
        }
    }
    
    private async void do_validate_until_successful_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null)
        throws IOError {
        yield validate_until_successful_async(account_information, cancellable);
    }
    
    private async void validate_until_successful_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) 
        throws IOError {
        bool success = yield account_information.validate_async(cancellable);
        
        if (success) {
            account_information.store_async.begin(cancellable);
            account = account_information.get_account();
            account.report_problem.connect(on_report_problem);
            controller.connect_account(account);
        } else {
            Geary.AccountInformation new_account_information =
                request_account_information(account_information);
            
            // If the user refused to enter account information.
            if (new_account_information == null) {
                account = null;
                return;
            }
            
            yield validate_until_successful_async(new_account_information, cancellable);
        }
    }
    
    private void open_account(string username) {
        string? password = get_password(username);
        if (password == null) {
            password = request_password(username);
            
            // If the user refused to enter a password.
            if (password == null) {
                account = null;
                return;
            }
        }
        
        // Now we know password is non-null.
        Geary.Credentials credentials = new Geary.Credentials(username, password);
        Geary.AccountInformation account_information = new Geary.AccountInformation(credentials);
        try {
            account_information.load_info_from_file();
        } catch (Error err) {
            error("Problem loading account information: %s", err.message);
        }
        
        account = account_information.get_account();
        account.report_problem.connect(on_report_problem);
        controller.connect_account(account);
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
    
    private string? get_password(string username) {
        // TODO: For now we always get the password from the keyring. This will change when we
        // allow users to not save their password.
        string? password = keyring_get_password(username);
        return Geary.String.is_empty(password) ? null : password;
     }
    
    private string get_default_real_name() {
        string real_name = Environment.get_real_name();
        return real_name == "Unknown" ? "" : real_name;
    }
    
    private string? request_password(string username) {
        // TODO: For now we use the full LoginDialog. This should be changed to a dialog that only
        // allows editting the password.
        
        Geary.Credentials credentials = new Geary.Credentials(username, null);
        
        Geary.AccountInformation old_account_information = new Geary.AccountInformation(credentials);
        try {
            old_account_information.load_info_from_file();
        } catch (Error err) {
            debug("Problem loading account information: %s", err.message);
            old_account_information = null;
        }
        
        Geary.AccountInformation account_information = request_account_information(old_account_information);
        return account_information == null ? null : account_information.credentials.pass;
    }
    
    // Prompt the user for a service, real name, username, and password, and try to start Geary.
    private Geary.AccountInformation? request_account_information(
        Geary.AccountInformation? old_account_information = null) {
        LoginDialog login_dialog = old_account_information == null ?
            new LoginDialog(get_default_real_name()) :
            new LoginDialog.from_account_information(old_account_information);
        
        if (!login_dialog.show()) {
            exit(1);
            return null;
        }
        
        // TODO: This should be optional.
        keyring_save_password(login_dialog.account_information.credentials);
          
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
                if (controller != null)
                    controller.stop();
                account.report_problem.disconnect(on_report_problem);
                initialize_account(true);
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

