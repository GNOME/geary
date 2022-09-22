/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Account is the basic interface to the user's email account, {@link Folder}s, and various signals,
 * monitors, and notifications of account activity.
 *
 * In addition to providing an interface to the various Folders, Account offers aggregation signals
 * indicating changes to all Folders as they're discovered.  Because some mail interfaces don't
 * provide account-wide notification, these signals may only be fired when the Folder is open,
 * which sometimes happens in the background as background synchronization occurs.
 *
 * Accounts must be opened and closed with {@link open_async} and {@link close_async}.  Most
 * methods only work if the Account is opened (if not, that will be mentioned in their
 * documentation).
 *
 * A list of all Accounts may be retrieved from the {@link Engine} singleton.
 */

public abstract class Geary.Account : BaseObject, Logging.Source {


    /** Number of times to attempt re-authentication. */
    internal const uint AUTH_ATTEMPTS_MAX = 3;


     /**
     * Denotes the account's current status.
     *
     * @see Account.current_status
     * @see ClientService.current_status
     */
    [Flags]
    public enum Status {

        /**
         * The account is currently online and operating normally.
         *
         * This flags will be set when the account's {@link incoming}
         * service's {@link ClientService.current_status} is {@link
         * ClientService.Status.CONNECTED}.
         */
        ONLINE,

        /**
         * One or of the account's services is degraded.
         *
         * This flag will be set when one or both of its services has
         * encountered a problem. Consult the {@link
         * ClientService.current_status} to determine which and the
         * exact problem.
         */
        SERVICE_PROBLEM;


        /** Determines if the {@link ONLINE} flag is set. */
        public bool is_online() {
            return (this & ONLINE) == ONLINE;
        }

        /** Determines if the {@link SERVICE_PROBLEM} flag is set. */
        public bool has_service_problem() {
            return (this & SERVICE_PROBLEM) == SERVICE_PROBLEM;
        }

    }

    /**
     * A utility method to sort a Gee.Collection of {@link Folder}s by
     * their {@link FolderPath}s to ensure they comport with {@link
     * folders_available_unavailable}, {@link folders_created}, {@link
     * folders_deleted} signals' contracts.
     */
    public static Gee.BidirSortedSet<Folder>
        sort_by_path(Gee.Collection<Folder> folders) {
        Gee.TreeSet<Folder> sorted =
            new Gee.TreeSet<Folder>(Account.folder_path_comparator);
        sorted.add_all(folders);
        return sorted;
    }

    /**
     * Comparator used to sort folders.
     *
     * @see sort_by_path
     */
    public static int folder_path_comparator(Geary.Folder a, Geary.Folder b) {
        return a.path.compare_to(b.path);
    }


    /**
     * The account's current configuration.
     */
    public AccountInformation information { get; protected set; }

    /**
     * The account's current status.
     *
     * This property's value is set based on the {@link
     * ClientService.current_status} of the account's {@link incoming}
     * and {@link outgoing} services. See {@link Status} for more
     * information.
     *
     * The initial value for this property is {@link Status.ONLINE},
     * which may or may not be incorrect. However the once the account
     * has been opened, its services will begin checking connectivity
     * and the value will be updated to match in due course.
     *
     * @see ClientService.current_status
     */
    public Status current_status { get; protected set; default = ONLINE; }

    /**
     * The service manager for the incoming email service.
     */
    public ClientService incoming { get; private set; }

    /**
     * The service manager for the outgoing email service.
     */
    public ClientService outgoing { get; private set; }

    /**
     * The contact information store for this account.
     */
    public Geary.ContactStore contact_store { get; protected set; }

    /**
     * The root path for all local folders.
     *
     * Any local folders create by the engine or clients must use this
     * as the root for local folders.
     */
    public FolderRoot local_folder_root {
        get; private set; default = new Geary.FolderRoot("$geary-local", true);
    }

    public ProgressMonitor background_progress { get; protected set; }
    public ProgressMonitor db_upgrade_monitor { get; protected set; }
    public ProgressMonitor db_vacuum_monitor { get; protected set; }

    /**
     * The last time the account storage was cleaned.
     *
     * This does not imply that a full reap plus vacuum garbage
     * collection (GC) is performed, merely that:
     * 1. Any old messages are removed
     * 2. If any old messages were removed, or the defined period
     * (in ImapDB.GC) has past, a GC reap is performed
     * 3. GC vacuum is run if recommended
     */
    public GLib.DateTime? last_storage_cleanup { get; set; }

    public signal void opened();

    public signal void closed();


    /**
     * Emitted to notify the client that some problem has occurred.
     *
     * The engine uses this signal to report internal errors and other
     * issues that the client should notify the user about. The {@link
     * ProblemReport} class provides context about the nature of the
     * problem itself.
     */
    public signal void report_problem(Geary.ProblemReport problem);

    /**
     * Fired when folders become available or unavailable in the account.
     *
     * Folders become available when the account is first opened or when
     * they're created later; they become unavailable when the account is
     * closed or they're deleted later.
     *
     * Folders are ordered for the convenience of the caller from the
     * top of the hierarchy to lower in the hierarchy.  In other
     * words, parents are listed before children, assuming the
     * collections are traversed in natural order.
     *
     * @see sort_by_path
     */
    public signal void
        folders_available_unavailable(Gee.BidirSortedSet<Folder>? available,
                                      Gee.BidirSortedSet<Folder>? unavailable);

    /**
     * Fired when new folders have been created.
     *
     * This is fired in response to new folders appearing, for example
     * the user created a new folder. It will be fired after {@link
     * folders_available_unavailable} has been fired to mark the
     * folders as having been made available.
     *
     * Folders are ordered for the convenience of the caller from the
     * top of the hierarchy to lower in the hierarchy.  In other
     * words, parents are listed before children, assuming the
     * collection is traversed in natural order.
     */
    public signal void folders_created(Gee.BidirSortedSet<Geary.Folder> created);

    /**
     * Fired when existing folders are deleted.
     *
     * This is fired in response to existing folders being removed,
     * for example if the user deleted a folder. it will be fired
     * after {@link folders_available_unavailable} has been fired to
     * mark the folders as having been made unavailable.
     *
     * Folders are ordered for the convenience of the caller from the
     * top of the hierarchy to lower in the hierarchy.  In other
     * words, parents are listed before children, assuming the
     * collection is traversed in natural order.
     */
    public signal void folders_deleted(Gee.BidirSortedSet<Geary.Folder> deleted);

    /**
     * Fired when a Folder's special use is detected having changed.
     */
    public signal void folders_use_changed(Gee.Collection<Geary.Folder> altered);

    /**
     * Fired when emails are appended to a folder in this account.
     */
    public signal void email_appended(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when emails are inserted to a folder in this account.
     *
     * @see Folder.email_inserted
     */
    public signal void email_inserted(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when emails are removed from a folder in this account.
     */
    public signal void email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when emails are removed from a local folder in this account.
     */
    public signal void email_locally_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when one or more emails have been locally saved to a folder with
     * the full set of Fields.
     */
    public signal void email_locally_complete(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when one or more emails have been discovered (added) to the Folder, but not necessarily
     * appended (i.e. old email pulled down due to user request or background fetching).
     */
    public signal void email_discovered(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids);

    /**
     * Fired when the supplied email flags have changed from any folder.
     */
    public signal void email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map);

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return null; } }


    protected Account(AccountInformation information,
                      ClientService incoming,
                      ClientService outgoing) {
        this.information = information;
        this.incoming = incoming;
        this.outgoing = outgoing;

        incoming.notify["current-status"].connect(
            on_service_status_notify
        );
        outgoing.notify["current-status"].connect(
            on_service_status_notify
        );
    }

    /**
     * Opens the {@link Account} and makes it and its {@link Folder}s available for use.
     *
     * @throws EngineError.CORRUPT if the local store is corrupt or unusable
     * @throws EngineError.PERMISSIONS if the local store is inaccessible
     * @throws EngineError.VERSION if the local store was created or updated for a different
     *         version of Geary.
     */
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;

    /**
     * Closes the {@link Account}, which makes most its operations unavailable.
     *
     * This does not delete the Account, merely closes database and network channels.
     *
     * Returns without error if the Account is already closed.
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;

    /**
     * Returns true if this account is open, else false.
     */
    public abstract bool is_open();

    /**
     * Cancel any running/pending remote update for this {@link Account}.
     */
    public abstract void cancel_remote_update();

    /**
     * Rebuild the local data stores for this {@link Account}.
     *
     * This should only be used if {@link open_async} throws {@link EngineError.CORRUPT},
     * indicating that the local data store is corrupted and cannot be used.
     *
     * ''rebuild_async() will delete all local data''.
     *
     * If the Account is backed by a synchronized copy on the network, it will rebuild its local
     * mail store.  If not, the data is forever deleted.  Hence, it's best to query the user before
     * calling this method.
     *
     * Unlike most methods in Account, this should only be called when the Account is closed.
     */
    public abstract async void rebuild_async(Cancellable? cancellable = null) throws Error;

    /**
     * Returns an email identifier from its serialised form.
     *
     * This is useful for converting a string representation of a
     * email id back into an actual instance of an id. This does not
     * guarantee that the email represented by the id will exist.
     *
     * @see EmailIdentifier.to_variant
     * @throws EngineError.BAD_PARAMETERS when the variant is not the
     * have the correct type.
     */
    public abstract EmailIdentifier to_email_identifier(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS;

    /**
     * Returns the folder path from its serialised form.
     *
     * This is useful for converting a string representation of a
     * folder path back into an actual instance of a path. This does
     * not guarantee that the folder represented by the path will
     * exist.
     *
     * @see FolderPath.to_variant
     * @throws EngineError.BAD_PARAMETERS when the variant is not the
     * have the correct type or if no folder root with an appropriate
     * label exists.
     */
    public abstract FolderPath to_folder_path(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS;

    /**
     * Determines if a folder is known to the engine.
     *
     * This method only considers currently known folders, it does not
     * check the remote to see if a previously folder exists.
     */
    public virtual bool has_folder(FolderPath path) {
        try {
            get_folder(path);
            return true;
        } catch (EngineError.NOT_FOUND err) {
            return false;
        }
    }

    /**
     * Returns the folder represented by a specific path.
     *
     * This method only considers currently known folders, it does not
     * check the remote to see if a previously folder exists.
     *
     * @throws EngineError.NOT_FOUND if the folder does not exist.
     */
    public abstract Folder get_folder(FolderPath path)
        throws EngineError.NOT_FOUND;

    /**
     * Lists all currently-available folders.
     *
     * @see list_matching_folders
     */
    public abstract Gee.Collection<Folder> list_folders();

    /**
     * Lists all currently-available folders found a under parent.
     *
     * If the parent path cannot be found, EngineError.NOT_FOUND is
     * thrown. However, the caller should be prepared to deal with an
     * empty list being returned instead.
     */
    public abstract Gee.Collection<Folder> list_matching_folders(FolderPath? parent)
        throws EngineError.NOT_FOUND;

    /**
     * Returns a folder for the given special folder type, it is exists.
     */
    public virtual Geary.Folder? get_special_folder(Folder.SpecialUse use) {
        return traverse<Folder>(list_folders())
            .first_matching(f => f.used_as == use);
    }

    /**
     * Returns the Folder object with the given special folder type.  The folder will be
     * created on the server if it doesn't already exist.  An error will be thrown if the
     * folder doesn't exist and can't be created.  The only valid special folder types that
     * can be required are: DRAFTS, SENT, JUNK, and TRASH.
     */
    public abstract async Geary.Folder get_required_special_folder_async(
        Folder.SpecialUse special,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

    /**
     * Creates a new folder in the root of the personal name space.
     *
     * If this account is backed by a remote server, calling this
     * causes the folder to be created on the remote.
     */
    public abstract async Folder create_personal_folder(
        string name,
        Folder.SpecialUse use = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

    /**
     * Registers a local folder with the account.
     *
     * The registering a local folder will cause the account will hook
     * to the folder's signals such as {@link Folder.email_appended}
     * and forward them on to the account-wide equivalents, include
     * the list folder in the folder list, allow email in the folder
     * to be found by account-wide operations, and so on. The folder
     * will then be signalled as being available via {@link
     * folders_available_unavailable}.
     *
     * A {@link EngineError.ALREADY_EXISTS} exception will be thrown
     * if the given folder is already registered, or {@link
     * EngineError.NOT_FOUND} if its path does not have {@link
     * local_folder_root} as its root.
     *
     * @see deregister_local_folder
     */
    public abstract void register_local_folder(Folder local)
        throws GLib.Error;

    /**
     * De-registers a local folder with the account.
     *
     * De-registering a previously registered local folder will signal
     * it as being unavailable via {@link
     * folders_available_unavailable} and unhook it from the account.
     *
     * A {@link local_folder_root} error will be thrown if the given
     * folder is not already registered.
     *
     * @see register_local_folder
     */
    public abstract void deregister_local_folder(Folder local)
        throws GLib.Error;

    /**
     * Search the local account for emails referencing a Message-ID value
     * (which can appear in the Message-ID header itself, as well as the
     * In-Reply-To header, and maybe more places).  Fetch the requested fields,
     * optionally ignoring emails that don't have the requested fields set.
     * Don't include emails that appear in any of the blacklisted folders in
     * the result.  If null is included in the blacklist, omit emails appearing
     * in no folders.  Return a map of Email object to a list of FolderPaths
     * it's in, which can be null if it's in no folders.
     */
    public abstract async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Geary.EmailFlags? flag_blacklist,
        Cancellable? cancellable = null) throws Error;

    /**
     * Return a single email fulfilling the required fields.  The email to pull
     * is identified by an EmailIdentifier from a previous call to
     * local_search_message_id_async() or local_search_async().  Throw
     * EngineError.NOT_FOUND if the email isn't found and
     * EngineError.INCOMPLETE_MESSAGE if the fields aren't available.
     */
    public abstract async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;

    /**
     * Return a collection of email with the given identifiers.
     *
     * The returned collection will be in the same order as the
     * natural ordering of the given identifiers.
     *
     * Throws {@link EngineError.NOT_FOUND} if any email is not found
     * and {@link EngineError.INCOMPLETE_MESSAGE} if the fields aren't
     * available.
     */
    public abstract async Gee.List<Email> list_local_email_async(
        Gee.Collection<EmailIdentifier> ids,
        Email.Field required_fields,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

    /**
     * Create a new search query for this account.
     */
    public abstract SearchQuery new_search_query(
        Gee.List<SearchQuery.Term> expression,
        string text
    ) throws GLib.Error;

    /**
     * Performs a search with the given query.  Optionally, a list of folders not to search
     * can be passed as well as a list of email identifiers to restrict the search to only those messages.
     * Returns a list of EmailIdentifiers, or null if there are no results.
     * The list is limited to a maximum number of results and starting offset,
     * so you can walk the table.  limit can be negative to mean "no limit" but
     * offset must not be negative.
     */
    public abstract async Gee.Collection<Geary.EmailIdentifier>? local_search_async(Geary.SearchQuery query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error;

    /**
     * Given a list of mail IDs, returns a set of casefolded words that match for the query.
     */
    public abstract async Gee.Set<string>? get_search_matches_async(Geary.SearchQuery query,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;

    /**
     * Return a map of each passed-in email identifier to the set of folders
     * that contain it.  If an email id doesn't appear in the resulting map,
     * it isn't contained in any folders.  Return null if the resulting map
     * would be empty.  Only throw database errors et al., not errors due to
     * the email id not being found.
     */
    public abstract async Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? get_containing_folders_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error;

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(this, this.information.id);
    }

    /**
     * Perform cleanup of account storage.
     *
     * Work is performed if the appropriate interval has past since last
     * execution. Alternatively if the interval has not past but vacuum GC
     * has been flagged to run this will be executed. Designed to be run
     * while the app is in the background and idle.
     */
    public abstract async void cleanup_storage(GLib.Cancellable? cancellable)
        throws GLib.Error;

    /** Fires a {@link opened} signal. */
    protected virtual void notify_opened() {
        opened();
    }

    /** Fires a {@link closed} signal. */
    protected virtual void notify_closed() {
        closed();
    }

    /** Fires a {@link folders_available_unavailable} signal. */
    protected virtual void
        notify_folders_available_unavailable(Gee.BidirSortedSet<Folder>? available,
                                             Gee.BidirSortedSet<Folder>? unavailable) {
        folders_available_unavailable(available, unavailable);
    }

    /** Fires a {@link folders_created} signal. */
    protected virtual void notify_folders_created(Gee.BidirSortedSet<Geary.Folder> created) {
        folders_created(created);
    }

    /** Fires a {@link folders_deleted} signal. */
    protected virtual void notify_folders_deleted(Gee.BidirSortedSet<Geary.Folder> deleted) {
        folders_deleted(deleted);
    }

    /** Fires a {@link email_appended} signal. */
    protected virtual void notify_email_appended(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        email_appended(folder, ids);
    }

    /** Fires a {@link email_inserted} signal. */
    protected virtual void notify_email_inserted(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        email_inserted(folder, ids);
    }

    /** Fires a {@link email_removed} signal. */
    protected virtual void notify_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        email_removed(folder, ids);
    }

    /** Fires a {@link email_locally_removed} signal. */
    protected virtual void notify_email_locally_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_removed(folder, ids);
    }

    /** Fires a {@link email_locally_complete} signal. */
    protected virtual void notify_email_locally_complete(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids) {
        email_locally_complete(folder, ids);
    }

    /** Fires a {@link email_discovered} signal. */
    protected virtual void notify_email_discovered(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids) {
        email_discovered(folder, ids);
    }

    /** Fires a {@link email_flags_changed} signal. */
    protected virtual void notify_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        email_flags_changed(folder, flag_map);
    }

    /** Fires a {@link report_problem} signal for this account. */
    protected virtual void notify_report_problem(ProblemReport report) {
        report_problem(report);
    }

    /**
     * Fires a {@link report_problem} signal for this account.
     */
    protected virtual void notify_account_problem(Error? err) {
        report_problem(new AccountProblemReport(this.information, err));
    }

    /** Fires a {@link report_problem} signal for a service for this account. */
    protected virtual void notify_service_problem(ServiceInformation service,
                                                  Error? err) {
        report_problem(
            new ServiceProblemReport(this.information, service, err)
        );
    }

    private void on_service_status_notify() {
        Status new_status = 0;
        // Don't consider service status UNKNOWN to indicate being
        // offline, since clients will indicate offline status, but
        // not indicate online status. So when at startup, or when
        // restarting services, we don't want to cause them to
        // spuriously indicate being offline.
        if (incoming.current_status != UNREACHABLE) {
            new_status |= ONLINE;
        }
        if (incoming.current_status.is_error() ||
            outgoing.current_status.is_error()) {
            new_status |= SERVICE_PROBLEM;
        }
        this.current_status = new_status;
    }

}
