/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// This is coded this way to allow for libindicate and libmessagingmenu to coexist in code (if not
// compiled at same time) and minimize the exposure of differences to the rest of the application.
// Subclasses should trap the "notify::count" signal and use that to perform whatever magic
// they need for their implementation.

public abstract class NewMessagesIndicator : Object {
    public int count { get; private set; default = 0; }
    
    private Gee.HashSet<Geary.EmailIdentifier> new_ids = new Gee.HashSet<Geary.EmailIdentifier>(
        Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    
    public signal void application_activated(uint32 timestamp);
    
    public signal void inbox_activated(uint32 timestamp);
    
    public signal void composer_activated(uint32 timestamp);
    
    protected NewMessagesIndicator() {
    }
    
    public void new_message(Geary.EmailIdentifier email_id) {
        new_ids.add(email_id);
        update_count();
    }
    
    public void not_new_message(Geary.EmailIdentifier email_id) {
        new_ids.remove(email_id);
        update_count();
    }
    
    public void clear_new_messages() {
        new_ids.clear();
        update_count();
    }
    
    private void update_count() {
        // Documentation for "notify" signal seems to suggest that it's possible for the signal to
        // fire even if the value of the property doesn't change.  Since this signal can trigger
        // big events, want to avoid firing it unless necessary
        if (count != new_ids.size)
            count = new_ids.size;
    }
    
    public static NewMessagesIndicator create() {
#if HAVE_LIBINDICATE
        return new Libindicate();
#else
        return new NullIndicator();
#endif
    }
}

