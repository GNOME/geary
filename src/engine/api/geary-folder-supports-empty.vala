/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Empty interface to a {@link
 * Geary.Folder} indicates that it supports removing (deleting) all
 * email quickly.
 *
 * This generally means that the message is deleted from the server
 * and is not recoverable.  It does ''not'' mean the messages are
 * moved to a Trash folder where they may or may not be automatically
 * deleted some time later.  Users invoking empty are expecting all
 * contents on the remote to be removed entirely, whether or not any
 * or all of them have been synchronized locally.
 *
 * @see FolderSupport.Remove
 */
public interface Geary.FolderSupport.Empty : Folder {

    /**
     * Removes all email from the folder.
     */
    public abstract async void
        empty_folder_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
