/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListStoreCache {

    private Gee.HashMap<Geary.ContactStore, ContactListStore> cache =
        new Gee.HashMap<Geary.ContactStore, ContactListStore>();

    public ContactListStore create(Geary.ContactStore contact_store) {
        ContactListStore list_store = new ContactListStore(contact_store);

        this.cache.set(contact_store, list_store);

        //list_store.load.begin();

        return list_store;
    }

    public ContactListStore? get(Geary.ContactStore contact_store) {
        return this.cache.get(contact_store);
    }

    public void unset(Geary.ContactStore contact_store) {
        this.cache.unset(contact_store);
    }
}
