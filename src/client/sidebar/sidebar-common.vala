/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A simple grouping Entry that is only expandable
public class Sidebar.Grouping : Object, Sidebar.Entry, Sidebar.ExpandableEntry,
    Sidebar.RenameableEntry {
    
    private string name;
    private string? tooltip;
    private Icon? open_icon;
    private Icon? closed_icon;
    
    public Grouping(string name, Icon? open_icon, Icon? closed_icon = null, string? tooltip = null) {
        this.name = name;
        this.open_icon = open_icon;
        this.closed_icon = closed_icon ?? open_icon;
        this.tooltip = tooltip;
    }
    
    public void rename(string name) {
        this.name = name;
        sidebar_name_changed(name);
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
    
    public Icon? get_sidebar_icon() {
        return null;
    }
    
    public Icon? get_sidebar_open_icon() {
        return open_icon;
    }
    
    public Icon? get_sidebar_closed_icon() {
        return closed_icon;
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

