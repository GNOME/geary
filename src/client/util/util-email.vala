/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public int compare_conversation_ascending(Geary.Conversation a, Geary.Conversation b) {
    Geary.Email? a_latest = a.get_latest_email(true);
    Geary.Email? b_latest = b.get_latest_email(true);
    
    if (a_latest == null)
        return (b_latest == null) ? 0 : -1;
    else if (b_latest == null)
        return 1;
    
    // use date-received so newly-arrived messages float to the top, even if they're send date
    // was earlier (think of mailing lists that batch up forwarded mail)
    return a_latest.properties.date_received.compare(b_latest.properties.date_received);
}

public int compare_conversation_descending(Geary.Conversation a, Geary.Conversation b) {
    return compare_conversation_ascending(b, a);
}

public async Geary.Email fetch_full_message_async(Geary.Email email, Geary.Folder folder,
    Geary.Email.Field required_fields, Cancellable? cancellable) throws Error {
    Geary.Email full_email;
    if (email.id.folder_path == null) {
        full_email = yield folder.account.local_fetch_email_async(
            email.id, required_fields, cancellable);
    } else {
        full_email = yield folder.fetch_email_async(email.id,
            required_fields, Geary.Folder.ListFlags.NONE, cancellable);
    }
    
    return full_email;
}
