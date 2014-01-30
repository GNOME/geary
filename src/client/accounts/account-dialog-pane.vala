/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Base class for account dialog panes.
// Could be factored into a generic "StackPage" class if needed.
public class AccountDialogPane : Gtk.Box {
    private weak Gtk.Stack parent_stack;
    
    public class AccountDialogPane(Gtk.Stack parent_stack) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        
        this.parent_stack = parent_stack;
        parent_stack.add(this);
    }
    
    public virtual void present() {
        parent_stack.set_visible_child(this);
    }
}

