/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListStore : Gtk.ListStore, Geary.BaseInterface {

    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.ContactImportance CONTACT_VISIBILITY_THRESHOLD = Geary.ContactImportance.TO_TO;

    // Batch size for loading contacts asynchronously
    private uint LOAD_BATCH_SIZE = 4096;


    private static int sort_func(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        // Order by importance, then by real name, then by email.
        GLib.Value avalue, bvalue;
        model.get_value(aiter, Column.CONTACT_OBJECT, out avalue);
        model.get_value(biter, Column.CONTACT_OBJECT, out bvalue);
        Geary.Contact? acontact = avalue.get_object() as Geary.Contact;
        Geary.Contact? bcontact = bvalue.get_object() as Geary.Contact;

        // Contacts can be null if the sort func is called between TreeModel.append and
        // TreeModel.set.
        if (acontact == bcontact)
            return 0;
        if (acontact == null && bcontact != null)
            return -1;
        if (acontact != null && bcontact == null)
            return 1;

        // First order by importance.
        if (acontact.highest_importance > bcontact.highest_importance)
            return -1;
        if (acontact.highest_importance < bcontact.highest_importance)
            return 1;

        // Then order by real name.
        string? anormalized_real_name = acontact.real_name == null ? null :
            acontact.real_name.normalize().casefold();
        string? bnormalized_real_name = bcontact.real_name == null ? null :
            bcontact.real_name.normalize().casefold();
        // strcmp correctly marks 'null' as first in lexigraphic order, so we don't need to
        // special-case it.
        int result = strcmp(anormalized_real_name, bnormalized_real_name);
        if (result != 0)
            return result;

        // Finally, order by email.
        return strcmp(acontact.normalized_email, bcontact.normalized_email);
    }


    public enum Column {
        CONTACT_OBJECT,
        PRIOR_KEYS;

        public static Type[] get_types() {
            return {
                typeof (Geary.Contact), // CONTACT_OBJECT
                typeof (Gee.HashSet)    // PRIOR_KEYS
            };
        }
    }

    public Geary.ContactStore contact_store { get; private set; }

    public ContactListStore(Geary.ContactStore contact_store) {
        base_ref();
        set_column_types(Column.get_types());
        this.contact_store = contact_store;
        //contact_store.contacts_added.connect(on_contacts_added);
        //contact_store.contacts_updated.connect(on_contacts_updated);
    }

    ~ContactListStore() {
        base_unref();
        //this.contact_store.contacts_added.disconnect(on_contacts_added);
        //this.contact_store.contacts_updated.disconnect(on_contacts_updated);
    }

    /**
     * Loads contacts from the model's contact store.
     */
    public async void load() {
        // uint count = 0;
        // foreach (Geary.Contact contact in this.contact_store.contacts) {
        //     add_contact(contact);
        //     count++;
        //     if (count % LOAD_BATCH_SIZE == 0) {
        //         Idle.add(load.callback);
        //         yield;
        //     }
        // }
    }

    public void set_sort_function() {
        set_sort_func(Column.CONTACT_OBJECT, ContactListStore.sort_func);
        set_sort_column_id(Column.CONTACT_OBJECT, Gtk.SortType.ASCENDING);
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
        if (contact.highest_importance >= CONTACT_VISIBILITY_THRESHOLD) {
            Gtk.TreeIter iter;
            append(out iter);
            set(iter,
                Column.CONTACT_OBJECT, contact,
                Column.PRIOR_KEYS, new Gee.HashSet<string>());
        }
    }

    private void update_contact(Geary.Contact updated_contact) {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return;

        do {
            if (get_contact(iter) != updated_contact)
                continue;

            Gtk.TreePath? path = get_path(iter);
            if (path != null)
                row_changed(path, iter);

            return;
        } while (iter_next(ref iter));
    }

    private void on_contacts_added(Gee.Collection<Geary.Contact> contacts) {
        foreach (Geary.Contact contact in contacts)
            add_contact(contact);
    }

    private void on_contacts_updated(Gee.Collection<Geary.Contact> contacts) {
        foreach (Geary.Contact contact in contacts)
            update_contact(contact);
    }

}

