/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A stack-like widget for displaying Components.InfoBar widgets.
 *
 * The stack ensures only one info bar is shown at once, shows a frame
 * around the info bar, and manages revealing and hiding itself and
 * the info bars as needed.
 */
public class Components.InfoBarStack : Gtk.Frame, Geary.BaseInterface {


    /**
     * GLib.Object data key for priority queue value.
     *
     * @see StackType.PRIORITY_QUEUE
     * @see priority_queue_comparator
     */
    public const string PRIORITY_QUEUE_KEY =
        "Components.InfoBarStack.PRIORITY_QUEUE_KEY";


    /** Supported stack algorithms. */
    public enum StackType {
        /** Always shows the most recently added info bar. */
        SINGLE,

        /**
         * Shows the highest priority infobar.
         *
         * @see priority_queue_comparator
         */
        PRIORITY_QUEUE;

    }


    private class SingletonQueue : Gee.AbstractQueue<Components.InfoBar> {

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

        private Components.InfoBar? element = null;


        public override bool add(Components.InfoBar to_add) {
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

        public override bool contains(Components.InfoBar other) {
            return (this.element == other);
        }

        public override Gee.Iterator<Components.InfoBar> iterator() {
            // This sucks but it won't ever be used so oh well
            return (
                this.element == null
                ? Gee.Collection.empty<Components.InfoBar>().iterator()
                : Geary.Collection.single(this.element).iterator()
            );
        }

        public override bool remove(Components.InfoBar to_remove) {
            var removed = false;
            if (this.element == to_remove) {
                this.element = null;
                removed = true;
            }
            return removed;
        }

        public override Components.InfoBar peek() {
            return this.element;
        }

        public override Components.InfoBar poll() {
            var element = this.element;
            this.element = null;
            return element;
        }

    }


    /**
     * Comparator used for the priority queue algorithm.
     *
     * When {@link algorithm} is set to {@link
     * StackType.PRIORITY_QUEUE}, this comparator is used for the
     * priority queue to compare info bars. It uses an integer value
     * stored via GLib.Object.set_data with {@link PRIORITY_QUEUE_KEY}
     * as a key to determine the relative priority between two info
     * bars.
     *
     * @see algorithm
     * @see StackType.PRIORITY_QUEUE
     */
    public static int priority_queue_comparator(Components.InfoBar a, Components.InfoBar b) {
        return (
            b.get_data<int>(PRIORITY_QUEUE_KEY) -
            a.get_data<int>(PRIORITY_QUEUE_KEY)
        );
    }


    /** The algorithm used when showing info bars. */
    public StackType algorithm {
        get { return this._algorithm; }
        construct set {
            this._algorithm = value;
            update_queue_type();
        }
    }
    private StackType _algorithm = SINGLE;

    /** Determines if an info bar is currently being shown. */
    public bool has_current {
        get { return (this.current_info_bar != null); }
    }

    /** Returns the currently displayed info bar, if any. */
    public Components.InfoBar? current_info_bar {
        get { return get_child() as Components.InfoBar; }
    }

    private Gee.Queue<Components.InfoBar> available;


    construct {
        get_style_context().add_class("geary-info-bar-stack");
        update_queue_type();
    }

    public InfoBarStack(StackType algorithm) {
        Object(algorithm: algorithm);
    }

    /**
     * Adds an info bar to the stack.
     *
     * If this is the first info bar added, the stack will show itself
     * and reveal the info bar. Otherwise, depending on the type of
     * stack constructed, the info bar may or may not be revealed
     * immediately.
     */
    public new void add(Components.InfoBar to_add) {
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
    public new void remove(Components.InfoBar to_remove) {
        if (this.available.remove(to_remove)) {
            update();
        }
    }

    /**
     * Removes all info bars from the stack, hiding the stack.
     */
    public new void remove_all() {
        if (!this.available.is_empty) {
            this.available.clear();
            update();
        }
    }

    private void update() {
        var current = this.current_info_bar;
        var next = this.available.peek();
        if (current == null && next != null) {
            // Not currently showing an info bar but have one to show,
            // so show it
            this.visible = true;
            base.add(next);
            next.revealed = true;
        } else if (current != null && next != current) {
            // Currently showing an info bar but should be showing
            // something else, so start hiding it
            current.notify["revealed"].connect(on_revealed);
            current.revealed = false;
        } else if (current == null && next == null) {
            // Not currently showing anything and there's nothing to
            // show, so hide the frame
            this.visible = false;
        }
    }

    private void update_queue_type() {
        switch (this._algorithm) {
        case SINGLE:
            this.available = new SingletonQueue();
            break;
        case PRIORITY_QUEUE:
            this.available = new Gee.PriorityQueue<Components.InfoBar>(
                InfoBarStack.priority_queue_comparator
            );
            break;
        }
        update();
    }

    private void on_revealed(GLib.Object target, GLib.ParamSpec param) {
        var info_bar = target as Components.InfoBar;
        target.notify["revealed"].disconnect(on_revealed);
        base.remove(info_bar);
        remove(info_bar);
    }

}
