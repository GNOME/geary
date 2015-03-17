/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public int compare_conversation_ascending(Geary.App.Conversation a, Geary.App.Conversation b) {
    Geary.Email? a_latest = a.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    Geary.Email? b_latest = b.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    
    if (a_latest == null)
        return (b_latest == null) ? 0 : -1;
    else if (b_latest == null)
        return 1;
    
    // use date-received so newly-arrived messages float to the top, even if they're send date
    // was earlier (think of mailing lists that batch up forwarded mail)
    return Geary.Email.compare_recv_date_ascending(a_latest, b_latest);
}

public int compare_conversation_descending(Geary.App.Conversation a, Geary.App.Conversation b) {
    return compare_conversation_ascending(b, a);
}

namespace EmailUtil {

public string strip_subject_prefixes(Geary.Email email) {
    string? cleaned = (email.subject != null) ? email.subject.strip_prefixes() : null;
    
    return !Geary.String.is_empty(cleaned) ? cleaned : _("(no subject)");
}

}

