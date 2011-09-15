/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Defined by wscript
extern const string _PREFIX;

/**
 * YorbaApplication is a poor man's lookalike of GNOME 3's GApplication, with a couple of additions.
 * It's only here to give some of GApplication's functionality in a GTK+ 2 environment.  The idea
 * is to ease a future migration to GTK 3.
 *
 * YorbaApplication specifically expects to be run in a GTK environment, and Gtk.init() *must* be 
 * called prior to invoking YorbaApplication.
 */

public abstract class YorbaApplication {
    public static YorbaApplication? instance { get; private set; default = null; }
    
    public const string PREFIX = _PREFIX;
    
    public bool registered { get; private set; }
    public string[]? args { get; private set; }
    
    private string app_id;
    private bool running = false;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private File exec_dir;
    private Unique.App? unique_app = null;
    
    /**
     * This signal is fired only when the application is starting the first time, not on
     * subsequent activations (i.e. the application is launched while running by the user).
     *
     * The args[] array will be available when this signal is fired.
     */
    public virtual signal int startup() {
        return 0;
    }
    
    public virtual signal void activate() {
    }
    
    public virtual signal void exiting(bool panicked) {
    }
    
    /**
     * application_title is a localized name of the application.  program_name is non-localized
     * and used by the system.  app_id is a CORBA-esque program identifier.
     *
     * Only one YorbaApplication instance may be created in an program.
     */
    protected YorbaApplication(string application_title, string program_name, string app_id) {
        this.app_id = app_id;
        
        Environment.set_application_name(application_title);
        Environment.set_prgname(program_name);
        
        assert(instance == null);
        instance = this;
    }
    
    public bool register(Cancellable? cancellable = null) throws Error {
        if (registered)
            return false;
        
        unique_app = new Unique.App(app_id, null);
        unique_app.message_received.connect(on_unique_app_message);
        
        // If app already running, activate it and exit
        if (unique_app.is_running) {
            unique_app.send_message((int) Unique.Command.ACTIVATE, null);
            
            return false;
        }
        
        registered = true;
        
        return true;
    }
    
    private Unique.Response on_unique_app_message(Unique.App app, int command,
        Unique.MessageData data, uint timestamp) {
        switch (command) {
            case Unique.Command.ACTIVATE:
                activate();
            break;
            
            default:
                return Unique.Response.PASSTHROUGH;
        }
        
        return Unique.Response.OK;
    }
    
    public int run(string[] args) {
        if (!registered)
            error("Must register application before calling run().");
        
        if (running)
            error("run() called twice.");
        
        this.args = args;
        
        exec_dir = (File.new_for_path(Environment.find_program_in_path(args[0]))).get_parent();
        
        running = true;
        exitcode = startup();
        
        // enter the main loop
        if (exitcode == 0)
            Gtk.main();
        
        return exitcode;
    }
    
    // This call will fire "exiting" only if it's not already been fired.
    public void exit(int exitcode = 0) {
        if (exiting_fired || !running)
            return;
        
        this.exitcode = exitcode;
        
        exiting_fired = true;
        exiting(false);
        
        Gtk.main_quit();
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
}

