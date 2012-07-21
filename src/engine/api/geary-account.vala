/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Account : Object {
    public enum Problem {
        LOGIN_FAILED,
        HOST_UNREACHABLE,
        NETWORK_UNAVAILABLE,
        DATABASE_FAILURE
    }
    
    public signal void opened();
    
    public signal void closed();
    
    public signal void report_problem(Geary.Account.Problem problem, Geary.Credentials? credentials,
        Error? err);
    
    public signal void folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
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
    protected abstract void notify_report_problem(Geary.Account.Problem problem,
        Geary.Credentials? credentials, Error? err);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
    /**
     *
     */
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;
    
    /**
     *
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * Lists all the folders found under the parent path unless it's null, in which case it lists
     * all the root folders.  If the parent path cannot be found, EngineError.NOT_FOUND is thrown.
     * If no folders exist in the root, EngineError.NOT_FOUND may be thrown as well.  However,
     * the caller should be prepared to deal with an empty list being returned instead.
     *
     * The same Geary.Folder objects (instances) will be returned if the same path is submitted
     * multiple times.  This means that multiple callers may be holding references to the same
     * Folders.  This is important when thinking of opening and closing folders and signal
     * notifications.
     */
    public abstract async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error;
    
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
     * Used only for debugging.  Should not be used for user-visible strings.
     */
    public abstract string to_string();
}

