/* Copyright 2012-2013 Yorba Foundation
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
    public enum Result {
        CREATED,
        MERGED
    }
    
    /**
     * Creates a message in the folder.  If the message already exists in the {@link Geary.Folder},
     * it will be merged (that is, fields in the message not already present will be added).
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Result create_email_async(Geary.RFC822.Message rfc822, Cancellable? cancellable = null)
        throws Error;
}
