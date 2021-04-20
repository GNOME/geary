// The whole goal of this class to wrap the ConversationMonitor with a view that presents a sorted list
public class ConversationList.Model {
    internal ListStore store = new ListStore(typeof(Geary.App.Conversation));
    internal Geary.App.ConversationMonitor monitor { get; set; }

    internal Model (Geary.App.ConversationMonitor monitor) {
        this.monitor = monitor;
        foreach (Geary.App.Conversation convo in monitor.read_only_view) {
            insert(convo);
        }

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

    /**
     * Informs observers that batch of updates is complete.
     *
     * GTK's ListModel interface reports updates as additions and subtractions
     * at a specific index, meaning the results of a scan can require several
     * invocations of items_changed. This signal allows consumers to know when
     * those invocations have stopped.
     */
    internal signal void update_complete();

    private static int compare(Object a, Object b) {
        return Util.Email.compare_conversation_descending(a as Geary.App.Conversation, b as Geary.App.Conversation);
    }

    private void insert(Geary.App.Conversation convo)  {
        store.insert_sorted(convo, compare);
    }

    // ------------------------
    //  Scanning and load_more
    // ------------------------
    private bool scanning = false;

    private void on_scan_started(Geary.App.ConversationMonitor source) {
        scanning = true;
    }
    private void on_scan_completed(Geary.App.ConversationMonitor source) {
        scanning = false;
        update_complete();
    }

    public bool load_more(int amount) {
        if (scanning) {
            return false;
        }

        this.monitor.min_window_count += amount;
        return true;
    }


    // Monitor Lifecycle handles
    private void on_conversations_added(Gee.Collection<Geary.App.Conversation> conversations) {
        debug("Adding %d conversations.", conversations.size);
        int added = 0;
        foreach (Geary.App.Conversation conversation in conversations) {
            if (upsert_conversation(conversation)) {
                added++;
            }
        }
        debug("Added %d/%d conversations.", added, conversations.size);
    }

    private void on_conversations_removed(Gee.Collection<Geary.App.Conversation> conversations) {
        debug("Removing %d conversations.", conversations.size);
        int removed = 0;
        foreach (Geary.App.Conversation conversation in conversations) {
            if (remove_conversation(conversation)) {
                removed++;
            }
        }
        debug("Removed %d/%d conversations.", removed, conversations.size);
    }

    private void on_conversation_updated(Geary.App.ConversationMonitor sender, Geary.App.Conversation convo, Gee.Collection<Geary.Email> emails) {
        upsert_conversation(convo);
    }

    // Monitor helpers
    private bool upsert_conversation(Geary.App.Conversation convo) {
        // The conversation may be bogus, if so don't do anything
        Geary.Email? last_email = convo.get_latest_recv_email(Geary.App.Conversation.Location.ANYWHERE);

        if (last_email == null) {
            debug("Cannot add conversation: last email is null");
            return false;
        }

        remove_conversation(convo);
        insert(convo);

        return true;
    }

    private bool remove_conversation(Geary.App.Conversation conversation) {
        uint index;
        if (store.find(conversation, out index)) {
            store.remove(index);
            return true;
        }

        return false;
    }

}
