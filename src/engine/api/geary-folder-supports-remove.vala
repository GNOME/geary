/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupportsRemove interface to a Geary.Folder indicates that it
 * supports a remove email operation.  This generally means that the message is deleted from the
 * server and is not recoverable.  It may mean the message is moved to a Trash folder where it may
 * or may not be automatically deleted some time later.
 *
 * The remove operation is distinct from the archive operation, available via
 * Geary.FolderSupportsArchive.
 */
public interface Geary.FolderSupportsRemove : Geary.Folder {
    /**
     * Removes the specified emails from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Removes one email from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public virtual async void remove_single_email_async(Geary.EmailIdentifier email_id,
        Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>(
            Equalable.equal_func);
        ids.add(email_id);
        
        yield remove_email_async(ids, cancellable);
    }
}

