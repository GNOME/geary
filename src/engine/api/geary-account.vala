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
    
    public signal void report_problem(Geary.Account.Problem problem, Geary.Credentials? credentials,
        Error? err);
    
    public signal void folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
    protected abstract void notify_report_problem(Geary.Account.Problem problem,
        Geary.Credentials? credentials, Error? err);
    
    protected abstract void notify_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed);
    
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
    
    /**
     * Lists all the folders found under the parent path unless it's null, in which case it lists
     * all the root folders.  If the parent path cannot be found, EngineError.NOT_FOUND is thrown.
     * If no folders exist in the root, EngineError.NOT_FOUND may be thrown as well.  However,
     * the caller should be prepared to deal with an empty list being returned instead.
     */
    public abstract async Gee.Collection<Geary.Folder> list_folders_async(Geary.FolderPath? parent,
        Cancellable? cancellable = null) throws Error;
    
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
     */
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    public abstract string to_string();
}

