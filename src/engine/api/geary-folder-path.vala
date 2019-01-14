/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic structure for representing and maintaining folder paths.
 *
 * A FolderPath may have one parent and one child.  A FolderPath without a parent is called a
 * root folder can be be created with {@link FolderRoot}, which is a FolderPath.
 *
 * @see FolderRoot
 */

public class Geary.FolderPath :
    BaseObject, Gee.Hashable<FolderPath>, Gee.Comparable<FolderPath> {


    // Workaround for Vala issue #659. See children below.
    private class FolderPathWeakRef {

        GLib.WeakRef weak_ref;

        public FolderPathWeakRef(FolderPath path) {
            this.weak_ref = GLib.WeakRef(path);
        }

        public FolderPath? get() {
            return this.weak_ref.get() as FolderPath;
        }

    }


    /** The base name of this folder, excluding parents. */
    public string name { get; private set; }

    /**
     * Whether this path is lexiographically case-sensitive.
     *
     * This has implications, as {@link FolderPath} is Comparable and Hashable.
     */
    public bool case_sensitive { get; private set; }

    /** Determines if this path is a root folder path. */
    public bool is_root {
        get { return this.parent == null; }
    }

    /** Determines if this path is a child of the root folder. */
    public bool is_top_level {
        get {
            FolderPath? parent = parent;
            return parent != null && parent.is_root;
        }
    }

    /** Returns the parent of this path. */
    public FolderPath? parent { get; private set; }

    private string[] path;

    // Would use a `weak FolderPath` value type for this map instead of
    // the custom class, but we can't currently reassign built-in
    // weak refs back to a strong ref at the moment, nor use a
    // GLib.WeakRef as a generics param. See Vala issue #659.
    private Gee.Map<string,FolderPathWeakRef?> children =
        new Gee.HashMap<string,FolderPathWeakRef?>();

    private uint? stored_hash = null;


    /** Constructor only for use by {@link FolderRoot}. */
    internal FolderPath() {
        this.name = "";
        this.parent = null;
        this.case_sensitive = false;
        this.path = new string[0];
    }

    private FolderPath.child(FolderPath parent,
                             string name,
                             bool case_sensitive) {
        this.parent = parent;
        this.name = name;
        this.case_sensitive = case_sensitive;
        this.path = parent.path.copy();
        this.path += name;
    }

    /**
     * Returns the {@link FolderRoot} of this path.
     */
    public Geary.FolderRoot get_root() {
        FolderPath? path = this;
        while (path.parent != null) {
            path = path.parent;
        }
        return (FolderRoot) path;
    }

    /**
     * Returns an array of the names of non-root elements in the path.
     */
    public string[] as_array() {
        return this.path;
    }

    /**
     * Creates a path that is a child of this folder.
     *
     * Specifying {@link Trillian.TRUE} or {@link Trillian.FALSE} for
     * `is_case_sensitive` forces case-sensitivity either way. If
     * {@link Trillian.UNKNOWN}, then {@link
     * FolderRoot.default_case_sensitivity} is used.
     */
    public virtual FolderPath
        get_child(string name,
                  Trillian is_case_sensitive = Trillian.UNKNOWN) {
        FolderPath? child = null;
        FolderPathWeakRef? child_ref = this.children.get(name);
        if (child_ref != null) {
            child = child_ref.get();
        }
        if (child == null) {
            child = new FolderPath.child(
                this,
                name,
                is_case_sensitive.to_boolean(
                    get_root().default_case_sensitivity
                )
            );
            this.children.set(name, new FolderPathWeakRef(child));
        }
        return child;
    }

    /**
     * Determines if this path is a strict ancestor of another.
     */
    public bool is_descendant(FolderPath target) {
        bool is_descendent = false;
        FolderPath? path = target.parent;
        while (path != null) {
            if (path.equal_to(this)) {
                is_descendent = true;
                break;
            }
            path = path.parent;
        }
        return is_descendent;
    }

    /**
     * Does a Unicode-normalized, case insensitive match.  Useful for
     * getting a rough idea if a folder matches a name, but shouldn't
     * be used to determine strict equality.
     */
    public int compare_normalized_ci(FolderPath other) {
        return compare_internal(other, false, true);
    }

    /**
     * {@inheritDoc}
     *
     * Comparisons for FolderPath is defined as (a) empty paths
     * are less-than non-empty paths and (b) each element is compared
     * to the corresponding path element of the other FolderPath
     * following collation rules for casefolded (case-insensitive)
     * compared, and (c) shorter paths are less-than longer paths,
     * assuming the path elements are equal up to the shorter path's
     * length.
     *
     * Note that {@link FolderPath.case_sensitive} affects comparisons.
     *
     * Returns -1 if this path is lexiographically before the other, 1
     * if its after, and 0 if they are equal.
     */
    public int compare_to(FolderPath other) {
        return compare_internal(other, true, false);
    }

    /**
     * {@inheritDoc}
     *
     * Note that {@link FolderPath.case_sensitive} affects comparisons.
     */
    public uint hash() {
        if (this.stored_hash == null) {
            this.stored_hash = 0;
            FolderPath? path = this;
            while (path != null) {
                this.stored_hash ^= (case_sensitive)
                    ? str_hash(path.name) : str_hash(path.name.down());
                path = path.parent;
            }
        }
        return this.stored_hash;
    }

    /** {@inheritDoc} */
    public bool equal_to(FolderPath other) {
        if (this == other) {
            return true;
        }

        FolderPath? a = this;
        FolderPath? b = other;
        while (a != null && b != null) {
            if (a == b) {
                return true;
            }

            if ((a != null && b == null) ||
                (a == null && b != null)) {
                return false;
            }

            if (a.case_sensitive || b.case_sensitive) {
                if (a.name != b.name) {
                    return false;
                }
            } else {
                if (a.name.down() != b.name.down()) {
                    return false;
                }
            }

            a = a.parent;
            b = b.parent;
        }

        return true;
    }

    /**
     * Returns a string version of the path using a default separator.
     *
     * Do not use this for obtaining an IMAP mailbox name to send to a
     * server, use {@link
     * Geary.Imap.MailboxSpecifier.MailboxSpecifier.from_folder_path}
     * instead. This method is useful for debugging and logging only.
     */
    public string to_string() {
        const char SEP = '>';
        StringBuilder builder = new StringBuilder();
        if (this.is_root) {
            builder.append_c(SEP);
        } else {
            foreach (string name in this.path) {
                builder.append_c(SEP);
                builder.append(name);
            }
        }
        return builder.str;
    }

    private int compare_internal(FolderPath other,
                                 bool allow_case_sensitive,
                                 bool normalize) {
        if (this == other)
            return 0;

        FolderPath a = this;
        FolderPath b = other;

        // Get the common-length prefix of both
        while (a.path.length != b.path.length) {
            if (a.path.length > b.path.length) {
                a = a.parent;
            } else if (b.path.length > a.path.length) {
                b = b.parent;
            }
        }

        // Compare the common-length prefixes of both
        while (a != null && b != null) {
            string a_name = a.name;
            string b_name = b.name;

            if (normalize) {
                a_name = a_name.normalize();
                b_name = b_name.normalize();
            }

            if (!allow_case_sensitive
                // if either case-sensitive, then comparison is CS
                || (!a.case_sensitive && !b.case_sensitive)) {
                a_name = a_name.casefold();
                b_name = b_name.casefold();
            }

            int result = a_name.collate(b_name);
            if (result != 0) {
                return result;
            }

            a = a.parent;
            b = b.parent;
        }

        // paths up to the min element count are equal, shortest path
        // is less-than, otherwise equal paths
        return this.path.length - other.path.length;
    }

}

/**
 * The root of a folder hierarchy.
 *
 * A {@link FolderPath} can only be created by starting with a
 * FolderRoot and adding children via {@link FolderPath.get_child}.
 * Because all FolderPaths hold references to their parents, this
 * element can be retrieved with {@link FolderPath.get_root}.
 */
public class Geary.FolderRoot : FolderPath {


    /**
     * The default case sensitivity of descendant folders.
     *
     * @see FolderRoot.case_sensitive
     * @see FolderPath.get_child
     */
    public bool default_case_sensitivity { get; private set; }


    /**
     * Constructs a new folder root with given default sensitivity.
     */
    public FolderRoot(bool default_case_sensitivity) {
        base();
        this.default_case_sensitivity = default_case_sensitivity;
    }

}
