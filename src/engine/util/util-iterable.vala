/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary {
    /**
     * Take a Gee object and return a Geary.Iterable for convenience.
     */
    public Geary.Iterable<G> traverse<G>(Gee.Iterable<G> i) {
        return new Geary.Iterable<G>(i.iterator());
    }

    /**
     * Take some non-null items (all must be of type G) and return a
     * Geary.Iterable for convenience.
     */
    public Geary.Iterable<G> iterate<G>(G g, ...) {
        va_list args = va_list();
        G arg = g;

        // Use a linked list since we will only ever be iterating over
        // it
        var list = new Gee.LinkedList<G>();
        do {
            list.add(arg);
        } while((arg = args.arg()) != null);

        return Geary.traverse<G>(list);
    }

    /**
     * Take an array of items and return a Geary.Iterable for convenience.
     */
    public Geary.Iterable<G> iterate_array<G>(G[] a, owned Gee.EqualDataFunc<G>? equal_func = null) {
        // Use a linked list since we will only ever be iterating over
        // it
        var list = new Gee.LinkedList<G>((owned) equal_func);
        list.add_all_array(a);
        return Geary.traverse<G>(list);
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
    /**
     * A private class that lets us take a Geary.Iterable and convert it back
     * into a Gee.Iterable.
     */
    private class GeeIterable<G> : Gee.Traversable<G>, Gee.Iterable<G>, BaseObject {
        private Gee.Iterator<G> i;

        public GeeIterable(Gee.Iterator<G> iterator) {
            i = iterator;
        }

        public Gee.Iterator<G> iterator() {
            return i;
        }

        // Unfortunately necessary for Gee.Traversable.
        public virtual bool @foreach(Gee.ForallFunc<G> f) {
            foreach (G g in this) {
                if (!f(g))
                    return false;
            }
            return true;
        }
    }

    private Gee.Iterator<G> i;


    /**
     * Internal only constructor.
     *
     * Applications should use {@link traverse}, {@link iterate} or
     * {@link iterate_array} instead.
     */
    internal Iterable(Gee.Iterator<G> iterator) {
        i = iterator;
    }

    /** Returns the iterable's underlying iterator. */
    public virtual Gee.Iterator<G> iterator() {
        return i;
    }

    /**
     * Applies a function to each iterable element.
     *
     * @see Gee.Traversable.map
     */
    public Iterable<A> map<A>(Gee.MapFunc<A, G> f) {
        return new Iterable<A>(i.map<A>(f));
    }

    /**
     * Applies a function to each element and previous result.
     *
     * @see Gee.Traversable.scan
     */
    public Iterable<A> scan<A>(Gee.FoldFunc<A, G> f, owned A seed) {
        return new Iterable<A>(i.scan<A>(f, seed));
    }

    /**
     * Returns the elements which satisfy the given predicate.
     *
     * @see Gee.Traversable.filter
     */
    public Iterable<G> filter(owned Gee.Predicate<G> f) {
        return new Iterable<G>(i.filter((owned) f));
    }

    /**
     * Truncates the start and optionally end of the iterable.
     *
     * @see Gee.Traversable.chop
     */
    public Iterable<G> chop(int offset, int length = -1) {
        return new Iterable<G>(i.chop(offset, length));
    }

    /**
     * Returns the non-null results of a call to {@link map}.
     *
     * @see Gee.Traversable.chop
     */
    public Iterable<A> map_nonnull<A>(Gee.MapFunc<A, G> f) {
        return new Iterable<A>(i.map<A>(f).filter(g => g != null));
    }

    /**
     * Return only objects of the destination type, as that type.
     *
     * Only works on types derived from Object.
     */
    public Iterable<A> cast_object<A>() {
        return new Iterable<G>(
            // This would be a lot simpler if valac didn't barf on the shorter,
            // more obvious syntax for each of these delegates here.
            i.filter(g => ((Object) g).get_type().is_a(typeof(A)))
            .map<A>(g => { return (A) g; }));
    }

    /** Returns the first element of the iterable. */
    public G? first() {
        return (i.next() ? i.@get() : null);
    }

    /** Returns the first element that satisfies the given predicate. */
    public G? first_matching(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (f(g))
                return g;
        }
        return null;
    }

    /* Returns true if at least one element satisfies the predicate. */
    public bool any(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (f(g))
                return true;
        }
        return false;
    }

    /* Returns true if all elements satisfies the predicate. */
    public bool all(owned Gee.Predicate<G> f) {
        foreach (G g in this) {
            if (!f(g))
                return false;
        }
        return true;
    }

    /* Returns the number of elements satisfying the predicate. */
    public int count_matching(owned Gee.Predicate<G> f) {
        int count = 0;
        foreach (G g in this) {
            if (f(g))
                count++;
        }
        return count;
    }

    /**
     * The resulting Gee.Iterable comes with the same caveat that you may only
     * iterate over it once.
     */
    public Gee.Iterable<G> to_gee_iterable() {
        return new GeeIterable<G>(i);
    }

    /** Adds all elements to the given collection. */
    public Gee.Collection<G> add_all_to(Gee.Collection<G> c) {
        while (i.next())
            c.add(i.@get());
        return c;
    }

    /** Adds all elements to a map, with keys generated by key_func. */
    public Gee.Map<K, G> add_all_to_map<K>(Gee.Map<K, G> c, Gee.MapFunc<K, G> key_func) {
        while (i.next()) {
            G g = i.@get();
            c.@set(key_func(g), g);
        }
        return c;
    }

    /** Returns a new array list containing all elements. */
    public Gee.ArrayList<G> to_array_list(owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.ArrayList<G>) add_all_to(new Gee.ArrayList<G>((owned) equal_func));
    }

    /**
     * Returns a new list containing all elements, sorted.
     *
     * The ordering is applied after adding all elements to the list,
     * so as to minimise computational overhead.
     */
    public Gee.ArrayList<G> to_sorted_list(owned GLib.CompareDataFunc<G> comparator,
                                           owned Gee.EqualDataFunc<G>? equal_func = null) {
        var list = to_array_list((owned) equal_func);
        list.sort((owned) comparator);
        return list;
    }

    /** Returns a new linked list containing all elements. */
    public Gee.LinkedList<G> to_linked_list(owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.LinkedList<G>) add_all_to(new Gee.LinkedList<G>((owned) equal_func));
    }

    /** Returns a new hash set containing all elements. */
    public Gee.HashSet<G> to_hash_set(owned Gee.HashDataFunc<G>? hash_func = null,
        owned Gee.EqualDataFunc<G>? equal_func = null) {
        return (Gee.HashSet<G>) add_all_to(new Gee.HashSet<G>((owned) hash_func, (owned) equal_func));
    }

    /** Returns a new tree set with all elements added to it. */
    public Gee.TreeSet<G> to_tree_set(owned CompareDataFunc<G>? compare_func = null) {
        return (Gee.TreeSet<G>) add_all_to(new Gee.TreeSet<G>((owned) compare_func));
    }

    /** Returns a new hash map, adding elements with keys generated by key_func. */
    public Gee.HashMap<K, G>
        to_hash_map<K>(Gee.MapFunc<K, G> key_func,
                       owned Gee.HashDataFunc<K>? key_hash_func = null,
                       owned Gee.EqualDataFunc<K>? key_equal_func = null,
                       owned Gee.EqualDataFunc<G>? value_equal_func = null) {
            return (Gee.HashMap<K, G>) add_all_to_map<K>(
                new Gee.HashMap<K, G>((owned) key_hash_func,
                                      (owned) key_equal_func,
                                      (owned) value_equal_func),
                key_func
            );
    }
}
