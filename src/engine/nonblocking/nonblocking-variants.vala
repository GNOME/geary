/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.NonblockingSemaphore : Geary.NonblockingAbstractSemaphore {
    public NonblockingSemaphore(Cancellable? cancellable = null) {
        base (true, false, cancellable);
    }
}

public class Geary.NonblockingEvent : Geary.NonblockingAbstractSemaphore {
    public NonblockingEvent(Cancellable? cancellable = null) {
        base (true, true, cancellable);
    }
}

public class Geary.NonblockingSpinlock : Geary.NonblockingAbstractSemaphore {
    public NonblockingSpinlock(Cancellable? cancellable = null) {
        base (false, true, cancellable);
    }
}

