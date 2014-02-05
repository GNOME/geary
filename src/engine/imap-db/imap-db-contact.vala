/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ImapDB {

private Contact? do_fetch_contact(Db.Connection cx, string email, Cancellable? cancellable)
    throws Error {
    Db.Statement stmt = cx.prepare(
        "SELECT real_name, highest_importance, normalized_email, flags FROM ContactTable "
        + "WHERE email=?");
    stmt.bind_string(0, email);
    
    Db.Result result = stmt.exec(cancellable);
    if (result.finished)
        return null;
    
    return new Contact(email, result.string_at(0), result.int_at(1), result.string_at(2),
        ContactFlags.deserialize(result.string_at(3)));
}

// Insert or update a contact in the ContactTable.  If contact already exists, flags are merged
// and the importance is updated to the highest importance seen.
private void do_update_contact(Db.Connection connection, Contact contact,
    Cancellable? cancellable) throws Error {
    Contact? existing_contact = do_fetch_contact(connection, contact.email, cancellable);
    
    // If not found, insert and done
    if (existing_contact == null) {
        Db.Statement stmt = connection.prepare(
            "INSERT INTO ContactTable(normalized_email, email, real_name, flags, highest_importance) "
            + "VALUES(?, ?, ?, ?, ?)");
        stmt.bind_string(0, contact.normalized_email);
        stmt.bind_string(1, contact.email);
        stmt.bind_string(2, contact.real_name);
        stmt.bind_string(3, (contact.contact_flags != null) ? contact.contact_flags.serialize() : null);
        stmt.bind_int(4, contact.highest_importance);
        
        stmt.exec(cancellable);
        
        return;
    }
    
    // merge two flags sets together
    ContactFlags? merged_flags = contact.contact_flags;
    if (existing_contact.contact_flags != null) {
        if (merged_flags != null)
            merged_flags.add_all(existing_contact.contact_flags);
        else
            merged_flags = existing_contact.contact_flags;
    }
    
    // update remaining fields, careful not to overwrite non-null real_name with null (but
    // using latest real_name if supplied) ... email is not updated (it's how existing_contact was
    // keyed), normalized_email is inserted at the same time as email, leaving only real_name,
    // flags, and highest_importance
    Db.Statement stmt = connection.prepare(
        "UPDATE ContactTable SET real_name=?, flags=?, highest_importance=? WHERE email=?");
    stmt.bind_string(0, !String.is_empty(contact.real_name) ? contact.real_name : existing_contact.real_name);
    stmt.bind_string(1, (merged_flags != null) ? merged_flags.serialize() : null);
    stmt.bind_int(2, int.max(contact.highest_importance, existing_contact.highest_importance));
    stmt.bind_string(3, contact.email);
    
    stmt.exec(cancellable);
}

}

