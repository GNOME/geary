/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Copy interface to a {@link
 * Geary.Folder} indicates it supports a copy email operation.
 *
 * A copied email will not be removed from the current folder but will
 * appear in the destination.
 *
 * Copy does not imply {@link Geary.FolderSupport.Move}, or
 * vice-versa.
 */
public interface Geary.FolderSupport.Copy : Folder {

    /**
     * Copies messages into another folder.
     *
     * If the destination is this {@link Folder}, the operation will
     * not make a copy of the message but will return success.
     *
     * This folder must be opened prior to attempting this operation.
     */
    public abstract async void
        copy_email_async(Gee.Collection<EmailIdentifier> to_copy,
                         FolderPath destination,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
