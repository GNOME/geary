/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListStore : Gtk.TreeStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.PROPERTIES;
    
    public enum Column {
        DATE,
        FROM,
        SUBJECT,
        MESSAGE_OBJECT,
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                DATE,
                FROM,
                SUBJECT,
                MESSAGE_OBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (string),            // DATE
                typeof (string),            // FROM
                typeof (string),            // SUBJECT
                typeof (Geary.Email)        // MESSAGE_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case DATE:
                    return _("Date");
                
                case FROM:
                    return _("From");
                
                case SUBJECT:
                    return _("Subject");
                
                case MESSAGE_OBJECT:
                    return "(hidden)";
                
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
        
        string? pre = null;;
        string? post = null;
        if (envelope.properties != null) {
            pre = envelope.properties.is_unread() ? "<b>" : null;
            post = envelope.properties.is_unread() ? "</b>" : null;
        }
        
        string date = to_markup(Date.pretty_print(envelope.date.value), pre, post);
        string from = to_markup(envelope.from[0].get_short_address(), pre, post);
        string subject = to_markup(envelope.subject.value, pre, post);
        
        set(iter,
            Column.DATE, date,
            Column.FROM, from,
            Column.SUBJECT, subject,
            Column.MESSAGE_OBJECT, envelope
        );
    }
    
    public Geary.Email? get_message_at(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.Email email;
        get(iter, Column.MESSAGE_OBJECT, out email);
        
        return email;
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
    
    private static string to_markup(string str, string? pre = null, string? post = null) {
        return "%s%s%s".printf(
            (pre != null) ? pre : "",
            Markup.escape_text(str),
            (post != null) ? post : ""
        );
    }
}

