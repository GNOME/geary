/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A stack-like widget for displaying Gtk InfoBar widgets.
 *
 * The stack ensures only one info bar is shown at once, shows a frame
 * around the info bar, and manages revealing and hiding itself and
 * the info bars as needed.
 */
public class Components.InfoBarStack : Gtk.Frame, Geary.BaseInterface {


    private class SingletonQueue : Gee.AbstractQueue<Gtk.InfoBar> {

        public override bool read_only {
            get { return false; }
        }

        public override int size {
            get { return (this.element == null) ? 0 : 1; }
        }

        public override int capacity {
            get { return 1; }
        }

        public override bool is_full {
            get { return (this.element != null); }
        }

        public override int remaining_capacity {
            get { return (this.element != null) ? 0 : 1; }
        }

        private Gtk.InfoBar? element = null;


        public override bool add(Gtk.InfoBar to_add) {
            var added = false;
            if (this.element != to_add) {
                this.element = to_add;
                added = true;
            }
            return added;
        }

        public override void clear() {
            this.element = null;
        }

        public override bool contains(Gtk.InfoBar other) {
            return (this.element == other);
        }

        public override Gee.Iterator<Gtk.InfoBar> iterator() {
            // This sucks but it won't ever be used so oh well
            return (
                this.element == null
                ? Gee.Collection.empty<Gtk.InfoBar>().iterator()
                : Geary.Collection.single(this.element).iterator()
            );
        }

        public override bool remove(Gtk.InfoBar to_remove) {
            var removed = false;
            if (this.element == to_remove) {
                this.element = null;
                removed = true;
            }
            return removed;
        }

        public override Gtk.InfoBar peek() {
            return this.element;
        }

        public override Gtk.InfoBar poll() {
            var element = this.element;
            this.element = null;
            return element;
        }

    }


    /** Determines if an info bar is currently being shown. */
    public bool has_current {
        get { return (this.current_info_bar != null); }
    }

    /** Returns the currently displayed info bar, if any. */
    public Gtk.InfoBar? current_info_bar {
        get { return get_child() as Gtk.InfoBar; }
    }

    private Gee.Queue<Gtk.InfoBar> available = new SingletonQueue();


    construct {
        get_style_context().add_class("geary-info-bar-stack");
    }

    /**
     * Adds an info bar to the stack.
     *
     * If this is the first info bar added, the stack will show itself
     * and reveal the info bar. Otherwise, depending on the type of
     * stack constructed, the info bar may or may not be revealed
     * immediately.
     */
    public new void add(Gtk.InfoBar to_add) {
        if (this.available.offer(to_add)) {
            update();
        }
    }

    /**
     * Removes an info bar to the stack.
     *
     * If the info bar is currently visible, it will be hidden and
     * replaced with the next info bar added. If the only info bar
     * present is removed, the stack also hides itself.
     */
    public new void remove(Gtk.InfoBar to_remove) {
        if (this.available.remove(to_remove)) {
            update();
        }
    }

    /**
     * Removes all info bars from the stack, hiding the stack.
     */
    public new void remove_all() {
        this.available.clear();
        update();
    }

    private void update() {
        var current = this.current_info_bar;
        var next = this.available.peek();
        if (current == null && next != null) {
            // Not currently showing an info bar but have one to show,
            // so show it
            this.visible = true;
            base.add(next);
            this.size_allocate.connect(on_allocation_changed);
            next.revealed = true;
            next.notify["revealed"].connect(on_revealed);
        } else if (current != null && next != current) {
            // Currently showing an info bar but should be showing
            // something else, so start hiding it
            current.notify["revealed"].disconnect(on_revealed);
            current.revealed = false;
        } else if (current == null && next == null) {
            // Not currently showing anything and there's nothing to
            // show, so hide the frame
            this.visible = false;
        }
    }

    private void on_allocation_changed() {
        var current = this.current_info_bar;
        if (current != null) {
            Gtk.Allocation alloc;
            get_allocation(out alloc);
            if (alloc.height < 2) {
                this.size_allocate.disconnect(on_allocation_changed);
                base.remove(current);
                update();
            }
        }
    }

    private void on_revealed(GLib.Object target, GLib.ParamSpec param) {
        var current = this.current_info_bar;
        if (current == target && !current.revealed) {
            remove(current);
        }
    }

}
