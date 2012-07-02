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

}
