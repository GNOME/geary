/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Mark interface indicates the {@link Geary.Folder}
 * supports marking and unmarking messages with system and user-defined flags.
 */
public interface Geary.FolderSupport.Mark : Geary.Folder {
    /**
     * Adds and removes flags from a list of messages.
     *
     * The {@link Geary.Folder} must be opened prior to attempting this operation.
     */
    public abstract async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Adds and removes flags from a single message.
     *
     * The {@link Geary.Folder} must be opened prior to attempting this operation.
     */
    public virtual async void mark_single_email_async(Geary.EmailIdentifier to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove,
        Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        list.add(to_mark);
        
        yield mark_email_async(list, flags_to_add, flags_to_remove, cancellable);
    }
}

