/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public int compare_email(Geary.Email aenvelope, Geary.Email benvelope) {
    int diff = aenvelope.date.value.compare(benvelope.date.value);
    
    // stabilize sort by using the mail's ordering, which is always unique in a folder
    return (diff != 0) ? diff : aenvelope.id.compare(benvelope.id);
}

public int compare_email_id_desc(Geary.Email aenvelope, Geary.Email benvelope) {
    return (int) (aenvelope.id.ordering - benvelope.id.ordering);
}

public int compare_conversation(Geary.Conversation a, Geary.Conversation b) {
    Gee.SortedSet<Geary.Email> apool = a.get_email_sorted(compare_email);
    Gee.SortedSet<Geary.Email> bpool = b.get_email_sorted(compare_email);
    
    if (apool.last() == null)
        return -1;
    else if (bpool.last() == null)
        return 1;
    
    return compare_email(apool.last(), bpool.last());
}

public int compare_conversation_desc(Geary.Conversation a, Geary.Conversation b) {
    return -compare_conversation(a, b);
}
