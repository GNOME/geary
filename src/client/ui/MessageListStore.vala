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
    }
    
    // The Email should've been fetched with Geary.Email.Field.ENVELOPE, at least.
    //
    // TODO: Need to insert email's in their proper position, not merely append.
    public void append_envelope(Geary.Email envelope) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter,
            Column.DATE, Date.pretty_print(envelope.date.value),
            Column.FROM, envelope.from[0].get_short_address(),
            Column.SUBJECT, envelope.subject.value,
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
}

