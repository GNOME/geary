/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Move interface indicates that the
 * {@link Geary.Folder} supports a move email operation.  Moved messages are
 * removed from this Folder.
 *
 * Move does not imply {@link Geary.FolderSupport.Copy}, or vice-versa.
 */
public interface Geary.FolderSupport.Move : Geary.Folder {
    /**
     * Moves messages to another folder.
     *
     * If the destination is this {@link Folder}, the operation will not move the message in any
     * way but will return success.
     *
     * The {@link Geary.Folder} must be opened prior to attempting this operation.
     */
    public abstract async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error;
}

