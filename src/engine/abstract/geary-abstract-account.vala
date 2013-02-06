/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.AbstractAccount : Object, Geary.Account {
    public Geary.AccountInformation information { get; protected set; }
    
    private string name;
    
    public AbstractAccount(string name, AccountInformation information) {
        this.name = name;
        this.information = information;
    }
    
    protected virtual void notify_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        folders_available_unavailable(available, unavailable);
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
    
    protected virtual void notify_email_sent(RFC822.Message message) {
        email_sent(message);
    }
    
    protected virtual void notify_report_problem(Geary.Account.Problem problem, Error? err) {
        report_problem(problem, err);
    }
    
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract bool is_open();
    
    public abstract Gee.Collection<Geary.Folder> list_matching_folders(
        Geary.FolderPath? parent) throws Error;
    
    public abstract Gee.Collection<Geary.Folder> list_folders() throws Error;
    
    public abstract Geary.ContactStore get_contact_store();
    
    public abstract async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
    
    public virtual string to_string() {
        return name;
    }
}

