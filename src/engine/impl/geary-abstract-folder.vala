/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractFolder : Object, Geary.Folder {
    /*
     * notify_* methods for AbstractFolder are marked internal because the SendReplayOperations
     * need access to them to report changes as they occur.
     */
    
    internal virtual void notify_opened(Geary.Folder.OpenState state, int count) {
        opened(state, count);
    }
    
    internal virtual void notify_open_failed(Geary.Folder.OpenFailed failure, Error? err) {
        open_failed(failure, err);
    }
    
    internal virtual void notify_closed(Geary.Folder.CloseReason reason) {
        closed(reason);
    }
    
    internal virtual void notify_email_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_appended(ids);
    }
    
    internal virtual void notify_email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_appended(ids);
    }
    
    internal virtual void notify_email_removed(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_removed(ids);
    }
    
    internal virtual void notify_email_count_changed(int new_count, Folder.CountChangeReason reason) {
        email_count_changed(new_count, reason);
    }
    
    internal virtual void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map) {
        email_flags_changed(flag_map);
    }
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.Trillian has_children();
    
    public abstract Geary.SpecialFolderType? get_special_folder_type();
    
    public abstract Geary.Folder.OpenState get_open_state();
    
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
    
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public abstract void lazy_list_email_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
    public abstract async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
    
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

    public abstract async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error;

    public abstract async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error;

    public virtual string to_string() {
        return get_path().to_string();
    }
}

