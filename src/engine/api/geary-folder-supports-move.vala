/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupportsMove interface indicates that the Folder supports a move
 * email operation.  Moved messages are removed from this Folder.
 *
 * FoldeSupportsMove does not imply FolderSupportsCopy, or vice-versa.
 */
public interface Geary.FolderSupportsMove : Geary.Folder {
    /**
     * Moves messages to another folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error;
}

