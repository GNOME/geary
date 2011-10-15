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
    
    public enum Direction {
        BEFORE,
        AFTER
    }
    
    [Flags]
    public enum ListFlags {
        NONE = 0,
        FAST;
        
        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }
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
     * "messages-appended" is fired when new messages have been appended to the list of messages in
     * the folder (and therefore old message position numbers remain valid, but the total count of
     * the messages in the folder has changed).
     */
    public signal void messages_appended(int total);
    
    /**
     * "message-removed" is fired when a message has been removed (deleted or moved) from the
     * folder (and therefore old message position numbers may no longer be valid, i.e. those after
     * the removed message).
     */
    public signal void message_removed(int position, int total);
    
    /**
     * "positions-reordered" is fired when message positions on emails in the folder may no longer
     * be valid, which may happen even if a message has not been removed.  In other words, if a
     * message is removed and it causes positions to change, "message-remove" will be fired followed
     * by this signal.
     *
     * Although reordering may be rare (positions shifting is a better description), it is possible
     * for messages in a folder to change positions completely.  This signal covers both
     * circumstances.
     */
    public signal void positions_reordered();
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_opened(OpenState state);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_closed(CloseReason reason);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_messages_appended(int total);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_positions_reordered();
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_message_removed(int position, int total);
    
    public abstract Geary.FolderPath get_path();
    
    public abstract Geary.FolderProperties? get_properties();
    
    public abstract ListFlags get_supported_list_flags();
    
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
     * case of the local store, this might differ from the number on the network server.  Folders
     * created by Engine are aggregating objects and will return the true count.  However, this
     * might require a round-trip to the server.
     *
     * Also note that local folders may be sparsely populated.  get_email_count_async() returns the
     * total number of recorded emails, but it's possible none of them have more than placeholder
     * information.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async int get_email_count_async(Cancellable? cancellable = null) throws Error;
    
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
     * and proceeds to all available emails.  If low is -1, the *last* (most recent) 'count' emails
     * are returned.  If both low and count are -1, it's no different than calling with low as
     * 1 and count -1, that is, all emails are returned.  (See normalize_span_specifiers() for
     * a utility function that handles all aspects of these requirements.)
     *
     * The returned list is not guaranteed to be in any particular order.  The position index
     * (starting from low) *is* ordered, however, from oldest to newest (in terms of receipt by the 
     * SMTP server, not necessarily the Sent: field), so if the caller wants the latest emails,
     * they should calculate low by subtracting from get_email_count() or set low to -1 and use
     * count to fetch the last n emails.
     *
     * If any position in low to (low + count) are out of range, only the email within range are
     * reported.  No error is thrown.  This allows callers to blindly request the first or last n
     * emails in a folder without determining the count first.
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
     * If the caller would prefer the Folder return emails it has immediately available rather than
     * make an expensive I/O call to "properly" fetch the emails, it should pass ListFlags.FAST.
     * However, this also means avoiding a full synchronization, so it's possible the fetched
     * emails do not correspond to what's actually available on the server.
     * The best use of this method is to quickly retrieve a block of email for display or processing
     * purposes, immediately followed by a non-fast list operation and then merging the two results.
     *
     * Note that implementing ListFlags.FAST is advisory, not required.  The implementation may
     * ignore it completely.  See get_supported_list_flags() for more information.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * low is one-based, unless -1 is specified, as explained above.
     */
    public abstract async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
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
    public abstract void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        ListFlags flags, EmailCallback cb, Cancellable? cancellable = null);
    
    /**
     * Like list_email_async(), but the caller passes a sparse list of email by it's ordered
     * position in the folder.  If any of the positions in the sparse list are out of range,
     * only the emails within range are reported.  The list is not guaranteed to be in any
     * particular order.
     *
     * See the notes in list_email_async() regarding issues about local versus remote stores.
     *
     * The Folder must be opened prior to attempting this operation.
     *
     * All positions are one-based.
     */
    public abstract async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Similar in contract to list_email_sparse_async(), but like lazy_list_email(), the
     * messages are passed back to the caller in chunks as they're retrieved.  When null is passed
     * as the first parameter, all the messages have been fetched.  If an Error occurs during
     * processing, it's passed as the second parameter.  There's no guarantee of the returned
     * message's order.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_sparse(int[] by_position,
        Geary.Email.Field required_fields, ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
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
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    /**
     * Removes the email at the supplied position from the folder.  If the email position is
     * invalid for any reason, EngineError.NOT_FOUND is thrown.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void remove_email_async(int position, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * check_span_specifiers() verifies that the span specifiers match the requirements set by
     * list_email_async() and lazy_list_email_async().  If not, this method throws
     * EngineError.BAD_PARAMETERS.
     */
    protected static void check_span_specifiers(int low, int count) throws EngineError {
        if ((low < 1 && low != -1) || (count < 0 && count != -1))
            throw new EngineError.BAD_PARAMETERS("low=%d count=%d", low, count);
    }
    
    /**
     * normalize_span_specifiers() deals with the varieties of span specifiers that can be passed
     * to list_email_async() and lazy_list_email_async().  Note that this function is for
     * implementations to convert 'low' and 'count' into positive values (1-based in the case of
     * low) that are within an appropriate range.
     *
     * The caller should plug in 'low' and 'count' passed from the user as well as the total
     * number of emails available (i.e. the complete span is 1..total).
     */
    protected static void normalize_span_specifiers(ref int low, ref int count, int total) 
        throws EngineError {
        check_span_specifiers(low, count);
        
        if (total < 0)
            throw new EngineError.BAD_PARAMETERS("total=%d", total);
        
        // if both are -1, it's no different than low=1 count=-1 (that is, return all email)
        if (low == -1 && count == -1)
            low = 1;
        
        // if count is -1, it's like a globbed star (return everything starting at low)
        if (count == -1 || total == 0)
            count = total;
            
        if (low == -1)
            low = ((total - count) + 1).clamp(1, total);
        
        if ((low + (count - 1)) > total)
            count = ((total - low) + 1).clamp(1, total);
    }
    
    /**
     * Used for debugging.  Should not be used for user-visible labels.
     */
    public abstract string to_string();
}

