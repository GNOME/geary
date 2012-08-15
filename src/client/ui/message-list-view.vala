/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListView : Gtk.TreeView {
    const int LOAD_MORE_HEIGHT = 100;
    
    private bool enable_load_more = true;
    
    // Used to avoid repeated calls to load_more(). Contains the last "upper" bound of the
    // scroll adjustment seen at the call to load_more().
    private double last_upper = -1.0;
    private bool reset_adjustment = false;
    private Gee.Set<Geary.Conversation> selected = new Gee.HashSet<Geary.Conversation>();
    
    public signal void conversations_selected(Gee.Set<Geary.Conversation> selected);
    
    public virtual signal void load_more() {
        enable_load_more = false;
    }
    
    public signal void mark_conversation(Geary.Conversation conversation,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview);
    
    private MessageListStore message_list_store;
    private Geary.ConversationMonitor? conversation_monitor;
    
    public MessageListView(MessageListStore message_list_store) {
        this.message_list_store = message_list_store;
        set_model(message_list_store);
        
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
        
        get_model().row_deleted.connect(on_row_deleted);
        message_list_store.conversations_added_began.connect(on_conversations_added_began);
        message_list_store.conversations_added_finished.connect(on_conversations_added_finished);
        button_press_event.connect(on_button_press);

        // Set up drag and drop.
        Gtk.drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, FolderList.TARGET_ENTRY_LIST,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
    }
    
    public void set_conversation_monitor(Geary.ConversationMonitor? new_conversation_monitor) {
        if (conversation_monitor != null) {
            conversation_monitor.scan_started.disconnect(on_scan_started);
            conversation_monitor.scan_completed.disconnect(on_scan_completed);
            conversation_monitor.conversation_removed.disconnect(on_conversation_removed);
        }
        
        conversation_monitor = new_conversation_monitor;
        
        if (conversation_monitor != null) {
            conversation_monitor.scan_started.connect(on_scan_started);
            conversation_monitor.scan_completed.connect(on_scan_completed);
            conversation_monitor.conversation_removed.connect(on_conversation_removed);
        }
    }
    
    private void on_scan_started() {
        enable_load_more = false;
    }
    
    private void on_scan_completed() {
        enable_load_more = true;
        
        // Select first conversation.
        if (GearyApplication.instance.config.autoselect)
            select_first_conversation();
    }
    
    private void on_conversation_removed(Geary.Conversation conversation) {
        if (!GearyApplication.instance.config.autoselect)
            unselect_all();
    }
    
    private void on_conversations_added_began() {
        Gtk.Adjustment? adjustment = get_adjustment();
        // If we were at the top, we want to stay there after conversations are added.
        reset_adjustment = adjustment != null && adjustment.get_value() == 0;
    }
    
    private void on_conversations_added_finished() {
        if (!reset_adjustment)
            return;
        
        Gtk.Adjustment? adjustment = get_adjustment();
        if (adjustment == null)
            return;
        
        adjustment.set_value(0);
    }
    
    private Gtk.Adjustment? get_adjustment() {
        Gtk.ScrolledWindow? parent = get_parent() as Gtk.ScrolledWindow;
        if (parent == null) {
            debug("Parent was not scrolled window");
            return null;
        }
        
        return parent.get_vadjustment();
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
            
            Geary.Conversation conversation = message_list_store.get_conversation_at_path(path);
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
        ((Gtk.Scrollable) this).get_vadjustment().value_changed.connect(on_value_changed);
    }
    
    private void on_value_changed() {
        if (!enable_load_more)
            return;
        
        // Check if we're at the very bottom of the list. If we are, it's time to
        // issue a load_more signal.
        Gtk.Adjustment adjustment = ((Gtk.Scrollable) this).get_vadjustment();
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
    
    private List<Gtk.TreePath> get_all_selected_paths() {
        Gtk.TreeModel model;
        return get_selection().get_selected_rows(out model);
    }
    
    private Gtk.TreePath? get_selected_path() {
        return get_all_selected_paths().nth_data(0);
    }
    
    // Gtk.TreeSelection can fire its "changed" signal even when nothing's changed, so look for that
    // and prevent to avoid subscribers from doing the same things multiple times
    private void on_selection_changed() {
        List<Gtk.TreePath> paths = get_all_selected_paths();
        if (paths.length() == 0) {
            // only notify if this is different than what was previously reported
            if (selected.size != 0) {
                selected.clear();
                conversations_selected(selected.read_only_view);
            }
            
            return;
        }
        
        // Conversations are selected, so collect them and signal if different
        Gee.HashSet<Geary.Conversation> new_selected = new Gee.HashSet<Geary.Conversation>();
        foreach (Gtk.TreePath path in paths) {
            Geary.Conversation? conversation = message_list_store.get_conversation_at_path(path);
            if (conversation != null)
                new_selected.add(conversation);
        }
        
        // only notify if different than what was previously reported
        if (!Geary.Collection.are_sets_equal<Geary.Conversation>(selected, new_selected)) {
            selected = new_selected;
            conversations_selected(selected.read_only_view);
        }
    }
    
    // Selects the first conversation, if nothing has been selected yet.
    public void select_first_conversation() {
        if (get_selected_path() == null) {
            set_cursor(new Gtk.TreePath.from_indices(0, -1), null, false);
        }
    }

    public void select_conversation(Geary.Conversation conversation) {
        Gtk.TreePath path = message_list_store.get_path_for_conversation(conversation);
        if (path != null)
            set_cursor(path, null, false);
    }

    private void on_row_deleted(Gtk.TreePath path) {
        // if one or more rows are deleted in the model, reset the last upper limit so scrolling to
        // the bottom will always activate a reload (this is particularly important if the model
        // is cleared)
        last_upper = -1.0;
        
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

    private void on_display_preview_changed() {
        style_set(null);
        model.foreach(refresh_path);
    }
    
    private bool refresh_path(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
        model.row_changed(path, iter);
        return false;
    }
}

