/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListStore : Gtk.TreeStore {
    
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.PROPERTIES;
    
    public enum Column {
        MESSAGE_DATA,
        MESSAGE_OBJECT,
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                MESSAGE_DATA,
                MESSAGE_OBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (FormattedMessageData), // MESSAGE_DATA
                typeof (Geary.Conversation)    // MESSAGE_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case MESSAGE_DATA:
                    return "data";
                case MESSAGE_OBJECT:
                    return "envelope";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public MessageListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(TreeSortable.DEFAULT_SORT_COLUMN_ID, Gtk.SortType.DESCENDING);
    }
    
    // The Email should've been fetched with REQUIRED_FIELDS.
    public void append_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        
        if (pool != null && pool.size > 0)
            set(iter,
                Column.MESSAGE_DATA, new FormattedMessageData.from_email(pool.first(), pool.size),
                Column.MESSAGE_OBJECT, conversation
            );
    }
    
    public void update_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!find_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            append_conversation(conversation);
            
            return;
        }
        
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        if (pool == null) {
            // empty conversation, remove from store
            remove_conversation(conversation);
            
            return;
        }
        
        Geary.Email preview = pool.first();
        
        FormattedMessageData? existing = null;
        get(iter, Column.MESSAGE_DATA, out existing);
        
        // Update the preview if needed.
        if (existing == null || !existing.email.id.equals(preview.id))
            set(iter, Column.MESSAGE_DATA, new FormattedMessageData.from_email(preview, pool.size)); 
    }
    
    public void remove_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!find_conversation(conversation, out iter)) {
            // unknown, nothing to do here
            return;
        }
        
        if (!remove(iter))
            debug("Unable to remove conversation from MessageListStore");
    }
    
    public bool has_conversation(Geary.Conversation conversation) {
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            if (conversation == get_conversation_at_index(ctr))
                return true;
        }
        
        return false;
    }
    
    public Geary.Conversation? get_conversation_at_index(int index) {
        return get_conversation_at(new Gtk.TreePath.from_indices(index, -1));
    }
    
    public Geary.Email? get_newest_message_at_index(int index) {
        Geary.Conversation? c = get_conversation_at_index(index);
        if (c == null)
            return null;
        
        Gee.SortedSet<Geary.Email>? pool = c.get_pool_sorted(compare_email);
        
        return pool != null ? pool.first() : null;
    }
    
    public void set_preview_at_index(int index, Geary.Email email) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, new Gtk.TreePath.from_indices(index, -1))) {
            warning("Unable to get tree path from position: %d".printf(index));
            
            return;
        }
        
        int num_emails = 1;
        Geary.Conversation? c = get_conversation_at_index(index);
        if (c != null) {
            Gee.Set<Geary.Email>? list = c.get_pool();
            if (list != null)
                num_emails = list.size;
        }
        
        set(iter, Column.MESSAGE_DATA, new FormattedMessageData.from_email(email, num_emails));
    }
    
    public int get_count() {
        return iter_n_children(null);
    }
    
    public Geary.Conversation? get_conversation_at(Gtk.TreePath path) {
       Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.Conversation? conversation;
        get(iter, Column.MESSAGE_OBJECT, out conversation);
        
        return conversation;
    }
    
    public Geary.EmailIdentifier? get_email_id_lowest() {
        Geary.EmailIdentifier? low = null;
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Conversation c = get_conversation_at_index(ctr);
            Gee.SortedSet<Geary.Email>? mail = c.get_pool_sorted(compare_email_id_desc);
            if (mail == null)
                continue;
            
            Geary.EmailIdentifier pos = mail.first().id;
            if (low == null || pos.ordering < low.ordering)
                low = pos;
        }
        
        return low;
    }
    
    private bool find_conversation(Geary.Conversation conversation, out Gtk.TreeIter iter) {
        iter = Gtk.TreeIter();
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            if (conversation == get_conversation_at_index(ctr))
                return get_iter(out iter, new Gtk.TreePath.from_indices(ctr, -1));
        }
        
        return false;
    }
    
    private int sort_by_date(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        Geary.Conversation a, b;
        
        get(aiter, Column.MESSAGE_OBJECT, out a);
        get(biter, Column.MESSAGE_OBJECT, out b);
        
        Gee.SortedSet<Geary.Email>? apool = a.get_pool_sorted(compare_email);
        Gee.SortedSet<Geary.Email>? bpool = b.get_pool_sorted(compare_email);
        
        if (apool == null || apool.first() == null)
            return -1;
        else if (bpool == null || bpool.first() == null)
            return 1;
        
        return compare_email(apool.first(), bpool.first());
    }
}

