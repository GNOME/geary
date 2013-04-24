/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of this interface to Geary.Folder indicates that this Folder supports an archive
 * operation (which may or may not be in addition to a remove operation via Geary.SupportsRemove).
 *
 * An archive operation acts like remove except that the mail is still available on the server,
 * usually in an All Mail folder and perhaps others.  It does not imply that the mail message was
 * moved to the Trash folder.
 */
public interface Geary.FolderSupportsArchive : Geary.Folder {
    /**
     * Archives the specified emails from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void archive_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Archive one email from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public virtual async void archive_single_email_async(Geary.EmailIdentifier email_id,
        Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>(
            Equalable.equal_func);
        ids.add(email_id);
        
        yield archive_email_async(ids, cancellable);
    }
}

