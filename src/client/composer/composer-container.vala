/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic interface for widgets that have a single composer child.
 */
public interface Composer.Container {

    /** The top-level window for the container, if any. */
    public abstract Gtk.ApplicationWindow? top_window { get; }

    /** The container's current composer, if any. */
    internal abstract Widget composer { get; set; }

    /** Causes the composer's top-level window to be presented. */
    public virtual void present() {
        Gtk.ApplicationWindow top = top_window;
        if (top != null) {
            top.present();
        }
    }

    /** Returns the top-level window's current focus widget, if any. */
    public virtual Gtk.Widget? get_focus() {
        Gtk.Widget? focus = null;
        Gtk.ApplicationWindow top = top_window;
        if (top != null) {
            focus = top.get_focus();
        }
        return focus;
    }

    /**
     * Removes the composer and destroys the container.
     */
    public abstract void close();

}
