/*
 * Copyright © 2022 John Renner <john@jrenner.net>
 * Copyright © 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Represents in folder conversations list.
 *
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-list-view.ui")]
public class ConversationList.View : Adw.Bin, Geary.BaseInterface {

    /**
     * The fields that must be available on any ConversationMonitor
     * passed to ConversationList.View
     */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.FLAGS |
        Geary.Email.Field.PROPERTIES
    );

    [CCode(notify = false)]
    public bool selection_mode_enabled {
        get {
            return this.list.get_selection_mode() == Gtk.SelectionMode.MULTIPLE;
        }
        set {
            Gtk.SelectionMode mode = value ? Gtk.SelectionMode.MULTIPLE : Gtk.SelectionMode.SINGLE;
            if (this.list.get_selection_mode() != mode) {
                this.list.set_selection_mode(mode);
                notify_property("selection-mode-enabled");
            }
        }
    }

    public Gee.Set<Geary.App.Conversation> selected {
        get; set; default = new Gee.HashSet<Geary.App.Conversation>();
    }

    private Application.Configuration config;

    private Gtk.GestureLongPress long_press_gesture;
    private Gdk.ModifierType last_modifier_type;

    [GtkChild] public unowned Gtk.ScrolledWindow scrolled_window;

    [GtkChild] private unowned Gtk.ListBox list;

    /*
     * Use to restore selected row when exiting selection/edition
     */
    private Gtk.ListBoxRow? to_restore_row = null;

    public View(Application.Configuration config) {
        this.config = config;

        this.notify["selection-mode-enabled"].connect(on_selection_mode_changed);

        this.list.selected_rows_changed.connect(on_selected_rows_changed);
        this.list.row_activated.connect(on_row_activated);

        this.list.set_header_func(header_func);

        this.scrolled_window.vadjustment.value_changed.connect(maybe_load_more);
        this.scrolled_window.vadjustment.value_changed.connect(update_visible_conversations);

        this.long_press_gesture = new Gtk.GestureLongPress();
        this.long_press_gesture.propagation_phase = CAPTURE;
        this.long_press_gesture.pressed.connect((n_press, x, y) => {
            Row? row = (Row) this.list.get_row_at_y((int) y);
            if (row != null) {
                this.list.unselect_all();
                this.selection_mode_enabled = true;
            }
        });
        this.list.add_controller(this.long_press_gesture);

        //XXX GTK4 - check if started on click
        var drag_source = new Gtk.DragSource();
        drag_source.drag_begin.connect(on_drag_begin);
        drag_source.drag_end.connect(on_drag_end);
        this.list.add_controller(drag_source);
    }

    static construct {
        set_css_name("conversation-list");
    }

    // -------
    //   UI
    // -------
    private void header_func(Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
        if (before != null) {
            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            sep.show();
            row.set_header(sep);
        }
    }

    /**
     * Updates the display of the received time on each list row.
     *
     * Because the received time is displayed as relative to the current time,
     * it must be periodically updated. ConversationList.View does not do this
     * automatically but instead it must be externally scheduled
     */
    public void refresh_times() {
        int i = 0;
        Row? row = this.list.get_row_at_index(0) as Row;
        while (row != null) {
            row.refresh_time();
            i++;
            row = this.list.get_row_at_index(i) as Row;
        }
    }

    // -------------------
    //  Model Management
    // -------------------

    /**
     * The currently bound model
     */
    private Model? model;

    /**
     * Set the conversation monitor which the listview is displaying
     */
    public void set_monitor(Geary.App.ConversationMonitor? monitor) {
        if (this.model != null) {
            this.model.conversations_loaded.disconnect(on_conversations_loaded);
            this.model.conversations_removed.disconnect(on_conversations_removed);
            this.model.conversation_updated.disconnect(on_conversation_updated);
        }
        if (monitor == null) {
            this.model = null;
            this.list.bind_model(null, row_factory);
        } else {
            this.model = new Model(monitor);
            this.list.bind_model(this.model, row_factory);
            this.model.conversations_loaded.connect(on_conversations_loaded);
            this.model.conversations_removed.connect(on_conversations_removed);
            this.model.conversation_updated.connect(on_conversation_updated);
        }
    }

    /**
     * Attempt to load more conversations from the current monitor
     */
    public void load_more(int request) {
        if (model != null) {
            model.load_more(request);
        }
    }

    public void scroll(Gtk.ScrollType scroll_type) {
        Gtk.ListBoxRow row = this.list.get_selected_row();

        if (row == null) {
            return;
        }

        int index = row.get_index();
        if (scroll_type == Gtk.ScrollType.STEP_UP) {
            row = this.list.get_row_at_index(index - 1);
        } else {
            row = this.list.get_row_at_index(index + 1);
        }

        if (row != null) {
            this.list.select_row(row);
        }
    }

    private Gtk.Widget row_factory(Object convo_obj) {
        var convo = (Geary.App.Conversation) convo_obj;
        var row = new Row(config, convo, this.selection_mode_enabled);
        row.toggle_flag.connect(on_toggle_flags);
        row.toggle_selection.connect(on_toggle_selection);
        return row;
    }


    // --------------------
    //  Right-click Popup
    // --------------------
    private void context_menu(Row row, Gdk.Rectangle? rect=null) {
        if (!row.is_selected()) {
            this.list.unselect_all();
            this.list.select_row(row);
        }

        var popup_menu = construct_popover(row, this.list.get_selected_rows().length());
        if (rect != null) {
            popup_menu.set_pointing_to(rect);
        }
        popup_menu.popup();
    }

    private Gtk.Popover construct_popover(Row row, uint selection_size) {
        GLib.Menu context_menu_model = new GLib.Menu();
        var main = get_root() as Application.MainWindow;

        if (main != null) {
            if (!main.is_shift_down) {
                context_menu_model.append(
                    /// Translators: Context menu item
                    ngettext(
                        "Move conversation to _Trash",
                        "Move conversations to _Trash",
                        selection_size
                    ),
                    Action.Window.prefix(
                        Application.MainWindow.ACTION_TRASH_CONVERSATION
                    )
                );
            } else {
                context_menu_model.append(
                    /// Translators: Context menu item
                    ngettext(
                        "_Delete conversation",
                        "_Delete conversations",
                        selection_size
                    ),
                    Action.Window.prefix(
                        Application.MainWindow.ACTION_DELETE_CONVERSATION
                    )
                );
            }
        }

        if (row.conversation.is_unread()) {
            context_menu_model.append(
                _("Mark as _Read"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_READ
                )
            );
        }

        if (row.conversation.has_any_read_message()) {
            context_menu_model.append(
                _("Mark as _Unread"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_UNREAD
                )
            );
        }

        if (row.conversation.is_flagged()) {
            context_menu_model.append(
                _("U_nstar"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_UNSTARRED
                )
            );
        } else {
            context_menu_model.append(
                _("_Star"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_STARRED
                )
            );
        }

        if ((row.conversation.base_folder.used_as != ARCHIVE) &&
            (row.conversation.base_folder.used_as != ALL_MAIL)) {
                context_menu_model.append(
                    ngettext(
                        "_Archive conversation",
                        "_Archive conversations",
                        selection_size
                    ),
                    Action.Window.prefix(
                        Application.MainWindow.ACTION_ARCHIVE_CONVERSATION
                    )
                );
        }

        Menu actions_section = new Menu();
        actions_section.append(
            _("_Reply"),
            Action.Window.prefix(
                Application.MainWindow.ACTION_REPLY_CONVERSATION
            )
        );
        actions_section.append(
            _("R_eply All"),
            Action.Window.prefix(
                Application.MainWindow.ACTION_REPLY_ALL_CONVERSATION
            )
        );
        actions_section.append(
            _("_Forward"),
            Action.Window.prefix(
                Application.MainWindow.ACTION_FORWARD_CONVERSATION
            )
        );
        context_menu_model.append_section(null, actions_section);

        var context_menu = new Gtk.PopoverMenu.from_model(context_menu_model);
        context_menu.set_parent(row);

        return context_menu;
    }

    // -------------------
    //  Selection
    // -------------------

    /**
     * Emitted when one or more conversations are selected
     */
    public signal void conversations_selected(Gee.Set<Geary.App.Conversation> selected);

    /**
     * Emitted when one conversation is activated
     */
    public signal void conversation_activated(Geary.App.Conversation activated,
                                              uint button);

    /**
     * Gets the conversations represented by the current selection in the ListBox
     */
    public Gee.Set<Geary.App.Conversation> get_selected_conversations() {
        var selected = new Gee.HashSet<Geary.App.Conversation>();

        foreach (var row in this.list.get_selected_rows()) {
            selected.add(((Row) row).conversation);
        }
        return selected;
    }

    /**
     * Selects the rows for a given collection of conversations
     *
     * If a conversation is not present in the ListBox, it is ignored.
     */
    public void select_conversations(Gee.Collection<Geary.App.Conversation> selection) {
        int i = 0;
        Row? row = this.list.get_row_at_index(0) as Row;
        while (row != null) {
            Geary.App.Conversation conversation = row.conversation;
            if (selection.contains(conversation)) {
                this.list.select_row(row);
            }
            i++;
            row = this.list.get_row_at_index(i) as Row;
        }
    }

    /**
     * Activate currently selected row
     *
     * If more than one selected, activate the first one
     */
    public void activate_selected() {
        Gee.Set<Geary.App.Conversation> conversations = get_selected_conversations();
        if (!conversations.is_empty) {
            conversation_activated(conversations.to_array()[0], 1);
        }
    }

    /**
     * Selects all conversations
     */
    public void select_all() {
        this.selection_mode_enabled = true;
        this.list.select_all();
    }

    /**
     * Unselects all conversations
     */
    public void unselect_all() {
        this.list.unselect_all();
    }

    private bool selection_changed(Gee.Set<Geary.App.Conversation> selection) {
        bool changed = this.selected.size != selection.size;
        if (changed) {
            return true;
        }
        foreach (Geary.App.Conversation conversation in selection) {
            if (!this.selected.contains(conversation)) {
                changed = true;
            }
        }
        return changed;
    }

    private void restore_row() {
        if (this.to_restore_row != null) {
            // Workaround GTK issue, activating/selecting row while model is
            // updated scrolls to top
            GLib.Timeout.add(100, () => {
                this.to_restore_row.activate();
                this.to_restore_row = null;
                return false;
            });
        }
    }

    // -----------------
    //  Button Actions
    // ----------------

    /**
     * Emitted when the user expresses intent to update the flags on a set of conversations
     */
    public signal void mark_conversations(Gee.Collection<Geary.App.Conversation> conversations,
                                          Geary.NamedFlag flag);


    private void on_toggle_flags(ConversationList.Row row, Geary.NamedFlag flag) {
        if (row.is_selected()) {
            mark_conversations(this.selected, flag);
        } else {
            mark_conversations(Geary.Collection.single(row.conversation), flag);
        }
    }

    private void on_toggle_selection(ConversationList.Row row, bool active) {
        if (active) {
            this.list.select_row(row);
        } else {
            this.list.unselect_row(row);
        }
    }

    // ----------------
    //  Visibility
    // ---------------

    /**
     * If the number of pixels between the bottom of the viewport and the bottom of
     * of the listbox is less than LOAD_MORE_THRESHOLD, request more from the
     * monitor.
     */
    private double LOAD_MORE_THRESHOLD = 100;
    private int LOAD_MORE_COUNT = 50;

    /**
     * Called on scroll to possibly load more conversations from the model
     */
    private void maybe_load_more(Gtk.Adjustment adjustment) {
        double upper = adjustment.get_upper();
        double threshold = upper - adjustment.page_size - LOAD_MORE_THRESHOLD;

        if (this.is_visible() && adjustment.get_value() >= threshold) {
            this.load_more(LOAD_MORE_COUNT);
        }
    }

    /**
     * Time in milliseconds to delay updating the set of visible conversations.
     * If another update is triggered during this delay, it will be discarded
     * and the delay begins again.
     */
    private int VISIBILITY_UPDATE_DELAY_MS = 1000;

    /**
     * The set of all conversations currently displayed in the viewport
     */
    public Gee.Set<Geary.App.Conversation> visible_conversations {get; private set; default = new Gee.HashSet<Geary.App.Conversation>(); }
    private Geary.Scheduler.Scheduled? scheduled_visible_update;

    /**
     * Called on scroll to update the set of visible conversations
     */
    private void update_visible_conversations() {
        if(scheduled_visible_update != null) {
            scheduled_visible_update.cancel();
        }

        scheduled_visible_update = Geary.Scheduler.after_msec(VISIBILITY_UPDATE_DELAY_MS, () => {
            var visible = new Gee.HashSet<Geary.App.Conversation>();
            Gtk.ListBoxRow? first = this.list.get_row_at_y((int) this.scrolled_window.vadjustment.value);

            if (first == null) {
                this.visible_conversations = visible;
                return Source.REMOVE;
            }

            uint start_index = ((uint) first.get_index());
            uint end_index = uint.min(
                // Assume that all messages are the same height
                start_index + (uint) (this.scrolled_window.vadjustment.page_size / first.get_allocated_height()),
                this.model.get_n_items()
            );

            for (uint i = start_index; i < end_index; i++) {
                visible_conversations.add(
                    this.model.get_item(i) as Geary.App.Conversation
                );
            }

            this.visible_conversations = visible;
            return Source.REMOVE;
        }, GLib.Priority.DEFAULT_IDLE);
    }

    // ------------
    // Model
    // ------------
    private bool should_inhibit_autoactivate = false;

    /**
     * Informs the listbox to suppress autoactivate behavior on the next update
     */
    public void inhibit_next_autoselect() {
        should_inhibit_autoactivate = true;
    }

    /**
     * Find a selectable conversation near current selection
     */
    private Gtk.ListBoxRow? get_next_conversation(bool asc=true) {
        int index = asc ? 0 : int.MAX;
        GLib.List<unowned Gtk.ListBoxRow> selected_rows;

        selected_rows = this.list.get_selected_rows();
        if (selected_rows.length() == 0 ) {
            return null;
        }

        foreach (var row in selected_rows) {
            if ((asc && row.get_index() > index) ||
                (!asc && row.get_index() < index)) {
                index = row.get_index();
            }
        }
        if (asc) {
            index += 1;
        } else {
            index -= 1;
        }
        Gtk.ListBoxRow? row = this.list.get_row_at_index(index);
        return row != null || !asc ? row : get_next_conversation(false);
    }

    private void on_conversations_loaded() {
        if (this.config.autoselect &&
            !this.should_inhibit_autoactivate &&
            this.list.get_selected_rows().length() == 0) {

            Gtk.ListBoxRow first_row = this.list.get_row_at_index(0);
            if (first_row != null) {
                this.list.select_row(first_row);
            }
        }

        this.should_inhibit_autoactivate = false;
    }

    /*
     * Select next conversation
     */
    private void on_conversations_removed(bool start) {
        // Before model update, just find a conversation
        if (this.config.autoselect && start) {
            this.to_restore_row = get_next_conversation();
        // If in selection mode, leaving will do the job
        } else if (this.selection_mode_enabled) {
            this.selection_mode_enabled = false;
        // Set next conversation
        } else if (this.config.autoselect &&
                   this.list.get_selected_rows().length() == 0) {
            restore_row();
        }
    }

    /*
     * Update conversation row
     */
    private void on_conversation_updated(Geary.App.Conversation convo) {
        int i = 0;
        Row? row = this.list.get_row_at_index(0) as Row;
        while (row != null) {
            if (convo == row.conversation) {
                row.update();
            }

            i++;
            row = this.list.get_row_at_index(i) as Row;
        }
    }

    // ----------
    // Gestures
    // ----------

    [GtkCallback]
    private void on_press_gesture_released(Gtk.GestureClick click_gesture, int n_press, double x, double y) {
        var row = (Row) this.list.get_row_at_y((int) y);

        if (row == null)
            return;

        var button = click_gesture.get_current_button();
        if (button == Gdk.BUTTON_PRIMARY) {
            Gdk.EventSequence sequence = click_gesture.get_current_sequence();
            Gdk.Event event = click_gesture.get_last_event(sequence);
            this.last_modifier_type = event.get_modifier_state();
            if (!this.selection_mode_enabled) {
                if ((this.last_modifier_type & Gdk.ModifierType.SHIFT_MASK) ==
                        Gdk.ModifierType.SHIFT_MASK ||
                    (this.last_modifier_type & Gdk.ModifierType.CONTROL_MASK) ==
                        Gdk.ModifierType.CONTROL_MASK) {
                    this.selection_mode_enabled = true;
                } else {
                    conversation_activated(((Row) row).conversation, 1);
                }
            }
        } else if (button == Gdk.BUTTON_MIDDLE) {
            conversation_activated(row.conversation, 2);
        } else if (button == Gdk.BUTTON_SECONDARY) {
            Graphene.Point p = { (float) x, (float) y };
            Graphene.Point p_row;
            this.list.compute_point(row, p, out p_row);
            Gdk.Rectangle rect = { (int) p_row.x, (int) p_row.y, 0, 0 };
            context_menu(row, rect);
        }
    }

    [GtkCallback]
    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType modifier_type) {
        switch (keyval) {
        case Gdk.Key.Up:
        case Gdk.Key.Down:
            if ((modifier_type & Gdk.ModifierType.SHIFT_MASK) ==
                    Gdk.ModifierType.SHIFT_MASK) {
                this.selection_mode_enabled = true;
            }
            break;
        case Gdk.Key.Escape:
            if (this.selection_mode_enabled) {
                this.selection_mode_enabled = false;
                return true;
            }
            break;
        }
        return false;
    }


    /**
     * Widgets used as drag icons have to be explicitly destroyed after the drag
     * so we track the widget as a private member
     */
    private Row? drag_widget = null;

    private void on_drag_begin(Gtk.DragSource drag_source, Gdk.Drag drag) {
        int screen_x, screen_y;
        Gdk.ModifierType _modifier;

        Row? row = this.list.get_row_at_y((int) this.scrolled_window.vadjustment.value) as Row?;
        if (row != null) {
            // If the user has a selection but drags starting from an unselected
            // row, we need to set the selection to that row
            if (!row.is_selected()) {
                this.list.unselect_all();
                this.list.select_row(row);
            }

            this.drag_widget = new Row(this.config, row.conversation, false);
            this.drag_widget.width_request = row.get_allocated_width();
            this.drag_widget.add_css_class("drag-n-drop");
            this.drag_widget.visible = true;

            double hot_x, hot_y;
            // XXX GTK4 - this might be a bit more work to do properly wiht Paintable
            translate_coordinates(row, 0, 0, out hot_x, out hot_y);
            // drag_source.set_icon(this.drag_widget, hot_x, hot_y);
        }
    }

    private void on_drag_end(Gtk.DragSource drag_source, Gdk.Drag drag, bool delete_data) {
        if (this.drag_widget != null) {
            this.drag_widget = null;
        }
    }

    private void on_selected_rows_changed() {
        var selected = get_selected_conversations();

        if (!selection_changed(selected)) {
            return;
        }

        this.selected = selected;
        if (this.selected.size > 0 || this.to_restore_row == null) {
            conversations_selected(this.selected);
        }
    }

    private void on_row_activated() {
        var row = this.list.get_selected_row();
        if (row != null) {
            conversation_activated(((Row) row).conversation, 1);
        }
    }

    private void on_selection_mode_changed() {
        int i = 0;
        Row? row = this.list.get_row_at_index(0) as Row;
        while (row != null) {
            row.set_selection_enabled(this.selection_mode_enabled);
            i++;
            row = this.list.get_row_at_index(i) as Row;
        }

        if (this.selection_mode_enabled) {
            this.to_restore_row = this.list.get_selected_row();
        } else {
            restore_row();
        }
    }
}
