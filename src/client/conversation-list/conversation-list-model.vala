/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A GLib.ListModel of sorted {@link Geary.App.Conversation}s.
 *
 * Conversations are sorted by {@link
 * Geary.EmailProperties.date_received} (IMAP's INTERNALDATE) rather
 * than the Date: header, as that ensures newly received email sort to
 * the top where the user expects to see them.  The ConversationViewer
 * sorts by the Date: header, as that presents better to the user.
 */
public class ConversationListModel : Geary.BaseObject, GLib.ListModel {


    private Geary.App.ConversationMonitor monitor;

    // Can't just derive from this directly since it's a compact class
    private ListStore conversations = new ListStore(typeof(Geary.App.Conversation));


    public Object? get_item(uint position) {
        return this.conversations.get_item(position);
    }

    public uint get_n_items() {
        return this.conversations.get_n_items();
    }

    public Type get_item_type() {
        return this.conversations.get_item_type();
    }


    public ConversationListModel(Geary.App.ConversationMonitor monitor) {
        this.monitor = monitor;

        //monitor.scan_completed.connect(on_scan_completed);
        monitor.conversations_added.connect(on_conversations_added);
        //monitor.conversations_removed.connect(on_conversation_removed);
        //monitor.conversation_appended.connect(on_conversation_appended);
        //monitor.conversation_trimmed.connect(on_conversation_trimmed);
        //monitor.email_flags_changed.connect(on_email_flags_changed);

        // add all existing monitor
        on_conversations_added(monitor.get_conversations());

        this.conversations.items_changed.connect((position, removed, added) => {
                this.items_changed(position, removed, added);
            });
    }

    private void on_conversations_added(Gee.Collection<Geary.App.Conversation> monitor) {
        foreach (Geary.App.Conversation conversation in monitor) {
            this.conversations.insert_sorted(
                conversation,
                (a, b) => {
                    return - compare_conversation_ascending(a as Geary.App.Conversation,
                                                            b as Geary.App.Conversation); }
            );
        }
    }

}
