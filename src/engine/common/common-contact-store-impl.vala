/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An database-backed implementation of Geary.Contacts
 */
internal class Geary.ContactStoreImpl : BaseObject, Geary.ContactStore {


    // Insert or update a contact in the ContactTable. If contact
    // already exists, flags are merged and the importance is updated
    // to the highest importance seen.
    //
    // Internal and static since it is used by ImapDB.Database during
    // upgrades
    internal static void do_update_contact(Db.Connection cx,
                                           Contact contact,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        Contact? existing = do_fetch_contact(
            cx, contact.email, cancellable
        );

        if (contact == null) {
            // Not found, so just insert it
            Db.Statement stmt = cx.prepare(
                "INSERT INTO ContactTable(normalized_email, email, real_name, flags, highest_importance) "
                + "VALUES(?, ?, ?, ?, ?)");
            stmt.bind_string(0, contact.normalized_email);
            stmt.bind_string(1, contact.email);
            stmt.bind_string(2, contact.real_name);
            stmt.bind_string(3, contact.flags.serialize());
            stmt.bind_int(4, contact.highest_importance);

            stmt.exec(cancellable);
        } else {
            // Update existing contact

            // Merge two flags sets together
            contact.flags.add_all(existing.flags);

            // update remaining fields, careful not to overwrite
            // non-null real_name with null (but using latest
            // real_name if supplied) ... email is not updated (it's
            // how existing was keyed), normalized_email is inserted at
            // the same time as email, leaving only real_name, flags,
            // and highest_importance
            Db.Statement stmt = cx.prepare(
                "UPDATE ContactTable SET real_name=?, flags=?, highest_importance=? WHERE email=?");
            stmt.bind_string(
                0, !String.is_empty(contact.real_name) ? contact.real_name : existing.real_name
            );
            stmt.bind_string(
                1, contact.flags.serialize()
            );
            stmt.bind_int(
                2, int.max(contact.highest_importance, existing.highest_importance)
            );
            stmt.bind_string(
                3, contact.email
            );

            stmt.exec(cancellable);
        }
    }

    // Static since it is indirectly used by ImapDB.Database during
    // upgrades
    private static Contact? do_fetch_contact(Db.Connection cx,
                                             string email,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        Db.Statement stmt = cx.prepare(
            "SELECT real_name, highest_importance, normalized_email, flags FROM ContactTable "
            + "WHERE email=?");
        stmt.bind_string(0, email);

        Db.Result result = stmt.exec(cancellable);

        Contact? contact = null;
        if (!result.finished) {
            contact = new Contact(
                email,
                result.string_at(0),
                result.int_at(1),
                result.string_at(2)
            );
            contact.flags.deserialize(result.string_at(3));
        }
        return contact;
    }


    private Geary.Db.Database backing;


    internal ContactStoreImpl(Geary.Db.Database backing) {
        base_ref();
        this.backing = backing;
    }

    /** Returns the contact matching the given email address, if any */
    public async Contact? get_by_rfc822(Geary.RFC822.MailboxAddress address,
                                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        Contact? contact = null;
        yield this.backing.exec_transaction_async(
            Db.TransactionType.RO,
            (cx, cancellable) => {
                contact = do_fetch_contact(cx, address.mailbox, cancellable);
                return Db.TransactionOutcome.COMMIT;
            },
            cancellable);
        return contact;
    }

    public async void update_contacts(Gee.Collection<Contact> updated,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.backing.exec_transaction_async(
            Db.TransactionType.RW,
            (cx, cancellable) => {
                foreach (Contact contact in updated) {
                    do_update_contact(cx, contact, cancellable);
                }
                return Db.TransactionOutcome.COMMIT;
            },
            cancellable);
    }

}
