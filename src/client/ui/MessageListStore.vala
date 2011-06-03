/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListStore : Gtk.TreeStore {
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
                typeof (Geary.EmailHeader)  // MESSAGE_OBJECT
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
    }
    
    public void append_header(Geary.EmailHeader header) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter,
            Column.DATE, Date.pretty_print(header.sent.value),
            Column.FROM, header.from.get_at(0).get_short_address(),
            Column.SUBJECT, header.subject.value,
            Column.MESSAGE_OBJECT, header
        );
    }
    
    public Geary.EmailHeader? get_message_at(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.EmailHeader header;
        get(iter, Column.MESSAGE_OBJECT, out header);
        
        return header;
    }
}

