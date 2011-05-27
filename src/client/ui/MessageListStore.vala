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
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                DATE,
                FROM,
                SUBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (string),        // DATE
                typeof (string),        // FROM
                typeof (string)         // SUBJECT
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
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public MessageListStore() {
        set_column_types(Column.get_types());
    }
    
    public void append_message(Geary.Message msg) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter, Column.DATE, Date.pretty_print(msg.sent.value), Column.FROM, 
            msg.from.get_at(0).get_short_address(), Column.SUBJECT, msg.subject.value);
    }
}

