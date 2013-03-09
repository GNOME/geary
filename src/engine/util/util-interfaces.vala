/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Comparable {
    public abstract int compare(Comparable other);
    
    /**
     * A CompareFunc for any object that implements Comparable
     * (ascending order).
     */
    public static int compare_func(void *a, void *b) {
        return ((Comparable *) a)->compare((Comparable *) b);
    }
    
    /**
     * A reverse CompareFunc for any object that implements
     * Comparable (descending order).
     */
    public static int reverse_compare_func(void *a, void *b) {
        return ((Comparable *) b)->compare((Comparable *) a);
    }
    
    /**
     * A CompareFunc for DateTime.
     */
    public static int date_time_compare(void *a, void *b) {
        return ((DateTime) a).compare((DateTime) b);
    }
    
    public static int int64_compare(void* a, void *b) {
        int64 diff = *((int64 *) a) - *((int64 *) b);
        if (diff < 0)
            return -1;
        else if (diff > 0)
            return 1;
        else
            return 0;
    }
}

public interface Geary.Equalable {
    public abstract bool equals(Equalable other);
    
    /**
     * An EqualFunc for any object that implements Equalable.
     */
    public static bool equal_func(void *a, void *b) {
        return ((Equalable *) a)->equals((Equalable *) b);
    }
    
    /**
     * EqualFunc for nullable objects that implement Equalable.
     */
    public static bool nullable_equal_func(void *a, void *b) {
        if (a == null || b == null)
            return (a == null && b == null);
        return equal_func(a, b);
    }
    
    /**
     * The EqualsFunc counterpart to Hashable.bare_int64_hash().
     */
    public static bool bare_int64_equals(void *a, void *b) {
        return *((int64 *) a) == *((int64 *) b);
    }
    
    /**
     * An EqualFunc for DateTime.
     */
    public static bool date_time_equal(void *a, void *b) {
        return ((DateTime) a).equal((DateTime) b);
    }
}

public interface Geary.Hashable {
    public abstract uint to_hash();
    
    /**
     * A HashFunc for any object that implements Hashable.
     */
    public static uint hash_func(void *ptr) {
        return ((Hashable *) ptr)->to_hash();
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
}

