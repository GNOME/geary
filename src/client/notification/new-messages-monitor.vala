/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// NewMessagesMonitor is a central data store for new message information that the various
// notification methods (libnotify, libindicate, libunity, etc.) can monitor to do their thing.
// Subclasses should trap the "notify::count" signal and use that to perform whatever magic
// they need for their implementation, or trap "new-messages" to receive notifications of the emails
// themselves as they're added.  In the latter case, subscribers should add required Email.Field
// flags to the object with add_required_fields().

public class NewMessagesMonitor : Object {
    public delegate bool ShouldNotifyNewMessages();
    
    public Geary.Folder folder { get; private set; }
    public int count { get; private set; default = 0; }
    public Geary.Email? last_new_message { get; private set; default = null; }
    public Geary.Email.Field required_fields { get; private set; default = Geary.Email.Field.FLAGS; }
    
    private unowned ShouldNotifyNewMessages? should_notify_new_messages;
    private Cancellable? cancellable;
    private Gee.HashSet<Geary.EmailIdentifier> new_ids = new Gee.HashSet<Geary.EmailIdentifier>(
        Geary.Hashable.hash_func, Geary.Equalable.equal_func);
    
    public signal void new_messages_arrived();
    
    public signal void new_messages_retired();
    
    public NewMessagesMonitor(Geary.Folder folder, ShouldNotifyNewMessages? should_notify_new_messages,
        Cancellable? cancellable) {
        this.folder = folder;
        this.should_notify_new_messages = should_notify_new_messages;
        this.cancellable = cancellable;
        
        folder.email_locally_appended.connect(on_email_locally_appended);
        folder.email_flags_changed.connect(on_email_flags_changed);
        folder.email_removed.connect(on_email_removed);
    }
    
    ~NewMessagesMonitor() {
        folder.email_locally_appended.disconnect(on_email_locally_appended);
        folder.email_flags_changed.disconnect(on_email_flags_changed);
        folder.email_removed.disconnect(on_email_removed);
    }
    
    public void add_required_fields(Geary.Email.Field fields) {
        required_fields |= fields;
    }
    
    public bool are_any_new_messages(Gee.Collection<Geary.EmailIdentifier> ids) {
        foreach (Geary.EmailIdentifier id in ids) {
            if (new_ids.contains(id))
                return true;
        }
        
        return false;
    }
    
    private void on_email_locally_appended(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        do_process_new_email.begin(email_ids);
    }
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ids) {
        retire_new_messages(ids.keys);
    }
    
    private void on_email_removed(Gee.Collection<Geary.EmailIdentifier> ids) {
        retire_new_messages(ids);
    }
    
    private async void do_process_new_email(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        if (should_notify_new_messages != null && !should_notify_new_messages())
            return;
        
        try {
            Gee.List<Geary.Email>? list = yield folder.list_email_by_sparse_id_async(email_ids,
                required_fields, Geary.Folder.ListFlags.NONE, cancellable);
            if (list == null || list.size == 0) {
                debug("Warning: %d new emails, but none could be listed", email_ids.size);
                
                return;
            }
            
            new_messages(list);
            
            debug("do_process_new_email: %d messages listed, %d unread", list.size, count);
        } catch (Error err) {
            debug("Unable to notify of new email: %s", err.message);
        }
    }
    
    private void new_messages(Gee.Collection<Geary.Email> emails) {
        foreach (Geary.Email email in emails) {
            if (!email.fields.fulfills(required_fields)) {
                debug("Warning: new message %s (%Xh) does not fulfill NewMessagesMonitor required fields of %Xh",
                    email.id.to_string(), email.fields, required_fields);
            }
            
            if (new_ids.contains(email.id))
                continue;
            
            if (!email.email_flags.is_unread())
                continue;
            
            if (last_new_message == null || last_new_message.position < email.position)
                last_new_message = email;
            
            new_ids.add(email.id);
        }
        
        update_count(true);
    }
    
    private void retire_new_messages(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        foreach (Geary.EmailIdentifier email_id in email_ids) {
            if (last_new_message != null && last_new_message.id.equals(email_id))
                last_new_message = null;
            
            new_ids.remove(email_id);
        }
        
        update_count(false);
    }
    
    public void clear_new_messages() {
        new_ids.clear();
        last_new_message = null;
        
        update_count(false);
    }
    
    private void update_count(bool arrived) {
        // Documentation for "notify" signal seems to suggest that it's possible for the signal to
        // fire even if the value of the property doesn't change.  Since this signal can trigger
        // big events, want to avoid firing it unless necessary
        if (count == new_ids.size)
            return;
        
        count = new_ids.size;
        if (arrived)
            new_messages_arrived();
        else
            new_messages_retired();
    }
}

