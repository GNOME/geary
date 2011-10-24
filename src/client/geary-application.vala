/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Defined by wscript
extern const string _PREFIX;

public class GearyApplication : YorbaApplication {
    // TODO: replace static strings with const strings when gettext is integrated properly
    public const string NAME = "Geary";
    public const string PRGNAME = "geary";
    public static string DESCRIPTION = _("Email Client");
    public const string VERSION = "0.0.0+trunk";
    public const string COPYRIGHT = "Copyright 2011 Yorba Foundation";
    public const string WEBSITE = "http://www.yorba.org";
    public static string WEBSITE_LABEL = _("Visit the Yorba web site");
    
    // Named actions.
    public const string ACTION_DONATE = "GearyDonate";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    
    public const string PREFIX = _PREFIX;
    
    public const string[] AUTHORS = {
        "Jim Nelson <jim@yorba.org>",
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
    
    private MainWindow? main_window = null;
    private Geary.EngineAccount? account = null;
    
    private File exec_dir;
    
    public GearyApplication() {
        base (NAME, PRGNAME, "org.yorba.geary");
        
        _instance = this;
    }
    
    public override void activate() {
        // If Geary is already running, show the main window and return.
        if (main_window != null) {
            main_window.present();
            return;
        }
        
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        
        // Start Geary.
        actions.add_actions(create_actions(), this);
        ui_manager.insert_action_group(actions, 0);
        
        main_window = new MainWindow();
        
        config = new Configuration(GearyApplication.instance.get_install_dir() != null,
            GearyApplication.instance.get_exec_dir().get_child("build/src/client").get_path());
        
        // Get saved credentials. If not present, ask user.
        string username = "";
        string? password = null;
        try {
            Gee.List<string> accounts = Geary.Engine.get_usernames(get_user_data_directory());
            if (accounts.size > 0) {
                username = accounts.get(0);
                password = keyring_get_password(username);
            }
        } catch (Error e) {
            debug("Unable to fetch accounts. Error: %s", e.message);
        }
        
        if (password == null) {
            LoginDialog login = new LoginDialog(username);
            login.show();
            if (login.get_response() == Gtk.ResponseType.OK) {
                username = login.username;
                password = login.password;
                
                // TODO: check credentials before saving password in keyring.
                keyring_save_password(username, password);
            } else {
                exit(1);
            }
        }
        
        Geary.Credentials cred = new Geary.Credentials(username, password);
        
        try {
            account = Geary.Engine.open(cred, get_user_data_directory(), get_resource_directory());
        } catch (Error err) {
            error("Unable to open mail database for %s: %s", cred.user, err.message);
        }
        
        main_window.show_all();
        main_window.start(account);
        return;
    }
    
    public override void exiting(bool panicked) {
        if (main_window != null)
            main_window.destroy();
    }
    
    public File get_user_data_directory() {
        return File.new_for_path(Environment.get_user_data_dir()).get_child(Environment.get_prgname());
    }
    
    /**
     * Returns the base directory that the application's various resource files are stored.  If the
     * application is running from its installed directory, this will point to
     * $(BASEDIR)/share/<program name>.  If it's running from the build directory, this points to
     * that.
     *
     * TODO: Implement.  This is placeholder code for build environments and assumes you're running
     * the program in the build directory.
     */
    public File get_resource_directory() {
        return File.new_for_path(Environment.get_current_dir());
    }
    
    // Returns the directory the application is currently executing from.
    public File get_exec_dir() {
        return exec_dir;
    }
    
    // Returns the installation directory, or null if we're running outside of the installation
    // directory.
    public File? get_install_dir() {
        File prefix_dir = File.new_for_path(PREFIX);
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
    
    // Loads a UI file (in the ui directory) into the UI manager.
    public void load_ui_file(string ui_filename) {
        try {
            ui_manager.add_ui_from_file(get_resource_directory().get_child("ui").get_child(
                ui_filename).get_path());
        } catch(GLib.Error error) {
            warning("Unable to create Gtk.UIManager: %s".printf(error.message));
        }
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry donate = { ACTION_DONATE, null, TRANSLATABLE, null, null, on_donate };
        donate.label = _("_Donate");
        entries += donate;
        
        Gtk.ActionEntry about = { ACTION_ABOUT, Gtk.Stock.ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        Gtk.ActionEntry quit = { ACTION_QUIT, Gtk.Stock.QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, Gtk.Stock.NEW, TRANSLATABLE, "<Ctrl>N", 
            null, on_new_message };
        new_message.label = _("_New Message");
        entries += new_message;
        
        return entries;
    }
    
    public void on_quit() {
        GearyApplication.instance.exit();
    }
    
    public void on_about() {
        Gtk.show_about_dialog(main_window,
            "program-name", GearyApplication.NAME,
            "comments", GearyApplication.DESCRIPTION,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL
        );
    }
    
    public void on_donate() {
        try {
            Gtk.show_uri(main_window.get_screen(), "http://yorba.org/donate/", Gdk.CURRENT_TIME);
        } catch (Error err) {
            debug("Unable to open URL. %s", err.message);
        }
    }
    
    private void on_new_message() {
        ComposerWindow w = new ComposerWindow();
        w.set_position(Gtk.WindowPosition.CENTER);
        w.send.connect(on_send);
        w.show_all();
    }
    
    private void on_send(ComposerWindow cw) {
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames(GearyApplication.instance.get_user_data_directory())
                .get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        
        Geary.ComposedEmail email = new Geary.ComposedEmail(new DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.from_rfc822_string(username));
        
        email.to = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.to);
        email.cc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.cc);
        email.bcc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.bcc);
        email.subject = new Geary.RFC822.Subject(cw.subject);
        email.body = new Geary.RFC822.Text(new Geary.Memory.StringBuffer(cw.message));
        
        account.send_email_async.begin(email);
        
        cw.destroy();
    }
    
    public Gtk.Window get_main_window() {
        return main_window;
    }
}

