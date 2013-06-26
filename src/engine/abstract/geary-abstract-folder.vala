/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.AbstractFolder : BaseObject, Geary.Folder {
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
    
    internal virtual void notify_special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        special_folder_type_changed(old_type, new_type);
    }

    public abstract Geary.Account account { get; }
    
    public abstract Geary.FolderProperties properties { get; }
    
    public abstract Geary.FolderPath path { get; }
    
    public abstract Geary.SpecialFolderType special_folder_type { get; }
    
    /**
     * Default is to display the basename of the Folder's path.
     */
    public virtual string get_display_name() {
        return (special_folder_type == Geary.SpecialFolderType.NONE)
            ? path.basename : special_folder_type.get_display_name();
    }
    
    public abstract Geary.Folder.OpenState get_open_state();
    
    public abstract async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async void wait_for_open_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
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
    
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public virtual void lazy_list_email_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_sparse_id_async.begin(ids, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable) {
        try {
            Gee.List<Geary.Email>? list = yield list_email_by_sparse_id_async(ids,
                required_fields, flags, cancellable);
            if (list != null && list.size > 0)
                cb(list, null);
            
            cb(null, null);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    public abstract async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return "%s:%s".printf(account.to_string(), path.to_string());
    }
}

