/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Mark interface indicates
 * the {@link Geary.Folder} supports marking and unmarking messages
 * with system and user-defined flags.
 */
public interface Geary.FolderSupport.Mark : Geary.Folder {

    /**
     * Adds and removes flags from a list of messages.
     *
     * This folder must be opened prior to attempting this operation.
     */
    public abstract async void
        mark_email_async(Gee.Collection<EmailIdentifier> to_mark,
                         EmailFlags? flags_to_add,
                         EmailFlags? flags_to_remove,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error;

}
