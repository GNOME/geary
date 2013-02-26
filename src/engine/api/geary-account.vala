/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Account : Object {
    public enum Problem {
        RECV_EMAIL_LOGIN_FAILED,
        SEND_EMAIL_LOGIN_FAILED,
        HOST_UNREACHABLE,
        NETWORK_UNAVAILABLE,
        DATABASE_FAILURE
    }
    
    public abstract Geary.AccountInformation information { get; protected set; }
    
    public signal void opened();
    
    public signal void closed();
    
    public signal void email_sent(Geary.RFC822.Message rfc822);
    
    public signal void report_problem(Geary.Account.Problem problem, Error? err);
    
    /**
     * Fired when folders become available or unavailable in the account.
     * Folders become available when the account is first opened or when
     * they're created later; they become unavailable when the account is
     * closed or they're deleted later.
     */
    public signal void folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable);

    /**
     * Fired when folders are created or deleted.
     */
    public signal void folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
    /**
     * Fired when a Folder's contents is detected having changed.
     */
    public signal void folders_contents_altered(Gee.Collection<Geary.Folder> altered);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_opened();
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_closed();
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_email_sent(Geary.RFC822.Message rfc822);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_report_problem(Geary.Account.Problem problem, Error? err);
    
    /**
     * Signal notification method for subclasses to use.
     */
    public abstract void notify_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable);

    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_contents_altered(Gee.Collection<Geary.Folder> altered);
    
    /**
     *
     */
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;
    
    /**
     *
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns true if this account is open, else false.
     */
    public abstract bool is_open();
    
    /**
     * Lists all the currently-available folders found under the parent path
     * unless it's null, in which case it lists all the root folders.  If the
     * parent path cannot be found, EngineError.NOT_FOUND is thrown.  If no
     * folders exist in the root, EngineError.NOT_FOUND may be thrown as well.
     * However, the caller should be prepared to deal with an empty list being
     * returned instead.
     *
     * The same Geary.Folder objects (instances) will be returned if the same path is submitted
     * multiple times.  This means that multiple callers may be holding references to the same
     * Folders.  This is important when thinking of opening and closing folders and signal
     * notifications.
     */
    public abstract Gee.Collection<Geary.Folder> list_matching_folders(
        Geary.FolderPath? parent) throws Error;
    
    /**
     * Lists all currently-available folders.  See caveats under
     * list_matching_folders().
     */
    public abstract Gee.Collection<Geary.Folder> list_folders() throws Error;
    
    /**
     * Gets a perpetually update-to-date collection of autocompletion contacts.
     */
    public abstract Geary.ContactStore get_contact_store();

    /**
     * Returns true if the folder exists.
     *
     * This method never throws EngineError.NOT_FOUND.
     */
    public abstract async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Fetches a Folder object corresponding to the supplied path.  If the backing medium does
     * not have a record of a folder at the path, EngineError.NOT_FOUND will be thrown.
     *
     * The same Geary.Folder object (instance) will be returned if the same path is submitted
     * multiple times.  This means that multiple callers may be holding references to the same
     * Folders.  This is important when thinking of opening and closing folders and signal
     * notifications.
     */
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns the folder representing the given special folder type.  If no such folder exists,
     * null is returned.
     */
    public abstract Geary.Folder? get_special_folder(Geary.SpecialFolderType special) throws Error;
    
    /**
     * Submits a ComposedEmail for delivery.  Messages may be scheduled for later delivery or immediately
     * sent.  Subscribe to the "email-sent" signal to be notified of delivery.  Note that that signal
     * does not return the ComposedEmail object but an RFC822-formatted object.  Allowing for the
     * subscriber to attach some kind of token for later comparison is being considered.
     */
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Search the local account for emails with a matching Message-ID header.
     * Fetch the requested fields, optionally ignoring emails that don't have
     * the requested fields set.  Don't include any of the blacklisted folders
     * in the result.  Return a map of Email object to a list of FolderPaths
     * it's in, which can be null if it's in no folders (note that emails only
     * in blacklisted folders won't show up at all).
     */
    public abstract async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath>? folder_blacklist, Cancellable? cancellable = null) throws Error;

    /**
     * Used only for debugging.  Should not be used for user-visible strings.
     */
    public abstract string to_string();
}

