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
internal class Geary.ContactStoreImpl : ContactStore, BaseObject {


    private Geary.Db.Database backing;


    internal ContactStoreImpl(Geary.Db.Database backing) {
        this.backing = backing;
    }

    public async Contact? get_by_rfc822(Geary.RFC822.MailboxAddress mailbox,
                                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        Contact? contact = null;
        yield this.backing.exec_transaction_async(
            Db.TransactionType.RO,
            (cx, cancellable) => {
                contact = do_fetch_contact(cx, mailbox.address, cancellable);
                return Db.TransactionOutcome.COMMIT;
            },
            cancellable);
        return contact;
    }

    public async Gee.Collection<Contact> search(string query,
                                                uint min_importance,
                                                uint limit,
                                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        Gee.Collection<Contact>? contacts = null;
        yield this.backing.exec_transaction_async(
            Db.TransactionType.RO,
            (cx, cancellable) => {
                contacts = do_search_contacts(
                    cx, query, min_importance, limit, cancellable
                );
                return Db.TransactionOutcome.COMMIT;
            },
            cancellable);
        return contacts;
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

    private Contact? do_fetch_contact(Db.Connection cx,
                                      string email,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        string normalised_query = email.make_valid();
        Db.Statement stmt = cx.prepare(
            "SELECT real_name, highest_importance, normalized_email, flags FROM ContactTable "
            + "WHERE email=?");
        stmt.bind_string(0, normalised_query);

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

    private Gee.Collection<Contact>
        do_search_contacts(Db.Connection cx,
                           string query,
                           uint min_importance,
                           uint limit,
                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        Gee.Collection<Contact> contacts = new Gee.LinkedList<Contact>();
        string normalised_query = Geary.Db.normalise_case_insensitive_query(query);
        if (!String.is_empty(normalised_query)) {
            normalised_query = normalised_query + "%";
            Db.Statement stmt = cx.prepare("""
                SELECT * FROM ContactTable
                WHERE highest_importance >= ? AND (
                    UTF8FOLD(real_name) LIKE ? OR
                    UTF8FOLD(email) LIKE ?
                )
                ORDER BY highest_importance DESC,
                         real_name IS NULL,
                         real_name COLLATE UTF8COLL,
                         email COLLATE UTF8COLL
                LIMIT ?
            """);
            stmt.bind_uint(0, min_importance);
            stmt.bind_string(1, normalised_query);
            stmt.bind_string(2, normalised_query);
            stmt.bind_uint(3, limit);

            Db.Result result = stmt.exec(cancellable);

            while (!result.finished) {
                Contact contact = new Contact(
                    result.string_for("email"),
                    result.string_for("real_name"),
                    result.int_for("highest_importance"),
                    result.string_for("normalized_email")
                );
                contact.flags.deserialize(result.string_for("flags"));
                contacts.add(contact);

                result.next(cancellable);
            }
        }
        return contacts;
    }

    private void do_update_contact(Db.Connection cx,
                                   Contact updated,
                                   GLib.Cancellable? cancellable)
        throws GLib.Error {
        Db.Statement stmt = cx.prepare("""
            INSERT INTO ContactTable(
                normalized_email, email, real_name, flags, highest_importance
            ) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(email) DO UPDATE SET
              real_name = excluded.real_name,
              flags = excluded.flags,
              highest_importance = excluded.highest_importance
        """);
        stmt.bind_string(
            0, updated.normalized_email
        );
        stmt.bind_string(
            1, updated.email.make_valid()
        );
        stmt.bind_string(
            2, updated.real_name != null ? updated.real_name.make_valid() : null
        );
        stmt.bind_string(
            3, updated.flags.serialize()
        );
        stmt.bind_int(
            4, updated.highest_importance
        );

        stmt.exec(cancellable);
    }

}
