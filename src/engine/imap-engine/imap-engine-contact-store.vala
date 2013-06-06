/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
 
internal class Geary.ImapEngine.ContactStore : Geary.ContactStore {
    private weak ImapDB.Account account;
    
    internal ContactStore(ImapDB.Account account) {
        this.account = account;
    }
    
    public override async void mark_contacts_async(Gee.Collection<Contact> contacts, ContactFlags? to_add,
        ContactFlags? to_remove) throws Error{
        foreach (Contact contact in contacts) {
            if (contact.contact_flags == null)
                contact.contact_flags = new Geary.ContactFlags();
            
            if (to_add != null)
                contact.contact_flags.add_all(to_add);
            
            if (to_remove != null)
                contact.contact_flags.remove_all(to_remove);
            
            yield account.update_contact_flags_async(contact, null);
        }
    }
}
