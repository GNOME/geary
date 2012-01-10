/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListView : Gtk.TreeView {
    const int LOAD_MORE_HEIGHT = 100;
    
    public bool enable_load_more { get; set; default = true; }
    
    // Used to avoid repeated calls to load_more(). Contains the last "upper" bound of the
    // scroll adjustment seen at the call to load_more().
    private double last_upper = -1.0;
    
    public signal void conversation_selected(Geary.Conversation? conversation);
    public signal void load_more();
    
    public MessageListView(MessageListStore store) {
        set_model(store);
        
        set_show_expanders(false);
        set_headers_visible(false);
        enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
        
        append_column(create_column(MessageListStore.Column.MESSAGE_DATA, new MessageListCellRenderer(),
            MessageListStore.Column.MESSAGE_DATA.to_string(), 0));
        
        get_selection().changed.connect(on_selection_changed);
        style_set.connect(on_style_changed);
        show.connect(on_show);
        
        store.row_deleted.connect(on_row_deleted);
    }
    
    private void on_style_changed() {
        // Recalculate dimensions of child cells.
        MessageListCellRenderer.style_changed(this);
    }
    
    private void on_show() {
        // Wait until we're visible to set this signal up.
        get_vadjustment().value_changed.connect(on_value_changed);
    }
    
    private void on_value_changed() {
        if (!enable_load_more)
            return;
        
        // Check if we're at the very bottom of the list. If we are, it's time to
        // issue a load_more signal.
        if (get_vadjustment().get_value() >= get_vadjustment().get_upper() - 
            get_vadjustment().page_size - LOAD_MORE_HEIGHT && get_vadjustment().get_upper() 
            > last_upper) {
            load_more();
            last_upper = get_vadjustment().get_upper();
        }
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
    
    private Gtk.TreePath? get_selected_path() {
        Gtk.TreeModel model;
        return get_selection().get_selected_rows(out model).nth_data(0);
    }
    
    private void on_selection_changed() {
        Gtk.TreePath? path = get_selected_path();
        if (path == null) {
            conversation_selected(null);
            
            return;
        }
        
        Geary.Conversation? conversation = get_store().get_conversation_at(path);
        if (conversation != null)
            conversation_selected(conversation);
    }
    
    // Selects the first conversation, if nothing has been selected yet.
    public void select_first_conversation() {
        if (get_selected_path() == null) {
            set_cursor(new Gtk.TreePath.from_indices(0, -1), null, false);
        }
    }
    
    private void on_row_deleted(Gtk.TreePath path) {
        if (GearyApplication.instance.config.autoselect) {
            // Move to next conversation.
            set_cursor(path, null, false);
            
            // If the current path is no longer valid, try the previous message.
            if (get_selected_path() == null) {
                path.prev();
                set_cursor(path, null, false);
            }
        }
    }
}

