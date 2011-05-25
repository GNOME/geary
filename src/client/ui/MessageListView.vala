/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListView : Gtk.TreeView {
    public MessageListView(MessageListStore store) {
        set_model(store);
        
        append_column(create_text_column(MessageListStore.Column.DATE, _("Date")));
        append_column(create_text_column(MessageListStore.Column.FROM, _("From")));
        append_column(create_text_column(MessageListStore.Column.SUBJECT, _("Subject")));
    }
    
    private Gtk.TreeViewColumn create_text_column(int column, string name, int width = 0,
        Gtk.CellRendererText? renderer = null) {
        Gtk.TreeViewColumn view_column = new Gtk.TreeViewColumn.with_attributes(name,
            (renderer != null) ? renderer : new Gtk.CellRendererText(), "text", column);
        view_column.set_resizable(true);
        
        if (width != 0) {
            view_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
            view_column.set_fixed_width(width);
        }
        
        return view_column;
    }
}

