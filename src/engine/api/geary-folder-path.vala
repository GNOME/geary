/* Copyright 2011-2013 Yorba Foundation
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
 * A FolderPath has a delimiter.  This delimiter is specified in the FolderRoot.
 *
 * @see FolderRoot
 */

public class Geary.FolderPath : BaseObject, Gee.Hashable<Geary.FolderPath>,
    Gee.Comparable<Geary.FolderPath> {
    /**
     * The name of this folder (without any child or parent names or delimiters).
     */
    public string basename { get; private set; }
    
    private Gee.List<Geary.FolderPath>? path = null;
    private string? fullpath = null;
    private string? fullpath_separator = null;
    private uint stored_hash = uint.MAX;
    
    protected FolderPath(string basename) {
        assert(this is FolderRoot);
        
        this.basename = basename;
    }
    
    private FolderPath.child(Gee.List<Geary.FolderPath> path, string basename) {
        assert(path[0] is FolderRoot);
        
        this.path = path;
        this.basename = basename;
    }
    
    /**
     * Returns true if this {@link FolderPath} is a root folder.
     *
     * This means that the FolderPath ''should'' be castable into {@link FolderRoot}, which is
     * enforced through the constructor and accessor styles of this class.  However, this test
     * merely checks if this FolderPath has any children.  A GObject "is" operation is the
     * reliable way to cast to FolderRoot.
     */
    public bool is_root() {
        return (path == null || path.size == 0);
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
     * Creates a {@link FolderPath} object that is a child of this folder.
     */
    public Geary.FolderPath get_child(string basename) {
        // Build the child's path, which is this node's path plus this node
        Gee.List<FolderPath> child_path = new Gee.ArrayList<FolderPath>();
        if (path != null)
            child_path.add_all(path);
        child_path.add(this);
        
        return new FolderPath.child(child_path, basename);
    }
    
    /**
     * Returns true if this {@link FolderPath} has a default separator.
     *
     * It determines this by returning true if its {@link FolderRoot.default_separator} is
     * non-null and non-empty.
     */
    public bool has_default_separator() {
        return get_root().default_separator != null;
    }
    
    /**
     * Returns true if the other {@link FolderPath} has the same parent as this one.
     *
     * Like {@link equal_to} and {@link compare_to}, this comparison does not account for the
     * {@link FolderRoot.default_separator}.  The comparison is lexiographic, not by reference.
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
     * Returns the {@link FolderPath} as a single string with the supplied separator used as a
     * delimiter.
     *
     * If null is passed in, {@link FolderRoot.default_separator} is used.  If the default
     * separator is null, no fullpath can be produced and this method will return null.
     *
     * The separator is not appended to the fullpath.
     *
     * @see has_default_separator
     */
    public string? get_fullpath(string? use_separator) {
        string? separator = use_separator ?? get_root().default_separator;
        
        // no separator, no fullpath
        if (separator == null)
            return null;
        
        // use cached copy if the stars align
        if (fullpath != null && fullpath_separator == separator)
            return fullpath;
        
        StringBuilder builder = new StringBuilder();
        
        if (path != null) {
            foreach (Geary.FolderPath folder in path) {
                builder.append(folder.basename);
                builder.append(separator);
            }
        }
        
        builder.append(basename);
        
        fullpath = builder.str;
        fullpath_separator = separator;
        
        return fullpath;
    }
    
    private uint get_basename_hash(bool cs) {
        return cs ? str_hash(basename) : str_hash(basename.down());
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
     * Note that the {@link FolderRoot.default_separator} has no bearing on comparisons, although
     * {@link FolderRoot.case_sensitive} does.
     *
     * Returns -1 if this path is lexiographically before the other, 1 if its after, and 0 if they
     * are equal.
     */
    public int compare_to(Geary.FolderPath other) {
        if (this == other)
            return 0;
        
        // walk elements using as_list() as that includes the basename (whereas path does not),
        // avoids the null problem, and makes comparisons straightforward
        Gee.List<string> this_list = as_list();
        Gee.List<string> other_list = other.as_list();
        
        // if paths exist, do comparison of each parent in order
        int min = int.min(this_list.size, other_list.size);
        for (int ctr = 0; ctr < min; ctr++) {
            int result = this_list[ctr].casefold().collate(other_list[ctr].casefold());
            if (result != 0)
                return result;
        }
        
        // paths up to the min element count are equal, shortest path is less-than, otherwise
        // equal paths
        return this_list.size - other_list.size;
    }
    
    /**
     * {@inheritDoc}
     *
     * As with {@link compare_to}, the {@link FolderRoot.default_separator} has no bearing on the
     * hash, although {@link FolderRoot.case_sensitive} does.
     */
    public uint hash() {
        if (stored_hash != uint.MAX)
            return stored_hash;
        
        bool cs = get_root().case_sensitive;
        
        // always one element in path
        uint calc = get_folder_at(0).get_basename_hash(cs);
        
        int path_length = get_path_length();
        for (int ctr = 1; ctr < path_length; ctr++)
            calc ^= get_folder_at(ctr).get_basename_hash(cs);
        
        stored_hash = calc;
        
        return stored_hash;
    }
    
    private bool is_basename_equal(string cmp, bool cs) {
        return cs ? (basename == cmp) : (basename.down() == cmp.down());
    }
    
    /**
     * {@inheritDoc}
     */
    public bool equal_to(Geary.FolderPath other) {
        int path_length = get_path_length();
        if (other.get_path_length() != path_length)
            return false;
        
        bool cs = get_root().case_sensitive;
        if (other.get_root().case_sensitive != cs) {
            message("Comparing %s and %s with different case sensitivities", to_string(),
                other.to_string());
        }
        
        for (int ctr = 0; ctr < path_length; ctr++) {
            if (!get_folder_at(ctr).is_basename_equal(other.get_folder_at(ctr).basename, cs))
                return false;
        }
        
        return true;
    }
    
    /**
     * Returns the fullpath using the default separator.
     *
     * Use only for debugging and logging.
     */
    public string to_string() {
        // use slash if no default separator available
        return get_fullpath(has_default_separator() ? null : "/");
    }
}

/**
 * The root of a folder heirarchy.
 *
 * A {@link FolderPath} can only be created by starting with a FolderRoot and adding children
 * via {@link FolderPath.get_child}.  Because all FolderPaths hold references to their parents,
 * this element can be retrieved with {@link FolderPath.get_root}.
 */
public class Geary.FolderRoot : Geary.FolderPath {
    /**
     * The default separator (delimiter) for this path.
     *
     * If null, the separator can be supplied later to {@link FolderPath.get_fullpath}.
     *
     * This value will never be empty (i.e. zero-length).  A zero-length separator passed to the
     * constructor will result in this property being null.
     */
    public string? default_separator { get; private set; }
    /**
     * Whether this path is lexiographically case-sensitive.
     *
     * This has implications, as {@link FolderPath} is Comparable and Hashable.
     */
    public bool case_sensitive { get; private set; }
    
    public FolderRoot(string basename, string? default_separator, bool case_sensitive) {
        base (basename);
        
        this.default_separator = !String.is_empty(default_separator) ? default_separator : null;
        this.case_sensitive;
    }
}

