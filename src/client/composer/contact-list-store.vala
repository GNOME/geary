/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListStore : Gtk.ListStore {
    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.ContactImportance CONTACT_VISIBILITY_THRESHOLD = Geary.ContactImportance.TO_TO;
    
    public enum Column {
        CONTACT_OBJECT,
        CONTACT_MARKUP_NAME,
        PRIOR_KEYS;
        
        public static Type[] get_types() {
            return {
                typeof (Geary.Contact), // CONTACT_OBJECT
                typeof (string),        // CONTACT_MARKUP_NAME
                typeof (Gee.HashSet)    // PRIOR_KEYS
            };
        }
    }
    
    public Geary.ContactStore contact_store { get; private set; }
    
    public ContactListStore(Geary.ContactStore contact_store) {
        set_column_types(Column.get_types());
        
        this.contact_store = contact_store;
        
        foreach (Geary.Contact contact in contact_store.contacts)
            add_contact(contact);
        
        // set sort function *after* adding all the contacts
        set_sort_func(Column.CONTACT_OBJECT, sort_func);
        set_sort_column_id(Column.CONTACT_OBJECT, Gtk.SortType.ASCENDING);
        
        contact_store.contact_added.connect(on_contact_added);
        contact_store.contact_updated.connect(on_contact_updated);
    }
    
    ~ContactListStore() {
        contact_store.contact_added.disconnect(on_contact_added);
        contact_store.contact_updated.disconnect(on_contact_updated);
    }
    
    public Geary.Contact get_contact(Gtk.TreeIter iter) {
        GLib.Value contact_value;
        get_value(iter, Column.CONTACT_OBJECT, out contact_value);
        
        return (Geary.Contact) contact_value.get_object();
    }
    
    public string get_full_address(Gtk.TreeIter iter) {
        return get_contact(iter).get_rfc822_address().get_full_address();
    }
    
    // Highlighted result should be Markup.escaped for presentation to the user
    public void set_highlighted_result(Gtk.TreeIter iter, string highlighted_result,
        string current_address_key) {
        // get the previous keys for this row for comparison
        GLib.Value prior_keys_value;
        get_value(iter, Column.PRIOR_KEYS, out prior_keys_value);
        Gee.HashSet<string> prior_keys = (Gee.HashSet<string>) prior_keys_value.get_object();
        
        // Changing a row in the list store causes Gtk.EntryCompletion to re-evaluate
        // completion_match_func for that row. Thus we need to make sure the key has
        // actually changed before settings the highlighting--otherwise we will cause
        // an infinite loop.
        if (!(current_address_key in prior_keys)) {
            prior_keys.add(current_address_key);
            set(iter, Column.CONTACT_MARKUP_NAME, highlighted_result, -1);
        }
    }
    
    private void add_contact(Geary.Contact contact) {
        if (contact.highest_importance < CONTACT_VISIBILITY_THRESHOLD)
            return;
        
        string full_address = contact.get_rfc822_address().get_full_address();
        Gtk.TreeIter iter;
        append(out iter);
        set(iter,
            Column.CONTACT_OBJECT, contact,
            Column.CONTACT_MARKUP_NAME, Markup.escape_text(full_address),
            Column.PRIOR_KEYS, new Gee.HashSet<string>());
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
    
    private void on_contact_added(Geary.Contact contact) {
        add_contact(contact);
    }
    
    private void on_contact_updated(Geary.Contact contact) {
        update_contact(contact);
    }
    
    private int sort_func(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
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
}

