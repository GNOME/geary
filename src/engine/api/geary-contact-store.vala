/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.ContactStore : BaseObject {
    public Gee.Collection<Contact> contacts {
        owned get { return contact_map.values; }
    }

    private Gee.Map<string, Contact> contact_map;

    public signal void contacts_added(Gee.Collection<Contact> contacts);

    public signal void contacts_updated(Gee.Collection<Contact> contacts);

    protected ContactStore() {
        contact_map = new Gee.HashMap<string, Contact>();
    }

    public void update_contacts(Gee.Collection<Contact> new_contacts) {
        Gee.LinkedList<Contact> added = new Gee.LinkedList<Contact>();
        Gee.LinkedList<Contact> updated = new Gee.LinkedList<Contact>();

        foreach (Contact contact in new_contacts) {
            Contact? old_contact = contact_map[contact.normalized_email];
            if (old_contact == null) {
                contact_map[contact.normalized_email] = contact;
                added.add(contact);
            } else if (old_contact.highest_importance < contact.highest_importance) {
                old_contact.highest_importance = contact.highest_importance;
                updated.add(contact);
            }
        }

        if (!added.is_empty)
            contacts_added(added);

        if (!updated.is_empty)
            contacts_updated(updated);
    }

    public abstract async void mark_contacts_async(Gee.Collection<Contact> contacts, ContactFlags? to_add,
        ContactFlags? to_remove) throws Error;

    public Contact? get_by_rfc822(Geary.RFC822.MailboxAddress address) {
        return contact_map[address.address.normalize().casefold()];
    }
}
