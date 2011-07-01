/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractAccount : Object, Geary.Account {
    private string name;
    
    public AbstractAccount(string name) {
        this.name = name;
    }
    
    protected virtual void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        folders_added_removed(added, removed);
    }
    
    public abstract Geary.Email.Field get_required_fields_for_writing();
    
    public abstract async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return name;
    }
}

