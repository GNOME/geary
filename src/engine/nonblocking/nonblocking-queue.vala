/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An asynchronous queue, first-in first-out (FIFO) or priority.
 *
 * This class can be used to asynchronously wait for items to be added
 * to the queue, the asynchronous call blocking until an item is
 * ready. Multiple asynchronous tasks can queue objects via {@link
 * send}, and tasks can wait for items via {@link receive}. If there
 * are multiple tasks waiting for items, the first to wait will
 * receive the next item.
 */
public class Geary.Nonblocking.Queue<G> : BaseObject {

    /** Returns the number of items currently in the queue. */
    public int size { get { return queue.size; } }

    /** Determines if any items are in the queue. */
    public bool is_empty { get { return queue.is_empty; } }

    /**
     * Determines if duplicate items can be added to the queue.
     *
     * If a priory queue, this applies to items of the same priority,
     * otherwise uses the item's natural identity.
     */
    public bool allow_duplicates { get; set; default = true; }

    /**
     * Determines if duplicate items will be added to the queue.
     *
     * If {@link allow_duplicates} is `true` and an item is already in
     * the queue, this determines if it will be added again.
     */
    public bool requeue_duplicate { get; set; default = false; }

    /**
     * Determines if the queue is currently running.
     */
    public bool is_paused {
        get { return _is_paused; }

        set {
            // if no longer paused, wake up any waiting recipients
            if (_is_paused && !value)
                spinlock.blind_notify();

            _is_paused = value;
        }
    }
    private bool _is_paused = false;

    private Gee.Queue<G> queue;
    private Nonblocking.Spinlock spinlock = new Nonblocking.Spinlock();


    /**
     * Constructs a new first-in first-out (FIFO) queue.
     *
     * If `equalator` is not null it will be used to determine the
     * identity of objects in the queue, else the items' natural
     * identity will be used.
     */
    public Queue.fifo(owned Gee.EqualDataFunc<G>? equalator = null) {
        this(new Gee.LinkedList<G>((owned) equalator));
    }

    /**
     * Constructs a new priority queue.
     *
     * If `comparator` is not null it will be used to determine the
     * ordering of objects in the queue, else the items' natural
     * ordering will be used.
     */
    public Queue.priority(owned CompareDataFunc<G>? comparator = null) {
        this(new Gee.PriorityQueue<G>((owned) comparator));
    }

    /**
     * Constructs a new queue.
     */
    protected Queue(Gee.Queue<G> queue) {
        this.queue = queue;
    }

    /**
     * Adds an item to the queue.
     *
     * If the queue is a priority queue, it is added according to its
     * relative priority, else it is added to the end.
     *
     * Returns `true` if the item was added to the queue.
     */
    public bool send(G msg) {
        if (!allow_duplicates && queue.contains(msg)) {
            if (requeue_duplicate)
                queue.remove(msg);
            else
                return false;
        }

        if (!queue.offer(msg))
            return false;

        if (!is_paused)
            spinlock.blind_notify();

        return true;
    }

    /**
     * Removes and returns the next queued item, blocking until available.
     *
     * If the queue is paused, this will continue to wait until
     * unpaused and an item is ready. If `cancellable` is non-null,
     * when used will cancel this call.
     */
    public async G receive(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0 && !is_paused)
                return queue.poll();

            yield spinlock.wait_async(cancellable);
        }
    }

    /**
     * Returns the next queued item without removal, blocking until available.
     *
     * If the queue is paused, this will continue to wait until
     * unpaused and an item is ready. If `cancellable` is non-null,
     * when used will cancel this call.
     */
    public async G peek(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0 && !is_paused)
                return queue.peek();

            yield spinlock.wait_async(cancellable);
        }
    }

    /**
     * Removes all items in queue, returning the number of removed items.
     */
    public int clear() {
        int count = queue.size;
        if (count != 0)
            queue.clear();

        return count;
    }

    /**
     * Removes an item from the queue, returning `true` if removed.
     */
    public bool revoke(G msg) {
        return queue.remove(msg);
    }

    /**
     * Remove items matching the given predicate, returning those removed.
     */
    public Gee.Collection<G> revoke_matching(owned Gee.Predicate<G> predicate) {
        Gee.ArrayList<G> removed = new Gee.ArrayList<G>();
        // Iterate over a copy so we can modify the original.
        foreach (G msg in queue.to_array()) {
            if (predicate(msg)) {
                queue.remove(msg);
                removed.add(msg);
            }
        }

        return removed;
    }

    /**
     * Returns a read-only version of the queue queue.
     *
     * Since the queue could potentially alter when the main loop
     * runs, it's important to only examine the queue when not
     * allowing other operations to process.
     */
    public Gee.Collection<G> get_all() {
        return queue.read_only_view;
    }
}
