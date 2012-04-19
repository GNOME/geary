/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public int compare_email_date_ascending(Geary.Email aenvelope, Geary.Email benvelope) {
    int diff = aenvelope.date.value.compare(benvelope.date.value);
    
    // stabilize sort by using the mail's ordering, which is always unique in a folder
    return (diff != 0) ? diff : aenvelope.id.compare(benvelope.id);
}

public int compare_conversation_ascending(Geary.Conversation a, Geary.Conversation b) {
    Gee.SortedSet<Geary.Email> apool = a.get_email(Geary.Conversation.Ordering.DATE_ASCENDING);
    Gee.SortedSet<Geary.Email> bpool = b.get_email(Geary.Conversation.Ordering.DATE_ASCENDING);
    
    if (apool.last() == null)
        return (bpool.last() != null) ? -1 : 0;
    else if (bpool.last() == null)
        return 1;
    
    return compare_email_date_ascending(apool.last(), bpool.last());
}

public int compare_conversation_descending(Geary.Conversation a, Geary.Conversation b) {
    return compare_conversation_ascending(b, a);
}

