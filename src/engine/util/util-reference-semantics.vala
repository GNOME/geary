/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * ReferenceSemantics solves a problem due to a limitation of GObject and the current
 * implementation of Vala.
 *
 * What would be handy in GObject is a signal or callback to let an observer know when all the
 * references to an Object have been released and is about to be destroyed.  It does have this
 * feature (via WeakPointers), but Vala does not implement the weak keyword in this way currently
 * and does not (today) have semantics to be notified when the weak reference has turned to null.
 *
 * Additionally, there are situations where an Object may be held in some primary table inside an
 * object and references to it are handed out to one or more callers.  The primary class would like
 * to know when all those references have been dropped although (of course) Object has not been
 * destroyed (even with a proper weak ref) because it's held in a table.  Even if a
 * WeakReferenceTable is somehow implemented and used, there are situations where it's necessary to
 * be able to use the destroying object and clean up (close connections, change contexts, close
 * files, etc.)
 *
 * ReferenceSemantics manually implements such a scheme.  The Object (held in a table or with a
 * simple ref) implements the ReferenceSemantics interface.  (Note that the only required field to
 * implement is manual_ref_count.)  The objects that are distributed to callers are subclasses
 * of SmartReference.  When all the SmartReferences are destroyed, the ReferenceSemantics
 * "freed" signal will fire.  Any final references to the underlying Object can be dropped and/or
 * clean up can then occur.
 *
 * If the ReferenceSemantics object needs all the SmartReferences to drop their reference to it,
 * fire the "release-now" signal.  Although the SmartReferences will still be active in the system,
 * they will fire their own "reference-broken" signal.  Subclasses or observers should trap or
 * override this signal and move the object to a closed or broken state, or merely drop their own
 * reference to the SmartReference.
 */
public interface Geary.ReferenceSemantics : BaseObject {
    protected abstract int manual_ref_count { get; protected set; }

    /**
     * A ReferenceSemantics object can fire this signal for force all SmartReferences to drop their
     * reference to it.
     */
    public signal void release_now();

    /**
     * This signal is fired when all SmartReferences to the ReferenceSemantics object have dropped
     * their reference.
     */
    public signal void freed();

    internal void claim() {
        manual_ref_count++;
    }

    internal void release() {
        assert(manual_ref_count > 0);

        if (--manual_ref_count == 0)
            freed();
    }

    public bool is_freed() {
        return (manual_ref_count == 0);
    }
}

/**
 * A SmartReference holds a reference to a ReferenceSemantics object.  See that class for more
 * information on the operation of these two classes.
 */
public abstract class Geary.SmartReference : BaseObject {
    private ReferenceSemantics? reffed;

    /**
     * This signal is fired when the SmartReference drops its reference to a ReferenceSemantics
     * object due to it firing "release-now".
     *
     * This signal is *not* fired when SmartReference drops its reference in its destructor.
     */
    public virtual signal void reference_broken() {
    }

    protected SmartReference(ReferenceSemantics reffed) {
        this.reffed = reffed;

        reffed.release_now.connect(on_release_now);

        reffed.claim();
    }

    ~SmartReference() {
        if (reffed != null)
            reffed.release();
    }

    public ReferenceSemantics? get_reference() {
        return reffed;
    }

    private void on_release_now() {
        reffed.release();
        reffed = null;

        reference_broken();
    }
}

