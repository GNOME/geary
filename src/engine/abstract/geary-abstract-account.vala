/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.AbstractAccount : BaseObject, Geary.Account {
    public Geary.AccountInformation information { get; protected set; }
    public Geary.ProgressMonitor search_upgrade_monitor { get; protected set; }
    
    private string name;
    
    public AbstractAccount(string name, AccountInformation information) {
        this.name = name;
        this.information = information;
    }
    
    protected virtual void notify_folders_available_unavailable(Gee.List<Geary.Folder>? available,
        Gee.List<Geary.Folder>? unavailable) {
        folders_available_unavailable(available, unavailable);
    }

    protected virtual void notify_folders_added_removed(Gee.List<Geary.Folder>? added,
        Gee.List<Geary.Folder>? removed) {
        folders_added_removed(added, removed);
    }
    
    protected virtual void notify_folders_contents_altered(Gee.Collection<Geary.Folder> altered) {
        folders_contents_altered(altered);
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
    
    public virtual Geary.Folder? get_special_folder(Geary.SpecialFolderType special) throws Error {
        foreach (Folder folder in list_folders()) {
            if (folder.get_special_folder_type() == special)
                return folder;
        }
        
        return null;
    }
    
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.Collection<Geary.EmailIdentifier>? local_search_async(string keywords,
        Geary.Email.Field requested_fields, bool partial_ok, Geary.FolderPath? email_id_folder_path,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error;
    
    public abstract async Gee.Collection<string>? get_search_keywords_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
    
    public virtual string to_string() {
        return name;
    }
}

