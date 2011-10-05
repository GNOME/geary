/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListStore : Gtk.TreeStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.PROPERTIES;
    
    public enum Column {
        MESSAGE_DATA,
        MESSAGE_OBJECT,
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                MESSAGE_DATA,
                MESSAGE_OBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (FormattedMessageData), // MESSAGE_DATA
                typeof (Geary.Email)           // MESSAGE_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case MESSAGE_DATA:
                    return "data";
                case MESSAGE_OBJECT:
                    return "envelope";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public MessageListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(TreeSortable.DEFAULT_SORT_COLUMN_ID, Gtk.SortType.DESCENDING);
    }
    
    // The Email should've been fetched with REQUIRED_FIELDS.
    public void append_envelope(Geary.Email envelope) {
        assert(envelope.fields.fulfills(REQUIRED_FIELDS));
        
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter,
            Column.MESSAGE_DATA, new FormattedMessageData.from_email(envelope),
            Column.MESSAGE_OBJECT, envelope
        );
        
        envelope.location.position_deleted.connect(on_email_position_deleted);
    }
    
    // The Email should've been fetched with REQUIRED_FIELDS.
    public bool has_envelope(Geary.Email envelope) {
        assert(envelope.fields.fulfills(REQUIRED_FIELDS));
        
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Email? email = get_message_at_index(ctr);
            if (email == null)
                break;
            
            if (email.location.position == envelope.location.position)
                return true;
        }
        
        return false;
    }
    
    public Geary.Email? get_message_at_index(int index) {
        return get_message_at(new Gtk.TreePath.from_indices(index, -1));
    }
    
    public void set_preview_at_index(int index, Geary.Email email) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, new Gtk.TreePath.from_indices(index, -1))) {
            warning("Unable to get tree path from position: %d".printf(index));
            
            return;
        }
        
        set(iter, Column.MESSAGE_DATA, new FormattedMessageData.from_email(email));
    }
    
    public int get_count() {
        return iter_n_children(null);
    }
    
    public Geary.Email? get_message_at(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.Email email;
        get(iter, Column.MESSAGE_OBJECT, out email);
        
        return email;
    }
    
    // Returns -1 if the list is empty.
    public int get_highest_folder_position() {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return -1;
        
        int high = int.MIN;
        
        // TODO: It would be more efficient to maintain highest and lowest values in a table or
        // as items are added and removed; this will do for now.
        do {
            Geary.Email email;
            get(iter, Column.MESSAGE_OBJECT, out email);
            
            if (email.location.position > high)
                high = email.location.position;
        } while (iter_next(ref iter));
        
        return high;
    }
    
    private bool remove_at_position(int position) {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return false;
        
        do {
            Geary.Email email;
            get(iter, Column.MESSAGE_OBJECT, out email);
            
            if (email.location.position == position) {
                remove(iter);
                
                email.location.position_deleted.disconnect(on_email_position_deleted);
                
                return true;
            }
        } while (iter_next(ref iter));
        
        return false;
    }
    
    private int sort_by_date(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        Geary.Email aenvelope;
        get(aiter, Column.MESSAGE_OBJECT, out aenvelope);
        
        Geary.Email benvelope;
        get(biter, Column.MESSAGE_OBJECT, out benvelope);
        
        int diff = aenvelope.date.value.compare(benvelope.date.value);
        if (diff != 0)
            return diff;
        
        // stabilize sort by using the mail's position, which is always unique in a folder
        return aenvelope.location.position - benvelope.location.position;
    }
    
    private void on_email_position_deleted(int position) {
        if (!remove_at_position(position))
            debug("on_email_position_deleted: unable to find email at position %d", position);
    }
}

