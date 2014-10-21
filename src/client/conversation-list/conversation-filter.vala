/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationFilter : Gtk.TreeModelFilter {
    private bool filter_unread = false;
    private bool filter_starred = false;
    private Gee.HashSet<Geary.App.Conversation> filtered_conversations;
    
    public signal void conversations_added_began();
    
    public signal void conversations_added_finished();
    
    public ConversationFilter(ConversationListStore conversation_list_store) {
        Object(child_model: conversation_list_store, virtual_root: null);
        
        filtered_conversations = new Gee.HashSet<Geary.App.Conversation>();
        
        set_visible_func(filter_func);
        
        conversation_list_store.conversations_added_began.connect(on_conversations_added_began);
        conversation_list_store.conversations_added_finished.connect(on_conversations_added_finished);
    }
    
    public void set_starred_filter(bool enabled) {
        filter_starred = enabled;
        filtered_conversations.clear();
        refilter();
    }
    
    public void set_unread_filter(bool enabled) {
        filter_unread = enabled;
        filtered_conversations.clear();
        refilter();
    }
    
    private bool filter_func(Gtk.TreeModel model, Gtk.TreeIter iter) {
        Geary.App.Conversation conversation;
        model.get(iter, ConversationListStore.Column.CONVERSATION_OBJECT, out conversation);
        
        bool pass = ( (!filter_starred || conversation.is_flagged()) &&
                      (!filter_unread || conversation.is_unread()) );
        if (pass) {
            // Remember this conversation until filtering conditions change
            filtered_conversations.add(conversation);
        } else {
            // Keep the conversation visible until filtering conditions change, even if user alters
            // conversation's attributes so that the conversation would be filtered out
            pass = filtered_conversations.contains(conversation);
        }
        
        return pass;
    }
    
    private void on_conversations_added_began() {
        conversations_added_began();
    }
    
    private void on_conversations_added_finished() {
        conversations_added_finished();
    }
    
    public Geary.App.Conversation? get_conversation_at_path(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        return get_conversation_at_iter(iter);
    }
    
    private Geary.App.Conversation? get_conversation_at_iter(Gtk.TreeIter iter) {
        Geary.App.Conversation? conversation;
        get(iter, ConversationListStore.Column.CONVERSATION_OBJECT, out conversation);
        
        return conversation;
    }
    
    public Gtk.TreePath? get_path_for_conversation(Geary.App.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!get_iter_for_conversation(conversation, out iter))
            return null;
        
        return get_path(iter);
    }
    
    private bool get_iter_for_conversation(Geary.App.Conversation conversation, out Gtk.TreeIter iter) {
        if (!get_iter_first(out iter))
            return false;
        
        do {
            if (get_conversation_at_iter(iter) == conversation)
                return true;
        } while (iter_next(ref iter));
        
        return false;
    }
}

