/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if REF_TRACKING
private class Counts {
    public int created = 0;
    public int destroyed = 0;
}

private static GLib.Mutex reflock;
private static Gee.HashMap<unowned string,Counts?> refmap;
#endif

/**
 * Common parent class for Geary Engine objects.
 *
 * Most Engine classes should be derived from this class to be able to
 * access common functionality.
 *
 * Currently, this class enables automatic application-based reference
 * tracking of objects, which can assist in tracking down memory
 * leaks. To enable this, set the //ref_track// compile time option to
 * true and compile. An application can then call {@link dump_refs} to
 * output a list of objects with both instantiation and destruction
 * counts.
 *
 * This class can only be used for classes that would otherwise derive
 * directly from GLib.Object. If a class must be derived from some
 * other pre-existing class, it is possible to use {@link
 * BaseInterface} as a mixin with a little extra work instead.
 */
public abstract class Geary.BaseObject : Geary.BaseInterface, Object {

#if REF_TRACKING
    static construct {
        reflock = GLib.Mutex();
        refmap = new Gee.HashMap<unowned string,Counts?>(
            // because strings are unowned and guaranteed to be
            // unique by GType, use direct comparison functions,
            // more efficient then string hash/equal
            Gee.Functions.get_hash_func_for(typeof(void*)),
            Gee.Functions.get_equal_func_for(typeof(void*))
        );
    }
#endif

    /**
     * Constructs a new base object.
     *
     * This constructor automatically increments the reference count
     * by calling {@link BaseInterface.base_ref} if reference tracking
     * is enabled at compile-time, otherwise this is a no-op.
     */
    construct {
#if REF_TRACKING
        base_ref();
#endif
    }

    /**
     * Destructs an existing base object.
     *
     * This constructor automatically decrements the reference count
     * by calling {@link BaseInterface.base_unref} if reference
     * tracking is enabled at compile-time, otherwise this is a no-op.
     */
    ~BaseObject() {
#if REF_TRACKING
        base_unref();
#endif
    }

    /**
     * Dumps reference counting logs to the given stream.
     *
     * This method prints a list of reference-counted classes, and the
     * number of times each was constructed and destructed along with
     * a flag indicating those that are not equal. If reference
     * tracking was not enabled at compile-time, this is no-op.
     */
    public static void dump_refs(FileStream outs) {
#if REF_TRACKING
        if (!refmap.is_empty) {
            Gee.ArrayList<unowned string> list = new Gee.ArrayList<unowned string>();
            list.add_all(refmap.keys);
            list.sort();
            outs.printf("?   created/destroyed class\n");
            foreach (unowned string classname in list) {
                Counts? counts = refmap.get(classname);
                string alert = " ";
                if (counts.created != counts.destroyed) {
                    double leak_rate = (counts.created - counts.destroyed) / counts.created;
                    alert = (leak_rate > 0.1) ? "!" : "*";
                }
                outs.printf(
                    "%s %9d/%9d %s\n",
                    alert,
                    counts.created,
                    counts.destroyed,
                    classname
                );
            }
        } else {
            outs.printf("No references to report.\n");
        }
#endif
    }

}

/**
 * Base mixin interface for Engine objects derived from another.
 *
 * This interface provides an analogue to {@link BaseObject} for
 * objects that must be derived from an existing class, such a GTK
 * widget. Since this is simply a mixin, some additional work is
 * required to use this interface compared to BaseObject.
 *
 * To use this interface, declare it as a parent of your class and
 * call {@link base_ref} immediately after the base constructor is
 * called, and call {@link base_unref} at the end of the destructor:
 *
 *     public class CustomWidget : Gtk.Widget, Geary.BaseInterface {
 *
 *         public CustomWidget() {
 *              base_ref();
 *              ...
 *         }
 *
 *         ~CustomWidget() {
 *              ...
 *              base_unref();
 *         }
 *
 *     }
 *
 * Care must be taken to ensure that if {@link base_unref} is not
 * called for an instance if {@link base_ref} was not called.
 */
public interface Geary.BaseInterface {

    /**
     * Increments the reference count for the implementing class.
     *
     * Implementing classes should call this as soon as possible after
     * the base class's constructor is called. This method is a no-op
     * if reference tracking is not enabled at compile-time.
     */
    protected void base_ref() {
#if REF_TRACKING
        reflock.lock();
        unowned string classname = get_classname();
        Counts? counts = refmap.get(classname);
        if (counts == null) {
            counts = new Counts();
            refmap.set(classname, counts);
        }
        counts.created++;
        reflock.unlock();
#endif
    }

    /**
     * Decrements the reference count for the implementing class.
     *
     * Implementing classes should call this at the end of the class's
     * destructor. This method is a no-op if reference tracking is not
     * enabled at compile-time.
     */
    protected void base_unref() {
#if REF_TRACKING
        reflock.lock();
        refmap.get(get_classname()).destroyed++;
        reflock.unlock();
#endif
    }

#if REF_TRACKING
    private unowned string get_classname() {
        return ((Object) this).get_type().name();
    }

#endif
}
