/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** A simple least-recently-used cache. */
public class Util.Cache.Lru<T> : Geary.BaseObject {


    private class CacheEntry<T> {


        public static int lru_compare(CacheEntry<T> a, CacheEntry<T> b) {
            return (a.key == b.key)
                ? 0 : (int) (a.last_used - b.last_used);
        }


        public string key;
        public T value;
        public int64 last_used;


        public CacheEntry(string key, T value, int64 last_used) {
            this.key = key;
            this.value = value;
            this.last_used = last_used;
        }

    }


    /** Specifies the maximum number of cache entries to be stored. */
    public uint max_size { get; set; }

    /** Determines if the cache has any entries or not. */
    public bool is_empty {
        get { return this.cache.is_empty; }
    }

    /** Determines the current number of cache entries. */
    public uint size {
        get { return this.cache.size; }
    }

    private Gee.Map<string,CacheEntry<T>> cache =
        new Gee.HashMap<string,CacheEntry<T>>();
    private Gee.SortedSet<CacheEntry<T>> ordering =
        new Gee.TreeSet<CacheEntry<T>>(CacheEntry.lru_compare);


    /**
     * Creates a new least-recently-used cache with the given size.
     */
    public Lru(uint max_size) {
        this.max_size = max_size;
    }

    /**
     * Sets an entry in the cache, replacing any existing entry.
     *
     * The entry is added to the back of the removal queue. If adding
     * the entry causes the size of the cache to exceed the maximum,
     * the entry at the front of the queue will be evicted.
     */
    public void set_entry(string key, T value) {
        int64 now = GLib.get_monotonic_time();
        CacheEntry<T> entry = new CacheEntry<T>(key, value, now);
        this.cache.set(key, entry);
        this.ordering.add(entry);

        // Prune if needed
        if (this.cache.size > this.max_size) {
            CacheEntry oldest = this.ordering.first();
            this.cache.unset(oldest.key);
            this.ordering.remove(oldest);
        }
    }

    /**
     * Returns the entry from the cache, if found.
     *
     * If the entry was found, it is move to the back of the removal
     * queue.
     */
    public T get_entry(string key) {
        int64 now = GLib.get_monotonic_time();
        CacheEntry<T>? entry = this.cache.get(key);
        T value = null;
        if (entry != null) {
            value = entry.value;
            // Need to remove the entry from the ordering before
            // updating the last used time since doing so changes the
            // ordering
            this.ordering.remove(entry);
            entry.last_used = now;
            this.ordering.add(entry);
        }
        return value;
    }

    /** Removes an entry from the cache and returns it, if found. */
    public T remove_entry(string key) {
        CacheEntry<T>? entry = null;
        T value = null;
        this.cache.unset(key, out entry);
        if (entry != null) {
            this.ordering.remove(entry);
            value = entry.value;
        }
        return value;
    }

    /** Evicts all entries in the cache. */
    public void clear() {
        this.cache.clear();
        this.ordering.clear();
    }

}
