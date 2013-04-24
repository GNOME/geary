/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupportsCreate interface on a Folder indicates the create email
 * operation is supported.  Created emails are uploaded to the Folder and stored there.
 *
 * Note that creating an email in the Outbox will queue it for sending.  Thus, it may be removed
 * without user interaction at some point the future.
 */
public interface Geary.FolderSupportsCreate : Geary.Folder {
    public enum Result {
        CREATED,
        MERGED
    }
    
    /**
     * Creates a message in the folder.  If the message already exists in the Folder, it will be
     * merged (that is, fields in the message not already present will be added).  Not all folders
     * support merging.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Result create_email_async(Geary.RFC822.Message rfc822, Cancellable? cancellable = null)
        throws Error;
}
