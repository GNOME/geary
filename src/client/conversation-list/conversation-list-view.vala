[GtkTemplate (ui = "/org/gnome/Geary/conversation-list-view.ui")]
public class ConversationList.View : Gtk.ScrolledWindow, Geary.BaseInterface {
    /**
     * The fields that must be available on any ConversationMonitor
     * passed to ConversationList.View
     */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.FLAGS |
        Geary.Email.Field.PROPERTIES
    );

    private Application.Configuration config;
    private Gtk.GestureMultiPress press_gesture;
    private Gtk.GestureLongPress long_press_gesture;

    [GtkChild] private unowned Gtk.ListBox list;


    public View(Application.Configuration config) {
        this.config = config;

        this.list.selected_rows_changed.connect(() => {
            conversations_selected(get_selected());
        });

        this.list.set_header_func(header_func);

        this.vadjustment.value_changed.connect(maybe_load_more);
        this.vadjustment.value_changed.connect(update_visible_conversations);

        this.press_gesture = new Gtk.GestureMultiPress(this.list);
        this.press_gesture.set_button(3);
        this.press_gesture.released.connect((n_press, x, y) => {
            var row = (Row) this.list.get_row_at_y((int) y);
            context_menu(row);
        });

        this.long_press_gesture = new Gtk.GestureLongPress(this.list);
        this.long_press_gesture.propagation_phase = CAPTURE;
        this.long_press_gesture.pressed.connect((n_press, x, y) => {
            var row = (Row) this.list.get_row_at_y((int) y);
            context_menu(row);
        });

        Gtk.drag_source_set(this.list, Gdk.ModifierType.BUTTON1_MASK, FolderList.Tree.TARGET_ENTRY_LIST,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        this.list.drag_begin.connect(on_drag_begin);
        this.list.drag_end.connect(on_drag_end);
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
        this.list.foreach((child) => {
            var row = (Row) child;
            row.refresh_time();
        });
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
            this.model.update_complete.disconnect(on_model_items_changed);
        }
        if (monitor == null) {
            this.model = null;
            this.list.bind_model(null, row_factory);
        } else {
            this.model = new Model(monitor);
            this.list.bind_model(this.model.store, row_factory);
            this.model.update_complete.connect(on_model_items_changed);
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

    private Gtk.Widget row_factory(Object convo_obj) {
        var convo = (Geary.App.Conversation) convo_obj;
        var row = new Row(config, convo);
        row.toggle_flag.connect(toggle_flags);
        return row;
    }


    // --------------------
    //  Right-click Popup
    // --------------------
    private void context_menu(Row row) {
        if (!row.is_selected()) {
            this.list.unselect_all();
            this.list.select_row(row);
        }

        var popup_menu = construct_popover(row, this.list.get_selected_rows().length());
        popup_menu.popup();
    }

    private Gtk.Popover construct_popover(Row row, uint selection_size) {
        GLib.Menu context_menu_model = new GLib.Menu();
        var main = get_toplevel() as Application.MainWindow;
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

        if (row.conversation.is_unread())
            context_menu_model.append(
                _("Mark as _Read"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_READ
                )
            );

        if (row.conversation.has_any_read_message())
            context_menu_model.append(
                _("Mark as _Unread"),
                Action.Window.prefix(
                    Application.MainWindow.ACTION_MARK_AS_UNREAD
                )
            );

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

        // Use a popover rather than a regular context menu since
        // the latter grabs the event queue, so the MainWindow
        // will not receive events if the user releases Shift,
        // making the trash/delete header bar state wrong.
        Gtk.Popover context_menu = new Gtk.Popover.from_model(
            row, context_menu_model
        );

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
     * Emitted when one or more conversations are activated
     *
     * If more than one conversation is activated, this signal is emitted
     * multiple times with the single flag false
     */
    public signal void conversation_activated(Geary.App.Conversation activated, bool single = false);

    /**
     * Gets the conversations represented by the current selection in the ListBox
     */
    public Gee.Set<Geary.App.Conversation> get_selected() {
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
        this.list.foreach((child) => {
            var row = (Row) child;
            Geary.App.Conversation conversation = row.conversation;
            if (selection.contains(conversation)) {
                this.list.select_row(row);
            }

        });
    }

    /**
     * Unselects all conversations
     */
    public void unselect_all() {
        this.list.unselect_all();
    }

    // -----------------
    //  Button Actions
    // ----------------

    /**
     * Emitted when the user expresses intent to update the flags on a set of conversations
     */
    public signal void mark_conversations(Gee.Collection<Geary.App.Conversation> conversations,
                                          Geary.NamedFlag flag);


    private void toggle_flags(ConversationList.Row row, Geary.NamedFlag flag) {
        if (row.is_selected()) {
            mark_conversations(get_selected(), flag);
        } else {
            mark_conversations(Geary.Collection.single(row.conversation), flag);
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
            Gtk.ListBoxRow? first = this.list.get_row_at_y((int) this.vadjustment.value);
            if (first == null) {
                this.visible_conversations = visible;
                return Source.REMOVE;
            }

            uint start_index = ((uint) first.get_index());
            uint end_index = uint.min(
                // Assume that all messages are the same height
                start_index + (uint) (this.vadjustment.page_size / first.get_allocated_height()),
                this.model.store.get_n_items()
            );

            for (uint i = start_index; i < end_index; i++) {
                visible_conversations.add(this.model.store.get_item(i) as Geary.App.Conversation);
            }

            this.visible_conversations = visible;
            return Source.REMOVE;
        }, GLib.Priority.DEFAULT_IDLE);
    }

    // ------------
    // Autoselect
    // ------------
    private bool should_inhibit_autoselect = false;

    /**
     * Informs the listbox to suppress autoselect behavior on the next update
     */
    public void inhibit_next_autoselect() {
        should_inhibit_autoselect = true;
    }

    private void on_model_items_changed() {
        if (this.config.autoselect &&
            !this.should_inhibit_autoselect &&
            this.list.get_selected_rows().length() == 0) {

            Gtk.ListBoxRow first_row = this.list.get_row_at_index(0);
            if (first_row != null) {
                this.list.select_row(first_row);
            }
        }
        this.should_inhibit_autoselect = false;
    }

	/**
	 * Widgets used as drag icons have to be explicitly destroyed after the drag
	 * so we track the widget as a private member
	 */
    private Row? drag_widget = null;

    private void on_drag_begin(Gdk.DragContext ctx) {
        int screen_x, screen_y;
        Gdk.ModifierType _modifier;
        this.get_window().get_device_position(ctx.get_device(), out screen_x, out screen_y, out _modifier);

        // If the user has a selection but drags starting from an unselected
        // row, we need to set the selection to that row
        Row? row = this.list.get_row_at_y(screen_y + (int) this.vadjustment.value) as Row?;
        if (!row.is_selected()) {
            this.list.unselect_all();
            this.list.select_row(row);
        }

        this.drag_widget = new Row(this.config, row.conversation);
        this.drag_widget.width_request = row.get_allocated_width();
        this.drag_widget.get_style_context().add_class("drag-n-drop");
        this.drag_widget.visible = true;

        int hot_x, hot_y;
        this.translate_coordinates(row, screen_x, screen_y, out hot_x, out hot_y);
        Gtk.drag_set_icon_widget(ctx, this.drag_widget, hot_x, hot_y);
    }

    private void on_drag_end(Gdk.DragContext ctx) {
        if (this.drag_widget != null) {
            this.drag_widget.destroy();
            this.drag_widget = null;
        }
    }

    // ----------------
    //  Unknown
    // -----------------
    public void scroll(Gtk.ScrollType o) {}
}
