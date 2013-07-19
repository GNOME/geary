/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public int compare_conversation_ascending(Geary.Conversation a, Geary.Conversation b) {
    Gee.List<Geary.Email> apool = a.get_emails(Geary.Conversation.Ordering.DATE_ASCENDING);
    Gee.List<Geary.Email> bpool = b.get_emails(Geary.Conversation.Ordering.DATE_ASCENDING);
    
    if (apool.size == 0)
        return (bpool.size > 0) ? -1 : 0;
    else if (bpool.size == 0)
        return 1;
    
    return Geary.Email.compare_date_ascending(apool.last(), bpool.last());
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
