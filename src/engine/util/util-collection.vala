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

public void add_all_array<G>(Gee.Collection<G> c, G[] ar) {
    foreach (G g in ar)
        c.add(g);
}

public G? get_first<G>(Gee.Collection<G> c) {
    Gee.Iterator<G> iter = c.iterator();
    
    return iter.next() ? iter.get() : null;
}

/**
 * Returns the first element in the Collection that passes the Predicte function.
 *
 * The Collection is walked in Iterator order.
 */
public G? find_first<G>(Gee.Collection<G> c, owned Gee.Predicate<G> pred) {
    Gee.Iterator<G> iter = c.iterator();
    while (iter.next()) {
        if (pred(iter.get()))
            return iter.get();
    }
    
    return null;
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
 * Removes all elements from the Collection that do pass the Predicate function.
 *
 * Note that this modifies the supplied Collection.
 */
public Gee.Collection<G> remove_if<G>(Gee.Collection<G> c, owned Gee.Predicate<G> pred) {
    Gee.Iterator<G> iter = c.iterator();
    while (iter.next()) {
        if (pred(iter.get()))
            iter.remove();
    }
    
    return c;
}

/**
 * Sets the dest Map with all keys and values in src.
 */
public void map_set_all<K, V>(Gee.Map<K, V> dest, Gee.Map<K, V> src) {
    foreach (K key in src.keys)
        dest.set(key, src.get(key));
}

/**
 * Sets multiple elements with the same key in a MultiMap.
 */
public void multi_map_set_all<K, V>(Gee.MultiMap<K, V> dest, K key, Gee.Collection<V> values) {
    foreach (V value in values)
        dest.set(key, value);
}

/**
 * Return a MultiMap of value => key of the input map's key => values.
 */
public Gee.MultiMap<V, K> reverse_multi_map<K, V>(Gee.MultiMap<K, V> map) {
    Gee.HashMultiMap<V, K> reverse = new Gee.HashMultiMap<V, K>();
    foreach (K key in map.get_keys()) {
        foreach (V value in map.get(key))
            reverse.set(value, key);
    }
    
    return reverse;
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
