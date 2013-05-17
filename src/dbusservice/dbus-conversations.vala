/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[DBus (name = "org.yorba.Geary.Conversations", timeout = 120000)]
public class Geary.DBus.Conversations : Object {
    public static const string INTERFACE_NAME = "org.yorba.Geary.Conversations";
    
    public signal void scan_started();
    
    public signal void scan_error();
    
    public signal void scan_completed();
    
    public signal void conversations_added(ObjectPath[] conversations);
    
    public signal void conversation_removed(ObjectPath conversation);
    
    public signal void conversation_appended(ObjectPath conversation, ObjectPath[] emails);
    
    public signal void conversation_trimmed(ObjectPath conversation, ObjectPath email);
    
    private Geary.Folder folder;
    private Geary.ConversationMonitor conversations;
    
    public Conversations(Geary.Folder folder) {
        this.folder = folder;
        conversations = new Geary.ConversationMonitor(folder, Geary.Folder.OpenFlags.NONE,
            Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS);
        
        start_monitoring_async.begin();
    }
    
    private async void start_monitoring_async() {
        try {
            yield conversations.start_monitoring_async(0);
        } catch (Error err) {
            debug("Unable to start monitoring %s for conversations: %s", folder.to_string(),
                err.message);
            
            return;
        }
        
        conversations.scan_started.connect(on_scan_started);
        conversations.scan_error.connect(on_scan_error);
        conversations.scan_completed.connect(on_scan_completed);
        conversations.conversations_added.connect(on_conversations_added);
        conversations.conversation_appended.connect(on_conversation_appended);
        conversations.conversation_trimmed.connect(on_conversation_trimmed);
        conversations.conversation_removed.connect(on_conversation_removed);
        
        folder.email_flags_changed.connect(on_email_flags_changed);
    }
    
    public void fetch_messages(int num_messages) throws IOError {
        conversations.load_async.begin(-1, num_messages, Geary.Folder.ListFlags.NONE, null);
    }
    
    private void on_scan_started() {
        scan_started();
    }
    
    private void on_scan_error(Error err) {
        scan_error();
    }
    
    private void on_scan_completed() {
        scan_completed();
    }
    
    private void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        debug("Conversation added: %d conversations", conversations.size);
        ObjectPath[] paths = new ObjectPath[0];
        
        foreach (Geary.Conversation c in conversations) {
            paths += new ObjectPath(Database.instance.get_conversation_path(c, folder));
        }
        
        conversations_added(paths);
    }
    
    private void on_conversation_removed(Geary.Conversation conversation) {
        debug("conversation removed");
        // Fire signal, then delete.
        ObjectPath path = Database.instance.get_conversation_path(conversation, folder);
        
        conversation_removed(path);
        Database.instance.remove_by_path(path);
    }
    
    private void on_conversation_appended(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email_list) {
        debug("conversation appended");
        
        ObjectPath[] email_paths = new ObjectPath[0];
        foreach (Geary.Email e in email_list)
            email_paths += Database.instance.get_email_path(e, folder);
        
        conversation_appended(Database.instance.get_conversation_path(conversation, folder),
            email_paths);
    }
    
    private void on_conversation_trimmed(Geary.Conversation conversation, Geary.Email email) {
        debug("conversation trimmed");
        // Fire signal, then delete.
        ObjectPath email_path = Database.instance.get_email_path(email, folder);
        conversation_trimmed(Database.instance.get_conversation_path(conversation, folder),
            email_path);
        Database.instance.remove_by_path(email_path);
    }
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        //TODO
    }
}

