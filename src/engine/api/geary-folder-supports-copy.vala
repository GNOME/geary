/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * The addition of the Geary.FolderSupportsCopy interface indicates the Folder supports a copy
 * email operation.  A copied email will not be removed from the current folder but will appear in
 * the destination.
 *
 * FolderSupportsCopy does not imply FolderSupportsMove, or vice-versa.
 */
public interface Geary.FolderSupportsCopy : Geary.Folder {
    /**
     * Copies messages into another folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error;
}

