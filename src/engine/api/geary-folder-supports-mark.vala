/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * The addition of the Geary.FolderSupportsMark interface indicates the Folder supports mark and
 * unmark operations on email messages.
 */
public interface Geary.FolderSupportsMark : Geary.Folder {
    /**
     * Adds and removes flags from a list of messages.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Adds and removes flags from a single message.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public virtual async void mark_single_email_async(Geary.EmailIdentifier to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove,
        Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>(
            Equalable.equal_func);
        list.add(to_mark);
        
        yield mark_email_async(list, flags_to_add, flags_to_remove, cancellable);
    }
}

