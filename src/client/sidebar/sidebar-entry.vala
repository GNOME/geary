/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Sidebar.Entry : Object {


    public signal void entry_changed();


    public abstract string get_sidebar_name();

    public abstract string? get_sidebar_tooltip();

    public abstract string? get_sidebar_icon();

    public abstract int get_count();

    public abstract string to_string();

    internal virtual void grafted(Sidebar.Tree tree) {
    }

    internal virtual void pruned(Sidebar.Tree tree) {
    }
}

public interface Sidebar.ExpandableEntry : Sidebar.Entry {
    public abstract bool expand_on_select();
}

public interface Sidebar.SelectableEntry : Sidebar.Entry {
}

public interface Sidebar.RenameableEntry : Sidebar.Entry {
    public abstract void rename(string new_name);

    // Return true to allow the user to rename the sidebar entry in the UI.
    public abstract bool is_user_renameable();
}

public interface Sidebar.EmphasizableEntry : Sidebar.Entry {
    public abstract bool is_emphasized();
}

public interface Sidebar.DestroyableEntry : Sidebar.Entry {
    public abstract void destroy_source();
}

public interface Sidebar.InternalDropTargetEntry : Sidebar.Entry {
    // Returns true if drop was successful
    public abstract bool internal_drop_received(Sidebar.Tree parent,
                                                Gdk.DragContext context,
                                                Gtk.SelectionData data);
}

public interface Sidebar.InternalDragSourceEntry : Sidebar.Entry {
    public abstract void prepare_selection_data(Gtk.SelectionData data);
}
