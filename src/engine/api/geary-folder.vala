/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public delegate void Geary.EmailCallback(Gee.List<Geary.Email>? emails, Error? err);

public interface Geary.Folder : Object {
    public enum OpenState {
        REMOTE,
        LOCAL,
        BOTH
    }
    
    public enum CloseReason {
        LOCAL_CLOSE,
        REMOTE_CLOSE,
        FOLDER_CLOSED
    }
    
    /**
     * This is fired when the Folder is successfully opened by a caller.  It will only fire once
     * until the Folder is closed, with the OpenState indicating what has been opened.
     */
    public signal void opened(OpenState state);
    
    /**
     * This is fired when the Folder is successfully closed by a caller.  It will only fire once
     * until the Folder is re-opened.
     *
     * The CloseReason enum can be used to inspect why the folder was closed: the connection was
     * broken locally or remotely, or the Folder was simply closed (and the underlying connection
     * is still available).
     */
    public signal void closed(CloseReason reason);
    
    /**
     * "email-added-removed" is fired when new email has been detected due to background monitoring
     * operations or if an unrelated operation causes or reveals the existence or removal of
     * messages.
     *
     * There are no guarantees of what Geary.Email.Field fields will be available when these are
     * reported.  If more information is required, use the fetch or list operations.
     */
    public signal void email_added_removed(Gee.List<Geary.Email>? added,
        Gee.List<Geary.Email>? removed);
    
    /**
     * TBD.
     */
    public signal void updated();
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected virtual void notify_opened(OpenState state) {
        opened(state);
    }
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected virtual void notify_closed(CloseReason reason) {
        closed(reason);
    }
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected virtual void notify_email_added_removed(Gee.List<Geary.Email>? added,
        Gee.List<Geary.Email>? removed) {
        email_added_removed(added, removed);
    }
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    public virtual void notify_updated() {
        updated();
    }
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.FolderProperties? get_properties();
    
    /**
     * The Folder must be opened before most operations may be performed on it.  Depending on the
     * implementation this might entail opening a network connection or setting the connection to
     * a particular state, opening a file or database, and so on.
     *
     * If the Folder has been opened previously, EngineError.ALREADY_OPEN is thrown.  There are no
     * other side-effects.
     */
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    /**
     * The Folder should be closed when operations on it are concluded.  Depending on the
     * implementation this might entail closing a network connection or reverting it to another
     * state, or closing file handles or database connections.
     *
     * If the Folder is already closed, the method silently returns.
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    /*
     * Returns the number of messages in the Folder.  They can be addressed by their position,
     * from 1 to n.
     *
     * Note that this only returns the number of messages available to the backing medium.  In the
     * case of the local store, this might be less than the number on the network server.  Folders
     * created by Engine are aggregating objects and will return the true count.  However, this
     * might require a round-trip to the server.
     *
     * Also note that local folders may be sparsely populated.  get_count() returns the last position
     * available, but not all emails from 1 to n may be available.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async int get_email_count(Cancellable? cancellable = null) throws Error;
    
    /**
     * If the Folder object detects that the supplied Email does not have sufficient fields for
     * writing it, it should throw an EngineError.INCOMPLETE_MESSAGE.  Use
     * get_required_fields_for_writing() to determine which fields must be present to create the
     * email.
     *
     * This method will throw EngineError.ALREADY_EXISTS if the email already exists in the folder
     * *and* the backing medium allows for checking prior to creation (which is not necessarily
     * the case with network folders).  Use LocalFolder.update_email_async() to update fields on
     * an existing message in the local store.  Saving an email on the server will be available
     * later.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void create_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Returns a list of messages that fulfill the required_fields flags starting at the low
     * position and moving up to (low + count).  If count is -1, the returned list starts at low
     * and proceeds to all available emails.  The returned list is not guaranteed to be in any
     * particular order.
     *
     * If any position in low to (low + count) are out of range, only the email within range are
     * reported.  No error is thrown.  This allows callers to blindly request the first n emails
     * in a folder without determining the count first.
     *
     * Note that this only returns the emails with the required fields that are available to the
     * Folder's backing medium.  The local store may have fewer or incomplete messages, meaning that
     * this will return an incomplete list.  It is up to the caller to determine what's missing
     * and take the appropriate steps.
     *
     * In the case of a Folder returned by Engine, it will use what's available in the local store
     * and fetch from the network only what it needs, so that the caller gets a full list.
     * Note that this means the call may require a round-trip to the server.
     *
     * TODO: Delayed listing methods (where what's available are reported via a callback after the
     * async method has completed) will be implemented in the future for more responsive behavior.
     * These may be operations only available from Folders returned by Engine.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * low is one-based.
     */
    public abstract async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    /**
     * Similar in contract to list_email_async(), however instead of the emails being returned all
     * at once at completion time, the emails are delivered to the caller in chunks via the
     * EmailCallback.  The method indicates when all the message have been fetched by passing a null
     * for the first parameter.  If an Error occurs while processing, it will be passed as the
     * second parameter.  There's no guarantess of the order the messages will be delivered to the
     * caller.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_async(int low, int count, Geary.Email.Field required_fields,
        EmailCallback cb, Cancellable? cancellable = null);
    
    /**
     * Like list_email_async(), but the caller passes a sparse list of email by it's ordered
     * position in the folder.  If any of the positions in the sparse list are out of range,
     * only the emails within range are reported.  The list is not guaranteed to be in any
     * particular order.
     *
     * See the notes in list_email_async() regarding issues about local versus remote stores and
     * possible future additions to the API.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * All positions are one-based.
     */
    public abstract async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    /**
     * Similar in contract to list_email_sparse_async(), but like lazy_list_email_async(), the
     * messages are passed back to the caller in chunks as they're retrieved.  When null is passed
     * as the first parameter, all the messages have been fetched.  If an Error occurs during
     * processing, it's passed as the second parameter.  There's no guarantee of the returned
     * message's order.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, EmailCallback cb, Cancellable? cancellable = null);
    
    /**
     * Returns a single email that fulfills the required_fields flag at the ordered position in
     * the folder.  If position is invalid for the folder's contents, an EngineError.NOT_FOUND
     * error is thrown.  If the requested fields are not available, EngineError.INCOMPLETE_MESSAGE
     * is thrown.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * position is one-based.
     */
    public abstract async Geary.Email fetch_email_async(int position, Geary.Email.Field required_fields,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Used for debugging.  Should not be used for user-visible labels.
     */
    public abstract string to_string();
}

