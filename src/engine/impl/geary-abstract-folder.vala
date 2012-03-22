/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractFolder : Object, Geary.Folder {
    protected virtual void notify_opened(Geary.Folder.OpenState state, int count) {
        opened(state, count);
    }
    
    protected virtual void notify_closed(Geary.Folder.CloseReason reason) {
        closed(reason);
    }
    
    internal virtual void notify_messages_appended(int total) {
        messages_appended(total);
    }
    
    internal virtual void notify_message_removed(Geary.EmailIdentifier id) {
        message_removed(id);
    }
    
    internal virtual void notify_email_count_changed(int new_count, Folder.CountChangeReason reason) {
        email_count_changed(new_count, reason);
    }
    
    internal virtual void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map) {
        email_flags_changed(flag_map);
    }
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.Folder.ListFlags get_supported_list_flags();
    
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async int get_email_count_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async bool create_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null);
    
    public abstract async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract void lazy_list_email_sparse(int[] by_position,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids, 
        Cancellable? cancellable = null) throws Error;
    
    public virtual async void remove_single_email_async(Geary.EmailIdentifier email_id,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        list.add(email_id);
        
        yield remove_email_async(list, cancellable);
    }
    
    public abstract async void mark_email_async(
        Gee.List<Geary.EmailIdentifier> to_mark, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return get_path().to_string();
    }
}

