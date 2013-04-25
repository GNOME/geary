/* Copyright 2011-2013 Yorba Foundation
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

