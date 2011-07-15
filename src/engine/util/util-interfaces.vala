/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Comparable {
    public abstract int compare(Comparable other);
    
    public static int compare_func(void *a, void *b) {
        return ((Comparable *) a)->compare((Comparable *) b);
    }
}

public interface Geary.Equalable {
    public abstract bool equals(Equalable other);
    
    public static bool equal_func(void *a, void *b) {
        return ((Equalable *) a)->equals((Equalable *) b);
    }
}

public interface Geary.Hashable {
    public abstract uint to_hash();
    
    public static uint hash_func(void *ptr) {
        return ((Hashable *) ptr)->to_hash();
    }
}

