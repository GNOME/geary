/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationListView : Gtk.TreeView, Geary.BaseInterface {
    const int LOAD_MORE_HEIGHT = 100;

    // Used to be able to refer to the action names of the MainWindow
    private weak MainWindow main_window;

    private bool enable_load_more = true;

    private bool reset_adjustment = false;
    private Geary.App.ConversationMonitor? conversation_monitor;
    private Gee.Set<Geary.App.Conversation>? current_visible_conversations = null;
    private Geary.Scheduler.Scheduled? scheduled_update_visible_conversations = null;
    private Gee.Set<Geary.App.Conversation> selected = new Gee.HashSet<Geary.App.Conversation>();
    private Geary.IdleManager selection_update;
    private bool suppress_selection = false;

    public signal void conversations_selected(Gee.Set<Geary.App.Conversation> selected);

    // Signal for when a conversation has been double-clicked, or selected and enter is pressed.
    public signal void conversation_activated(Geary.App.Conversation activated);

    public virtual signal void load_more() {
        enable_load_more = false;
    }

    public signal void mark_conversations(Gee.Collection<Geary.App.Conversation> conversations,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview);

    public signal void visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible);


    public ConversationListView(MainWindow parent) {
        base_ref();
        set_show_expanders(false);
        set_headers_visible(false);
        this.main_window = parent;

        append_column(create_column(ConversationListStore.Column.CONVERSATION_DATA,
            new ConversationListCellRenderer(), ConversationListStore.Column.CONVERSATION_DATA.to_string(),
            0));

        Gtk.TreeSelection selection = get_selection();
        selection.set_mode(Gtk.SelectionMode.MULTIPLE);
        style_updated.connect(on_style_changed);
        show.connect(on_show);
        row_activated.connect(on_row_activated);

        button_press_event.connect(on_button_press);

        // Set up drag and drop.
        Gtk.drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, FolderList.Tree.TARGET_ENTRY_LIST,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);

        GearyApplication.instance.config.settings.changed[Configuration.DISPLAY_PREVIEW_KEY].connect(
            on_display_preview_changed);
        GearyApplication.instance.controller.notify[GearyController.PROP_CURRENT_CONVERSATION].
            connect(on_conversation_monitor_changed);

        // Watch for mouse events.
        motion_notify_event.connect(on_motion_notify_event);
        leave_notify_event.connect(on_leave_notify_event);

        // GtkTreeView binds Ctrl+N to "move cursor to next".  Not so interested in that, so we'll
        // remove it.
        unowned Gtk.BindingSet? binding_set = Gtk.BindingSet.find("GtkTreeView");
        assert(binding_set != null);
        Gtk.BindingEntry.remove(binding_set, Gdk.Key.N, Gdk.ModifierType.CONTROL_MASK);

        this.selection_update = new Geary.IdleManager(do_selection_changed);
        this.selection_update.priority = Geary.IdleManager.Priority.LOW;
    }

    ~ConversationListView() {
        base_unref();
    }

    public override void destroy() {
        this.selection_update.reset();
        base.destroy();
    }

    public new ConversationListStore? get_model() {
        return (this as Gtk.TreeView).get_model() as ConversationListStore;
    }

    public new void set_model(ConversationListStore? new_store) {
        ConversationListStore? old_store = get_model();
        if (old_store != null) {
            old_store.conversations_added.disconnect(on_conversations_added);
            old_store.conversations_removed.disconnect(on_conversations_removed);
            old_store.row_inserted.disconnect(on_rows_changed);
            old_store.rows_reordered.disconnect(on_rows_changed);
            old_store.row_changed.disconnect(on_rows_changed);
            old_store.row_deleted.disconnect(on_rows_changed);
            old_store.destroy();
        }

        if (new_store != null) {
            new_store.row_inserted.connect(on_rows_changed);
            new_store.rows_reordered.connect(on_rows_changed);
            new_store.row_changed.connect(on_rows_changed);
            new_store.row_deleted.connect(on_rows_changed);
            new_store.conversations_removed.connect(on_conversations_removed);
            new_store.conversations_added.connect(on_conversations_added);
        }

        // Disconnect the selection handler since we don't want to
        // fire selection signals while changing the model.
        Gtk.TreeSelection selection = get_selection();
        selection.changed.disconnect(on_selection_changed);
        (this as Gtk.TreeView).set_model(new_store);
        this.selected.clear();
        selection.changed.connect(on_selection_changed);
    }

    /**
     * Specifies an action is currently changing the view's selection.
     */
    public void set_changing_selection(bool is_changing) {
        // Make sure that when not autoselecting, and if the user is
        // causing selected rows to be removed, the next row is not
        // automatically selected by GtkTreeView
        if (is_changing) {
            this.suppress_selection =
                !GearyApplication.instance.config.autoselect;
        } else {
            // If no longer changing, always re-enable selection
            get_selection().set_mode(Gtk.SelectionMode.MULTIPLE);
        }
    }

    private void check_load_more() {
        // Check if we're at the very bottom of the list. If we are,
        // it's time to issue a load_more signal.
        Gtk.Adjustment adjustment = ((Gtk.Scrollable) this).get_vadjustment();
        double upper = adjustment.get_upper();
        double threshold = upper - adjustment.page_size - LOAD_MORE_HEIGHT;
        if (this.is_visible() &&
            this.conversation_monitor.can_load_more &&
            adjustment.get_value() >= threshold) {
            load_more();
        }

        schedule_visible_conversations_changed();
    }

    private void on_conversation_monitor_changed() {
        if (conversation_monitor != null) {
            conversation_monitor.scan_started.disconnect(on_scan_started);
            conversation_monitor.scan_completed.disconnect(on_scan_completed);
        }

        conversation_monitor = GearyApplication.instance.controller.current_conversations;

        if (conversation_monitor != null) {
            conversation_monitor.scan_started.connect(on_scan_started);
            conversation_monitor.scan_completed.connect(on_scan_completed);
        }
    }

    private void on_scan_started() {
        this.enable_load_more = false;
    }

    private void on_scan_completed() {
        this.enable_load_more = true;
        check_load_more();

        // Select the first conversation, if autoselect is enabled,
        // nothing has been selected yet and we're not composing.
        if (GearyApplication.instance.config.autoselect &&
            get_selection().count_selected_rows() == 0 &&
            !GearyApplication.instance.controller.any_inline_composers()) {
            set_cursor(new Gtk.TreePath.from_indices(0, -1), null, false);
        }
    }

    private void on_conversations_added(bool start) {
        Gtk.Adjustment? adjustment = get_adjustment();
        if (start) {
            // If we were at the top, we want to stay there after
            // conversations are added.
            this.reset_adjustment = adjustment != null && adjustment.get_value() == 0;
        } else if (this.reset_adjustment && adjustment != null) {
            // Pump the loop to make sure the new conversations are
            // taking up space in the window.  Without this, setting
            // the adjustment here is a no-op because as far as it's
            // concerned, it's already at the top.
            while (Gtk.events_pending())
                Gtk.main_iteration();

            adjustment.set_value(0);
        }
        this.reset_adjustment = false;
    }

    private void on_conversations_removed(bool start) {
        if (!GearyApplication.instance.config.autoselect) {
            Gtk.SelectionMode mode = start
                // Stop GtkTreeView from automatically selecting the
                // next row after the removed rows
                ? Gtk.SelectionMode.NONE
                // Allow the user to make selections again
                : Gtk.SelectionMode.MULTIPLE;
            get_selection().set_mode(mode);
        }
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

        // Handle clicks to toggle read and starred status.
        if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0 &&
            (event.state & Gdk.ModifierType.CONTROL_MASK) == 0 &&
            event.type == Gdk.EventType.BUTTON_PRESS) {

            // Click positions depend on whether the preview is enabled.
            bool read_clicked = false;
            bool star_clicked = false;
            if (GearyApplication.instance.config.display_preview) {
                read_clicked = cell_x < 25 && cell_y >= 14 && cell_y <= 30;
                star_clicked = cell_x < 25 && cell_y >= 40 && cell_y <= 62;
            } else {
                read_clicked = cell_x < 25 && cell_y >= 8 && cell_y <= 22;
                star_clicked = cell_x < 25 && cell_y >= 28 && cell_y <= 43;
            }

            // Get the current conversation.  If it's selected, we'll apply the mark operation to
            // all selected conversations; otherwise, it just applies to this one.
            Geary.App.Conversation conversation = get_model().get_conversation_at_path(path);
            Gee.Collection<Geary.App.Conversation> to_mark;
            if (GearyApplication.instance.controller.get_selected_conversations().contains(conversation))
                to_mark = GearyApplication.instance.controller.get_selected_conversations();
            else
                to_mark = Geary.iterate<Geary.App.Conversation>(conversation).to_array_list();

            if (read_clicked) {
                // Read/unread.
                Geary.EmailFlags flags = new Geary.EmailFlags();
                flags.add(Geary.EmailFlags.UNREAD);

                if (conversation.is_unread())
                    mark_conversations(to_mark, null, flags, false);
                else
                    mark_conversations(to_mark, flags, null, true);

                return true;
            } else if (star_clicked) {
                // Starred/unstarred.
                Geary.EmailFlags flags = new Geary.EmailFlags();
                flags.add(Geary.EmailFlags.FLAGGED);

                if (conversation.is_flagged())
                    mark_conversations(to_mark, null, flags, false);
                else
                    mark_conversations(to_mark, flags, null, true);

                return true;
            }
        }

        if (!get_selection().path_is_selected(path) &&
            !GearyApplication.instance.controller.can_switch_conversation_view())
            return true;

        if (event.button == 3 && event.type == Gdk.EventType.BUTTON_PRESS) {
            Geary.App.Conversation conversation = get_model().get_conversation_at_path(path);

            Menu context_menu_model = new Menu();
            context_menu_model.append(_("Delete conversation"), "win."+GearyController.ACTION_DELETE_CONVERSATION);

            if (conversation.is_unread())
                context_menu_model.append(_("Mark as _Read"), "win."+GearyController.ACTION_MARK_AS_READ);

            if (conversation.has_any_read_message())
                context_menu_model.append(_("Mark as _Unread"), "win."+GearyController.ACTION_MARK_AS_UNREAD);

            if (conversation.is_flagged())
                context_menu_model.append(_("U_nstar"), "win."+GearyController.ACTION_MARK_AS_UNSTARRED);
            else
                context_menu_model.append(_("_Star"), "win."+GearyController.ACTION_MARK_AS_STARRED);

            Menu actions_section = new Menu();
            actions_section.append(_("_Reply"), "win."+GearyController.ACTION_REPLY_TO_MESSAGE);
            actions_section.append(_("R_eply All"), "win."+GearyController.ACTION_REPLY_ALL_MESSAGE);
            actions_section.append(_("_Forward"), "win."+GearyController.ACTION_FORWARD_MESSAGE);
            context_menu_model.append_section(null, actions_section);

            Gtk.Menu context_menu = new Gtk.Menu.from_model(context_menu_model);
            context_menu.insert_action_group("win", this.main_window);
            context_menu.popup_at_pointer(event);

            // When the conversation under the mouse is selected, stop event propagation
            return get_selection().path_is_selected(path);
        }

        return false;
    }

    private void on_style_changed() {
        // Recalculate dimensions of child cells.
        ConversationListCellRenderer.style_changed(this);

        schedule_visible_conversations_changed();
    }

    private void on_show() {
        // Wait until we're visible to set this signal up.
        ((Gtk.Scrollable) this).get_vadjustment().value_changed.connect(on_value_changed);
    }

    private void on_value_changed() {
        if (this.enable_load_more) {
            check_load_more();
        }
    }

    private static Gtk.TreeViewColumn create_column(ConversationListStore.Column column,
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

    private void on_selection_changed() {
        // Schedule processing selection changes at low idle for
        // two reasons: (a) if a lot of changes come in
        // back-to-back, this allows for all that activity to
        // settle before updating state and firing signals (which
        // results in a lot of I/O), and (b) it means the
        // ConversationMonitor's signals may be processed in any
        // order by this class and the ConversationListView and
        // not result in a lot of screen flashing and (again)
        // unnecessary I/O as both classes update selection state.
        this.selection_update.schedule();
    }

    // Gtk.TreeSelection can fire its "changed" signal even when
    // nothing's changed, so look for that to avoid subscribers from
    // doing the same things (in particular, I/O) multiple times
    private void do_selection_changed() {
        Gee.HashSet<Geary.App.Conversation> new_selection =
            new Gee.HashSet<Geary.App.Conversation>();
        List<Gtk.TreePath> paths = get_all_selected_paths();
        if (paths.length() != 0) {
            // Conversations are selected, so collect them and
            // signal if different
            foreach (Gtk.TreePath path in paths) {
                Geary.App.Conversation? conversation =
                get_model().get_conversation_at_path(path);
                if (conversation != null)
                    new_selection.add(conversation);
            }
        }

        // only notify if different than what was previously reported
        if (!Geary.Collection.are_sets_equal<Geary.App.Conversation>(
                this.selected, new_selection)) {
            this.selected = new_selection;
            conversations_selected(this.selected.read_only_view);
        }
    }

    public Gee.Set<Geary.App.Conversation> get_visible_conversations() {
        Gee.HashSet<Geary.App.Conversation> visible_conversations = new Gee.HashSet<Geary.App.Conversation>();

        Gtk.TreePath start_path;
        Gtk.TreePath end_path;
        if (!get_visible_range(out start_path, out end_path))
            return visible_conversations;

        while (start_path.compare(end_path) <= 0) {
            Geary.App.Conversation? conversation = get_model().get_conversation_at_path(start_path);
            if (conversation != null)
                visible_conversations.add(conversation);

            start_path.next();
        }

        return visible_conversations;
    }

    public Gee.Set<Geary.App.Conversation> get_selected_conversations() {
        Gee.HashSet<Geary.App.Conversation> selected_conversations = new Gee.HashSet<Geary.App.Conversation>();

        foreach (Gtk.TreePath path in get_all_selected_paths()) {
            Geary.App.Conversation? conversation = get_model().get_conversation_at_path(path);
            if (path != null)
                selected_conversations.add(conversation);
        }

        return selected_conversations;
    }

    // Always returns false, so it can be used as a one-time SourceFunc
    private bool update_visible_conversations() {
        Gee.Set<Geary.App.Conversation> visible_conversations = get_visible_conversations();
        if (current_visible_conversations != null
            && Geary.Collection.are_sets_equal<Geary.App.Conversation>(
            current_visible_conversations, visible_conversations)) {
            return false;
        }

        current_visible_conversations = visible_conversations;

        visible_conversations_changed(current_visible_conversations.read_only_view);

        return false;
    }

    private void schedule_visible_conversations_changed() {
        scheduled_update_visible_conversations = Geary.Scheduler.on_idle(update_visible_conversations);
    }

    public void select_conversation(Geary.App.Conversation conversation) {
        Gtk.TreePath path = get_model().get_path_for_conversation(conversation);
        if (path != null)
            set_cursor(path, null, false);
    }

    public void select_conversations(Gee.Set<Geary.App.Conversation> conversations) {
        Gtk.TreeSelection selection = get_selection();
        foreach (Geary.App.Conversation conversation in conversations) {
            Gtk.TreePath path = get_model().get_path_for_conversation(conversation);
            if (path != null)
                selection.select_path(path);
        }
    }

    private void on_rows_changed() {
        schedule_visible_conversations_changed();
    }

    private void on_display_preview_changed() {
        style_updated();
        model.foreach(refresh_path);

        schedule_visible_conversations_changed();
    }

    private bool refresh_path(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
        model.row_changed(path, iter);
        return false;
    }

    private void on_row_activated(Gtk.TreePath path) {
        Geary.App.Conversation? c = get_model().get_conversation_at_path(path);
        if (c != null)
            conversation_activated(c);
    }

    // Enable/disable hover effect on all selected cells.
    private void set_hover_selected(bool hover) {
        ConversationListCellRenderer.set_hover_selected(hover);
        queue_draw();
    }

    private bool on_motion_notify_event(Gdk.EventMotion event) {
        if (get_selection().count_selected_rows() > 0) {
            Gtk.TreePath? path = null;
            int cell_x, cell_y;
            get_path_at_pos((int) event.x, (int) event.y, out path, null, out cell_x, out cell_y);

            set_hover_selected(path != null && get_selection().path_is_selected(path));
        }
        return Gdk.EVENT_PROPAGATE;
    }

    private bool on_leave_notify_event() {
        if (get_selection().count_selected_rows() > 0) {
            set_hover_selected(false);
        }
        return Gdk.EVENT_PROPAGATE;

    }
}
