/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Do-nothing NewMessagesIndicator, used on non-Ubuntu compiles.

public class NullIndicator : NewMessagesIndicator {
    public NullIndicator(NewMessagesMonitor monitor) {
        base (monitor);
        
        debug("No messaging menu support in this build");
    }
}

