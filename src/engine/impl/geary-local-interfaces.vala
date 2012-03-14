/* Copyright 2011-2012 Yorba Foundation
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
     * Removes an email while returning the "marked" status flag.  This flag is used internally
     * by the SendReplayQueue to record whether we've already notified for the removal.
     */
    public async abstract void remove_marked_email_async(Geary.EmailIdentifier id, out bool marked,
        Cancellable? cancellable) throws Error;
    
    /**
     * Marks or unmarks an e-mail for removal.
     */
    public async abstract void mark_removed_async(Geary.EmailIdentifier id, bool remove, 
        Cancellable? cancellable) throws Error;
    
    /**
     * Retrieves email flags for the given list of email identifiers.
     */
    public async abstract Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> get_email_flags_async(
        Gee.List<Geary.EmailIdentifier> to_get, Cancellable? cancellable) throws Error;
    
    /**
     * Sets an e-mails flags based on the MessageFlags.  Note that the EmailFlags MUST be of
     * type Geary.Imap.EmailFlags and contain a valid MessageFlags object.
     */
    public async abstract void set_email_flags_async(Gee.Map<Geary.EmailIdentifier, 
        Geary.EmailFlags> map, Cancellable? cancellable) throws Error;
    
    /**
     * Converts a remote position and count into an email ID.
     */
    public async abstract Geary.EmailIdentifier? id_from_remote_position(int remote_position, 
        int new_remote_count) throws Error;
    
    /**
     * Returns a map of local emails and their stored fields.
     */
    public async abstract Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? get_email_fields_by_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error;
}

