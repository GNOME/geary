/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Nonblocking.Semaphore : Geary.Nonblocking.AbstractSemaphore {
    public Semaphore(Cancellable? cancellable = null) {
        base (true, false, cancellable);
    }
}

public class Geary.Nonblocking.Event : Geary.Nonblocking.AbstractSemaphore {
    public Event(Cancellable? cancellable = null) {
        base (true, true, cancellable);
    }
}

public class Geary.Nonblocking.Spinlock : Geary.Nonblocking.AbstractSemaphore {
    public Spinlock(Cancellable? cancellable = null) {
        base (false, true, cancellable);
    }
}

