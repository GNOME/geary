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



    /** Fired when a user changes the list's selection. */
    public signal void conversation_selection_changed(Gee.Set<Geary.App.Conversation> selection);

    /** Fired when a user activates a row in the list. */
    public signal void conversation_activated(Geary.App.Conversation activated);


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
    }

    public new void bind_model(Geary.App.ConversationMonitor monitor) {
        this.model = new ConversationListModel(monitor);
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

}
