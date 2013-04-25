/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// NewMessagesMonitor is a central data store for new message information that the various
// notification methods (libnotify, libunity, etc.) can monitor to do their thing.
// Subclasses should trap the "notify::count" signal and use that to perform whatever magic
// they need for their implementation, or trap "new-messages" to receive notifications of the emails
// themselves as they're added.  In the latter case, subscribers should add required Email.Field
// flags to the object with add_required_fields().

public class NewMessagesMonitor : Geary.BaseObject {
    public delegate bool ShouldNotifyNewMessages(Geary.Folder folder);
    
    private class MonitorInformation : Geary.BaseObject {
        public Geary.Folder folder;
        public Cancellable? cancellable = null;
        public int count = 0;
        public Gee.HashSet<Geary.EmailIdentifier> new_ids
            = new Gee.HashSet<Geary.EmailIdentifier>();
        
        public MonitorInformation(Geary.Folder folder, Cancellable? cancellable) {
            this.folder = folder;
            this.cancellable = cancellable;
        }
    }
    
    public Geary.Email.Field required_fields { get; private set; default = Geary.Email.Field.FLAGS; }
    public int total_count { get; private set; default = 0; }
    public Geary.Folder? last_new_message_folder { get; private set; default = null; }
    public Geary.Email? last_new_message { get; private set; default = null; }
    
    private Gee.HashMap<Geary.Folder, MonitorInformation> folder_information
        = new Gee.HashMap<Geary.Folder, MonitorInformation>();
    private unowned ShouldNotifyNewMessages? _should_notify_new_messages;
    
    public signal void folder_added(Geary.Folder folder);
    
    public signal void folder_removed(Geary.Folder folder);
    
    /**
     * Fired when the monitor finds new messages on a folder.  The count
     * argument is the updated count of new messages in that folder, not the
     * number of messages just added.
     */
    public signal void new_messages_arrived(Geary.Folder folder, int count);
    
    /**
     * Fired when the monitor clears the "new" status of some messages in the
     * folder.  The count argument is the updated count of new messages in that
     * folder, not the number of messages just retired.
     */
    public signal void new_messages_retired(Geary.Folder folder, int count);
    
    public NewMessagesMonitor(ShouldNotifyNewMessages? should_notify_new_messages) {
        _should_notify_new_messages = should_notify_new_messages;
    }
    
    public bool should_notify_new_messages(Geary.Folder folder) {
        return (_should_notify_new_messages == null ? true : _should_notify_new_messages(folder));
    }
    
    public void add_folder(Geary.Folder folder, Cancellable? cancellable = null) {
        assert(!folder_information.has_key(folder));
        
        folder.email_locally_appended.connect(on_email_locally_appended);
        folder.email_flags_changed.connect(on_email_flags_changed);
        folder.email_removed.connect(on_email_removed);
        
        folder_information.set(folder, new MonitorInformation(folder, cancellable));
        
        folder_added(folder);
    }
    
    public void remove_folder(Geary.Folder folder) {
        if (!folder_information.has_key(folder))
            return;
        
        folder.email_locally_appended.disconnect(on_email_locally_appended);
        folder.email_flags_changed.disconnect(on_email_flags_changed);
        folder.email_removed.disconnect(on_email_removed);
        
        total_count -= folder_information.get(folder).count;
        
        folder_information.unset(folder);
        
        folder_removed(folder);
    }
    
    public Gee.Collection<Geary.Folder> get_folders() {
        return folder_information.keys;
    }
    
    public int get_new_message_count(Geary.Folder folder) {
        assert(folder_information.has_key(folder));
        
        return folder_information.get(folder).count;
    }
    
    public void add_required_fields(Geary.Email.Field fields) {
        required_fields |= fields;
    }
    
    public bool are_any_new_messages(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids) {
        assert(folder_information.has_key(folder));
        MonitorInformation info = folder_information.get(folder);
        
        foreach (Geary.EmailIdentifier id in ids) {
            if (info.new_ids.contains(id))
                return true;
        }
        
        return false;
    }
    
    private void on_email_locally_appended(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        do_process_new_email.begin(folder, email_ids);
    }
    
    private void on_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ids) {
        retire_new_messages(folder, ids.keys);
    }
    
    private void on_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        retire_new_messages(folder, ids);
    }
    
    private async void do_process_new_email(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        MonitorInformation info = folder_information.get(folder);
        
        try {
            Gee.List<Geary.Email>? list = yield folder.list_email_by_sparse_id_async(email_ids,
                required_fields, Geary.Folder.ListFlags.NONE, info.cancellable);
            if (list == null || list.size == 0) {
                debug("Warning: %d new emails, but none could be listed", email_ids.size);
                
                return;
            }
            
            new_messages(info, list);
            
            debug("do_process_new_email: %d messages listed, %d unread in folder %s",
                list.size, info.count, folder.to_string());
        } catch (Error err) {
            debug("Unable to notify of new email: %s", err.message);
        }
    }
    
    private void new_messages(MonitorInformation info, Gee.Collection<Geary.Email> emails) {
        foreach (Geary.Email email in emails) {
            if (!email.fields.fulfills(required_fields)) {
                debug("Warning: new message %s (%Xh) does not fulfill NewMessagesMonitor required fields of %Xh",
                    email.id.to_string(), email.fields, required_fields);
            }
            
            if (info.new_ids.contains(email.id))
                continue;
            
            if (!email.email_flags.is_unread())
                continue;
            
            last_new_message_folder = info.folder;
            last_new_message = email;
            
            info.new_ids.add(email.id);
        }
        
        update_count(info, true);
    }
    
    private void retire_new_messages(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        MonitorInformation info = folder_information.get(folder);
        
        foreach (Geary.EmailIdentifier email_id in email_ids) {
            if (last_new_message != null && last_new_message.id.equal_to(email_id)) {
                last_new_message_folder = null;
                last_new_message = null;
            }
            
            info.new_ids.remove(email_id);
        }
        
        update_count(info, false);
    }
    
    public void clear_new_messages(Geary.Folder folder) {
        assert(folder_information.has_key(folder));
        MonitorInformation info = folder_information.get(folder);
        
        info.new_ids.clear();
        last_new_message_folder = null;
        last_new_message = null;
        
        update_count(info, false);
    }
    
    public void clear_all_new_messages() {
        foreach(Geary.Folder folder in folder_information.keys)
            clear_new_messages(folder);
    }
    
    private void update_count(MonitorInformation info, bool arrived) {
        int new_size = info.new_ids.size;
        
        // Documentation for "notify" signal seems to suggest that it's possible for the signal to
        // fire even if the value of the property doesn't change.  Since this signal can trigger
        // big events, want to avoid firing it unless necessary
        if (info.count == new_size)
            return;
        
        total_count += new_size - info.count;
        info.count = new_size;
        
        if (arrived)
            new_messages_arrived(info.folder, info.count);
        else
            new_messages_retired(info.folder, info.count);
    }
}

