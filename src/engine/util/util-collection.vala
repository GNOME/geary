/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Collection {

public delegate uint8 ByteTransformer(uint8 b);

// A substitute for ArrayList<G>.wrap() for compatibility with older versions of Gee.
public Gee.ArrayList<G> array_list_wrap<G>(G[] a, owned Gee.EqualDataFunc<G>? equal_func = null) {
    Gee.ArrayList<G> list = new Gee.ArrayList<G>(equal_func);
    add_all_array<G>(list, a);
    return list;
}

public Gee.ArrayList<G> to_array_list<G>(Gee.Collection<G> c) {
    Gee.ArrayList<G> list = new Gee.ArrayList<G>();
    list.add_all(c);
    
    return list;
}

public Gee.HashMap<Key, Value> to_hash_map<Key, Value>(
    Gee.Collection<Value> c, Gee.MapFunc<Key, Value> key_selector) {
    Gee.HashMap<Key, Value> map = new Gee.HashMap<Key, Value>();
    foreach (Value v in c)
        map.set(key_selector(v), v);
    return map;
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
 * Removes all keys from the Map.
 */
public void map_unset_all_keys<K, V>(Gee.Map<K, V> map, Gee.Collection<K> keys) {
    foreach (K key in keys)
        map.unset(key);
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
public inline static uint int64_hash(int64 value) {
    return hash_memory(&value, sizeof(int64));
}

/**
 * To be used as hash_func for Gee collections.
 */
public uint int64_hash_func(int64? n) {
    return hash_memory((uint8 *) n, sizeof(int64));
}

/**
 * To be used as equal_func for Gee collections.
 */
public bool int64_equal_func(int64? a, int64? b) {
    int64 *bia = (int64 *) a;
    int64 *bib = (int64 *) b;
    
    return (*bia) == (*bib);
}

/**
 * A rotating-XOR hash that can be used to hash memory buffers of any size.
 */
public uint hash_memory(void *ptr, size_t bytes) {
    if (bytes == 0)
        return 0;
    
    uint8 *u8 = (uint8 *) ptr;
    
    // initialize hash to first byte value and then rotate-XOR from there
    uint hash = *u8;
    for (int ctr = 1; ctr < bytes; ctr++)
        hash = (hash << 4) ^ (hash >> 28) ^ (*u8++);
    
    return hash;
}

/**
 * A rotating-XOR hash that can be used to hash memory buffers of any size until a terminator byte
 * is found.
 *
 * A {@link ByteTransformer} may be supplied to convert bytes before they are hashed.
 *
 * Returns zero if the initial byte is the terminator.
 */
public uint hash_memory_stream(void *ptr, uint8 terminator, ByteTransformer? cb) {
    uint8 *u8 = (uint8 *) ptr;
    
    uint hash = 0;
    for (;;) {
        uint8 b = *u8++;
        if (b == terminator)
            break;
        
        if (cb != null)
            b = cb(b);
        
        hash = (hash << 4) ^ (hash >> 28) ^ b;
    }
    
    return hash;
}

}
