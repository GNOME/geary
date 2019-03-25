/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic interface for widgets that have a single ComposerWidget-child.
 */
public interface ComposerContainer {

    // The ComposerWidget-child.
    internal abstract ComposerWidget composer { get; set; }

    // We use old_accelerators to keep track of the accelerators we temporarily disabled.
    protected abstract Gee.MultiMap<string, string>? old_accelerators { get; set; }

    // The toplevel window for the container. Note that it needs to be a GtkApplicationWindow.
    public abstract Gtk.ApplicationWindow top_window { get; }

    public virtual void present() {
        this.top_window.present();
    }

    public virtual unowned Gtk.Widget get_focus() {
        return this.top_window.get_focus();
    }

    public abstract void close_container();

    /**
     * Hides the widget (and possibly its parent). Usecase is when you don't want to close just yet
     * but the composer should not be visible any longer (e.g. when you're still saving a draft).
     */
    public abstract void vanish();

    /**
     * Removes the composer from this ComposerContainer (e.g. when detaching)
     */
    public abstract void remove_composer();

}
