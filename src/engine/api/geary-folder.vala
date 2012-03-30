/* Copyright 2011-2012 Yorba Foundation
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
    
    public enum CountChangeReason {
        ADDED,
        REMOVED
    }
    
    /**
     * Flags used for retrieving email.
     *   FAST:         fetch from the DB only
     *   FORCE_UPDATE: fetch from remote only
     *   EXCLUDING_ID: exclude the provided ID
     */
    [Flags]
    public enum ListFlags {
        NONE = 0,
        LOCAL_ONLY,
        FORCE_UPDATE,
        EXCLUDING_ID;
        
        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }
    }
    
    /**
     * This is fired when the Folder is successfully opened by a caller.  It will only fire once
     * until the Folder is closed, with the OpenState indicating what has been opened and the count
     * indicating the number of messages in the folder (in the case of OpenState.BOTH, it refers
     * to the authoritative number).
     */
    public signal void opened(OpenState state, int count);
    
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
     * "email-appended" is fired when new messages have been appended to the list of messages in
     * the folder (and therefore old message position numbers remain valid, but the total count of
     * the messages in the folder has changed).
     */
    public signal void email_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * "email-locally-appended" is fired when previously unknown messages have been appended to the
     * list of messages in the folder.  This is similar to "email-appended", but that signal
     * lists all messages appended to the folder.  "email-locally-appended" only reports emails that
     * have not been seen prior.  Hence, an email that is removed from the folder and returned
     * later will not be listed here (unless it was removed from the local store in the meantime).
     *
     * Note that these messages were appended as well, hence their positional addressing may have
     * changed since last seen in this folder.  However, it's important to realize that this list
     * does *not* represent all newly appended messages.
     */
    public signal void email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * "email-removed" is fired when a message has been removed (deleted or moved) from the
     * folder (and therefore old message position numbers may no longer be valid, i.e. those after
     * the removed message).
     *
     * NOTE: It's possible for the remote server to report a message has been removed that is not
     * known locally (and therefore the caller could not have record of).  If this happens, this
     * signal will *not* fire, although "email-count-changed" will.
     */
    public signal void email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * "email-count-changed" is fired when the total count of email in a folder has changed in any way.
     *
     * Note that this signal will be fired alongside "messages-appended" or "message-removed".
     * That is, do not use both signals to process email count changes; one will suffice.
     * This signal will fire after those (although see the note at "messages-removed").
     */
    public signal void email_count_changed(int new_count, CountChangeReason reason);
    
    /**
     * "email-flags-changed" is fired when an email's flag changed.
     *
     * This signal will be fired both when changes occur on the client side via the
     * mark_email_async() method as well as changes occur remotely.
     */
    public signal void email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_opened(OpenState state, int count);
    
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
    protected abstract void notify_email_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_email_count_changed(int new_count, CountChangeReason reason);
    
    /**
     * This helper method should be called by implementors of Folder rather than firing the signal
     * directly.  This allows subclasses and superclasses the opportunity to inspect the email
     * and update state before and/or after the signal has been fired.
     */
    protected abstract void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map);
    
    public abstract Geary.FolderPath get_path();
    
    /**
     * Returns the special folder type of the folder. If the the folder is not a special one then
     * null is returned.
     */
    public abstract Geary.SpecialFolderType? get_special_folder_type();
    
    /**
     * The Folder must be opened before most operations may be performed on it.  Depending on the
     * implementation this might entail opening a network connection or setting the connection to
     * a particular state, opening a file or database, and so on.
     *
     * In the case of a Folder that is aggregating the contents of synchronized folder, it's possible
     * for this method to complete even though all internal opens haven't completed.  The "opened"
     * signal is the final say on when a Folder is fully opened with its OpenState parameter
     * indicating how open it really is.  In general, a Folder's local state will occur immediately
     * while it may take time (if ever) for the remote state to open.  Thus, it's possible for
     * the "opened" signal to fire some time *after* this method completes.
     *
     * However, even if the method returns before the Folder's OpenState is BOTH, this Folder is
     * ready for operation if this method returns without error.  The messages the folder returns
     * may not reflect the full state of the Folder, however, and returned emails may subsequently
     * have their state changed (such as their EmailLocation).
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
    
    /**
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
     * If the Folder supports duplicate detection, it may merge in additional fields from this Email
     * and associate the revised Email with this Folder.  See LocalFolder for specific calls that
     * deal with this.  Callers from outside the Engine don't need to worry about this; it's taken
     * care of under the covers.
     *
     * Returns true if the email was created in the folder, false if it was merged.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async bool create_email_async(Geary.Email email, Cancellable? cancellable = null)
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
     * Similar in contract to list_email_async(), but uses Geary.EmailIdentifier rather than
     * positional addressing.  This allows for a batch of messages to be listed from a starting
     * identifier, going up and down the stack depending on the count parameter.
     *
     * The count parameter is exclusive of the Email at initial_id.  That is, if count is one,
     * two Emails may be returned: the one for initial_id and the next one.  If count is zero,
     * only the Email with the specified initial_id will be listed, making this method operate
     * like fetch_email_async().
     *
     * If count is positive, initial_id is the *lowest* identifier and the returned list is going
     * up the stack (toward the most recently added).  If the count is negative, initial_id is
     * the *highest* identifier and the returned list is going down the stack (toward the earliest
     * added).
     *
     * To fetch all available messages in one direction or another, use int.MIN or int.MAX.
     *
     * initial_id *must* be an EmailIdentifier available to the Folder for this to work, as listing
     * a range inevitably requires positional addressing under the covers.  However, since it's
     * some times desirable to list messages excluding the specified EmailIdentifier, callers may
     * use ListFlags.EXCLUDING_ID (which is a flag only recognized by this method and
     * lazy_list_email_by_id()).  If the count is zero or one (or the number of messages remaining
     * on the stack from the initial ID's position is zero or one) *and* this flag is set, no
     * messages will be returned.
     *
     * There's no guarantee of the returned messages' order.
     *
     * There is (currently) no sparse version of list_email_by_id_async().
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Similar in contract to lazy_list_email_async(), but uses Geary.EmailIdentifier rather than
     * positional addressing, much like list_email_by_id_async().  See that method for more
     * information on its contract and how the count and flags parameters work.
     *
     * Like the other "lazy" methods, this method will call EmailCallback while the operation is
     * processing.  This method does not block.
     *
     * There is (currently) no sparse version of lazy_list_email_by_id().
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null);
    
    /**
     * Returns the locally available Geary.Email.Field fields for the specified emails.  If a
     * list or fetch operation occurs on the emails that specifies a field not returned here,
     * the Engine will either have to go out to the remote server to get it, or (if
     * ListFlags.LOCAL_ONLY is specified) not return it to the caller.
     *
     * If the EmailIdentifier is unknown locally, it will not be present in the returned Map.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns a single email that fulfills the required_fields flag at the ordered position in
     * the folder.  If the email_id is invalid for the folder's contents, an EngineError.NOT_FOUND
     * error is thrown.  If the requested fields are not available, EngineError.INCOMPLETE_MESSAGE
     * is thrown.
     *
     * Because fetch_email_async() is a form of listing (listing exactly one email), it takes
     * ListFlags as a parameter.  See list_email_async() for more information.  Note that one
     * flag (ListFlags.EXCLUDING_ID) makes no sense in this context.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null) throws Error;
    
    /**
     * Removes the specified emails from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Removes one email from the folder.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void remove_single_email_async(Geary.EmailIdentifier email_id,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Adds or removes a flag from a list of messages.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) throws Error;
    
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
    internal static void normalize_span_specifiers(ref int low, ref int count, int total) 
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

