/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Remove interface to a
 * {@link Geary.Folder} indicates that it supports removing (deleting)
 * email.
 *
 * This generally means that the message is deleted from the server
 * and is not recoverable.  It _may_ mean the message is moved to a
 * Trash folder where it may or may not be automatically deleted some
 * time later; this behavior is server-specific and not always
 * determinable by Geary (or worked around, either).
 *
 * The remove operation is distinct from the archive operation,
 * available via {@link Geary.FolderSupport.Archive}.
 *
 * A Folder that does not support Remove does not imply that email
 * might not be removed later, such as by the server.
 */
public interface Geary.FolderSupport.Remove : Folder {

    /**
     * Removes the specified emails from the folder.
     *
     * This folder must be opened prior to attempting this operation.
     */
    public abstract async void
        remove_email_async(Gee.Collection<EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
