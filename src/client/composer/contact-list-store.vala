/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListStore : Gtk.ListStore, Geary.BaseInterface {

    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.Contact.Importance VISIBILITY_THRESHOLD =
        Geary.Contact.Importance.RECEIVED_FROM;

    public enum Column {
        CONTACT_OBJECT;

        public static Type[] get_types() {
            return {
                typeof (Geary.Contact) // CONTACT_OBJECT
            };
        }
    }

    public Geary.ContactStore contact_store { get; private set; }

    public ContactListStore(Geary.ContactStore contact_store) {
        base_ref();
        set_column_types(Column.get_types());
        this.contact_store = contact_store;
    }

    ~ContactListStore() {
        base_unref();
    }

    public async void search(string query, GLib.Cancellable? cancellable) {
        try {
            Gee.Collection<Geary.Contact> results = yield this.contact_store.search(
                query,
                VISIBILITY_THRESHOLD,
                20,
                cancellable
            );

            clear();
            foreach (Geary.Contact contact in results) {
                add_contact(contact);
            }
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            debug("Error searching contacts for completion: %s", err.message);
        }
    }

    public Geary.Contact get_contact(Gtk.TreeIter iter) {
        GLib.Value contact_value;
        get_value(iter, Column.CONTACT_OBJECT, out contact_value);

        return (Geary.Contact) contact_value.get_object();
    }

    public string to_full_address(Gtk.TreeIter iter) {
        return get_contact(iter).get_rfc822_address().to_full_display();
    }

    private inline void add_contact(Geary.Contact contact) {
        Gtk.TreeIter iter;
        append(out iter);
        set(iter, Column.CONTACT_OBJECT, contact);
    }

}
