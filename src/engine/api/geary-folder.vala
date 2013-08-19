/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public delegate void Geary.EmailCallback(Gee.List<Geary.Email>? emails, Error? err);

public interface Geary.Folder : BaseObject {
    public enum OpenState {
        CLOSED,
        OPENING,
        REMOTE,
        LOCAL,
        BOTH
    }
    
    public enum OpenFailed {
        LOCAL_FAILED,
        REMOTE_FAILED
    }
    
    /**
     * Provides the reason why the folder is closing or closed when the {@link closed} signal
     * is fired.
     *
     * The closed signal will be fired multiple times after a Folder is opened.  It is fired
     * after the remote and local sessions close for various reasons, and fires once and only
     * once when the folder is completely closed.
     *
     * LOCAL_CLOSE or LOCAL_ERROR is only called once, depending on the situation determining the
     * value.  The same is true for REMOTE_CLOSE and REMOTE_ERROR.  A REMOTE_ERROR can trigger
     * a LOCAL_CLOSE and vice-versa.  The values may be called in any order.
     *
     * When the local and remote stores have closed (either normally or due to errors), FOLDER_CLOSED
     * will be sent.
     */
    public enum CloseReason {
        LOCAL_CLOSE,
        LOCAL_ERROR,
        REMOTE_CLOSE,
        REMOTE_ERROR,
        FOLDER_CLOSED;
        
        public bool is_error() {
            return (this == LOCAL_ERROR) || (this == REMOTE_ERROR);
        }
    }
    
    [Flags]
    public enum CountChangeReason {
        NONE = 0,
        APPENDED,
        INSERTED,
        REMOVED
    }
    
    /**
     * Flags modifying the behavior of open_async().
     */
    [Flags]
    public enum OpenFlags {
        NONE = 0,
        /**
         * Perform the minimal amount of activity possible to open the folder
         * and be synchronized with the server.  This may mean some attributes of
         * the messages (such as their flags or other metadata) may not be up-to-date
         * when the folder opens.  Not all folders will support this flag.
         */
        FAST_OPEN;
        
        public bool is_any_set(OpenFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool is_all_set(OpenFlags flags) {
            return (this & flags) == flags;
        }
    }
    
    /**
     * Flags modifying how email is retrieved.
     */
    [Flags]
    public enum ListFlags {
        NONE = 0,
        /**
         * Fetch from the local store only.
         */
        LOCAL_ONLY,
        /**
         * Fetch from remote store only (results merged into local store).
         */
        FORCE_UPDATE,
        /**
         * Include the provided EmailIdentifier (only respected by {@link list_email_by_id_async} and
         * {@link lazy_list_email_by_id}).
         */
        INCLUDING_ID,
        /**
         * Direction of list traversal (if not set, from newest to oldest).
         */
        OLDEST_TO_NEWEST;
        
        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }
        
        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }
        
        public bool is_local_only() {
            return is_all_set(LOCAL_ONLY);
        }
        
        public bool is_force_update() {
            return is_all_set(FORCE_UPDATE);
        }
        
        public bool is_including_id() {
            return is_all_set(INCLUDING_ID);
        }
        
        public bool is_oldest_to_newest() {
            return is_all_set(OLDEST_TO_NEWEST);
        }
        
        public bool is_newest_to_oldest() {
            return !is_oldest_to_newest();
        }
    }
    
    public abstract Geary.Account account { get; }
    
    public abstract Geary.FolderProperties properties { get; }
    
    public abstract Geary.FolderPath path { get; }
    
    public abstract Geary.SpecialFolderType special_folder_type { get; }
    
    /**
     * Fired when the folder is successfully opened by a caller.
     *
     * It will only fire once until the Folder is closed, with the {@link OpenState} indicating what
     * has been opened and the count indicating the number of messages in the folder.  In the case
     * of {@link OpenState.BOTH} or {@link OpenState.REMOTE}, it refers to the authoritative number.
     * For {@link OpenState.LOCAL}, it refers to the number of messages in the local store.
     *
     * {@link OpenState.REMOTE} will only be passed if there's no local store, indicating that it's
     * not a synchronized folder but rather one entirely backed by a network server.  Geary
     * currently has no such folder implemented like this.
     *
     * This signal will never fire with {@link OpenState.CLOSED} as a parameter.
     *
     * @see get_open_state
     */
    public signal void opened(OpenState state, int count);
    
    /**
     * Fired when {@link open_async} fails for one or more reasons.
     *
     * See open_async and {@link opened} for more information on how opening a Folder works, i  particular
     * how open_async may return immediately although the remote has not completely opened.
     * This signal may be called in the context of, or after completion of, open_async.  It will
     * ''not'' be called after {@link close_async} has completed, however.
     *
     * Note that this signal may be fired ''and'' open_async throw an Error.
     *
     * This signal may be fired more than once before the Folder is closed.  It will only fire once
     * for each type of failure, however.
     */
    public signal void open_failed(OpenFailed failure, Error? err);
    
    /**
     * Fired when the Folder is closed, either by the caller or due to errors in the local
     * or remote store(s).
     *
     * It will fire three times: to report how the local store closed
     * (gracefully or due to error), how the remote closed (similarly) and finally with
     * {@link CloseReason.FOLDER_CLOSED}.  The first two may come in either order; the third is
     * always the last.
     */
    public signal void closed(CloseReason reason);
    
    /**
     * Fired when email has been appended to the list of messages in the folder.
     *
     * The {@link EmailIdentifier} for all appended messages is supplied as a signal parameter.
     *
     * @see email_locally_appended
     */
    public signal void email_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when previously unknown messages have been appended to the list of email in the folder.
     *
     * This is similar to {@link email_appended}, but that signal
     * lists ''all'' messages appended to the folder.  email_locally_appended only reports email that
     * have not been seen prior.  Hence, an email that is removed from the folder and returned
     * later will not be listed here (unless it was removed from the local store in the meantime).
     *
     * @see email_appended
     */
    public signal void email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when email has been removed (deleted or moved) from the folder.
     *
     * This may occur due to the local user's action or reported from the server (i.e. another
     * client has performed the action).  Email positions greater than the removed emails are
     * affected.
     *
     * ''Note:'' It's possible for the remote server to report a message has been removed that is not
     * known locally (and therefore the caller could not have record of).  If this happens, this
     * signal will ''not'' fire, although {@link email_count_changed} will.
     */
    public signal void email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when the total count of email in a folder has changed in any way.
     *
     * Note that this signal will fire after {@link email_appended}, {@link email_locally_appended},
     * and {@link email_removed} (although see the note at email_removed).
     */
    public signal void email_count_changed(int new_count, CountChangeReason reason);
    
    /**
     * Fired when the supplied email flags have changed, whether due to local action or reported by
     * the server.
     */
    public signal void email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map);
    
    /**
     * Fired when one or more emails have been locally saved with the full set
     * of Fields.
     */
    public signal void email_locally_complete(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when one or more emails have been discovered (added) to the Folder, but not necessarily
     * appended (i.e. old email pulled down due to user request or background fetching).
     */
    public signal void email_discovered(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
    * Fired when the {@link SpecialFolderType} has changed.
    *
    * This will usually happen when the local object has been updated with data discovered from the
    * remote account.
    */
    public signal void special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type);
    
    protected abstract void notify_opened(OpenState state, int count);
    
    protected abstract void notify_open_failed(OpenFailed failure, Error? err);
    
    protected abstract void notify_closed(CloseReason reason);
    
    protected abstract void notify_email_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    protected abstract void notify_email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    protected abstract void notify_email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    
    protected abstract void notify_email_count_changed(int new_count, CountChangeReason reason);
    
    protected abstract void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map);
    
    protected abstract void notify_email_locally_complete(Gee.Collection<Geary.EmailIdentifier> ids);
    
    protected abstract void notify_email_discovered(Gee.Collection<Geary.EmailIdentifier> ids);
    
    protected abstract void notify_special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type);
    
    /**
     * Returns a name suitable for displaying to the user.
     */
    public abstract string get_display_name();
    
    /**
     * Returns the state of the Folder's connections to the local and remote stores.
     */
    public abstract OpenState get_open_state();
    
    /**
     * The Folder must be opened before most operations may be performed on it.  Depending on the
     * implementation this might entail opening a network connection or setting the connection to
     * a particular state, opening a file or database, and so on.
     *
     * In the case of a Folder that is aggregating the contents of synchronized folder, it's possible
     * for this method to complete even though all internal opens haven't completed.  The "opened"
     * signal is the final say on when a Folder is fully opened with its OpenState parameter
     * indicating how open it really is.  In general, a Folder's local store will open immediately
     * while it may take time (if ever) for the remote state to open.  Thus, it's possible for
     * the "opened" signal to fire some time *after* this method completes.
     *
     * However, even if the method returns before the Folder's OpenState is BOTH, this Folder is
     * ready for operation if this method returns without error.  The messages the folder returns
     * may not reflect the full state of the Folder, however, and returned emails may subsequently
     * have their state changed (such as their position).  Making a call that requires
     * accessing the remote store before OpenState.BOTH has been signalled will result in that
     * call blocking until the remote is open or an error state has occurred.  It's also possible for
     * the command to return early without waiting, depending on prior information of the folder.
     * See list_email_async() for special notes on its operation.  Also see wait_for_open_async().
     *
     * If there's an error while opening, "open-failed" will be fired.  (See that signal for more
     * information on how many times it may fire, and when.)  To prevent the Folder from going into
     * a halfway state, it will immediately schedule a close_async() to cleanup, and those
     * associated signals will be fired as well.
     *
     * If the Folder has been opened previously, an internal open count is incremented and the
     * method returns.  There are no other side-effects.  This means it's possible for the
     * open_flags parameter to be ignored.  See the returned result for more information.
     *
     * A Folder may be reopened after it has been closed.  This allows for Folder objects to be
     * emitted by the Account object cheaply, but the client should only have a few open at a time,
     * as each may represent an expensive resource (such as a network connection).
     *
     * Returns false if already opened.
     */
    public abstract async bool open_async(OpenFlags open_flags, Cancellable? cancellable = null) throws Error;
    
    /**
     * Wait for the Folder to become fully open or fails to open due to error.  If not opened
     * due to error, throws EngineError.ALREADY_CLOSED.
     *
     * NOTE: The current implementation requirements are only that should be work after an
     * open_async() call has completed (i.e. an open is in progress).  Calling this method
     * otherwise will throw an EngineError.OPEN_REQUIRED.
     */
    public abstract async void wait_for_open_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * The Folder should be closed when operations on it are concluded.  Depending on the
     * implementation this might entail closing a network connection or reverting it to another
     * state, or closing file handles or database connections.
     *
     * If the Folder is open, an internal open count is decremented.  If it remains above zero, the
     * method returns with no other side-effects.  If it decrements to zero, the Folder is closed,
     * tearing down network connections, closing files, and so forth.  See "closed" for signals
     * indicating the closing states.
     *
     * If the Folder is already closed, the method silently returns.
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * List emails from the {@link Folder} starting at a particular location within the vector
     * and moving either direction along the mail stack.
     *
     * If the {@link EmailIdentifier} is null, it indicates the end of the vector.  Which end
     * depends on the {@link ListFlags.OLDEST_TO_NEWEST} flag.  Without, the default is to traverse
     * from newest to oldest, with null being the newest email.  If set, the direction is reversed
     * and null indicates the oldest email.
     *
     * If not null, the EmailIdentifier ''must'' have originated from this Folder.
     *
     * To fetch all available messages in one call, use a count of int.MAX.
     *
     * Use {@link ListFlags.INCLUDING_ID} to include the {@link Email} for the particular identifier
     * in the results.  Otherwise, the specified email will not be included.  A null
     * EmailIdentifier implies that the top most email is included in the result (i.e.
     * ListFlags.INCLUDING_ID is not required);
     *
     * There's no guarantee of the returned messages' order.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
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
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_by_id(Geary.EmailIdentifier? initial_id, int count,
        Geary.Email.Field required_fields, ListFlags flags, EmailCallback cb, Cancellable? cancellable = null);
    
    /**
     * Similar in contract to {@link list_email_by_id_async}, but uses a list of
     * {@link Geary.EmailIdentifier}s rather than a range.
     *
     * Any Gee.Collection is accepted for EmailIdentifiers, but the returned list will only contain
     * one email for each requested; duplicates are ignored.  ListFlags.INCLUDING_ID is ignored
     * for this call and {@link lazy_list_email_by_sparse_id}.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * See {@link list_email_by_id_async} and {@link list_email_by_sparse_id_async}
     * for more information on {@link EmailIdentifier}s and how the flags and callback parameter
     * works.
     *
     * Like the other "lazy" method, this method will call EmailCallback while the operation is
     * processing.  This method does not block.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract void lazy_list_email_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
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
     * This method also works like the list variants in that it will not wait for the server to
     * connect if called in the OPENING state.  A ListFlag option may be offered in the future to
     * force waiting for the server to connect.  Unlike the list variants, if in the OPENING state
     * and the message is not found locally, EngineError.NOT_FOUND is thrown.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null) throws Error;
    
    /**
     * Used for debugging.  Should not be used for user-visible labels.
     */
    public abstract string to_string();
}

