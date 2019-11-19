/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Collection {

    public delegate uint8 ByteTransformer(uint8 b);


    /** Returns a modifiable collection containing a single element. */
    public Gee.Collection<T> single<T>(T element) {
        Gee.Collection<T> single = new Gee.LinkedList<T>();
        single.add(element);
        return single;
    }

    /** Returns a modifiable map containing a single entry. */
    public Gee.Map<K,V> single_map<K,V>(K key, V value) {
        Gee.Map<K,V> single = new Gee.HashMap<K,V>();
        single.set(key, value);
        return single;
    }

    /** Returns a copy of the given collection in a new collection. */
    public Gee.Collection<V> copy<V>(Gee.Collection<V> original) {
        // Use a linked list, the returned value can't be accessed by
        // index anyway
        var copy = new Gee.LinkedList<V>();
        copy.add_all(original);
        return copy;
    }

    /** Returns the first element from a collection. */
    public G? first<G>(Gee.Collection<G> c) {
        Gee.Iterator<G> iter = c.iterator();
        return iter.next() ? iter.get() : null;
    }

    /**
     * Removes all elements that pass the given predicate.
     *
     * Note that this modifies the supplied Collection.
     */
    public Gee.Collection<G> remove_if<G>(Gee.Collection<G> c,
                                          owned Gee.Predicate<G> pred) {
        Gee.Iterator<G> iter = c.iterator();
        while (iter.next()) {
            if (pred(iter.get())) {
                iter.remove();
            }
        }
        return c;
    }

    /**
     * Sets the dest Map with all keys and values in src.
     */
    public void map_set_all<K, V>(Gee.Map<K, V> dest, Gee.Map<K, V> src) {
        foreach (K key in src.keys) {
            dest.set(key, src.get(key));
        }
    }

    /**
     * Sets multiple elements with the same key in a MultiMap.
     */
    public void multi_map_set_all<K, V>(Gee.MultiMap<K, V> dest, K key, Gee.Collection<V> values) {
        foreach (V value in values) {
            dest.set(key, value);
        }
    }

    /**
     * Removes all keys from the Map.
     */
    public void map_unset_all_keys<K, V>(Gee.Map<K, V> map, Gee.Collection<K> keys) {
        foreach (K key in keys) {
            map.unset(key);
        }
    }

    /**
     * Return a MultiMap of value => key of the input map's key => values.
     */
    public Gee.MultiMap<V, K> reverse_multi_map<K, V>(Gee.MultiMap<K, V> map) {
        Gee.HashMultiMap<V, K> reverse = new Gee.HashMultiMap<V, K>();
        foreach (K key in map.get_keys()) {
            foreach (V value in map.get(key)) {
                reverse.set(value, key);
            }
        }

        return reverse;
    }

    /**
     * To be used by a Hashable's to_hash() method.
     */
    public inline uint int64_hash(int64 value) {
        return hash_memory(&value, sizeof(int64));
    }

    /**
     * To be used as hash_func for Gee collections.
     */
    public inline uint int64_hash_func(int64? n) {
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
        if (ptr == null || bytes == 0) {
            return 0;
        }

        uint8 *u8 = (uint8 *) ptr;

        // initialize hash to first byte value and then rotate-XOR from there
        uint hash = *u8;
        for (int ctr = 1; ctr < bytes; ctr++) {
            hash = (hash << 4) ^ (hash >> 28) ^ (*u8++);
        }

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
            if (b == terminator) {
                break;
            }

            if (cb != null) {
                b = cb(b);
            }

            hash = (hash << 4) ^ (hash >> 28) ^ b;
        }

        return hash;
    }

}
