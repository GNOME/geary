/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractAccount : Object, Geary.Account {
    private string name;
    
    public AbstractAccount(string name) {
        this.name = name;
    }
    
    public virtual void notify_report_problem(Geary.Account.Problem problem,
        Geary.Credentials? credentials, Error? err) {
        report_problem(problem, credentials, err);
    }
    
    protected virtual void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        folders_added_removed(added, removed);
    }
    
    protected virtual void notify_opened() {
        opened();
    }
    
    protected virtual void notify_closed() {
        closed();
    }
    
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error;
    
    public abstract Geary.ContactStore get_contact_store();
    
    public abstract async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return name;
    }
}

