/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
 
public class Geary.ContactStore : BaseObject {
    public Gee.Collection<Contact> contacts {
        owned get { return contact_map.values; }
    }
    
    private Gee.Map<string, Contact> contact_map;
    
    public signal void contact_added(Contact contact);
    
    public signal void contact_updated(Contact contact);
    
    internal ContactStore() {
        contact_map = new Gee.HashMap<string, Contact>();
    }
    
    public void update_contacts(Gee.Collection<Contact> new_contacts) {
        foreach (Contact contact in new_contacts)
            update_contact(contact);
    }
    
    private void update_contact(Contact contact) {
        Contact? old_contact = contact_map[contact.normalized_email];
        if (old_contact == null) {
            contact_map[contact.normalized_email] = contact;
            contact_added(contact);
        } else if (old_contact.highest_importance < contact.highest_importance) {
            old_contact.highest_importance = contact.highest_importance;
            contact_updated(old_contact);
        }
    }
}
