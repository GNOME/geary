/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.Collection {

public Gee.ArrayList<G> to_array_list<G>(Gee.Collection<G> c) {
    Gee.ArrayList<G> list = new Gee.ArrayList<G>();
    list.add_all(c);
    
    return list;
}

public G? get_first<G>(Gee.Collection<G> c) {
    Gee.Iterator<G> iter = c.iterator();
    
    return iter.next() ? iter.get() : null;
}

public bool are_sets_equal<G>(Gee.Set<G> a, Gee.Set<G> b) {
    if (a.size != b.size)
        return false;
    
    foreach (G element in a) {
        if (!b.contains(element))
            return false;
    }
    
    return true;
}

// This *must* be used in place of Gee,TreeSet until the fix for this bug is widely distributed:
// https://bugzilla.gnome.org/show_bug.cgi?id=695045
public class FixedTreeSet<G> : Gee.TreeSet<G> {
    public FixedTreeSet(CompareFunc? compare_func = null) {
        base (compare_func);
    }
    
    ~FixedTreeSet() {
        clear();
    }
}

}
