/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface ComposerContainer {
    public abstract Gtk.Window top_window { get; }
    
    public abstract void present();
    public abstract unowned Gtk.Widget get_focus();
}
