/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary {
    public Geary.Iterable<G> traverse<G>(Gee.Iterable<G> i) {
        return new Geary.Iterable<G>(i.iterator());
    }
}

/**
 * An Iterable that simply wraps an existing Iterator.  You get one iteration,
 * and only one iteration.  Basically every method triggers one iteration and
 * returns a new object.
 *
 * Note that this can't inherit from Gee.Iterable because its interface
 * requires that map/filter/etc. return Iterators, not Iterables.  It still
 * works in foreach.
 */

public class Geary.Iterable<G> : BaseObject {
    private Gee.Iterator<G> i;
    
    public Iterable(Gee.Iterator<G> iterator) {
        i = iterator;
    }
    
    public virtual Gee.Iterator<G> iterator() {
        return i;
    }
    
    public Iterable<A> map<A>(Gee.MapFunc<A, G> f) {
        return new Iterable<A>(i.map<A>(f));
    }
    
    public Iterable<A> scan<A>(Gee.FoldFunc<A, G> f, owned A seed) {
        return new Iterable<A>(i.scan<A>(f, seed));
    }
    
    public Iterable<G> filter(owned Gee.Predicate<G> f) {
        return new Iterable<G>(i.filter(f));
    }
    
    public Iterable<G> chop(int offset, int length = -1) {
        return new Iterable<G>(i.chop(offset, length));
    }
    
    public Iterable<A> map_nonnull<A>(Gee.MapFunc<A, G> f) {
        return new Iterable<A>(i.map<A>(f).filter(g => g != null));
    }
    
    /**
     * Return only objects of the destination type, as the destination type.
     * Only works on types derived from Object.
     */
    public Iterable<A> cast_object<A>() {
        return new Iterable<G>(
            // This would be a lot simpler if valac didn't barf on the shorter,
            // more obvious syntax for each of these delegates here.
            i.filter(g => ((Object) g).get_type().is_a(typeof(A)))
            .map<A>(g => { return (A) g; }));
    }
    
    public G? first() {
        return (i.next() ? i.@get() : null);
    }
    
    public G? first_matching(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (f(g))
                return g;
        }
        return null;
    }
    
    public bool any(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (f(g))
                return true;
        }
        return false;
    }
    
    public bool all(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (!f(g))
                return false;
        }
        return true;
    }
    
    public int count_matching(owned Gee.Predicate<G> f) {
        int count = 0;
        foreach (G g in this) {
            if (f(g))
                count++;
        }
        return count;
    }
    
    public Gee.Collection<G> add_all_to(Gee.Collection<G> c) {
        while (i.next())
            c.add(i.@get());
        return c;
    }
    
    public Gee.ArrayList<G> to_array_list(owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.ArrayList<G>) add_all_to(new Gee.ArrayList<G>(equal_func));
    }
    
    public Gee.LinkedList<G> to_linked_list(owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.LinkedList<G>) add_all_to(new Gee.LinkedList<G>(equal_func));
    }
    
    public Gee.HashSet<G> to_hash_set(owned Gee.HashDataFunc<G>? hash_func = null,
        owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.HashSet<G>) add_all_to(new Gee.HashSet<G>(hash_func, equal_func));
    }
    
    public Gee.TreeSet<G> to_tree_set(owned CompareDataFunc<G>? compare_func = null) {
        return (Gee.TreeSet<G>) add_all_to(new Gee.TreeSet<G>(compare_func));
    }
    
    public Gee.Map<K, G> add_all_to_map<K>(Gee.Map<K, G> c, Gee.MapFunc<K, G> key_func) {
        while (i.next()) {
            G g = i.@get();
            c.@set(key_func(g), g);
        }
        return c;
    }
    
    public Gee.HashMap<K, G> to_hash_map<K>(Gee.MapFunc<K, G> key_func,
        owned Gee.HashDataFunc<K>? key_hash_func = null,
        owned Gee.EqualDataFunc<K>? key_equal_func = null,
        owned Gee.EqualDataFunc<G>? value_equal_func = null) {
        return (Gee.HashMap<K, G>) add_all_to_map<K>(new Gee.HashMap<K, G>(
            key_hash_func, key_equal_func, value_equal_func), key_func);
    }
}
