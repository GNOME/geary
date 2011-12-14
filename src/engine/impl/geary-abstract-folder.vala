/* Copyright 2011 Yorba Foundation
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
    
    protected virtual void notify_messages_appended(int total) {
        messages_appended(total);
    }
    
    protected virtual void notify_message_removed(Geary.EmailIdentifier id) {
        message_removed(id);
    }
    
    protected virtual void notify_email_count_changed(int new_count, Folder.CountChangeReason reason) {
        email_count_changed(new_count, reason);
    }
    
    protected virtual void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map) {
        email_flags_changed(flag_map);
    }
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.FolderProperties? get_properties();
    
    public abstract Geary.Folder.ListFlags get_supported_list_flags();
    
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async int get_email_count_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async void create_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public virtual void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        do_lazy_list_email_async.begin(low, count, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_async(int low, int count, Geary.Email.Field required_fields,
        Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_async(low, count, required_fields, flags,
                cancellable);
            
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public virtual void lazy_list_email_sparse(int[] by_position,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_sparse_async.begin(by_position, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_sparse_async(by_position,
                required_fields, flags, cancellable);
            
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch(Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public virtual void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_id_async.begin(initial_id, count, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_by_id_async(initial_id, count,
                required_fields, flags, cancellable);
            
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    public abstract async void remove_email_async(Geary.EmailIdentifier email_id, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> mark_email_async(
        Gee.List<Geary.EmailIdentifier> to_mark, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return get_path().to_string();
    }
}

