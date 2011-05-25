/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

//
// YorbaApplication is a poor man's lookalike of GNOME 3's GApplication, with a couple of additions.
// It's only here to give some of GApplication's functionality in a GTK+ 2 environment.  The idea
// is to ease a future migration to GTK 3.
//
// YorbaApplication specifically expects to be run in a GTK environment, and Gtk.init() *must* be 
// called prior to invoking YorbaApplication.
//

public abstract class YorbaApplication {
    public bool registered { get; private set; }
    public string[]? args { get; private set; }
    
    private string app_id;
    private bool running = false;
    private bool exiting_fired = false;
    private int exitcode = 0;
    private Unique.App? unique_app = null;
    
    public virtual signal void startup() {
    }
    
    public virtual signal void activate() {
    }
    
    public virtual signal void exiting(bool panicked) {
    }
    
    protected YorbaApplication(string app_id) {
        this.app_id = app_id;
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
        
        running = true;
        startup();
        
        // enter the main loop
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
}

