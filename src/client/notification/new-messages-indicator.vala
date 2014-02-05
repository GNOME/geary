/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// This is coded this way to allow for multiple indicators to coexist in code (if not
// compiled at same time) and minimize the exposure of differences to the rest of the application.

public abstract class NewMessagesIndicator : Geary.BaseObject {
    protected NewMessagesMonitor monitor;
    
    public signal void application_activated(uint32 timestamp);
    
    public signal void inbox_activated(Geary.Folder folder, uint32 timestamp);
    
    public signal void composer_activated(uint32 timestamp);
    
    protected NewMessagesIndicator(NewMessagesMonitor monitor) {
        this.monitor = monitor;
    }
    
    public static NewMessagesIndicator create(NewMessagesMonitor monitor) {
        NewMessagesIndicator? indicator = null;
        
        // Indicators are ordered from most to least prefered.  If more than one is available,
        // use the first.
        
#if HAVE_LIBMESSAGINGMENU
        if (indicator == null)
            indicator = new Libmessagingmenu(monitor);
#endif
        
        if (indicator == null)
            indicator = new NullIndicator(monitor);
        
        assert(indicator != null);
        
        return indicator;
    }
    
    // Returns time as a uint32 (suitable for signals if event doesn't supply it)
    protected uint32 now() {
        return (uint32) TimeVal().tv_sec;
    }
}

