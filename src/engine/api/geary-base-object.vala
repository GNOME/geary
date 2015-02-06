/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.BaseObject : Object {
#if REF_TRACKING
    private static Gee.HashMap<unowned string, int>? refmap = null;
    
    protected BaseObject() {
        lock (refmap) {
            if (refmap == null) {
                // because strings are unowned and guaranteed to be
                // unique by GType, use direct comparison functions,
                // more efficient then string hash/equal
                refmap = new Gee.HashMap<unowned string, int>(
                    Gee.Functions.get_hash_func_for(typeof(void*)),
                    Gee.Functions.get_equal_func_for(typeof(void*)));
            }
            
            unowned string classname = get_classname();
            refmap.set(classname, refmap.get(classname) + 1);
        }
    }
    
    ~BaseObject() {
        lock (refmap) {
            unowned string classname = get_classname();
            int count = refmap.get(classname) - 1;
            if (count == 0)
                refmap.unset(classname);
            else
                refmap.set(classname, count);
        }
    }
    
    private unowned string get_classname() {
        return get_class().get_type().name();
    }
    
    public static void dump_refs(FileStream outs) {
        if (refmap == null || refmap.size == 0) {
            outs.printf("No references to report.\n");
            
            return;
        }
        
        Gee.ArrayList<unowned string> list = new Gee.ArrayList<unowned string>();
        list.add_all(refmap.keys);
        list.sort();
        foreach (unowned string classname in list)
            outs.printf("%9d %s\n", refmap.get(classname), classname);
    }
#else
    protected BaseObject() {
    }
    
    public static void dump(FileStream outs) {
        outs.printf("Reference tracking disabled.\n");
    }
#endif
}

