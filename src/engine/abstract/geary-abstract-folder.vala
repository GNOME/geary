/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.AbstractFolder : BaseObject, Geary.Folder {
    public Geary.ProgressMonitor opening_monitor { get; protected set; }
    
    public abstract Geary.Account account { get; }
    
    public abstract Geary.FolderProperties properties { get; }
    
    public abstract Geary.FolderPath path { get; }
    
    public abstract Geary.SpecialFolderType special_folder_type { get; }
    
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
    
    internal virtual void notify_email_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_inserted(ids);
    }
    
    internal virtual void notify_email_locally_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_inserted(ids);
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
    
    internal virtual void notify_email_locally_complete(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_complete(ids);
    }
    
    internal virtual void notify_special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        special_folder_type_changed(old_type, new_type);
        
        // in default implementation, this may also mean the display name changed; subclasses may
        // override this behavior, but no way to detect this, so notify
        if (special_folder_type != Geary.SpecialFolderType.NONE)
            notify_display_name_changed();
    }
    
    internal virtual void notify_display_name_changed() {
        display_name_changed();
    }
    
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
    
    public abstract async void find_boundaries_async(Gee.Collection<Geary.EmailIdentifier> ids,
        out Geary.EmailIdentifier? low, out Geary.EmailIdentifier? high,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return "%s:%s".printf(account.to_string(), path.to_string());
    }
}

