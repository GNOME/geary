/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// This is coded this way to allow for libindicate and libmessagingmenu to coexist in code (if not
// compiled at same time) and minimize the exposure of differences to the rest of the application.

public abstract class NewMessagesIndicator : Object {
    protected NewMessagesMonitor monitor;
    
    public signal void application_activated(uint32 timestamp);
    
    public signal void inbox_activated(uint32 timestamp);
    
    public signal void composer_activated(uint32 timestamp);
    
    protected NewMessagesIndicator(NewMessagesMonitor monitor) {
        this.monitor = monitor;
    }
    
    public static NewMessagesIndicator create(NewMessagesMonitor monitor) {
#if HAVE_LIBINDICATE
        return new Libindicate(monitor);
#else
        return new NullIndicator(monitor);
#endif
    }
}

