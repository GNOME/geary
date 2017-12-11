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


    /** Email fields required to load the message in this model. */
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.FLAGS |
        Geary.Email.Field.PROPERTIES;


    /** The source of conversations for this model. */
    public Geary.App.ConversationMonitor monitor { get; private set; }

    /** The preview loader for this model. */
    public PreviewLoader previews { get; private set; }

    // Backing store for this model
    private Sequence<Geary.App.Conversation> conversations =
        new Sequence<Geary.App.Conversation>();

    /** The model's native sort order. */
    private CompareDataFunc model_sort =
        (CompareDataFunc) compare_conversation_descending;


    /**
     * Constructs a new model for the conversation list.
     */
    public ConversationListModel(Geary.App.ConversationMonitor monitor,
                                 PreviewLoader previews) {
        this.monitor = monitor;
        this.previews = previews;

        // XXX Should only start loading when scan is completed
        //monitor.scan_completed.connect(on_scan_completed);
        monitor.conversations_added.connect(add);
        monitor.conversations_removed.connect(on_removed);
        monitor.conversation_appended.connect(on_updated);
        monitor.conversation_trimmed.connect(on_updated);

        // add all existing monitor
        add(monitor.get_conversations());
    }

    public void add(Gee.Collection<Geary.App.Conversation> to_add) {
        foreach (Geary.App.Conversation convo in to_add) {
            SequenceIter<Geary.App.Conversation>? existing =
                this.conversations.lookup(convo, this.model_sort);
            if (existing == null) {
                add_internal(convo);
            }
        }
    }

    public void remove(Gee.Collection<Geary.App.Conversation> to_remove) {
        foreach (Geary.App.Conversation convo in to_remove) {
            SequenceIter<Geary.App.Conversation>? existing =
                this.conversations.lookup(convo, this.model_sort);
            if (existing != null) {
                remove_internal(existing);
            }
        }
    }

    public Geary.App.Conversation get_conversation(uint position) {
        SequenceIter<Geary.App.Conversation>? existing =
            this.conversations.get_iter_at_pos((int) position);
        // XXX handle null here by throwing an error
        return (existing != null) ? existing.get() : null;
    }

    public Object? get_item(uint position) {
        SequenceIter<Geary.App.Conversation>? existing =
            this.conversations.get_iter_at_pos((int) position);
        return (existing != null) ? existing.get() : null;
    }

    public uint get_n_items() {
        return (uint) this.conversations.get_length();
    }

    public Type get_item_type() {
        return typeof(Geary.App.Conversation);
    }

    public SequenceIter<Geary.App.Conversation>?
        get_by_identity(Geary.App.Conversation target) {
        SequenceIter<Geary.App.Conversation> existing =
            this.conversations.get_begin_iter();
        while (!existing.is_end()) {
            if (existing.get() == target) {
                return existing;
            }
            existing = existing.next();
        }
        return null;
    }

    private void on_removed(Gee.Collection<Geary.App.Conversation> removed) {
        // We can't just use the conversation's sorted positions since
        // it would have changed as its emails were removed from it,
        // so we need to find it by identity instead.
        foreach (Geary.App.Conversation target in removed) {
            SequenceIter<Geary.App.Conversation>? existing = get_by_identity(
                target
            );
            if (existing != null) {
                debug("Removed conversation: %s", target.to_string());
                remove_internal(existing);
            }
        }
    }

    private void on_updated(Geary.App.Conversation updated) {
        debug("Conversation updated: %s", updated.to_string());
        // Need to remove and re-add the conversation to take into
        // account its new position. We can't just use its sorted
        // position however since it may have changed, so we need to
        // find it by identity instead.
        SequenceIter<Geary.App.Conversation>? existing = get_by_identity(
            updated
        );
        if (existing != null) {
            debug("Updating conversation: %s", updated.to_string());
            remove_internal(existing);
            add_internal(updated);
        }
    }

    private void add_internal(Geary.App.Conversation convo) {
        SequenceIter<Geary.App.Conversation> pos =
            this.conversations.insert_sorted(convo, this.model_sort);
        this.items_changed(pos.get_position(), 0, 1);
    }

    private void remove_internal(SequenceIter<Geary.App.Conversation> existing) {
        int pos = existing.get_position();
        existing.remove();
        this.items_changed(pos, 1, 0);
    }

}
