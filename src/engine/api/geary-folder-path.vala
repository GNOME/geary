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

public class Geary.FolderPath : BaseObject, Gee.Hashable<Geary.FolderPath>,
    Gee.Comparable<Geary.FolderPath> {


    /**
     * The name of this folder (without any child or parent names or delimiters).
     */
    public string basename { get; private set; }

    /**
     * Whether this path is lexiographically case-sensitive.
     *
     * This has implications, as {@link FolderPath} is Comparable and Hashable.
     */
    public bool case_sensitive { get; private set; }

    /**
     * Determines if this path is a root folder path.
     */
    public virtual bool is_root {
        get { return this.path == null || this.path.size == 0; }
    }

    /**
     * Determines if this path is a child of the root folder.
     */
    public bool is_top_level {
        get {
            FolderPath? parent = get_parent();
            return parent != null && parent.is_root;
        }
    }


    private Gee.List<Geary.FolderPath>? path = null;
    private uint stored_hash = uint.MAX;


    /** Constructor only for use by {@link FolderRoot}. */
    internal FolderPath() {
        this.basename = "";
        this.case_sensitive = false;
    }

    private FolderPath.child(Gee.List<Geary.FolderPath> path, string basename, bool case_sensitive) {
        assert(path[0] is FolderRoot);
        
        this.path = path;
        this.basename = basename;
        this.case_sensitive = case_sensitive;
    }

    /**
     * Returns the {@link FolderRoot} of this path.
     */
    public Geary.FolderRoot get_root() {
        return (FolderRoot) ((path != null && path.size > 0) ? path[0] : this);
    }
    
    /**
     * Returns the parent {@link FolderPath} of this folder or null if this is the root.
     *
     * @see is_root
     */
    public Geary.FolderPath? get_parent() {
        return (path != null && path.size > 0) ? path.last() : null;
    }
    
    /**
     * Returns the number of folders in this path, not including any children of this object.
     */
    public int get_path_length() {
        // include self, which is not stored in the path list
        return (path != null) ? path.size + 1 : 1;
    }
    
    /**
     * Returns the {@link FolderPath} object at the index, with this FolderPath object being
     * the farthest child.
     *
     * Root is at index 0 (zero).
     *
     * Returns null if index is out of bounds.  There is always at least one element in the path,
     * namely this one, meaning zero is always acceptable and that index[length - 1] will always
     * return this object.
     *
     * @see get_path_length
     */
    public Geary.FolderPath? get_folder_at(int index) {
        // include self, which is not stored in the path list ... essentially, this logic makes it
        // look like "this" is stored at the end of the path list
        if (path == null)
            return (index == 0) ? this : null;
        
        int length = path.size;
        if (index < length)
            return path[index];
        
        if (index == length)
            return this;
        
        return null;
    }
    
    /**
     * Returns the {@link FolderPath} as a List of {@link basename} strings, this FolderPath's
     * being the last in the list.
     *
     * Thus, the list should have at least one element.
     */
    public Gee.List<string> as_list() {
        Gee.List<string> list = new Gee.ArrayList<string>();
        
        if (path != null) {
            foreach (Geary.FolderPath folder in path)
                list.add(folder.basename);
        }
        
        list.add(basename);
        
        return list;
    }

    /**
     * Creates a path that is a child of this folder.
     *
     * Specifying {@link Trillian.TRUE} or {@link Trillian.FALSE} for
     * `is_case_sensitive` forces case-sensitivity either way. If
     * {@link Trillian.UNKNOWN}, then {@link
     * FolderRoot.default_case_sensitivity} is used.
     */
    public virtual Geary.FolderPath
        get_child(string basename,
                  Trillian is_case_sensitive = Trillian.UNKNOWN) {
        // Build the child's path, which is this node's path plus this node
        Gee.List<FolderPath> child_path = new Gee.ArrayList<FolderPath>();
        if (path != null)
            child_path.add_all(path);
        child_path.add(this);

        return new FolderPath.child(
            child_path,
            basename,
            is_case_sensitive.to_boolean(get_root().default_case_sensitivity)
        );
    }

    /**
     * Returns true if the other {@link FolderPath} has the same parent as this one.
     *
     * Like {@link equal_to} and {@link compare_to}, this comparison the comparison is
     * lexiographic, not by reference.
     */
    public bool has_same_parent(FolderPath other) {
        FolderPath? parent = get_parent();
        FolderPath? other_parent = other.get_parent();
        
        if (parent == other_parent)
            return true;
        
        if (parent != null && other_parent != null)
            return parent.equal_to(other_parent);
        
        return false;
    }

    /**
     * Determines if this path is a strict ancestor of another.
     */
    public bool is_descendant(FolderPath target) {
        bool is_descendent = false;
        Geary.FolderPath? path = target.get_parent();
        while (path != null) {
            if (path.equal_to(this)) {
                is_descendent = true;
                break;
            }
            path = path.get_parent();
        }
        return is_descendent;
    }

    private uint get_basename_hash() {
        return case_sensitive ? str_hash(basename) : str_hash(basename.down());
    }
    
    private int compare_internal(Geary.FolderPath other, bool allow_case_sensitive, bool normalize) {
        if (this == other)
            return 0;
        
        // walk elements using as_list() as that includes the basename (whereas path does not),
        // avoids the null problem, and makes comparisons straightforward
        Gee.List<string> this_list = as_list();
        Gee.List<string> other_list = other.as_list();
        
        // if paths exist, do comparison of each parent in order
        int min = int.min(this_list.size, other_list.size);
        for (int ctr = 0; ctr < min; ctr++) {
            string this_element = this_list[ctr];
            string other_element = other_list[ctr];
            
            if (normalize) {
                this_element = this_element.normalize();
                other_element = other_element.normalize();
            }
            if (!allow_case_sensitive
                // if either case-sensitive, then comparison is CS
                || (!get_folder_at(ctr).case_sensitive && !other.get_folder_at(ctr).case_sensitive)) {
                this_element = this_element.casefold();
                other_element = other_element.casefold();
            }
            
            int result = this_element.collate(other_element);
            if (result != 0)
                return result;
        }
        
        // paths up to the min element count are equal, shortest path is less-than, otherwise
        // equal paths
        return this_list.size - other_list.size;
    }
    
    /**
     * Does a Unicode-normalized, case insensitive match.  Useful for getting a rough idea if
     * a folder matches a name, but shouldn't be used to determine strict equality.
     */
    public int compare_normalized_ci(Geary.FolderPath other) {
        return compare_internal(other, false, true);
    }
    
    /**
     * {@inheritDoc}
     *
     * Comparisons for Geary.FolderPath is defined as (a) empty paths are less-than non-empty paths
     * and (b) each element is compared to the corresponding path element of the other FolderPath
     * following collation rules for casefolded (case-insensitive) compared, and (c) shorter paths
     * are less-than longer paths, assuming the path elements are equal up to the shorter path's
     * length.
     *
     * Note that {@link FolderPath.case_sensitive} affects comparisons.
     *
     * Returns -1 if this path is lexiographically before the other, 1 if its after, and 0 if they
     * are equal.
     */
    public int compare_to(Geary.FolderPath other) {
        return compare_internal(other, true, false);
    }
    
    /**
     * {@inheritDoc}
     *
     * Note that {@link FolderPath.case_sensitive} affects comparisons.
     */
    public uint hash() {
        if (stored_hash != uint.MAX)
            return stored_hash;
        
        // always one element in path
        stored_hash = get_folder_at(0).get_basename_hash();
        
        int path_length = get_path_length();
        for (int ctr = 1; ctr < path_length; ctr++)
            stored_hash ^= get_folder_at(ctr).get_basename_hash();
        
        return stored_hash;
    }
    
    private bool is_basename_equal(string cmp, bool other_cs) {
        // case-sensitive comparison if either is sensitive
        return (other_cs || case_sensitive) ? (basename == cmp) : (basename.down() == cmp.down());
    }
    
    /**
     * {@inheritDoc}
     */
    public bool equal_to(Geary.FolderPath other) {
        int path_length = get_path_length();
        if (other.get_path_length() != path_length)
            return false;
        
        for (int ctr = 0; ctr < path_length; ctr++) {
            // this should never return null as length is already checked
            FolderPath? other_folder = other.get_folder_at(ctr);
            assert(other_folder != null);
            
            if (!get_folder_at(ctr).is_basename_equal(other_folder.basename, other_folder.case_sensitive))
                return false;
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
        StringBuilder builder = new StringBuilder();
        if (this.path != null) {
            foreach (Geary.FolderPath folder in this.path) {
                builder.append(folder.basename);
                builder.append_c('>');
            }
        }
        builder.append(basename);
        return builder.str;
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
public class Geary.FolderRoot : Geary.FolderPath {


    /** {@inheritDoc} */
    public override bool is_root {
        get { return true; }
    }

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
