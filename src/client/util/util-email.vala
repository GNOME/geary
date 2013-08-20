/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public int compare_conversation_ascending(Geary.App.Conversation a, Geary.App.Conversation b) {
    Geary.Email? a_latest = a.get_latest_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    Geary.Email? b_latest = b.get_latest_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    
    if (a_latest == null)
        return (b_latest == null) ? 0 : -1;
    else if (b_latest == null)
        return 1;
    
    // use date-received so newly-arrived messages float to the top, even if they're send date
    // was earlier (think of mailing lists that batch up forwarded mail)
    return a_latest.properties.date_received.compare(b_latest.properties.date_received);
}

public int compare_conversation_descending(Geary.App.Conversation a, Geary.App.Conversation b) {
    return compare_conversation_ascending(b, a);
}

