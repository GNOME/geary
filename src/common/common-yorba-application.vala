/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * YorbaApplication is a poor man's lookalike of GNOME 3's GApplication, with a couple of additions.
 * The idea is to ease a future migration to GTK 3 once some outstanding problems with Gtk.Application
 * are resolved.
 *
 * For more information about why we built this class intead of using Gtk.Application, see the
 * following ticket:
 * http://redmine.yorba.org/issues/4266
 */

extern const string GETTEXT_PACKAGE;

public abstract class YorbaApplication {
    
    public bool registered { get; private set; }
    public string[]? args { get; private set; }
    
    private string app_id;
    private bool running = false;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private Unique.App? unique_app = null;
    
    /**
     * This signal is fired only when the application is starting the first time, not on
     * subsequent activations (i.e. the application is launched while running by the user).
     *
     * The args[] array will be available when this signal is fired.
     */
    public virtual signal int startup() {
        unowned string[] a = args;
        Gtk.init(ref a);
        
        // Sanitize the args.  Gtk's init function will leave null elements
        // in the array, which then causes OptionContext to crash.
        // See ticket: https://bugzilla.gnome.org/show_bug.cgi?id=674837
        string[] fixed_args = new string[0];
        for (int i = 0; i < args.length; i++) {
            if (args[i] != null)
                fixed_args += args[i];
        }
        args = fixed_args;
        
        return 0;
    }
    
    public virtual signal void activate(string[] args) {
    }
    
    /**
     * Signal that is activated when 'exit' is called, but before the application actually exits.
     *
     * To cancel an exit, a callback should return YorbaApplication.cancel_exit(). To procede with
     * an exit, a callback should return true.
     */
    public virtual signal bool exiting(bool panicked) {
        return true;
    }
    
    /**
     * application_title is a localized name of the application.  program_name is non-localized
     * and used by the system.  app_id is a CORBA-esque program identifier.
     *
     * Only one YorbaApplication instance may be created in an program.
     */
    public YorbaApplication(string application_title, string program_name, string app_id) {
        this.app_id = app_id;
        
        Environment.set_application_name(application_title);
        Environment.set_prgname(program_name);
    }
    
    public bool register(Cancellable? cancellable = null) throws Error {
        if (registered)
            return false;
        
        unique_app = new Unique.App(app_id, null);
        unique_app.message_received.connect(on_unique_app_message);
        
        // If app already running, activate it and exit
        if (unique_app.is_running()) {
            Unique.MessageData data = new Unique.MessageData();
            string argstr = string.joinv(", ", args);
            data.set_text(argstr, argstr.length);
            unique_app.send_message((int) Unique.Command.ACTIVATE, data);
            
            return false;
        }
        
        registered = true;
        
        return true;
    }
    
    private Unique.Response on_unique_app_message(Unique.App app, int command,
        Unique.MessageData data, uint timestamp) {
        switch (command) {
            case Unique.Command.ACTIVATE:
                activate(data.get_text().split(", "));
            break;
            
            default:
                return Unique.Response.PASSTHROUGH;
        }
        
        return Unique.Response.OK;
    }
    
    public void add_window(Gtk.Window window) {
        unique_app.watch_window(window);
    }
    
    public int run(string[] args) {
        if (running)
            error("run() called twice.");
        
        this.args = args;
        International.init(GETTEXT_PACKAGE, args[0]);
        
        running = true;
        exitcode = startup();
        if (exitcode != 0)
            return exitcode;
        
        try {
            if (!register()) {
                return exitcode;
            }
        } catch (Error e) {
            error("Unable to register application: %s", e.message);
        }
        
        activate(args);
        
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
        if (!exiting(false)) {
            exiting_fired = false;
            this.exitcode = 0;
            
            return;
        }
        
        if (Gtk.main_level() > 0)
            Gtk.main_quit();
        else
            Posix.exit(exitcode);
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
}

