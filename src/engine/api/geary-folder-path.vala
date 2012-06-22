/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.FolderPath : Object, Hashable, Equalable {
    public string basename { get; private set; }
    
    private Gee.List<Geary.FolderPath>? path = null;
    private string? fullpath = null;
    private string? fullpath_separator = null;
    private uint hash = uint.MAX;
    
    protected FolderPath(string basename) {
        assert(this is FolderRoot);
        
        this.basename = basename;
    }
    
    private FolderPath.child(Gee.List<Geary.FolderPath> path, string basename) {
        assert(path[0] is FolderRoot);
        
        this.path = path;
        this.basename = basename;
    }
    
    public bool is_root() {
        return (path == null || path.size == 0);
    }
    
    public Geary.FolderRoot get_root() {
        return (FolderRoot) ((path != null && path.size > 0) ? path[0] : this);
    }
    
    public Geary.FolderPath? get_parent() {
        return (path != null && path.size > 0) ? path.last() : null;
    }
    
    public int get_path_length() {
        // include self, which is not stored in the path list
        return (path != null) ? path.size + 1 : 1;
    }
    
    /**
     * Returns null if index is out of bounds.  There is always at least one element in the path,
     * namely this one.
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
    
    public Gee.List<string> as_list() {
        Gee.List<string> list = new Gee.ArrayList<string>();
        
        if (path != null) {
            foreach (Geary.FolderPath folder in path)
                list.add(folder.basename);
        }
        
        list.add(basename);
        
        return list;
    }
    
    public Geary.FolderPath get_child(string basename) {
        // Build the child's path, which is this node's path plus this node
        Gee.List<FolderPath> child_path = new Gee.ArrayList<FolderPath>();
        if (path != null)
            child_path.add_all(path);
        child_path.add(this);
        
        return new FolderPath.child(child_path, basename);
    }
    
    public string get_fullpath(string? use_separator = null) {
        string? separator = use_separator ?? get_root().default_separator;
        
        // no separator, no heirarchy
        if (separator == null)
            return basename;
        
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
    
    public uint to_hash() {
        if (hash != uint.MAX)
            return hash;
        
        bool cs = get_root().case_sensitive;
        
        // always one element in path
        uint calc = get_folder_at(0).get_basename_hash(cs);
        
        int path_length = get_path_length();
        for (int ctr = 1; ctr < path_length; ctr++)
            calc ^= get_folder_at(ctr).get_basename_hash(cs);
        
        hash = calc;
        
        return hash;
    }
    
    private bool is_basename_equal(string cmp, bool cs) {
        return cs ? (basename == cmp) : (basename.down() == cmp.down());
    }
    
    public bool equals(Equalable o) {
        FolderPath? other = o as FolderPath;
        if (o == null)
            return false;
        
        if (o == this)
            return true;
        
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
     * Returns the fullpath using the default separator.  Using only for debugging and logging.
     */
    public string to_string() {
        return get_fullpath();
    }
}

public class Geary.FolderRoot : Geary.FolderPath {
    public string? default_separator { get; private set; }
    public bool case_sensitive { get; private set; }
    
    public FolderRoot(string basename, string? default_separator, bool case_sensitive) {
        base (basename);
        
        this.default_separator = default_separator;
        this.case_sensitive;
    }
}

