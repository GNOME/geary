/* Copyright 2012-2013 Yorba Foundation
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

/**
 * To be used by a Hashable's to_hash() method.
 */
public static uint int64_hash(int64 value) {
    return hash_memory(&value, sizeof(int64));
}

/**
 * To be used as a raw HashFunc where an int64 is being stored directly.
 */
public static uint bare_int64_hash(void *ptr) {
    return hash_memory(ptr, sizeof(int64));
}

/**
 * A HashFunc for DateTime.
 */
public static uint date_time_hash(void *a) {
    return ((DateTime) a).hash();
}

/**
 * A rotating-XOR hash that can be used to hash memory buffers of any size.  Use only if
 * equality is determined by memory contents.
 */
public static uint hash_memory(void *ptr, size_t bytes) {
    uint8 *u8 = (uint8 *) ptr;
    uint hash = 0;
    for (int ctr = 0; ctr < bytes; ctr++)
        hash = (hash << 4) ^ (hash >> 28) ^ (*u8++);
    
    return hash;
}

/**
 * This *must* be used in place of Gee,TreeSet until the fix for this bug is widely distributed:
 * [[https://bugzilla.gnome.org/show_bug.cgi?id=695045]]
 */
public class FixedTreeSet<G> : Gee.TreeSet<G> {
    public FixedTreeSet(owned GLib.CompareDataFunc<G>? compare_func = null) {
        base ( (owned) compare_func);
    }
    
    ~FixedTreeSet() {
        clear();
    }
}

}
