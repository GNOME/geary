/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractFolder : Object, Geary.Folder {
    protected virtual void notify_opened(Geary.Folder.OpenState state) {
        opened(state);
    }
    
    protected virtual void notify_closed(Geary.Folder.CloseReason reason) {
        closed(reason);
    }
    
    protected virtual void notify_messages_appended(int total) {
        messages_appended(total);
    }
    
    protected virtual void notify_message_removed(int position, int total) {
        message_removed(position, total);
    }
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.FolderProperties? get_properties();
    
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async int get_email_count_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async void create_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    public virtual void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        EmailCallback cb, Cancellable? cancellable = null) {
        do_lazy_list_email_async.begin(low, count, required_fields, cb, cancellable);
    }
    
    private async void do_lazy_list_email_async(int low, int count, Geary.Email.Field required_fields,
        EmailCallback cb, Cancellable? cancellable = null) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_async(low, count, required_fields,
                cancellable);
            
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    public virtual void lazy_list_email_sparse(int[] by_position,
        Geary.Email.Field required_fields, EmailCallback cb, Cancellable? cancellable = null) {
        do_lazy_list_email_sparse_async.begin(by_position, required_fields, cb, cancellable);
    }
    
    private async void do_lazy_list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, EmailCallback cb, Cancellable? cancellable = null) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_sparse_async(by_position,
                required_fields, cancellable);
            
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch(Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    public abstract async void remove_email_async(int position, Cancellable? cancellable = null)
        throws Error;
    
    public virtual string to_string() {
        return get_path().to_string();
    }
}

