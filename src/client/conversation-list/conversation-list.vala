/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A Gtk.ListBox that displays a list of conversations.
 */
public class ConversationList : Gtk.ListBox {


    private const string CLASS = "geary-conversation-list";

    /** Underlying model for this list */
    public ConversationListModel? model { get; private set; default=null; }

    private Configuration config;

    private bool enable_load_more = true;
    private bool reset_adjustment = false;
    private double adj_last_upper = -1.0;


    /** Fired when a user changes the list's selection. */
    public signal void conversation_selection_changed(Gee.Set<Geary.App.Conversation> selection);

    /** Fired when a user activates a row in the list. */
    public signal void conversation_activated(Geary.App.Conversation activated);

    /** Fired when additional conversations are required. */
    public virtual signal void load_more() {
        this.enable_load_more = false;
    }

    public ConversationList(Configuration config) {
        this.config = config;
        get_style_context().add_class(CLASS);
        set_activate_on_single_click(true);
        set_selection_mode(Gtk.SelectionMode.SINGLE);

        this.row_activated.connect((row) => {
                uint activated = row.get_index();
                this.conversation_activated(this.model.get_conversation(activated));
            });
        this.selected_rows_changed.connect(() => {
                Gee.HashSet<Geary.App.Conversation> new_selection =
                    new Gee.HashSet<Geary.App.Conversation>();
                foreach (Gtk.ListBoxRow row in get_selected_rows()) {
                    uint selected = row.get_index();
                    new_selection.add(this.model.get_conversation(selected));
                }
                this.conversation_selection_changed(new_selection);
            });

        this.show.connect(on_show);
    }

    public new void bind_model(Geary.App.ConversationMonitor monitor) {
        monitor.scan_started.connect(on_scan_started);
        monitor.scan_completed.connect(on_scan_completed);

        this.model = new ConversationListModel(monitor);
        this.model.items_changed.connect(on_model_items_changed);

        Geary.Folder displayed = monitor.folder;
        Gee.List<Geary.RFC822.MailboxAddress> account_addresses = displayed.account.information.get_all_mailboxes();
        bool use_to = (displayed != null) && displayed.special_folder_type.is_outgoing();
        base.bind_model(this.model, (convo) => {
                return new ConversationListItem(convo as Geary.App.Conversation,
                                                account_addresses,
                                                use_to,
                                                this.config);
            }
        );
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

}
