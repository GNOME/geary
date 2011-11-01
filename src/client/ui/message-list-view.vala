/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListView : Gtk.TreeView {
    public signal void conversation_selected(Geary.Conversation? conversation);
    
    public MessageListView(MessageListStore store) {
        set_model(store);
        
        set_show_expanders(false);
        set_headers_visible(false);
        enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
        
        append_column(create_column(MessageListStore.Column.MESSAGE_DATA, new MessageListCellRenderer(),
            MessageListStore.Column.MESSAGE_DATA.to_string(), 0));
        
        get_selection().changed.connect(on_selection_changed);
        this.style_set.connect(on_style_changed);
    }
    
    private void on_style_changed() {
        // Recalculate dimensions of child cells.
        MessageListCellRenderer.style_changed(this);
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
    
    public MessageListStore get_store() {
        return (MessageListStore) get_model();
    }
    
    private void on_selection_changed() {
        Gtk.TreeModel model;
        Gtk.TreePath? path = get_selection().get_selected_rows(out model).nth_data(0);
        if (path == null) {
            conversation_selected(null);
            
            return;
        }
        
        Geary.Conversation? conversation = get_store().get_conversation_at(path);
        if (conversation != null)
            conversation_selected(conversation);
    }
}

