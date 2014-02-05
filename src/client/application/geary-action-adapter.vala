/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A bridge between Gtk.Action and GLib.Action.  Doesn't handle stateful
 * Actions.  Also, assumes most properties of the Gtk.Action won't change
 * during its life.
 *
 * NOTE: this *should* be subclassing SimpleAction, but trying that causes
 * GCC to throw errors at compile time.  See bug #720159.  Also *should* be at
 * least implementing Action, but trying that causes a whole different set of
 * compile-time errors.  :'(
 */
public class Geary.ActionAdapter : BaseObject {
    private delegate void RecursionGuardFunc();
    
    public Action action { get { return _action; } }
    public Gtk.Action gtk_action { get; private set; }
    
    private SimpleAction _action;
    private bool recursing = false;
    
    public ActionAdapter(Gtk.Action gtk_action) {
        _action = new SimpleAction(gtk_action.name, null);
        this.gtk_action = gtk_action;
        
        _action.activate.connect(on_activated);
        _action.notify["enabled"].connect(on_enabled_changed);
        
        gtk_action.activate.connect(on_gtk_activated);
        gtk_action.notify["sensitive"].connect(on_gtk_sensitive_changed);
    }
    
    private void guard_recursion(RecursionGuardFunc f) {
        if (recursing)
            return;
        
        recursing = true;
        f();
        recursing = false;
    }
    
    private void on_activated() {
        guard_recursion(() => gtk_action.activate());
    }
    
    private void on_enabled_changed() {
        guard_recursion(() => {
            if (gtk_action.sensitive != _action.enabled)
                gtk_action.sensitive = _action.enabled;
        });
    }
    
    private void on_gtk_activated() {
        guard_recursion(() => _action.activate(null));
    }
    
    private void on_gtk_sensitive_changed() {
        guard_recursion(() => {
            if (_action.enabled != gtk_action.sensitive)
                _action.set_enabled(gtk_action.sensitive);
        });
    }
}
