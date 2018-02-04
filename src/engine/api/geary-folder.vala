/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A Folder represents the basic unit of organization for email.
 *
 * Folders may contain a set of messages, either stored purely locally
 * (for example, in the case of an ''outbox'' for mail queued for
 * sending), or as a representation of those found in a mailbox on a
 * remote mail server, such as those provided by an IMAP server. For
 * folders that represent a remote mailbox, messages are cached
 * locally, and the set of cached messages may be a subset of those
 * available in the mailbox, depending on an account's settings. Note
 * that some folders may not be able to contain any messages, and may
 * exist purely to construct a hierarchy.
 *
 * The set of locally stored messages is called the folder's
 * ''vector'', and contains generally the most recent message in the
 * mailbox at the upper end, back through to some older message at the
 * start or lower end of the vector. Thus the ordering of the vector
 * is the ''natural'' ordering, based on the order in which messages
 * were appended to the folder, not when messages were sent or some
 * other criteria. For remote-backed folders, the engine will maintain
 * the vector in accordance with the value of {@link
 * AccountInformation.prefetch_period_days}, however the start of the
 * vector will be extended back past that over time and in response to
 * certain operations that cause the vector to be ''expanded'' ---
 * that is for additional messages to be loaded from the remote
 * server, extending the vector. The upper end of the vector is
 * similarly extended as new messages are appended to the folder by
 * another on the server or in response to user operations such as
 * moving a message.
 *
 * Each {@link Account} offers a hierarchical listing of Folders.
 * Folders must be opened (with {@link open_async} before using most
 * of its methods and should be closed with {@link close_async} when
 * completed, even if a method has failed with an IOError.
 *
 * Folders offer various open states indicating when its "local" (disk
 * or database) connection and "remote" (network) connections are
 * ready.  Generally the local connection opens first and the remote
 * connection takes time to establish.  When in this state, Folder's
 * methods still operate, but will only return locally stored
 * information.
 *
 * This class only offers a small selection of guaranteed
 * functionality (in particular, the ability to list its {@link
 * Email}).  Additional functionality for Folders is indicated by the
 * presence of {@link FolderSupport} interfaces, include {@link
 * FolderSupport.Remove}, {@link FolderSupport.Copy}, and so forth.
 *
 * @see Geary.SpecialFolderType
 */
public abstract class Geary.Folder : BaseObject {
    public enum OpenState {
        CLOSED,
        OPENING,
        REMOTE,
        LOCAL,
        BOTH
    }

    public enum OpenFailed {
        LOCAL_ERROR,
        REMOTE_ERROR,
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
        FAST_OPEN,
        /**
         * Do not delay opening a connection to the server.
         *
         * @see open_async
         */
        NO_DELAY;
        
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
         * Include the provided EmailIdentifier (only respected by {@link list_email_by_id_async}.
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
    
    public abstract Geary.ProgressMonitor opening_monitor { get; }

    /**
     * Fired when the folder moves through stages of being opened.
     *
     * It will fire at least once if the folder successfully opens,
     * with the {@link OpenState} indicating what has been opened and
     * the count indicating the number of messages in the folder. it
     * may fire additional times as remote sessions are established
     * and re-established after being lost.
     *
     * If //state// is {@link OpenState.LOCAL}, the local store for
     * the folder has opened and the count reflects the number of
     * messages in the local store.
     *
     * If //state// is {@link OpenState.BOTH}, it indicates both the
     * local store and a remote session has been established, and the
     * count reflects the number of messages on the remote.
     *
     * If //state// is {@link OpenState.REMOTE}, it indicates a folder
     * is not synchronized locally but rather one entirely backed by a
     * network server.
     *
     * In the case of {@link OpenState.BOTH} or {@link
     * OpenState.REMOTE}, it refers to the authoritative count.
     *
     * This signal will never fire with {@link OpenState.CLOSED} as a
     * parameter.
     *
     * @see get_open_state
     */
    public signal void opened(OpenState state, int count);

    /**
     * Fired when {@link open_async} fails for one or more reasons.
     *
     * See open_async and {@link opened} for more information on how
     * opening a Folder works, in particular how open_async may return
     * immediately although the remote has not completely opened.
     * This signal may be called in the context of, or after
     * completion of, open_async.  It will ''not'' be called after
     * {@link close_async} has completed, however.
     *
     * Note that this signal may be fired ''and'' open_async throw an
     * Error.
     *
     * This signal may be fired more than once before the Folder is
     * closed, especially in the case of a remote session 
     */
    public signal void open_failed(OpenFailed failure, Error? err);

    /**
     * Fired when the Folder is closed, either by the caller or due to
     * errors in the local or remote store(s).
     *
     * It will fire a number of times: to report how the local store
     * closed (gracefully or due to error), how the remote closed
     * (similarly) and finally with {@link CloseReason.FOLDER_CLOSED}.
     * The first two may come in either order; the third is always the
     * last.
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
     * This is similar to {@link email_appended}, but that signal lists ''all'' messages appended
     * to the folder.  email_locally_appended only reports email that have not been downloaded
     * prior to the database (and not removed permanently since).  Hence, an email that is removed
     * from the folder and returned later will not be listed here (unless it was removed from the
     * local store in the meantime).
     *
     * @see email_appended
     */
    public signal void email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when email has been inserted into the list of messages in the folder.
     *
     * The {@link EmailIdentifier} for all inserted messages is supplied as a signal parameter.
     * Inserted messages are not added to the "top" of the vector of messages, but rather into
     * the middle or beginning.  This can happen for a number of reasons.  Newly received messages
     * are appended.
     *
     * @see email_locally_inserted
     */
    public signal void email_inserted(Gee.Collection<Geary.EmailIdentifier> ids);
    
    /**
     * Fired when previously unknown messages have been appended to the list of email in the folder.
     *
     * This is similar to {@link email_inserted}, but that signal lists ''all'' messages inserted
     * to the folder.  email_locally_inserted only reports email that have not been downloaded
     * prior to the database (and not removed permanently since).  Hence, an email that is removed
     * from the folder and returned later will not be listed here (unless it was removed from the
     * local store in the meantime).
     *
     * @see email_inserted
     * @see email_locally_inserted
     */
    public signal void email_locally_inserted(Gee.Collection<Geary.EmailIdentifier> ids);
    
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
    * Fired when the {@link SpecialFolderType} has changed.
    *
    * This will usually happen when the local object has been updated with data discovered from the
    * remote account.
    */
    public signal void special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type);
    
    /**
     * Fired when the Folder's display name has changed.
     *
     * @see get_display_name
     */
    public signal void display_name_changed();
    
    protected Folder() {
    }
    
    protected virtual void notify_opened(Geary.Folder.OpenState state, int count) {
        opened(state, count);
    }
    
    protected virtual void notify_open_failed(Geary.Folder.OpenFailed failure, Error? err) {
        open_failed(failure, err);
    }
    
    protected virtual void notify_closed(Geary.Folder.CloseReason reason) {
        closed(reason);
    }
    
    protected virtual void notify_email_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_appended(ids);
    }
    
    protected virtual void notify_email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_appended(ids);
    }
    
    protected virtual void notify_email_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_inserted(ids);
    }
    
    protected virtual void notify_email_locally_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_inserted(ids);
    }
    
    protected virtual void notify_email_removed(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_removed(ids);
    }
    
    protected virtual void notify_email_count_changed(int new_count, Folder.CountChangeReason reason) {
        email_count_changed(new_count, reason);
    }
    
    protected virtual void notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier,
        Geary.EmailFlags> flag_map) {
        email_flags_changed(flag_map);
    }
    
    protected virtual void notify_email_locally_complete(Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_complete(ids);
    }

    /**
     * In its default implementation, this will also call {@link notify_display_name_changed} since
     * that's often the case; if not, subclasses should override.
     */
    protected virtual void notify_special_folder_type_changed(Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        special_folder_type_changed(old_type, new_type);

        // in default implementation, this may also mean the display name changed; subclasses may
        // override this behavior, but no way to detect this, so notify
        notify_display_name_changed();
    }

    protected virtual void notify_display_name_changed() {
        display_name_changed();
    }
    
    /**
     * Returns a name suitable for displaying to the user.
     *
     * Default is to display the basename of the Folder's path, unless it's a special folder,
     * in which case {@link SpecialFolderType.get_display_name} is returned.
     */
    public virtual string get_display_name() {
        return (special_folder_type == Geary.SpecialFolderType.NONE)
            ? path.basename : special_folder_type.get_display_name();
    }
    
    /**
     * Returns the state of the Folder's connections to the local and remote stores.
     */
    public abstract OpenState get_open_state();

    /**
     * Marks the folder's operations as being required for use.
     *
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
     * {@link OpenFlags.NO_DELAY} may be passed to force an immediate opening of the remote folder.
     * This still will not occur in the context of the open_async call, but will initiate the
     * connection immediately.  Use this only when it's known that remote calls or remote
     * notifications to the Folder are imminent or monitoring the Folder is vital (such as with the
     * Inbox).
     *
     * However, even if the method returns before the Folder's OpenState is BOTH, this Folder is
     * ready for operation if this method returns without error.  The messages the folder returns
     * may not reflect the full state of the Folder, however, and returned emails may subsequently
     * have their state changed (such as their position).  Making a call that requires
     * accessing the remote store before OpenState.BOTH has been signalled will result in that
     * call blocking until the remote is open or an error state has occurred.  It's also possible for
     * the command to return early without waiting, depending on prior information of the folder.
     * See list_email_async() for special notes on its operation.  Also see wait_for_remote_async().
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
     * Blocks waiting for the folder to establish a remote session.
     *
     * @throws EngineError.OPEN_REQUIRED if the folder has not already
     * been opened.
     * @throws EngineError.ALREADY_CLOSED if not opened due to error.
     */
    public abstract async void wait_for_remote_async(Cancellable? cancellable = null)
        throws Error;

    /**
     * Marks one use of the folder's operations as being completed.
     *
     * The Folder should be closed when operations on it are concluded.  Depending on the
     * implementation this might entail closing a network connection or reverting it to another
     * state, or closing file handles or database connections.
     *
     * If the Folder is open, an internal open count is decremented.  If it remains above zero, the
     * method returns with no other side-effects.  If it decrements to zero, the Folder is closed,
     * tearing down network connections, closing files, and so forth.  See "closed" for signals
     * indicating the closing states.
     *
     * Returns true if the open count decrements to zero and the folder is ''closing''.  Use
     * {@link wait_for_close_async} to block until the folder is completely closed.  Otherwise,
     * returns false.  Note that this semantic is slightly different than the result code for
     * {@link open_async}.
     *
     * @see open_async
     */
    public abstract async bool close_async(Cancellable? cancellable = null) throws Error;

    /**
     * Wait for the {@link Folder} to fully close.
     *
     * Unlike {@link wait_for_remote_async}, this will ''always'' block until a {@link Folder} is
     * closed, even if it's not open.
     */
    public abstract async void wait_for_close_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * Find the lowest- and highest-ordered {@link EmailIdentifier}s in the
     * folder, among the given set of EmailIdentifiers that may or may not be
     * in the folder.  If none of the given set are in the folder, return null.
     */
    public abstract async void find_boundaries_async(Gee.Collection<Geary.EmailIdentifier> ids,
        out Geary.EmailIdentifier? low, out Geary.EmailIdentifier? high,
        Cancellable? cancellable = null) throws Error;

    /**
     * List a number of contiguous emails in the folder's vector.
     *
     * Emails in the folder are listed starting at a particular
     * location within the vector and moving either direction along
     * it. For remote-backed folders, the remote server is contacted
     * if any messages stored locally do not meet the requirements
     * given by `required_fields`, or if `count` extends back past the
     * low end of the vector.
     *
     * If the {@link EmailIdentifier} is null, it indicates the end of
     * the vector, not the end of the remote.  Which end depends on
     * the {@link ListFlags.OLDEST_TO_NEWEST} flag.  If not set, the
     * default is to traverse from newest to oldest, with null being
     * the newest email in the vector. If set, the direction is
     * reversed and null indicates the oldest email in the vector, not
     * the oldest in the mailbox.
     *
     * If not null, the EmailIdentifier ''must'' have originated from
     * this Folder.
     *
     * To fetch all available messages in one call, use a count of
     * `int.MAX`. If the {@link ListFlags.OLDEST_TO_NEWEST} flag is
     * set then the listing will contain all messages in the vector,
     * and no expansion will be performed. It may still access the
     * remote however in case of any of the messages not meeting the
     * given `required_fields`. If {@link ListFlags.OLDEST_TO_NEWEST}
     * is not set, the call will cause the vector to be fully expanded
     * and the listing will return all messages in the remote
     * mailbox. Note that specifying `int.MAX` in either case may be a
     * expensive operation (in terms of both computation and memory)
     * if the number of messages in the folder or mailbox is large,
     * hence should be avoided if possible.
     *
     * Use {@link ListFlags.INCLUDING_ID} to include the {@link Email}
     * for the particular identifier in the results.  Otherwise, the
     * specified email will not be included.  A null EmailIdentifier
     * implies that the top most email is included in the result (i.e.
     * ListFlags.INCLUDING_ID is not required);
     *
     * If the remote connection fails, this call will return
     * locally-available Email without error.
     *
     * There's no guarantee of the returned messages' order.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error;

    /**
     * List a set of non-contiguous emails in the folder's vector.
     *
     * Similar in contract to {@link list_email_by_id_async}, but uses a list of
     * {@link Geary.EmailIdentifier}s rather than a range.
     *
     * Any Gee.Collection is accepted for EmailIdentifiers, but the returned list will only contain
     * one email for each requested; duplicates are ignored.  ListFlags.INCLUDING_ID is ignored
     * for this call.
     *
     * If the remote connection fails, this call will return locally-available Email without error.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, ListFlags flags,
        Cancellable? cancellable = null) throws Error;
    
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
    public virtual string to_string() {
        return "%s:%s".printf(this.account.information.id, this.path.to_string());
    }
}
