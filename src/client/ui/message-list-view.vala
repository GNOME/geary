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
    
    public signal void conversations_selected(Geary.Conversation[] conversations);
    public signal void load_more();
    public signal void mark_conversation(Geary.Conversation conversation,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview);
    
    public MessageListView(MessageListStore store) {
        set_model(store);
        
        set_show_expanders(false);
        set_headers_visible(false);
        enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
        
        append_column(create_column(MessageListStore.Column.MESSAGE_DATA, new MessageListCellRenderer(),
            MessageListStore.Column.MESSAGE_DATA.to_string(), 0));
        
        Gtk.TreeSelection selection = get_selection();
        selection.changed.connect(on_selection_changed);
        selection.set_mode(Gtk.SelectionMode.MULTIPLE);
        style_set.connect(on_style_changed);
        show.connect(on_show);
        
        store.row_deleted.connect(on_row_deleted);
        button_press_event.connect(on_button_press);
    }

    private bool on_button_press(Gdk.EventButton event) {
        // Get the coordinates on the cell as well as the clicked path.
        int cell_x;
        int cell_y;
        Gtk.TreePath? path;
        get_path_at_pos((int) event.x, (int) event.y, out path, null, out cell_x, out cell_y);
        
        // If the user clicked in an empty area, do nothing.
        if (path == null)
            return false;
        
        // If this is an unmodified click in the top-left of the cell, it is a star-click.
        if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0 &&
            (event.state & Gdk.ModifierType.CONTROL_MASK) == 0 &&
            event.type == Gdk.EventType.BUTTON_PRESS && cell_x < 25 && cell_y < 25) {
            
            Geary.Conversation conversation = get_store().get_conversation_at(path);
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.FLAGGED);
            if (conversation.is_flagged()) {
                mark_conversation(conversation, null, flags, false);
            } else {
                mark_conversation(conversation, flags, null, true);
            }
            return true;
        }
        return false;
    }

    private void on_style_changed() {
        // Recalculate dimensions of child cells.
        MessageListCellRenderer.style_changed(this);
    }
    
    private void on_show() {
        // Wait until we're visible to set this signal up.
        this.get_vadjustment().value_changed.connect(on_value_changed);
    }
    
    private void on_value_changed() {
        if (!enable_load_more)
            return;
        
        // Check if we're at the very bottom of the list. If we are, it's time to
        // issue a load_more signal.
        Gtk.Adjustment adjustment = this.get_vadjustment();
        double upper = adjustment.get_upper();
        if (adjustment.get_value() >= upper - adjustment.page_size - LOAD_MORE_HEIGHT &&
            upper > last_upper) {
            load_more();
            last_upper = upper;
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
    
    private List<Gtk.TreePath> get_all_selected_paths() {
        Gtk.TreeModel model;
        return get_selection().get_selected_rows(out model);
    }
    
    private Gtk.TreePath? get_selected_path() {
        return get_all_selected_paths().nth_data(0);
    }

    private void on_selection_changed() {
        // Get the selected paths. If no paths are selected then notify of that immediately.
        List<Gtk.TreePath> paths = get_all_selected_paths();
        Geary.Conversation[] conversations = new Geary.Conversation[0];
        if (paths.length() == 0) {
            conversations_selected(conversations);
            return;
        }

        // Conversations are selected, so lets collect all of their conversations and signal.
        foreach (Gtk.TreePath path in paths) {
            Geary.Conversation? conversation = get_store().get_conversation_at(path);
            if (conversation != null) {
                conversations += conversation;
            }
        }
        if (conversations.length != 0) {
            conversations_selected(conversations);
        }
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

    public void refresh() {
        model.foreach(refresh_path);
    }
    
    private bool refresh_path(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
        model.row_changed(path, iter);
        return false;
    }
}

