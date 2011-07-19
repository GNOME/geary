/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.LocalAccount : Object, Geary.Account {
    public abstract async void clone_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error;
    
    public abstract async void update_folder_async(Geary.Folder folder, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Returns true if the email (identified by its Message-ID) already exists in the account's
     * local store, no matter the folder.
     *
     * Note that there are no guarantees of the uniqueness of a Message-ID, or even that a message
     * will have one.  Because of this situation the method can return the number of messages
     * found with that ID.
     */
    public async abstract bool has_message_id_async(Geary.RFC822.MessageID message_id,
        out int count, Cancellable? cancellable = null) throws Error;
}

public interface Geary.LocalFolder : Object, Geary.Folder {
    public async abstract bool is_email_present(Geary.EmailIdentifier id,
        out Geary.Email.Field available_fields, Cancellable? cancellable = null) throws Error;
     
    /**
     * Geary allows for a single message to exist in multiple folders.  This method checks if the
     * email is associated with this folder.  It may rely on a Message-ID being present, in which
     * case if it's not the method will throw an EngineError.INCOMPLETE_MESSAGE.
     *
     * If the email is not in the local store, this method returns false.
     */
    public async abstract bool is_email_associated_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Geary allows for a single message to exist in multiple folders.  It also allows for partial
     * email information to be stored and updated, building the local store as more information is
     * downloaded from the server.
     *
     * update_email_async() updates the email's information in the local store, adding any new
     * fields not already present.  If the email has fields already stored, the local version *will*
     * be overwritten with this new information.  However, if the email has fewer fields than the
     * local version, the old information will not be lost.  In this sense this is a merge
     * operation.
     *
     * update_email_async() will also attempt to associate an email existing in the system with this
     * folder.  If the message has folder-specific properties that identify it, those will be used;
     * if not, update_email_async() will attempt to use the Message-ID.  If the Message-ID is not
     * available in the email, it will throw EngineError.INCOMPLETE_MESSAGE unless
     * duplicate_okay is true, which confirms that it's okay to not attempt the linkage (which
     * should be done if the message simply lacks a Message-ID).
     * TODO: Examine other fields in the email and attempt to match it with existing messages.
     *
     * The EmailLocation field is used to position the email in the folder's ordering.
     * If another email exists at the same EmailLocation.position, EngineError.ALREADY_EXISTS
     * will be thrown.
     *
     * If the email does not exist in the local store OR the email has no Message-ID and
     * no_incomplete_error is true OR multiple messages are found in the system with the same
     * Message-ID, update_email-async() will see if there's any indication of the email being
     * associated with the folder.  If so, it will merge in the new information.  If not, this
     * method will fall-through to create_email_async().
     */
    public async abstract void update_email_async(Geary.Email email, bool duplicate_okay,
        Cancellable? cancellable = null) throws Error;
}

