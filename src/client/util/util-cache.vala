/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** A simple least-recently-used cache. */
public class Util.Cache.Lru<T> : Geary.BaseObject {


    private class CacheEntry<T> {


        public static int lru_compare(CacheEntry a, CacheEntry b) {
            if (a.key == b.key) {
                return 0;
            }
            if (a.last_used != b.last_used) {
                return (int) (a.last_used - b.last_used);
            }
            // If all else is equal, use the keys themselves to
            // stabilise the sorting order
            return GLib.strcmp(a.key, b.key);
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
    private GLib.Sequence<CacheEntry<T>> ordering =
        new GLib.Sequence<CacheEntry<T>>();


    /**
     * Creates a new least-recently-used cache with the given size.
     */
    public Lru(uint max_size) {
        this.max_size = max_size;
    }

    /**
     * Determines if the given key exists in the cache.
     */
    public bool has_key(string key) {
        return this.cache.has_key(key);
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
        this.ordering.append(entry);

        // Prune if needed
        if (this.cache.size > this.max_size) {
            var oldest = this.ordering.get_begin_iter();
            if (oldest != null) {
                this.cache.unset(oldest.get().key);
                oldest.remove();
            }
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
            var to_remove = this.ordering.lookup(entry, CacheEntry.lru_compare);
            if (to_remove != null) {
                to_remove.remove();
            }
            entry.last_used = now;
            this.ordering.append(entry);
        }
        return value;
    }

    /** Removes an entry from the cache and returns it, if found. */
    public T remove_entry(string key) {
        CacheEntry<T>? entry = null;
        T value = null;
        this.cache.unset(key, out entry);
        if (entry != null) {
            var to_remove = this.ordering.lookup(entry, CacheEntry.lru_compare);
            if (to_remove != null) {
                to_remove.remove();
            }
            value = entry.value;
        }
        return value;
    }

    /** Evicts all entries in the cache. */
    public void clear() {
        this.cache.clear();

        var first = this.ordering.get_begin_iter();
        if (first != null) {
            var last = this.ordering.get_end_iter();
            first.remove_range(last);
        }
    }

}
