/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListView : Gtk.TreeView {
    public MessageListView(MessageListStore store) {
        set_model(store);
        
        Gtk.CellRendererText date_renderer = new Gtk.CellRendererText();
        date_renderer.xalign = 1.0f;
        append_column(create_column(MessageListStore.Column.FROM, new Gtk.CellRendererText(),
            "text", 200));
        append_column(create_column(MessageListStore.Column.SUBJECT, new Gtk.CellRendererText(),
            "text", 400));
        append_column(create_column(MessageListStore.Column.DATE, date_renderer, "text", 100));
    }
    
    private static Gtk.TreeViewColumn create_column(MessageListStore.Column column,
        Gtk.CellRenderer renderer, string attr, int width = 0) {
        Gtk.TreeViewColumn view_column = new Gtk.TreeViewColumn.with_attributes(column.to_string(),
            renderer, attr, column);
        view_column.set_resizable(true);
        
        if (width != 0) {
            view_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
            view_column.set_fixed_width(width);
        }
        
        return view_column;
    }
}

