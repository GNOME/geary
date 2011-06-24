/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Comparable {
    public abstract bool equals(Comparable other);
    
    public static bool equal_func(void *a, void *b) {
        return ((Comparable *) a)->equals((Comparable *) b);
    }
}

public interface Geary.Hashable {
    public abstract uint get_hash();
    
    public static uint hash_func(void *ptr) {
        return ((Hashable *) ptr)->get_hash();
    }
}

