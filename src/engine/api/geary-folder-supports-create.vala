/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Create interface on a {@link Geary.Folder} indicates it supports
 * creating email.
 *
 * Created emails are uploaded to the Folder and stored there.
 *
 * Note that creating an email in the Outbox will queue it for sending.  Thus, it may be removed
 * without user interaction at some point in the future.
 */

public interface Geary.FolderSupport.Create : Geary.Folder {
    /**
     *  Creates (appends) the message to this folder.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * The optional {@link EmailFlags} allows for those flags to be set when saved.  Some Folders
     * may ignore those flags (i.e. Outbox) if not applicable.
     *
     * The optional DateTime allows for the message's "date received" time to be set when saved.
     * Like EmailFlags, this is optional if not applicable.
     * 
     * If an id is passed, this will replace the existing message by deleting it after the new
     * message is created.  The new message's ID is returned.
     */
    public abstract async Geary.EmailIdentifier? create_email_async(Geary.RFC822.Message rfc822, EmailFlags? flags,
        DateTime? date_received, Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error;
}

