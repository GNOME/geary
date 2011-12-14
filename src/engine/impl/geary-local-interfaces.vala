/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private interface Geary.LocalAccount : Object, Geary.Account {
    public abstract async void clone_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async void update_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error;
}

private interface Geary.LocalFolder : Object, Geary.Folder {
    public async abstract bool is_email_present_async(Geary.EmailIdentifier id,
        out Geary.Email.Field available_fields, Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns the Geary.Email.Field bitfield of all email fields that must be requested from the
     * remote folder in order to do proper duplicate detection within the local folder.  May
     * return Geary.Email.Field.NONE if no duplicate detection is available.
     */
    public abstract Geary.Email.Field get_duplicate_detection_fields();
    
    /**
     * Converts an EmailIdentifier into positional addressing in the Folder.  This call relies on
     * the fact that when a Folder is fully opened, the local stores' tail list of messages (the
     * messages located at the top of the stack, i.e. the latest ones added) are synchronized with
     * the server and is gap-free, even if all the fields for those messages is not entirely
     * available.
     *
     * Returns a positive value locating the position of the email.  Other values (zero, negative)
     * indicate the EmailIdentifier is unknown, which could mean the message is not associated with
     * the folder, or is buried so far down the list on the remote server that it's not known
     * locally (yet).
     */
    public async abstract int get_id_position_async(Geary.EmailIdentifier id, Cancellable? cancellable)
        throws Error;
    
    /**
     * Sets an e-mails flags based on the MessageFlags.  Note that the EmailFlags MUST be of
     * type Geary.Imap.EmailFlags and contain a valid MessageFlags object.
     */
    public async abstract void set_email_flags_async(Gee.Map<Geary.EmailIdentifier, 
        Geary.EmailFlags> map, Cancellable? cancellable) throws Error;
}

