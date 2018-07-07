/*
 *Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Move interface indicates
 * that the {@link Geary.Folder} supports a move email operation.
 * Moved messages are removed from this Folder.
 *
 * Move does not imply {@link Geary.FolderSupport.Copy}, or
 * vice-versa.
 */
public interface Geary.FolderSupport.Move : Folder {

    /**
     * Moves messages to another folder.
     *
     * If the destination is this {@link Folder}, the operation will
     * not move the message in any way but will return success.
     *
     * This folder must be opened prior to attempting this operation.
     *
     * @return A {@link Geary.Revokable} that may be used to revoke
     * (undo) this operation later.
     */
    public abstract async Revokable?
        move_email_async(Gee.Collection<EmailIdentifier> to_move,
                         FolderPath destination,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
