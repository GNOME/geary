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

    private Configuration config;


    public ConversationList(Configuration config) {
        this.config = config;
        get_style_context().add_class(CLASS);
        set_activate_on_single_click(true);
        set_selection_mode(Gtk.SelectionMode.MULTIPLE);
    }

    public void set_model(Geary.App.ConversationMonitor monitor) {
        Geary.Folder displayed = monitor.folder;
        Gee.List<Geary.RFC822.MailboxAddress> account_addresses = displayed.account.information.get_all_mailboxes();
        bool use_to = (displayed != null) && displayed.special_folder_type.is_outgoing();
        bind_model(
            new ConversationListModel(monitor),
            (convo) => {
                return new ConversationListItem(convo as Geary.App.Conversation,
                                                account_addresses,
                                                use_to,
                                                this.config);
            }
        );
    }

}
