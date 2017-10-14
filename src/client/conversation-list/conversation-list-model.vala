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


    // The model's native sort order
    private static int model_sort(Geary.App.Conversation a, Geary.App.Conversation b) {
        return compare_conversation_descending(a, b);
    }


    private Geary.App.ConversationMonitor monitor;

    // Backing store for this model. We can't just derive from this
    // directly since GLib.ListStore is a compact class.
    private ListStore conversations = new ListStore(typeof(Geary.App.Conversation));


    public ConversationListModel(Geary.App.ConversationMonitor monitor) {
        this.monitor = monitor;

        //monitor.scan_completed.connect(on_scan_completed);
        monitor.conversations_added.connect(on_conversations_added);
        monitor.conversations_removed.connect(on_conversations_removed);
        // XXX
        //monitor.email_flags_changed.connect((convo) => { update(convo); });

        // add all existing monitor
        on_conversations_added(monitor.get_conversations());

        this.conversations.items_changed.connect((position, removed, added) => {
                this.items_changed(position, removed, added);
            });
    }

    public Object? get_item(uint position) {
        return this.conversations.get_item(position);
    }

    public uint get_n_items() {
        return this.monitor.get_conversation_count();
    }

    public Type get_item_type() {
        return this.conversations.get_item_type();
    }

    public Geary.App.Conversation get_conversation(uint position) {
        // XXX need to handle null here by throwing an error
        return this.conversations.get_item(position) as Geary.App.Conversation;
    }

    // private void update(Geary.App.Conversation target) {
    //     // XXX this is horribly inefficient
    //     this.conversations.sort((a, b) => {
    //             return model_sort(a as Geary.App.Conversation,
    //                               b as Geary.App.Conversation);
    //         });
    // }

    private uint get_index(Geary.App.Conversation target)
        throws Error {
        // Yet Another Binary Search Implementation :<
        uint lower = 0;
        uint upper = get_n_items();
        while (lower <= upper) {
            uint mid = (uint) Math.floor((upper + lower) / 2);
            int cmp = model_sort(get_conversation(mid), target);
            if (cmp < 1) {
                lower = mid + 1;
            } else if (cmp > 1) {
                upper = mid - 1;
            } else {
                return mid;
            }
        }
        // XXX UGH
        throw new IOError.NOT_FOUND("Not found");
    }

    private void on_conversations_added(Gee.Collection<Geary.App.Conversation> conversations) {
        foreach (Geary.App.Conversation convo in conversations) {
            this.conversations.insert_sorted(
                convo,
                (a, b) => {
                    return model_sort(a as Geary.App.Conversation,
                                      b as Geary.App.Conversation);
                }
            );
        }
    }

    private void on_conversations_removed(Gee.Collection<Geary.App.Conversation> conversations) {
        foreach (Geary.App.Conversation convo in conversations) {
            try {
                this.conversations.remove(get_index(convo));
            } catch (Error err) {
                debug("Failed to remove conversation");
            }
        }
    }

}
