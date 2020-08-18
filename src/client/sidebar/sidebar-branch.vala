/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public delegate bool Locator<G>(G item);

public class Sidebar.Branch : Geary.BaseObject {
    [Flags]
    public enum Options {
        NONE = 0,
        HIDE_IF_EMPTY,
        AUTO_OPEN_ON_NEW_CHILD,
        STARTUP_EXPAND_TO_FIRST_CHILD,
        STARTUP_OPEN_GROUPING;

        public bool is_hide_if_empty() {
            return (this & HIDE_IF_EMPTY) != 0;
        }

        public bool is_auto_open_on_new_child() {
            return (this & AUTO_OPEN_ON_NEW_CHILD) != 0;
        }

        public bool is_startup_expand_to_first_child() {
            return (this & STARTUP_EXPAND_TO_FIRST_CHILD) != 0;
        }

        public bool is_startup_open_grouping() {
            return (this & STARTUP_OPEN_GROUPING) != 0;
        }
    }

    private class Node {
        public delegate void PruneCallback(Node node);

        public delegate void ChildrenReorderedCallback(Node node);

        public Sidebar.Entry entry;
        public weak Node? parent;
        public CompareFunc<Sidebar.Entry> comparator;
        public Gee.SortedSet<Node>? children = null;

        public Node(Sidebar.Entry entry, Node? parent, CompareFunc<Sidebar.Entry> comparator) {
            this.entry = entry;
            this.parent = parent;
            this.comparator = comparator;
        }

        private static int comparator_wrapper(Node anode, Node bnode) {
            if (anode == bnode)
                return 0;

            assert(anode.parent == bnode.parent);

            return anode.parent.comparator(anode.entry, bnode.entry);
        }

        public bool has_children() {
            return (children != null && children.size > 0);
        }

        public void add_child(Node child) {
            child.parent = this;
            if (this.children == null) {
                this.children = new Gee.TreeSet<Node>(comparator_wrapper);
            }
            this.children.add(child);
        }

        public void remove_child(Node child) {
            Gee.SortedSet<Node> new_children = new Gee.TreeSet<Node>(comparator_wrapper);

            // For similar reasons as in reorder_child(), can't rely
            // on TreeSet to locate this node because we need
            // reference equality.
            foreach (Node c in children) {
                if (c != child) {
                    new_children.add(c);
                }
            }

            if (new_children.size != 0)
                children = new_children;
            else
                children = null;

            child.parent = null;
        }

        public void prune_children(PruneCallback cb) {
            if (children == null)
                return;

            foreach (Node child in children)
                child.prune_children(cb);

            Gee.SortedSet<Node> old_children = children;
            children = null;

            // Although this could've been done in the prior loop, it means notifying that
            // a child has been removed prior to it being removed; this can cause problem
            // if a signal handler calls back into the Tree to examine/add/remove nodes.
            foreach (Node child in old_children)
                cb(child);
        }

        // This returns the index of the Node purely by reference equality, making it useful if
        // the criteria the Node is sorted upon has changed.
        public int index_of_by_reference(Node child) {
            if (children == null)
                return -1;

            int index = 0;
            foreach (Node c in children) {
                if (child == c)
                    return index;

                index++;
            }

            return -1;
        }

        // Returns true if child moved when reordered.
        public bool reorder_child(Node child) {
            assert(children != null);

            int old_index = index_of_by_reference(child);
            assert(old_index >= 0);

            // Because Gee.SortedSet uses the comparator for equality, if the Node's entry state
            // has changed in such a way that the item is no longer sorted properly, the SortedSet's
            // search and remove methods are useless.  Makes no difference if children.remove() is
            // called or the set is manually iterated over and removed via the Iterator -- a
            // tree search is performed and the child will not be found.  Only easy solution is
            // to rebuild a new SortedSet and see if the child has moved.
            Gee.SortedSet<Node> new_children = new Gee.TreeSet<Node>(comparator_wrapper);
            bool added = new_children.add_all(children);
            assert(added);

            children = new_children;

            int new_index = index_of_by_reference(child);
            assert(new_index >= 0);

            return (old_index != new_index);
        }

        public void reorder_children(bool recursive, ChildrenReorderedCallback cb) {
            if (children == null)
                return;

            Gee.SortedSet<Node> reordered = new Gee.TreeSet<Node>(comparator_wrapper);
            reordered.add_all(children);
            children = reordered;

            if (recursive) {
                foreach (Node child in children)
                    child.reorder_children(true, cb);
            }

            cb(this);
        }

        public void change_comparator(CompareFunc<Sidebar.Entry> comparator, bool recursive,
            ChildrenReorderedCallback cb) {
            this.comparator = comparator;

            // reorder children, but need to do manual recursion to set comparator
            reorder_children(false, cb);

            if (recursive) {
                foreach (Node child in children)
                    child.change_comparator(comparator, true, cb);
            }
        }
    }

    private Node root;
    private Options options;
    private bool shown = true;
    private CompareFunc<Sidebar.Entry> default_comparator;
    private Gee.HashMap<Sidebar.Entry, Node> map = new Gee.HashMap<Sidebar.Entry, Node>();

    public signal void entry_added(Sidebar.Entry entry);

    public signal void entry_removed(Sidebar.Entry entry);

    public signal void entry_moved(Sidebar.Entry entry);

    public signal void entry_reparented(Sidebar.Entry entry, Sidebar.Entry old_parent);

    public signal void children_reordered(Sidebar.Entry entry);

    public signal void show_branch(bool show);

    public Branch(Sidebar.Entry root, Options options, CompareFunc<Sidebar.Entry> default_comparator,
        CompareFunc<Sidebar.Entry>? root_comparator = null) {
        this.default_comparator = default_comparator;
        this.root = new Node(root, null,
            (root_comparator != null) ? root_comparator : default_comparator);
        this.options = options;

        map.set(root, this.root);

        if (options.is_hide_if_empty())
            set_show_branch(false);
    }

    public Sidebar.Entry get_root() {
        return root.entry;
    }

    public void set_show_branch(bool shown) {
        if (this.shown == shown)
            return;

        this.shown = shown;
        show_branch(shown);
    }

    public bool get_show_branch() {
        return shown;
    }

    public bool is_auto_open_on_new_child() {
        return options.is_auto_open_on_new_child();
    }

    public bool is_startup_expand_to_first_child() {
        return options.is_startup_expand_to_first_child();
    }

    public bool is_startup_open_grouping() {
        return options.is_startup_open_grouping();
    }

    public void graft(Sidebar.Entry parent, Sidebar.Entry entry,
        CompareFunc<Sidebar.Entry>? comparator = null) {
        assert(map.has_key(parent));
        assert(!map.has_key(entry));

        if (options.is_hide_if_empty())
            set_show_branch(true);

        Node parent_node = map.get(parent);
        Node entry_node = new Node(entry, parent_node,
            (comparator != null) ? comparator : default_comparator);

        parent_node.add_child(entry_node);
        map.set(entry, entry_node);

        entry_added(entry);
    }

    // Cannot prune the root.  The Branch should simply be removed from the Tree.
    public void prune(Sidebar.Entry entry) {
        assert(entry != root.entry);
        assert(map.has_key(entry));

        Node entry_node = map.get(entry);

        entry_node.prune_children(prune_callback);

        assert(entry_node.parent != null);
        entry_node.parent.remove_child(entry_node);

        bool removed = map.unset(entry);
        assert(removed);

        entry_removed(entry);

        if (options.is_hide_if_empty() && !root.has_children())
            set_show_branch(false);
    }

    // Cannot reparent the root.
    public void reparent(Sidebar.Entry new_parent, Sidebar.Entry entry) {
        assert(entry != root.entry);
        assert(map.has_key(entry));
        assert(map.has_key(new_parent));

        Node entry_node = map.get(entry);
        Node new_parent_node = map.get(new_parent);

        assert(entry_node.parent != null);
        Sidebar.Entry old_parent = entry_node.parent.entry;

        entry_node.parent.remove_child(entry_node);
        new_parent_node.add_child(entry_node);

        entry_reparented(entry, old_parent);
    }

    public bool has_entry(Sidebar.Entry entry) {
        return (root.entry == entry || map.has_key(entry));
    }

    // Call when a value related to the comparison of this entry has changed.  The root cannot be
    // reordered.
    public void reorder(Sidebar.Entry entry) {
        assert(entry != root.entry);

        Node? entry_node = map.get(entry);
        assert(entry_node != null);

        assert(entry_node.parent != null);
        if (entry_node.parent.reorder_child(entry_node))
            entry_moved(entry);
    }

    // Call when the entire tree needs to be reordered.
    public void reorder_all() {
        root.reorder_children(true, children_reordered_callback);
    }

    // Call when the children of the entry need to be reordered.
    public void reorder_children(Sidebar.Entry entry, bool recursive) {
        Node? entry_node = map.get(entry);
        assert(entry_node != null);

        entry_node.reorder_children(recursive, children_reordered_callback);
    }

    public void change_all_comparators(CompareFunc<Sidebar.Entry>? comparator) {
        root.change_comparator(comparator, true, children_reordered_callback);
    }

    public void change_comparator(Sidebar.Entry entry, bool recursive,
        CompareFunc<Sidebar.Entry>? comparator) {
        Node? entry_node = map.get(entry);
        assert(entry_node != null);

        entry_node.change_comparator(comparator, recursive, children_reordered_callback);
    }

    public int get_child_count(Sidebar.Entry parent) {
        Node? parent_node = map.get(parent);
        assert(parent_node != null);

        return (parent_node.children != null) ? parent_node.children.size : 0;
    }

    // Gets a snapshot of the children of the entry; this list will not be changed as the
    // branch is updated.
    public Gee.List<Sidebar.Entry>? get_children(Sidebar.Entry parent) {
        assert(map.has_key(parent));

        Node parent_node = map.get(parent);
        if (parent_node.children == null)
            return null;

        Gee.List<Sidebar.Entry> child_entries = new Gee.ArrayList<Sidebar.Entry>();
        foreach (Node child in parent_node.children)
            child_entries.add(child.entry);

        return child_entries;
    }

    public Sidebar.Entry? find_first_child(Sidebar.Entry parent, Locator<Sidebar.Entry> locator) {
        Node? parent_node = map.get(parent);
        assert(parent_node != null);

        if (parent_node.children == null)
            return null;

        foreach (Node child in parent_node.children) {
            if (locator(child.entry))
                return child.entry;
        }

        return null;
    }

    // Returns null if entry is root;
    public Sidebar.Entry? get_parent(Sidebar.Entry entry) {
        if (entry == root.entry)
            return null;

        Node? entry_node = map.get(entry);
        assert(entry_node != null);
        assert(entry_node.parent != null);

        return entry_node.parent.entry;
    }

    // Returns null if entry is root;
    public Sidebar.Entry? get_previous_sibling(Sidebar.Entry entry) {
        if (entry == root.entry)
            return null;

        Node? entry_node = map.get(entry);
        assert(entry_node != null);
        assert(entry_node.parent != null);
        assert(entry_node.parent.children != null);

        Node? sibling = entry_node.parent.children.lower(entry_node);

        return (sibling != null) ? sibling.entry : null;
    }

    // Returns null if entry is root;
    public Sidebar.Entry? get_next_sibling(Sidebar.Entry entry) {
        if (entry == root.entry)
            return null;

        Node? entry_node = map.get(entry);
        assert(entry_node != null);
        assert(entry_node.parent != null);
        assert(entry_node.parent.children != null);

        Node? sibling = entry_node.parent.children.higher(entry_node);

        return (sibling != null) ? sibling.entry : null;
    }

    private void prune_callback(Node node) {
        entry_removed(node.entry);
    }

    private void children_reordered_callback(Node node) {
        children_reordered(node.entry);
    }
}

