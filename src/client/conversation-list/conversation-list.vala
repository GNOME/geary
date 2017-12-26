/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A GtkListBox that displays a list of conversations.
 *
 * This class uses the GtkListBox's selection system for selecting and
 * displaying individual conversations, and supports the GNOME3 HIG
 * selection mode pattern for to allow multiple conversations to be
 * marked, independent of the list's selection. These conversations
 * are referred to `selected` and `marked`, respectively, or
 * `highlighted` if referring to either.
 */
public class ConversationList : Gtk.ListBox {


    private const string LIST_CLASS = "geary-conversation-list";


    /** Underlying model for this list */
    public ConversationListModel? model { get; private set; default=null; }

    /**
     * The conversation highlighted as selected, if any.
     *
     * This is distinct to the conversations marked via selection
     * mode, which are checked and might not be highlighted.
     */
    public Geary.App.Conversation? selected { get; private set; default = null; }

    /** Determines if selection mode is enabled for the list. */
    public bool is_selection_mode_enabled { get; private set; default = false; }

    /** Determines if the list has selected or marked conversations. */
    public bool has_highlighted_conversations {
        get {
            return this.is_selection_mode_enabled
                ? !this.marked.is_empty
                : this.selected != null;
        }
    }

    private Configuration config;
    private int selected_index = -1;
    private bool selection_frozen = false;
    private Gee.Map<Geary.App.Conversation,ConversationListItem> marked =
        new Gee.HashMap<Geary.App.Conversation,ConversationListItem>();
    private Gee.Set<Geary.App.Conversation>? visible_conversations = null;
    private Geary.Scheduler.Scheduled? update_visible_scheduled = null;
    private bool enable_load_more = true;
    private bool reset_adjustment = false;
    private double adj_last_upper = -1.0;


    /** Fired when a user changes the list's selection. */
    public signal void conversation_selection_changed(Geary.App.Conversation? selection);

    /** Fired when a user activates a row in the list. */
    public signal void conversation_activated(Geary.App.Conversation activated);

    /** Fired the visible conversations in the widget change. */
    public signal void visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible);

    /** Fired when additional conversations are required. */
    public virtual signal void load_more() {
        this.enable_load_more = false;
    }

    /**
     * Fired when a list item was targeted with a selection gesture.
     *
     * Selection gestures include Ctrl-click or Shift-click on the
     * list row.
     */
    public signal void selection_mode_enabled();

    /**
     * Fired when all marked conversations were removed from the folder.
     */
    public signal void marked_conversations_evaporated();

    /**
     * Fired when a list item was marked as selected in selection mode.
     */
    public signal void item_marked(ConversationListItem item, bool marked);


    public ConversationList(Configuration config) {
        this.config = config;
        get_style_context().add_class(LIST_CLASS);
        set_activate_on_single_click(true);
        set_selection_mode(Gtk.SelectionMode.SINGLE);

        this.row_activated.connect((row) => {
                uint activated = row.get_index();
                this.conversation_activated(this.model.get_conversation(activated));
            });
        this.selected_rows_changed.connect(() => {
                selection_changed();
            });
        this.show.connect(on_show);
    }

    /**
     * Returns current selected or marked conversations, if any.
     */
    public bool is_highlighted(Geary.App.Conversation target) {
        return this.is_selection_mode_enabled
            ? this.marked.has_key(target)
            : this.selected == target;
    }

    /**
     * Returns current selected or marked conversations, if any.
     */
    public Gee.Collection<Geary.App.Conversation> get_highlighted_conversations() {
        Gee.Collection<Geary.App.Conversation>? highlighted = null;
        if (this.is_selection_mode_enabled) {
            highlighted = this.get_marked_items();
        } else {
            highlighted = new Gee.LinkedList<Geary.App.Conversation>();
            if (this.selected != null) {
                highlighted.add(this.selected);
            }
        }
        return highlighted;
    }

    /**
     * Returns a read-only collection of currently marked items.
     *
     * This is distinct to the conversations marked via the list's
     * selection, which are highlighted as selected.
     */
    public Gee.Collection<Geary.App.Conversation> get_marked_items() {
        return this.marked.keys.read_only_view;
    }

    public new void bind_model(Geary.App.ConversationMonitor monitor) {
        Geary.Folder displayed = monitor.base_folder;
        Geary.App.EmailStore store = new Geary.App.EmailStore(displayed.account);
        PreviewLoader loader = new PreviewLoader(store, new Cancellable()); // XXX

        monitor.scan_started.connect(on_scan_started);
        monitor.scan_completed.connect(on_scan_completed);
        monitor.scan_completed.connect(() => {
                loader.load_remote();
            });
        monitor.conversations_removed.connect(on_conversations_removed);

        this.model = new ConversationListModel(monitor, loader);
        this.model.items_changed.connect(on_model_items_changed);

        // Clear these since they will belong to the old model
        this.selected = null;
        this.selected_index = -1;
        this.marked.clear();
        this.visible_conversations = null;

        Gee.List<Geary.RFC822.MailboxAddress> account_addresses = displayed.account.information.get_all_mailboxes();
        bool use_to = displayed.special_folder_type.is_outgoing();
        base.bind_model(this.model, (convo) => {
                ConversationListItem item = new ConversationListItem(
                    convo as Geary.App.Conversation,
                    account_addresses,
                    use_to,
                    loader,
                    this.config
                );
                item.item_marked.connect(on_item_marked);
                return item;
            }
        );
    }

    public void freeze_selection() {
        this.selection_frozen = true;
        this.selected = null;
        set_selection_mode(Gtk.SelectionMode.NONE);
    }

    public void thaw_selection() {
        set_selection_mode(Gtk.SelectionMode.SINGLE);
        this.selection_frozen = false;
        restore_selection();
    }

    public void select_conversation(Geary.App.Conversation target) {
        for (int i = 0; i < this.model.get_n_items(); i++) {
            ConversationListItem? row = get_item_at_index(i);
            if (row.conversation == target) {
                select_row(row);
                break;
            }
        }
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (event.button == 1) {
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0) {
                // Shift isn't down
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    !this.is_selection_mode_enabled) {
                    // Not currently in selection mode, but Ctrl is
                    // down, so enable it
                    set_selection_mode_enabled(true);
                    selection_mode_enabled();
                }
                if (this.is_selection_mode_enabled) {
                    // Are (now) currently in selection mode, so
                    // toggle the row
                    ConversationListItem? row =
                        get_row_at_y((int) event.y) as ConversationListItem;
                    if (row != null) {
                        row.toggle_marked();
                    }
                }
            } else if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                // Shift is down, so emulate Gtk.TreeView-like
                // contiguous selection behaviour
                if (!this.is_selection_mode_enabled) {
                    set_selection_mode_enabled(true);
                    selection_mode_enabled();
                }
                ConversationListItem? clicked =
                    get_row_at_y((int) event.y)  as ConversationListItem;
                if (clicked != null) {
                    ConversationListItem? selected = get_selected_item();
                    if (selected == null) {
                        selected = get_item_at_index(0);
                    }

                    int index = int.min(clicked.get_index(), selected.get_index());
                    int end = index + (clicked.get_index() - selected.get_index()).abs();
                    while (index <= end) {
                        ConversationListItem? row = get_item_at_index(index++);
                        if (row != null) {
                            row.set_marked(true);
                        }
                    }
                }
            }
        }
        return base.button_press_event(event);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Return ||
            event.keyval == Gdk.Key.KP_Enter) {
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                !this.is_selection_mode_enabled) {
                set_selection_mode_enabled(true);
                selection_mode_enabled();
            }
            if (this.is_selection_mode_enabled) {
                // Are (now) currently in selection mode, so
                // toggle the row
                ConversationListItem? row = get_selected_item();
                if (row != null) {
                    row.toggle_marked();
                }
            }
        }
        return base.key_press_event(event);
    }

    internal Gee.Set<Geary.App.Conversation> get_visible_conversations() {
        Gee.HashSet<Geary.App.Conversation> visible = new Gee.HashSet<Geary.App.Conversation>();
        // XXX Implement me
        return visible;
    }

    internal void set_selection_mode_enabled(bool enabled) {
        if (enabled) {
            freeze_selection();
        } else {
            // Call to_array here to get a copy of the value
            // collection, since unmarking the items will cause the
            // underlying map to be modified
            foreach (ConversationListItem item in this.marked.values.to_array()) {
                item.set_marked(false);
            }
            this.marked.clear();
            thaw_selection();
        }
        this.is_selection_mode_enabled = enabled;
    }

    private inline ConversationListItem? get_item_at_index(int index) {
        return get_row_at_index(index) as ConversationListItem;
    }

    private inline ConversationListItem? get_selected_item() {
        return get_selected_row() as ConversationListItem;
    }

    private ConversationListItem? restore_selection() {
        ConversationListItem? row = null;
        if (this.selected_index >= 0) {
            int new_index = this.selected_index;
            if (new_index >= this.model.get_n_items()) {
                new_index = ((int) this.model.get_n_items()) - 1;
            }

            row = get_item_at_index(new_index);
            if (row != null) {
                if (this.config.autoselect) {
                    select_row(row);
                }

                // Grab the focus so the user can continue using the
                // keyboard to navigate if so desired.
                row.grab_focus();
            }
        }

        // Return null if not autoselecting so we don't emit a
        // selection signal, causing the conversation to be displayed.
        return this.config.autoselect ? row : null;
    }

    private void schedule_visible_conversations_changed() {
        this.update_visible_scheduled = Geary.Scheduler.on_idle(
            () => {
                update_visible_conversations();
                return Source.REMOVE; // one-shot
            });
    }

    private void selection_changed() {
        if (!this.selection_frozen) {
            Geary.App.Conversation? selected = null;
            ConversationListItem? row = get_selected_row() as ConversationListItem;

            // If a row was de-selected then we need to work out if
            // that was because of a conversation being removed from
            // the list, and if so select a new one
            if (row == null &&
                this.selected != null &&
                !this.model.monitor.has_conversation(this.selected)) {
                row = restore_selection();
            }

            if (row != null) {
                selected = row.conversation;
                this.selected_index = row.get_index();
            } else {
                this.selected_index = -1;
            }

            if (this.selected != selected) {
                debug("Selection changed to: %s",
                      selected != null ? selected.to_string() : null
                );
                this.selected = selected;
                this.conversation_selection_changed(selected);
            }
        }
    }

    private void update_visible_conversations() {
        Gee.Set<Geary.App.Conversation> visible_now = get_visible_conversations();
        if (this.visible_conversations == null ||
            Geary.Collection.are_sets_equal<Geary.App.Conversation>(
                this.visible_conversations, visible_now)) {
            this.visible_conversations = visible_now;
            this.visible_conversations_changed(visible_now.read_only_view);
        }
    }

    private void on_show() {
        // Wait until we're visible to set this signal up.
        get_adjustment().value_changed.connect(on_adjustment_value_changed);
    }

    private void on_adjustment_value_changed() {
        Gtk.Adjustment? adjustment = get_adjustment();
        if (this.enable_load_more && adjustment != null) {
            // Check if we're towards the bottom of the list. If we
            // are, it's time to issue a load_more signal.
            double value = adjustment.get_value();
            double upper = adjustment.get_upper();
            if ((value / upper) >= 0.85 &&
                upper > this.adj_last_upper) {
                load_more();
                this.adj_last_upper = upper;
            }

            schedule_visible_conversations_changed();
        }
    }

    private void on_scan_started() {
        this.enable_load_more = false;
    }

    private void on_scan_completed() {
        this.enable_load_more = true;

        // Select the first conversation, if autoselect is enabled,
        // nothing has been selected yet and we're not composing. Do
        // this here instead of in on_seed_completed since we want to
        // to select the first row on folder change as soon as
        // possible.
        if (this.config.autoselect && get_selected_row() == null) {
            Gtk.ListBoxRow? first = get_row_at_index(0);
            if (first != null) {
                select_row(first);
            }
        }
    }

    private void on_model_items_changed(uint pos, uint removed, uint added) {
        if (added > 0) {
            // Conversations were added
            Gtk.Adjustment? adjustment = get_adjustment();
            if (pos == 0) {
                // We were at the top and we want to stay there after
                // conversations are added
                this.reset_adjustment = (adjustment != null) && (adjustment.get_value() == 0);
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

        if (removed >= 0) {
            // Conversations were removed.

            // Reset the last upper limit so scrolling to the bottom
            // will always activate a reload (this is particularly
            // important if the model is cleared)
            this.adj_last_upper = -1.0;
        }
    }

    private void on_conversations_removed(Gee.Collection<Geary.App.Conversation> removed) {
        if (this.is_selection_mode_enabled) {
            foreach (Geary.App.Conversation convo in removed) {
                this.marked.remove(convo);
            }
            if (this.marked.is_empty) {
                marked_conversations_evaporated();
            }
        }
    }

    private void on_item_marked(ConversationListItem item, bool marked) {
        if (marked) {
            this.marked.set(item.conversation, item);
        } else {
            this.marked.remove(item.conversation);
        }
        item_marked(item, marked);
    }

}
