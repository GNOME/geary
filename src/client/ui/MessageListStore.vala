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
    }
    
    public MessageListStore() {
        set_column_types({
            typeof (string),        // DATE
            typeof (string),        // FROM
            typeof (string)         // SUBJECT
        });
    }
    
    public void append_message(Geary.Message msg) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        set(iter, Column.DATE, msg.sent.value, Column.FROM, msg.from.get_at(0).get_full_address(),
            Column.SUBJECT, msg.subject.value);
    }
}

