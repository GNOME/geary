/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Account : Object {
    public signal void folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
    protected virtual void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        folders_added_removed(added, removed);
    }
    
    /**
     * This method returns which Geary.Email.Field fields must be available in a Geary.Email to
     * write (or save or store) the message to the backing medium.  Different implementations will
     * have different requirements, which must be reconciled.
     *
     * In this case, Geary.Email.Field.NONE means "any".
     *
     * If a write operation is attempted on an email that does not have all these fields fulfilled,
     * an EngineError.INCOMPLETE_MESSAGE will be thrown.
     */
    public abstract Geary.Email.Field get_required_fields_for_writing();
    
    public abstract async void create_folder_async(Geary.Folder? parent, Geary.Folder folder,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async void create_many_folders_async(Geary.Folder? parent,
        Gee.Collection<Geary.Folder> folders, Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.Collection<Geary.Folder> list_folders_async(Geary.Folder? parent,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Folder fetch_folder_async(Geary.Folder? parent, string folder_name,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async void remove_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async void remove_many_folders_async(Gee.Set<Geary.Folder> folders,
        Cancellable? cancellable = null) throws Error;
}

