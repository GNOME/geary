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
    public const string DESKTOP_KEYWORDS = _("Email;E-mail;Mail");
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
    public File system_desktop_file_directory { get; private set;
        default = File.new_for_path("/usr/share/applications/"); }
    
    private static GearyApplication _instance = null;
    
    private GearyController? controller = null;
    
    private LoginDialog? login_dialog = null;
    
    private File exec_dir;
    
    public GearyApplication() {
        base (NAME, PRGNAME, "org.yorba.geary");
        
        _instance = this;
    }
    
    public override int startup() {
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        
        Configuration.init(is_installed(), GSETTINGS_DIR);
        Date.init();
        WebKit.set_cache_model(WebKit.CacheModel.DOCUMENT_BROWSER);
        
        int ec = base.startup();
        if (ec != 0)
            return ec;
        
        return Args.parse(args);
    }
    
    public override bool exiting(bool panicked) {
        if (controller.main_window != null)
            controller.main_window.destroy();
        
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

        Geary.Engine.instance.account_available.connect(on_account_available);
        Geary.Engine.instance.account_unavailable.connect(on_account_unavailable);
        
        config = new Configuration();
        controller = new GearyController();
        
        // Start Geary.
        try {
            yield Geary.Engine.instance.open_async(get_user_data_directory(), get_resource_directory(),
                new GnomeKeyringMediator());
            if (Geary.Engine.instance.get_accounts().size == 0)
                create_account();
        } catch (Error e) {
            error("Error opening Geary.Engine instance: %s", e.message);
        }

        handle_args(args);
    }
    
    // NOTE: This assert()'s if the Gtk.Action is not present in the default action group
    public Gtk.Action get_action(string name) {
        Gtk.Action? action = actions.get_action(name);
        assert(action != null);
        
        return action;
    }
    
    private void open_account(Geary.Account account) {
        account.report_problem.connect(on_report_problem);
        controller.connect_account_async.begin(account);
    }
    
    private void close_account(Geary.Account account) {
        account.report_problem.disconnect(on_report_problem);
        controller.disconnect_account_async.begin(account);
    }
    
    private Geary.Account get_account_instance(Geary.AccountInformation account_information) {
        try {
            return Geary.Engine.instance.get_account_instance(account_information);
        } catch (Error e) {
            error("Error creating account instance: %s", e.message);
        }
    }
    
    private void on_account_available(Geary.AccountInformation account_information) {
        open_account(get_account_instance(account_information));
    }
    
    private void on_account_unavailable(Geary.AccountInformation account_information) {
        close_account(get_account_instance(account_information));
    }
    
    private void create_account() {
        Geary.AccountInformation? account_information = request_account_information(null);
        if (account_information != null)
            do_validate_until_successful_async.begin(account_information);
    }
    
    private async void do_validate_until_successful_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.AccountInformation? result = account_information;
        do {
            result = yield validate_or_retry_async(result, cancellable);
        } while (result != null);

        if (login_dialog != null)
            login_dialog.hide();
    }

    // Returns null if we are done validating, or the revised account information if we should retry.
    private async Geary.AccountInformation? validate_or_retry_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.Engine.ValidationResult result = yield validate_async(account_information, cancellable);
        if (result == Geary.Engine.ValidationResult.OK)
            return null;
        
        debug("Validation failed. Prompting user for revised account information");
        Geary.AccountInformation? new_account_information =
            request_account_information(account_information, result);
        
        // If the user refused to enter account information. There is currently no way that we
        // could see this--we exit in request_account_information, and the only way that an
        // exit could be canceled is if there are unsaved composer windows open (which won't
        // happen before an account is created). However, best to include this check for the
        // future.
        if (new_account_information == null)
            return null;
        
        debug("User entered revised account information, retrying validation");
        return new_account_information;
    }
    
    // Attempts to validate and add an account.  Returns true on success, else false.
    public async Geary.Engine.ValidationResult validate_async(
        Geary.AccountInformation account_information, Cancellable? cancellable = null) {
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK;
        try {
            result = yield Geary.Engine.instance.validate_account_information_async(account_information,
                cancellable);
        } catch (Error err) {
            debug("Error validating account: %s", err.message);
            exit(-1); // Fatal error
            
            return result;
        }
        
        if (result == Geary.Engine.ValidationResult.OK) {
            account_information.store_async.begin(cancellable);
            do_update_stored_passwords_async.begin(Geary.CredentialsMediator.ServiceFlag.IMAP |
                Geary.CredentialsMediator.ServiceFlag.SMTP, account_information);
            
            debug("Successfully validated account information");
        }
        
        return result;
    }
    
    // Prompt the user for a service, real name, username, and password, and try to start Geary.
    private Geary.AccountInformation? request_account_information(Geary.AccountInformation? old_info,
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK) {
        Geary.AccountInformation? new_info = old_info;
        if (login_dialog == null)
            login_dialog = new LoginDialog(); // Create here so we know GTK is initialized.
        
        if (new_info != null)
            login_dialog.set_account_information(new_info, result);
        
        login_dialog.present();
        for (;;) {
            login_dialog.show_spinner(false);
            if (login_dialog.run() != Gtk.ResponseType.OK) {
                debug("User refused to enter account information. Exiting...");
                exit(1);
                return null;
            }
            
            login_dialog.show_spinner(true);
            new_info = login_dialog.get_account_information();
            
            if ((!new_info.default_imap_server_ssl && !new_info.default_imap_server_starttls)
                || (!new_info.default_smtp_server_ssl && !new_info.default_smtp_server_starttls)) {
                ConfirmationDialog security_dialog = new ConfirmationDialog(controller.main_window,
                    _("Your settings are insecure"),
                    _("Your IMAP and/or SMTP settings do not specify SSL or TLS.  This means your username and password could be read by another person on the network.  Are you sure you want to do this?"),
                    _("Co_ntinue"));
                if (security_dialog.run() != Gtk.ResponseType.OK)
                    continue;
            }
            
            break;
        }
        
        do_update_stored_passwords_async.begin(Geary.CredentialsMediator.ServiceFlag.IMAP |
            Geary.CredentialsMediator.ServiceFlag.SMTP, new_info);
        
        return new_info;
    }
    
    private async void do_update_stored_passwords_async(Geary.CredentialsMediator.ServiceFlag services,
        Geary.AccountInformation account_information) {
        try {
            yield account_information.update_stored_passwords_async(services);
        } catch (Error e) {
            debug("Error updating stored passwords: %s", e.message);
        }
    }
    
    private void on_report_problem(Geary.Account account, Geary.Account.Problem problem, Error? err) {
        debug("Reported problem: %s Error: %s", problem.to_string(), err != null ? err.message : "(N/A)");
        
        switch (problem) {
            case Geary.Account.Problem.DATABASE_FAILURE:
            case Geary.Account.Problem.HOST_UNREACHABLE:
            case Geary.Account.Problem.NETWORK_UNAVAILABLE:
                // TODO
            break;
            
            case Geary.Account.Problem.RECV_EMAIL_LOGIN_FAILED:
            case Geary.Account.Problem.SEND_EMAIL_LOGIN_FAILED:
                // At this point, we've prompted them for the password and
                // they've hit cancel, so there's not much for us to do here.
                close_account(account);
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    // Removes an existing account.
    public async void remove_account_async(Geary.AccountInformation account,
        Cancellable? cancellable = null) {
        try {
            yield GearyApplication.instance.get_account_instance(account).close_async(cancellable);
            yield Geary.Engine.instance.remove_account_async(account, cancellable);
        } catch (Error e) {
            message("Error removing account: %s", e.message);
        }
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
        File desktop_file = is_installed()
            ? system_desktop_file_directory.get_child("geary.desktop")
            : File.new_for_path(SOURCE_ROOT_DIR).get_child("build").get_child("desktop").get_child("geary.desktop");
        
        return desktop_file.query_exists() ? desktop_file : null;
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
            if (arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                controller.compose_mailto(arg);
            }
        }
    }
    
    public Gee.List<ComposerWindow>? get_composer_windows_for_account(Geary.AccountInformation account) {
        return controller.get_composer_windows_for_account(account);
    }
}

