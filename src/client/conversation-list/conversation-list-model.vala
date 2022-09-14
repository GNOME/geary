/*
 * Copyright © 2022 John Renner <john@jrenner.net>
 * Copyright © 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// The whole goal of this class to wrap the ConversationMonitor with a view that presents a sorted list
public class ConversationList.Model : Object, ListModel {
    internal GLib.GenericArray<Geary.App.Conversation> items = new GLib.GenericArray<Geary.App.Conversation>();
    internal Geary.App.ConversationMonitor monitor { get; set; }

    private bool scanning = false;

    internal Model(Geary.App.ConversationMonitor monitor) {
        this.monitor = monitor;

        monitor.conversations_added.connect(on_conversations_added);
        monitor.conversation_appended.connect(on_conversation_updated);
        monitor.conversation_trimmed.connect(on_conversation_updated);
        monitor.conversations_removed.connect(on_conversations_removed);
        monitor.scan_started.connect(on_scan_started);
        monitor.scan_completed.connect(on_scan_completed);
    }

    ~Model() {
        this.monitor.conversations_added.disconnect(on_conversations_added);
        this.monitor.conversation_appended.disconnect(on_conversation_updated);
        this.monitor.conversation_trimmed.disconnect(on_conversation_updated);
        this.monitor.conversations_removed.disconnect(on_conversations_removed);
        this.monitor.scan_started.disconnect(on_scan_started);
        this.monitor.scan_completed.disconnect(on_scan_completed);
    }

    public signal void conversations_added(bool start);
    public signal void conversations_removed(bool start);
    public signal void conversations_loaded();
    public signal void conversation_updated(Geary.App.Conversation convo);

    private static int compare(Object a, Object b) {
        return Util.Email.compare_conversation_descending(a as Geary.App.Conversation, b as Geary.App.Conversation);
    }

    // ------------------------
    //  Scanning and load_more
    // ------------------------

    private void on_scan_started(Geary.App.ConversationMonitor source) {
        this.scanning = true;
    }

    private void on_scan_completed(Geary.App.ConversationMonitor source) {
        this.scanning = false;
        GLib.Timeout.add(100, () => {
            if (!this.scanning) {
                conversations_loaded();
            }
            return false;
        });
    }

    public bool load_more(int amount) {
        if (this.scanning) {
            return false;
        }

        this.monitor.min_window_count += amount;
        return true;
    }


    // ------------------------
    // Model
    // ------------------------

    public Object? get_item(uint position) {
        return this.items.get(position);
    }

    public Type get_item_type() {
        return typeof(Geary.App.Conversation);
    }

    public uint get_n_items() {
        return this.items.length;
    }

    private bool insert_conversation(Geary.App.Conversation convo) {
        // The conversation may be bogus, if so don't do anything
        Geary.Email? last_email = convo.get_latest_recv_email(Geary.App.Conversation.Location.ANYWHERE);

        if (last_email == null) {
            debug("Cannot add conversation: last email is null");
            return false;
        }

        this.items.add(convo);

        return true;
    }

    private GenericArray<uint> conversations_indexes(Gee.Collection<Geary.App.Conversation> conversations) {
        GenericArray<uint> indexes = new GenericArray<uint>();
        uint index;

        foreach (Geary.App.Conversation convo in conversations) {
            if (this.items.find(convo, out index)) {
                indexes.add(index);
            }
        }

        return indexes;
    }

    private void update_added(GenericArray<uint> indexes) {
        indexes.sort((a, b) => {
            return (int) (a > b) - (int) (a < b);
        });

        while (indexes.length > 0) {
            uint? last_index = null;
            uint count = 0;
            foreach (unowned uint index in indexes) {
                if (last_index != null && index > last_index + 1) {
                    break;
                }
                last_index = (int) index;
                count++;
            }
            this.items_changed(indexes[0], 0, count);
            indexes.remove_range(0, count);
        }
    }

    private void update_removed(GenericArray<uint> indexes) {
        indexes.sort((a, b) => {
            return (int) (a < b) - (int) (a > b);
        });

        while (indexes.length > 0) {
            uint? last_index = null;
            uint count = 0;
            foreach (unowned uint index in indexes) {
                if (last_index != null && index < last_index - 1) {
                    break;
                }
                last_index = index;
                count++;
            }
            this.items_changed(last_index, count, 0);
            indexes.remove_range(0, count);
        }
    }

    private void on_conversations_added(Gee.Collection<Geary.App.Conversation> conversations) {
        debug("Adding %d conversations.", conversations.size);

        conversations_added(true);

        var added = 0;
        foreach (Geary.App.Conversation convo in conversations) {
            if (insert_conversation(convo)) {
                added++;
            }
        }
        this.items.sort(compare);

        GenericArray<uint> indexes = conversations_indexes(conversations);
        update_added(indexes);

        conversations_added(false);

        debug("Added %d/%d conversations.", added, conversations.size);
    }

    private void on_conversations_removed(Gee.Collection<Geary.App.Conversation> conversations) {
        GenericArray<uint> indexes = conversations_indexes(conversations);

        debug("Removing %d conversations.", conversations.size);

        conversations_removed(true);

        var removed = 0;
        foreach (Geary.App.Conversation convo in conversations) {
            this.items.remove(convo);
            removed++;
        }

        update_removed(indexes);

        conversations_removed(false);

        debug("Removed %ld/%d conversations.", removed, conversations.size);
    }

    private void on_conversation_updated(Geary.App.ConversationMonitor sender, Geary.App.Conversation convo, Gee.Collection<Geary.Email> emails) {
        conversation_updated(convo);

        uint initial_index;
        if (!this.items.find(convo, out initial_index)) {
            return;
        }

        this.items.sort(compare);

        uint final_index;
        if (!this.items.find(convo, out final_index) || initial_index == final_index) {
            return;
        }

        uint count = initial_index > final_index ?
            initial_index + 1 - final_index :
            final_index + 1 - initial_index;
        this.items_changed(uint.min(initial_index, final_index), count, count);
    }
}
