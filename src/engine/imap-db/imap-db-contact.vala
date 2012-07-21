/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.ImapDB {

private static void do_update_contact_importance(Db.Connection connection, Contact contact,
    Cancellable? cancellable = null) throws Error {
    // TODO: Don't overwrite a non-null real_name with a null real_name.
    Db.Statement statement = connection.prepare(
        "INSERT OR REPLACE INTO ContactTable(normalized_email, email, real_name, highest_importance)
        VALUES(?, ?, ?, MAX(COALESCE((SELECT highest_importance FROM ContactTable
        WHERE email=?1), -1), ?))");
    statement.bind_string(0, contact.normalized_email);
    statement.bind_string(1, contact.email);
    statement.bind_string(2, contact.real_name);
    statement.bind_int(3, contact.highest_importance);
    
    statement.exec(cancellable);
}

}

