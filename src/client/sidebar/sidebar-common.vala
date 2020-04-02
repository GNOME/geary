/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A simple grouping Entry that is only expandable
public class Sidebar.Grouping : Geary.BaseObject, Sidebar.Entry, Sidebar.ExpandableEntry,
    Sidebar.RenameableEntry {

    private string name;
    private string? tooltip;
    private string? icon;

    public Grouping(string name, string? icon, string? tooltip = null) {
        this.name = name;
        this.icon = icon;
        this.tooltip = tooltip;
    }

    public void rename(string name) {
        this.name = name;
        entry_changed();
    }

    public bool is_user_renameable() {
        return false;
    }

    public string get_sidebar_name() {
        return name;
    }

    public string? get_sidebar_tooltip() {
        return tooltip;
    }

    public string? get_sidebar_icon() {
        return icon;
    }

    public int get_count() {
        return -1;
    }

    public string to_string() {
        return name;
    }

    public bool expand_on_select() {
        return true;
    }
}

// A simple Sidebar.Branch where the root node is the branch in entirety.
public class Sidebar.RootOnlyBranch : Sidebar.Branch {
    public RootOnlyBranch(Sidebar.Entry root) {
        base (root, Sidebar.Branch.Options.NONE, null_comparator);
    }

    private static int null_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        return (a != b) ? -1 : 0;
    }
}

/**
 * A header is an entry that is visually distinguished from its children. Bug 6397 recommends
 * headers to appear bolded and without any icons. To prevent the icons from rendering, we set the
 * icons to null in the base class @see Sidebar.Grouping. But we also go a step further by
 * using a custom cell_data_function (@see Sidebar.Tree::icon_renderer_function) which ensures that
 * header icons won't be rendered. This approach avoids the blank icon spacing issues.
 */
public class Sidebar.Header : Sidebar.Grouping, Sidebar.EmphasizableEntry {
    private bool emphasized;

    public Header(string name, bool emphasized = true) {
        base(name, null);
        this.emphasized = emphasized;
    }

    public bool is_emphasized() {
        return emphasized;
    }
}

public interface Sidebar.Contextable : Object {
    // Return null if the context menu should not be invoked for this event
    public abstract Gtk.Menu? get_sidebar_context_menu(Gdk.EventButton event);
}

