/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Create interface on a
 * {@link Geary.Folder} indicates it supports creating email.
 *
 * Created emails are uploaded to the Folder and stored there.
 *
 * Note that creating an email in the Outbox will queue it for
 * sending.  Thus, it may be removed without user interaction at some
 * point in the future.
 */
public interface Geary.FolderSupport.Create : Folder {

    /**
     *  Creates (appends) the message to this folder.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * The optional {@link EmailFlags} allows for those flags to be
     * set when saved.  Some Folders may ignore those flags
     * (i.e. Outbox) if not applicable.
     *
     * The optional DateTime allows for the message's "date received"
     * time to be set when saved.  Like EmailFlags, this is optional
     * if not applicable.
     *
     * @see FolderProperties.create_never_returns_id
     */
    public abstract async EmailIdentifier?
        create_email_async(RFC822.Message rfc822,
                           EmailFlags? flags,
                           DateTime? date_received,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
