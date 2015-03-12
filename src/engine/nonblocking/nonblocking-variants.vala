/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A Semaphore is a broadcasting, manually-resetting {@link AbstractSemaphore}.
 */

public class Geary.Nonblocking.Semaphore : Geary.Nonblocking.AbstractSemaphore {
    public Semaphore(Cancellable? cancellable = null) {
        base (true, false, cancellable);
    }
}

/**
 * An Event is a broadcasting, auto-resetting {@link AbstractSemaphore}.
 */

public class Geary.Nonblocking.Event : Geary.Nonblocking.AbstractSemaphore {
    public Event(Cancellable? cancellable = null) {
        base (true, true, cancellable);
    }
}

/**
 * A Spinlock is a single-notifying, auto-resetting {@link AbstractSemaphore}.
 */

public class Geary.Nonblocking.Spinlock : Geary.Nonblocking.AbstractSemaphore {
    public Spinlock(Cancellable? cancellable = null) {
        base (false, true, cancellable);
    }
}

