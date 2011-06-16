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

public interface Geary.NetworkAccount : Object, Geary.Account {
}

public interface Geary.LocalAccount : Object, Geary.Account {
}

