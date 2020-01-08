/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.GenericAccount : Geary.Account {


    /** Default IMAP session pool size. */
    private const int IMAP_MIN_POOL_SIZE = 2;

    // This is high since it's an expensive operation, and we'll go
    // looking changes caused by local operations as they happen, so
    // we don't need to double check.
    private const int REFRESH_FOLDER_LIST_SEC = 15 * 60;

    private const Geary.SpecialFolderType[] SUPPORTED_SPECIAL_FOLDERS = {
        Geary.SpecialFolderType.DRAFTS,
        Geary.SpecialFolderType.SENT,
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
        Geary.SpecialFolderType.ARCHIVE,
    };

    private static GLib.VariantType email_id_type = new GLib.VariantType(
        EmailIdentifier.BASE_VARIANT_TYPE
    );


    /** Service for incoming IMAP connections. */
    public Imap.ClientService imap  { get; private set; }

    /** Service for outgoing SMTP connections. */
    public Smtp.ClientService smtp { get; private set; }

    /** Local database for the account. */
    public ImapDB.Account local { get; private set; }

    private bool open = false;
    private Cancellable? open_cancellable = null;
    private Nonblocking.Semaphore? remote_ready_lock = null;

    private Gee.Map<FolderPath,MinimalFolder> folder_map =
        new Gee.HashMap<FolderPath,MinimalFolder>();

    private AccountProcessor? processor;
    private AccountSynchronizer sync;
    private TimeoutManager refresh_folder_timer;

    private Gee.Map<Geary.SpecialFolderType, Gee.List<string>> special_search_names =
        new Gee.HashMap<Geary.SpecialFolderType, Gee.List<string>>();


    protected GenericAccount(AccountInformation config,
                             ImapDB.Account local,
                             Endpoint incoming_remote,
                             Endpoint outgoing_remote) {
        Imap.ClientService imap = new Imap.ClientService(
            config,
            config.incoming,
            incoming_remote
        );
        Smtp.ClientService smtp = new Smtp.ClientService(
            config,
            config.outgoing,
            outgoing_remote
        );

        base(config, imap, smtp);

        this.local = local;
        this.contact_store = new ContactStoreImpl(local.db);

        imap.min_pool_size = IMAP_MIN_POOL_SIZE;
        imap.notify["current-status"].connect(
            on_imap_status_notify
        );
        imap.set_logging_parent(this);
        this.imap = imap;

        smtp.outbox = new Outbox.Folder(this, local_folder_root, local);
        smtp.report_problem.connect(notify_report_problem);
        smtp.set_logging_parent(this);
        this.smtp = smtp;

        this.sync = new AccountSynchronizer(this);

        this.refresh_folder_timer = new TimeoutManager.seconds(
            REFRESH_FOLDER_LIST_SEC,
            () => { this.update_remote_folders(); }
         );

        this.background_progress = new ReentrantProgressMonitor(ACTIVITY);
        this.db_upgrade_monitor = local.upgrade_monitor;
        this.db_vacuum_monitor = local.vacuum_monitor;

        compile_special_search_names();
    }

    /** {@inheritDoc} */
    public override async void open_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account %s already opened", to_string());

        this.background_progress.notify_start();
        try {
            yield internal_open_async(cancellable);
        } finally {
            this.background_progress.notify_finish();
        }
    }

    private async void internal_open_async(Cancellable? cancellable) throws Error {
        this.open_cancellable = new Cancellable();
        this.remote_ready_lock = new Nonblocking.Semaphore(this.open_cancellable);

        this.processor = new AccountProcessor(this.background_progress);
        this.processor.operation_error.connect(on_operation_error);
        this.processor.set_logging_parent(this);

        try {
            yield this.local.open_async(cancellable);
        } catch (Error err) {
            // convert database-open errors
            if (err is DatabaseError.CORRUPT)
                throw new EngineError.CORRUPT("%s", err.message);
            else if (err is DatabaseError.ACCESS)
                throw new EngineError.PERMISSIONS("%s", err.message);
            else if (err is DatabaseError.SCHEMA_VERSION)
                throw new EngineError.VERSION("%s", err.message);
            else
                throw err;
        }

        this.open = true;
        notify_opened();

        this.queue_operation(
            new LoadFolders(this, this.local, get_supported_special_folders())
        );

        // Start the mail services. Start incoming directly, but queue
        // outgoing so local folders can be loaded first in case
        // queued mail gets sent and needs to get saved somewhere.
        yield this.imap.start(cancellable);
        this.queue_operation(new StartPostie(this));

        // Kick off a background update of the search table.
        //
        // XXX since this hammers the database, this is an example of
        // an operation for which we need an engine-wide operation
        // queue, not just an account-wide queue.
        this.queue_operation(new PopulateSearchTable(this));
    }

    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;

        // Stop attempting to send any outgoing messages
        try {
            yield this.smtp.stop();
        } catch (Error err) {
            debug("Error stopping SMTP service: %s", err.message);
        }

        // Halt internal tasks early so they stop using local and
        // remote connections.
        this.refresh_folder_timer.reset();
        this.open_cancellable.cancel();
        this.processor.stop();

        // Block obtaining and reusing IMAP connections. This *must*
        // happen after internal tasks above are cancelled otherwise
        // they may block while waiting/using a remote session.
        this.imap.discard_returned_sessions = true;
        this.remote_ready_lock.reset();

        // Close folders and ensure they do in fact close

        Gee.BidirSortedSet<Folder> remotes = sort_by_path(this.folder_map.values);
        this.folder_map.clear();
        notify_folders_available_unavailable(null, remotes);

        foreach (Geary.Folder folder in remotes) {
            debug("Waiting for remote to close: %s", folder.to_string());
            yield folder.wait_for_close_async();
        }

        // Close IMAP service manager now that folders are closed

        try {
            yield this.imap.stop();
        } catch (Error err) {
            debug("Error stopping IMAP service: %s", err.message);
        }
        this.remote_ready_lock = null;

        // Close local infrastructure

        try {
            yield local.close_async(cancellable);
        } finally {
            this.open = false;
            notify_closed();
        }
    }

    /** {@inheritDoc} */
    public override bool is_open() {
        return open;
    }

    public override async void rebuild_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (this.open) {
            throw new EngineError.ALREADY_OPEN(
                "Account cannot be open during rebuild"
            );
        }

        message("Rebuilding account local data");
        yield this.local.delete_all_data(cancellable);
        message("Rebuild complete");
    }

    /**
     * Queues an operation for execution by this account.
     *
     * The operation will added to the account's {@link
     * AccountProcessor} and executed asynchronously by that when it
     * reaches the front.
     */
    public void queue_operation(AccountOperation op)
        throws EngineError {
        check_open();
        debug("Enqueuing operation: %s", op.to_string());
        this.processor.enqueue(op);
    }

    /**
     * Claims a new IMAP account session from the pool.
     *
     * A new IMAP client session will be retrieved from the pool,
     * connecting if needed, and used for a new account session. This
     * call will wait until the pool is ready to provide sessions. The
     * session must be returned via {@link release_account_session}
     * after use.
     *
     * The account must have been opened before calling this method.
     */
    public async Imap.AccountSession claim_account_session(Cancellable? cancellable = null)
        throws Error {
        check_open();
        debug("Acquiring account session");
        yield this.remote_ready_lock.wait_async(cancellable);
        var client = yield this.imap.claim_authorized_session_async(cancellable);
        var session = new Imap.AccountSession(this.local.imap_folder_root, client);
        session.set_logging_parent(this.imap);
        return session;
    }

    /**
     * Returns an IMAP account session to the pool for re-use.
     */
    public void release_account_session(Imap.AccountSession session) {
        debug("Releasing account session");
        Imap.ClientSession? old_session = session.close();
        if (old_session != null) {
            this.imap.release_session_async.begin(
                old_session,
                (obj, res) => {
                    try {
                        this.imap.release_session_async.end(res);
                    } catch (Error err) {
                        debug(
                            "Error releasing account session: %s", err.message
                        );
                    }
                }
            );
        }
    }

    /**
     * Claims a new IMAP folder session from the pool.
     *
     * A new IMAP client session will be retrieved from the pool,
     * connecting if needed, and used for a new folder session. This
     * call will wait until the pool is ready to provide sessions. The
     * session must be returned via {@link release_folder_session}
     * after use.
     *
     * The account must have been opened before calling this method.
     */
    public async Imap.FolderSession claim_folder_session(Geary.FolderPath path,
                                                         Cancellable cancellable)
        throws Error {
        check_open();
        debug("Acquiring folder session for: %s", path.to_string());
        yield this.remote_ready_lock.wait_async(cancellable);

        // We manually construct an account session here and then
        // reuse it for the folder session so we only need to claim as
        // single session from the pool, not two.

        Imap.ClientSession? client =
            yield this.imap.claim_authorized_session_async(cancellable);
        Imap.AccountSession account = new Imap.AccountSession(
            this.local.imap_folder_root, client
        );
        account.set_logging_parent(this.imap);

        Imap.Folder? folder = null;
        GLib.Error? folder_err = null;
        try {
            folder = yield account.fetch_folder_async(path, cancellable);
        } catch (Error err) {
            folder_err = err;
        }

        account.close();

        Imap.FolderSession? folder_session = null;
        if (folder_err == null) {
            try {
                folder_session = yield new Imap.FolderSession(
                    client, folder, cancellable
                );
                folder_session.set_logging_parent(this.imap);
            } catch (Error err) {
                folder_err = err;
            }
        }

        if (folder_err != null) {
            try {
                yield this.imap.release_session_async(client);
            } catch (Error release_err) {
                debug("Error releasing folder session: %s", release_err.message);
            }

            throw folder_err;
        }

        return folder_session;
    }

    /**
     * Returns an IMAP folder session to the pool for cleanup and re-use.
     */
    public async void release_folder_session(Imap.FolderSession session) {
        debug("Releasing folder session");
        Imap.ClientSession? old_session = session.close();
        if (old_session != null) {
            try {
                yield this.imap.release_session_async(old_session);
            } catch (Error err) {
                debug("Error releasing %s session: %s",
                      session.folder.path.to_string(),
                      err.message);
            }
        }
    }

    /** {@inheritDoc} */
    public override EmailIdentifier to_email_identifier(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        if (!serialised.is_of_type(GenericAccount.email_id_type)) {
            throw new EngineError.BAD_PARAMETERS("Invalid outer serialised type");
        }
        char type = (char) serialised.get_child_value(0).get_byte();
        if (type == 'i')
            return new ImapDB.EmailIdentifier.from_variant(serialised);
        if (type == 'o')
            return new Outbox.EmailIdentifier.from_variant(serialised);

        throw new EngineError.BAD_PARAMETERS("Unknown serialised type: %c", type);
    }

    /** {@inheritDoc} */
    public override FolderPath to_folder_path(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        FolderPath? path = null;
        try {
            path = this.local.imap_folder_root.from_variant(serialised);
        } catch (EngineError.BAD_PARAMETERS err) {
            path = this.local_folder_root.from_variant(serialised);
        }
        return path;
    }

    /** {@inheritDoc} */
    public override Folder get_folder(FolderPath path)
        throws EngineError.NOT_FOUND {
        Folder? folder = this.folder_map.get(path);
        if (folder == null) {
            throw new EngineError.NOT_FOUND(
                "Folder not found: %s", path.to_string()
            );
        }
        return folder;
    }

    /** {@inheritDoc} */
    public override Gee.Collection<Folder> list_folders() {
        var all = new Gee.HashSet<Folder>();
        all.add_all(this.folder_map.values);
        return all;
    }

    /** {@inheritDoc} */
    public override Gee.Collection<Folder> list_matching_folders(FolderPath? parent)
        throws EngineError.NOT_FOUND {
        return traverse<FolderPath>(folder_map.keys)
            .filter(p => {
                FolderPath? path_parent = p.parent;
                return ((parent == null && path_parent == null) ||
                    (parent != null && path_parent != null &&
                     path_parent.equal_to(parent)));
            })
            .map<Geary.Folder>(p => folder_map.get(p))
            .to_array_list();
    }

    public override async Geary.Folder get_required_special_folder_async(Geary.SpecialFolderType special,
        Cancellable? cancellable) throws Error {
        if (!(special in get_supported_special_folders())) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid special folder type %s passed to get_required_special_folder_async",
                special.to_string());
        }
        check_open();

        Geary.Folder? folder = get_special_folder(special);
        if (folder == null) {
            Imap.AccountSession account = yield claim_account_session();
            try {
                folder = yield ensure_special_folder_async(account, special, cancellable);
            } finally {
                release_account_session(account);
            }
        }
        return folder;
    }

    private ImapDB.EmailIdentifier check_id(Geary.EmailIdentifier id) throws EngineError {
        ImapDB.EmailIdentifier? imapdb_id = id as ImapDB.EmailIdentifier;
        if (imapdb_id == null)
            throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not from ImapDB folder", id.to_string());

        return imapdb_id;
    }

    private Gee.Collection<ImapDB.EmailIdentifier> check_ids(Gee.Collection<Geary.EmailIdentifier> ids)
        throws EngineError {
        foreach (Geary.EmailIdentifier id in ids) {
            if (!(id is ImapDB.EmailIdentifier))
                throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not from ImapDB folder", id.to_string());
        }

        return (Gee.Collection<ImapDB.EmailIdentifier>) ids;
    }

    /** {@inheritDoc} */
    public override async SearchQuery new_search_query(string query,
                                                       SearchQuery.Strategy strategy,
                                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        return yield new ImapDB.SearchQuery(
            this, local, query, strategy, cancellable
        );
    }

    public override async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Geary.EmailFlags? flag_blacklist,
        Cancellable? cancellable = null) throws Error {
        return yield local.search_message_id_async(
            message_id, requested_fields, partial_ok, folder_blacklist, flag_blacklist, cancellable);
    }

    public override async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        return yield local.fetch_email_async(check_id(email_id), required_fields, cancellable);
    }

    /** {@inheritDoc} */
    public override async Gee.List<Email> list_local_email_async(
        Gee.Collection<EmailIdentifier> ids,
        Email.Field required_fields,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return yield local.list_email(
            check_ids(ids), required_fields, cancellable
        );
    }

    public override async Gee.Collection<Geary.EmailIdentifier>? local_search_async(Geary.SearchQuery query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error {
        if (offset < 0)
            throw new EngineError.BAD_PARAMETERS("Offset must not be negative");

        return yield local.search_async(query, limit, offset, folder_blacklist, search_ids, cancellable);
    }

    public override async Gee.Set<string>? get_search_matches_async(Geary.SearchQuery query,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        return yield local.get_search_matches_async(query, check_ids(ids), cancellable);
    }

    public override async Gee.MultiMap<EmailIdentifier,FolderPath>?
        get_containing_folders_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        Gee.MultiMap<EmailIdentifier,FolderPath> map =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        yield this.local.get_containing_folders_async(ids, map, cancellable);
        yield this.smtp.outbox.add_to_containing_folders_async(ids, map, cancellable);
        return (map.size == 0) ? null : map;
    }

    /**
     * Constructs a set of folders and adds them to the account.
     *
     * This constructs a high-level folder representation for each
     * folder, adds them to this account object, fires the appropriate
     * signals, then returns them. Both the local and remote folder
     * equivalents need to exist beforehand — they are not created.
     *
     * If `are_existing` is true, the folders are assumed to have been
     * seen before and the {@link Geary.Account.folders_created} signal is
     * not fired.
     */
    internal Gee.Collection<Folder> add_folders(Gee.Collection<ImapDB.Folder> db_folders,
                                                bool are_existing) {
        Gee.TreeSet<MinimalFolder> built_folders = new Gee.TreeSet<MinimalFolder>(
            Account.folder_path_comparator
        );
        foreach(ImapDB.Folder db_folder in db_folders) {
            if (!this.folder_map.has_key(db_folder.get_path())) {
                MinimalFolder folder = new_folder(db_folder);
                folder.report_problem.connect(notify_report_problem);
                built_folders.add(folder);
                this.folder_map.set(folder.path, folder);
            }
        }

        if (!built_folders.is_empty) {
            notify_folders_available_unavailable(built_folders, null);
            if (!are_existing) {
                notify_folders_created(built_folders);
            }
        }

        return built_folders;
    }

    /**
     * Fires appropriate signals for a single altered folder.
     *
     * This is functionally equivalent to {@link update_folders}.
     */
    internal void update_folder(Geary.Folder folder) {
        Gee.Collection<Geary.Folder> folders =
            new Gee.LinkedList<Geary.Folder>();
        folders.add(folder);
        debug("Folder updated: %s", folder.path.to_string());
        notify_folders_contents_altered(folders);
    }

    /**
     * Fires appropriate signals for folders have been altered.
     *
     * This is functionally equivalent to {@link update_folder}.
     */
    internal void update_folders(Gee.Collection<Geary.Folder> folders) {
        if (!folders.is_empty) {
            notify_folders_contents_altered(sort_by_path(folders));
        }
    }

    /**
     * Marks a folder as a specific special folder type.
     */
    internal void promote_folders(Gee.Map<Geary.SpecialFolderType,Geary.Folder> specials) {
        Gee.Set<Geary.Folder> changed = new Gee.HashSet<Geary.Folder>();
        foreach (Geary.SpecialFolderType special in specials.keys) {
            MinimalFolder? minimal = specials.get(special) as MinimalFolder;
            if (minimal.special_folder_type != special) {
                debug("Promoting %s to %s",
                      minimal.to_string(), special.to_string());
                minimal.set_special_folder_type(special);
                changed.add(minimal);

                MinimalFolder? existing =
                    get_special_folder(special) as MinimalFolder;
                if (existing != null && existing != minimal) {
                    existing.set_special_folder_type(SpecialFolderType.NONE);
                    changed.add(existing);
                }
            }
        }

        if (!changed.is_empty) {
            folders_special_type(changed);
        }
    }

    /**
     * Removes a set of folders from the account.
     *
     * This removes the high-level folder representations from this
     * account object, and fires the appropriate signals. Deletion of
     * both the local and remote folder equivalents must be handled
     * before, then after calling this method.
     *
     * A collection of folders that was actually removed is returned.
     */
    internal Gee.BidirSortedSet<MinimalFolder>
        remove_folders(Gee.Collection<Folder> folders) {
        Gee.TreeSet<MinimalFolder> removed = new Gee.TreeSet<MinimalFolder>(
            Account.folder_path_comparator
        );
        foreach(Geary.Folder folder in folders) {
            MinimalFolder? impl = this.folder_map.get(folder.path);
            if (impl != null) {
                this.folder_map.unset(folder.path);
                removed.add(impl);
            }
        }

        if (!removed.is_empty) {
            notify_folders_available_unavailable(null, removed);
            notify_folders_deleted(removed);
        }

        return removed;
    }

    /**
     * Locates a special folder, creating it if needed.
     */
    internal async Folder
        ensure_special_folder_async(Imap.AccountSession remote,
                                    SpecialFolderType type,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        Folder? special = get_special_folder(type);
        if (special == null) {
            FolderPath? path = information.get_special_folder_path(type);
            if (path != null) {
                if (!remote.is_folder_path_valid(path)) {
                    warning(
                        "Ignoring bad special folder path '%s' for type %s",
                        path.to_string(),
                        type.to_string()
                    );
                    path = null;
                } else {
                    path = this.local.imap_folder_root.copy(path);
                }
            }

            if (path == null) {
                FolderPath root =
                    yield remote.get_default_personal_namespace(cancellable);
                Gee.List<string> search_names = special_search_names.get(type);
                foreach (string search_name in search_names) {
                    FolderPath search_path = root.get_child(search_name);
                    foreach (FolderPath test_path in folder_map.keys) {
                        if (test_path.compare_normalized_ci(search_path) == 0) {
                            path = search_path;
                            break;
                        }
                    }
                    if (path != null)
                        break;
                }

                if (path == null) {
                    path = root.get_child(search_names[0]);
                }

                debug("Guessed folder \'%s\' for special_path %s",
                      path.to_string(), type.to_string()
                );
                information.set_special_folder_path(type, path);
            }

            if (!this.folder_map.has_key(path)) {
                debug("Creating \"%s\" to use as special folder %s",
                      path.to_string(), type.to_string());

                GLib.Error? created_err = null;
                try {
                    yield remote.create_folder_async(path, type, cancellable);
                } catch (GLib.Error err) {
                    // Hang on to the error since the folder might exist
                    // on the remote, so try fetching it anyway.
                    created_err = err;
                }

                Imap.Folder? remote_folder = null;
                try {
                    remote_folder = yield remote.fetch_folder_async(
                        path, cancellable
                    );
                } catch (GLib.Error err) {
                    // If we couldn't fetch it after also failing to
                    // create it, it's probably due to the problem
                    // creating it, so throw that error instead.
                    if (created_err != null) {
                        throw created_err;
                    } else {
                        throw err;
                    }
                }

                ImapDB.Folder local_folder =
                    yield this.local.clone_folder_async(
                        remote_folder, cancellable
                    );
                add_folders(
                    Collection.single(local_folder), created_err != null
                );
            }

            special= this.folder_map.get(path);
            promote_folders(
                Collection.single_map<SpecialFolderType,Folder>(
                    type, special
                )
            );
        }

        return special;
    }

    /**
     * Constructs a concrete folder implementation.
     *
     * Subclasses should implement this to return their flavor of a
     * MinimalFolder with the appropriate interfaces attached.  The
     * returned folder should have its SpecialFolderType set using
     * either the properties from the local folder or its path.
     *
     * This won't be called to build the Outbox or search folder, but
     * for all others (including Inbox) it will.
     */
    protected abstract MinimalFolder new_folder(ImapDB.Folder local_folder);

    /** {@inheritDoc} */
    protected override void
        notify_folders_available_unavailable(Gee.BidirSortedSet<Folder>? available,
                                             Gee.BidirSortedSet<Folder>? unavailable) {
        base.notify_folders_available_unavailable(available, unavailable);
        if (available != null) {
            foreach (Geary.Folder folder in available) {
                folder.email_appended.connect(notify_email_appended);
                folder.email_inserted.connect(notify_email_inserted);
                folder.email_removed.connect(notify_email_removed);
                folder.email_locally_removed.connect(notify_email_locally_removed);
                folder.email_locally_complete.connect(notify_email_locally_complete);
                folder.email_flags_changed.connect(notify_email_flags_changed);
            }
        }
        if (unavailable != null) {
            foreach (Geary.Folder folder in unavailable) {
                folder.email_appended.disconnect(notify_email_appended);
                folder.email_inserted.disconnect(notify_email_inserted);
                folder.email_removed.disconnect(notify_email_removed);
                folder.email_locally_removed.disconnect(notify_email_locally_removed);
                folder.email_locally_complete.disconnect(notify_email_locally_complete);
                folder.email_flags_changed.disconnect(notify_email_flags_changed);
            }
        }
    }

    /** {@inheritDoc} */
    protected override void notify_email_appended(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_appended(folder, ids);
        schedule_unseen_update(folder);
    }

    /** {@inheritDoc} */
    protected override void notify_email_inserted(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_inserted(folder, ids);
        schedule_unseen_update(folder);
    }

    /** {@inheritDoc} */
    protected override void notify_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_removed(folder, ids);
        schedule_unseen_update(folder);
    }

    /** {@inheritDoc} */
    protected override void notify_email_locally_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_locally_removed(folder, ids);
    }

    /** {@inheritDoc} */
    protected override void notify_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        base.notify_email_flags_changed(folder, flag_map);
        schedule_unseen_update(folder);
    }

    /**
     * Hooks up and queues an {@link UpdateRemoteFolders} operation.
     */
    private void update_remote_folders() {
        this.refresh_folder_timer.reset();

        UpdateRemoteFolders op = new UpdateRemoteFolders(
            this,
            get_supported_special_folders()
        );
        op.completed.connect(() => {
                this.refresh_folder_timer.start();
            });
        try {
            queue_operation(op);
        } catch (Error err) {
            // oh well
        }
    }

    /**
     * Hooks up and queues an {@link RefreshFolderUnseen} operation.
     */
    private void schedule_unseen_update(Geary.Folder folder) {
        MinimalFolder? impl = folder as MinimalFolder;
        if (impl != null) {
            impl.refresh_unseen();
        }
    }

    protected virtual Geary.SpecialFolderType[] get_supported_special_folders() {
        return SUPPORTED_SPECIAL_FOLDERS;
    }

    private void compile_special_search_names() {
        /*
         * Compiles the list of names used to search for special
         * folders when they aren't known in advance and the server
         * supports neither SPECIAL-USE not XLIST.
         *
         * Uses both translated and untranslated names in case the
         * server has not localised the folders that match the login
         * session's language. Also checks for lower-case versions of
         * each.
         */
        foreach (Geary.SpecialFolderType type in get_supported_special_folders()) {
            Gee.List<string> compiled = new Gee.ArrayList<string>();
            foreach (string names in get_special_search_names(type)) {
                foreach (string name in names.split("|")) {
                    name = name.strip();
                    if (name.length != 0) {
                        if (!(name in compiled)) {
                            compiled.add(name);
                        }

                        name = name.down();
                        if (!(name in compiled)) {
                            compiled.add(name);
                        }
                    }
                }
            }
            special_search_names.set(type, compiled);
        }
    }

    private Gee.List<string> get_special_search_names(Geary.SpecialFolderType type) {
        Gee.List<string> loc_names = new Gee.ArrayList<string>();
        Gee.List<string> unloc_names = new Gee.ArrayList<string>();
        switch (type) {
        case Geary.SpecialFolderType.DRAFTS:
            // List of general possible folder names to match for the
            // Draft mailbox. Separate names using a vertical bar and
            // put the most common localized name to the front for the
            // default. English names do not need to be included.
            loc_names.add(_("Drafts | Draft"));
            unloc_names.add("Drafts | Draft");
            break;

        case Geary.SpecialFolderType.SENT:
            // List of general possible folder names to match for the
            // Sent mailbox. Separate names using a vertical bar and
            // put the most common localized name to the front for the
            // default. English names do not need to be included.
            loc_names.add(_("Sent | Sent Mail | Sent Email | Sent E-Mail"));
            unloc_names.add("Sent | Sent Mail | Sent Email | Sent E-Mail");

            // The localised name(s) of the Sent folder name as used
            // by MS Outlook/Exchange.
            loc_names.add(NC_("Outlook localised name", "Sent Items"));
            unloc_names.add("Sent Items");

            break;

        case Geary.SpecialFolderType.SPAM:
            // List of general possible folder names to match for the
            // Spam mailbox. Separate names using a vertical bar and
            // put the most common localized name to the front for the
            // default. English names do not need to be included.
            loc_names.add(_("Junk | Spam | Junk Mail | Junk Email | Junk E-Mail | Bulk Mail | Bulk Email | Bulk E-Mail"));
            unloc_names.add("Junk | Spam | Junk Mail | Junk Email | Junk E-Mail | Bulk Mail | Bulk Email | Bulk E-Mail");

            break;

        case Geary.SpecialFolderType.TRASH:
            // List of general possible folder names to match for the
            // Trash mailbox. Separate names using a vertical bar and
            // put the most common localized name to the front for the
            // default. English names do not need to be included.
            loc_names.add(_("Trash | Rubbish | Rubbish Bin"));
            unloc_names.add("Trash | Rubbish | Rubbish Bin");

            // The localised name(s) of the Trash folder name as used
            // by MS Outlook/Exchange.
            loc_names.add(NC_("Outlook localised name", "Deleted Items"));
            unloc_names.add("Deleted Items");

            break;

        case Geary.SpecialFolderType.ARCHIVE:
            // List of general possible folder names to match for the
            // Archive mailbox. Separate names using a vertical bar
            // and put the most common localized name to the front for
            // the default. English names do not need to be included.
            loc_names.add(_("Archive | Archives"));
            unloc_names.add("Archive | Archives");

            break;
        }

        loc_names.add_all(unloc_names);
        return loc_names;
    }

    private void check_open() throws EngineError {
        if (!open)
            throw new EngineError.OPEN_REQUIRED("Account %s not opened", to_string());
    }

    private void on_operation_error(AccountOperation op, Error error) {
        notify_service_problem(this.information.incoming, error);
    }

    private void on_imap_status_notify() {
        if (this.open) {
            if (this.imap.current_status == CONNECTED) {
                this.remote_ready_lock.blind_notify();
                update_remote_folders();
            } else {
                this.remote_ready_lock.reset();
                this.refresh_folder_timer.reset();
            }
        }
    }

}


/**
 * Account operation for loading local folders from the database.
 */
internal class Geary.ImapEngine.LoadFolders : AccountOperation {


    private weak ImapDB.Account local;
    private Geary.SpecialFolderType[] specials;


    internal LoadFolders(GenericAccount account,
                         ImapDB.Account local,
                         Geary.SpecialFolderType[] specials) {
        base(account);
        this.local = local;
        this.specials = specials;
    }

    public override async void execute(Cancellable cancellable) throws Error {
        GenericAccount generic = (GenericAccount) this.account;
        Gee.List<ImapDB.Folder> folders = new Gee.LinkedList<ImapDB.Folder>();

        yield enumerate_local_folders_async(
            folders, generic.local.imap_folder_root, cancellable
        );
        generic.add_folders(folders, true);
        if (!folders.is_empty) {
            // If we have some folders to load, then this isn't the
            // first run, and hence the special folders should already
            // exist
            yield check_special_folders(cancellable);
        }
    }

    private async void enumerate_local_folders_async(Gee.List<ImapDB.Folder> folders,
                                                     Geary.FolderPath parent,
                                                     Cancellable? cancellable)
        throws Error {
        Gee.Collection<ImapDB.Folder>? children = null;
        try {
            children = yield this.local.list_folders_async(parent, cancellable);
        } catch (EngineError err) {
            // don't pass on NOT_FOUND's, that means we need to go to
            // the server for more info
            if (!(err is EngineError.NOT_FOUND))
                throw err;
        }

        if (children != null) {
            foreach (ImapDB.Folder child in children) {
                folders.add(child);
                yield enumerate_local_folders_async(
                    folders, child.get_path(), cancellable
                );
            }
        }
    }

    private async void check_special_folders(GLib.Cancellable cancellable)
        throws GLib.Error {
        // Local folders loaded that have the SPECIAL-USE flags set
        // will have been promoted already via derived account type's
        // new_child overrides or some other means. However for those
        // that do not have the flag, check here against the local
        // config and promote ASAP.
        //
        // Can't just use ensure_special_folder_async however since
        // that will attempt to create the folders if missing, which
        // is bad if offline.
        GenericAccount generic = (GenericAccount) this.account;
        Gee.Map<Geary.SpecialFolderType,Geary.Folder> added_specials =
            new Gee.HashMap<Geary.SpecialFolderType,Geary.Folder>();
        foreach (Geary.SpecialFolderType type in this.specials) {
            if (generic.get_special_folder(type) == null) {
                Geary.FolderPath? path =
                    generic.information.get_special_folder_path(type);
                path = this.local.imap_folder_root.copy(path);
                if (path != null) {
                    try {
                        Geary.Folder target = generic.get_folder(path);
                        added_specials.set(type, target);
                    } catch (Error err) {
                        debug(
                            "Previously used special folder %s not loaded: %s",
                            type.to_string(),
                            err.message
                        );
                    }
                }
            }
        }

        generic.promote_folders(added_specials);
    }

}


/**
 * Account operation for starting the outgoing service.
 */
internal class Geary.ImapEngine.StartPostie : AccountOperation {


    internal StartPostie(Account account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws GLib.Error {
        yield this.account.outgoing.start(cancellable);
    }

}


/**
 * Account operation for populating the full-text-search table.
 */
internal class Geary.ImapEngine.PopulateSearchTable : AccountOperation {


    internal PopulateSearchTable(GenericAccount account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws GLib.Error {
        yield ((GenericAccount) this.account).local.populate_search_table(
            cancellable
        );
    }

}


/**
 * Account operation that updates folders from the remote.
 */
internal class Geary.ImapEngine.UpdateRemoteFolders : AccountOperation {


    private weak GenericAccount generic_account;
    private Geary.SpecialFolderType[] specials;


    internal UpdateRemoteFolders(GenericAccount account,
                                 Geary.SpecialFolderType[] specials) {
        base(account);
        this.generic_account = account;
        this.specials = specials;
    }

    public override async void execute(Cancellable cancellable) throws Error {
        Gee.Map<FolderPath, Geary.Folder> existing_folders =
            Geary.traverse<Geary.Folder>(this.account.list_folders())
            .to_hash_map<FolderPath>(f => f.path);
        Gee.Map<FolderPath, Imap.Folder> remote_folders =
            new Gee.HashMap<FolderPath, Imap.Folder>();

        GenericAccount account = (GenericAccount) this.account;
        Imap.AccountSession remote = yield account.claim_account_session(
            cancellable
        );
        try {
            bool is_suspect = yield enumerate_remote_folders_async(
                remote,
                remote_folders,
                account.local.imap_folder_root,
                cancellable
            );

            debug("Existing folders:");
            foreach (FolderPath path in existing_folders.keys) {
                debug(" - %s (%u)", path.to_string(), path.hash());
            }
            debug("Remote folders:");
            foreach (FolderPath path in remote_folders.keys) {
                debug(" - %s (%u)", path.to_string(), path.hash());
            }

            // pair the local and remote folders and make sure
            // everything is up-to-date
            yield update_folders_async(
                remote, existing_folders, remote_folders, is_suspect, cancellable
            );
        } finally {
            account.release_account_session(remote);
        }
    }

    private async bool enumerate_remote_folders_async(Imap.AccountSession remote,
                                                      Gee.Map<FolderPath,Imap.Folder> folders,
                                                      Geary.FolderPath? parent,
                                                      Cancellable? cancellable)
        throws Error {
        bool results_suspect = false;

        Gee.List<Imap.Folder>? children = null;
        try {
            children = yield remote.fetch_child_folders_async(parent, cancellable);
        } catch (Error err) {
            // ignore everything but I/O and IMAP errors (cancellation is an IOError)
            if (err is IOError || err is ImapError)
                throw err;
            debug("Ignoring error listing child folders of %s: %s",
                  (parent != null ? parent.to_string() : "root"), err.message);
            results_suspect = true;
        }

        if (children != null) {
            foreach (Imap.Folder child in children) {
                FolderPath path = child.path;
                folders.set(path, child);
                if (child.properties.has_children.is_possible() &&
                    yield enumerate_remote_folders_async(
                        remote, folders, path, cancellable)) {
                    results_suspect = true;
                }
            }
        }

        return results_suspect;
    }

    private async void update_folders_async(Imap.AccountSession remote,
                                            Gee.Map<FolderPath,Geary.Folder> existing_folders,
                                            Gee.Map<FolderPath,Imap.Folder> remote_folders,
                                            bool remote_folders_suspect,
                                            Cancellable? cancellable) {
        // update all remote folders properties in the local store and
        // active in the system
        Gee.HashSet<Geary.FolderPath> altered_paths = new Gee.HashSet<Geary.FolderPath>();
        foreach (Imap.Folder remote_folder in remote_folders.values) {
            MinimalFolder? minimal_folder = existing_folders.get(remote_folder.path)
                as MinimalFolder;
            if (minimal_folder == null)
                continue;

            // only worry about alterations if the remote is openable
            if (remote_folder.properties.is_openable.is_possible()) {
                ImapDB.Folder local_folder = minimal_folder.local_folder;

                if (remote_folder.properties.have_contents_changed(local_folder.get_properties(),
                    minimal_folder.to_string())) {
                    altered_paths.add(remote_folder.path);
                }
            }

            // always update, openable or not; have the folder update the UID info the next time
            // it's opened
            try {
                yield minimal_folder.local_folder.update_folder_status(
                    remote_folder.properties, false, cancellable
                );
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.path.to_string(), update_error.message);
            }

            // set the engine folder's special type (but only promote,
            // not demote, since getting the special folder type via
            // its properties relies on the optional SPECIAL-USE or
            // XLIST extensions) use this iteration to add discovered
            // properties to map
            if (minimal_folder.special_folder_type == SpecialFolderType.NONE)
                minimal_folder.set_special_folder_type(remote_folder.properties.attrs.get_special_folder_type());
        }

        // If path in remote but not local, need to add it
        Gee.ArrayList<Imap.Folder> to_add = Geary.traverse<Imap.Folder>(remote_folders.values)
            .filter(f => !existing_folders.has_key(f.path))
            .to_array_list();

        // Remove if path in local but not remote
        Gee.ArrayList<Geary.Folder> to_remove
            = Geary.traverse<Gee.Map.Entry<FolderPath,Geary.Folder>>(existing_folders)
            .filter(e => !remote_folders.has_key(e.key))
            .map<Geary.Folder>(e => (Geary.Folder) e.value)
            .to_array_list();

        // For folders to add, clone them and their properties
        // locally, then add to the account
        ImapDB.Account local = ((GenericAccount) this.account).local;
        Gee.ArrayList<ImapDB.Folder> to_build = new Gee.ArrayList<ImapDB.Folder>();
        foreach (Geary.Imap.Folder remote_folder in to_add) {
            try {
                to_build.add(
                    yield local.clone_folder_async(remote_folder, cancellable)
                );
            } catch (Error err) {
                debug("Unable to clone folder %s in local store: %s",
                      remote_folder.path.to_string(),
                      err.message);
            }
        }
        this.generic_account.add_folders(to_build, false);

        if (remote_folders_suspect) {
            debug("Skipping removing folders due to prior errors");
        } else {
            Gee.BidirSortedSet<MinimalFolder> removed =
                this.generic_account.remove_folders(to_remove);

            Gee.BidirIterator<MinimalFolder> removed_iterator =
                removed.bidir_iterator();
            bool has_prev = removed_iterator.last();
            while (has_prev) {
                MinimalFolder folder = removed_iterator.get();

                try {
                    debug("Locally deleting removed folder %s", folder.to_string());
                    yield local.delete_folder_async(folder.path, cancellable);
                } catch (Error e) {
                    debug("Unable to locally delete removed folder %s: %s", folder.to_string(), e.message);
                }

                has_prev = removed_iterator.previous();
            }

            // Let the remote know as well
            remote.folders_removed(
                Geary.traverse<Geary.Folder>(removed)
                .map<FolderPath>(f => f.path).to_array_list()
            );
        }

        // report all altered folders
        if (altered_paths.size > 0) {
            Gee.ArrayList<Geary.Folder> altered = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.FolderPath altered_path in altered_paths) {
                if (existing_folders.has_key(altered_path))
                    altered.add(existing_folders.get(altered_path));
                else
                    debug("Unable to report %s altered: no local representation", altered_path.to_string());
            }
            this.generic_account.update_folders(altered);
        }

        // Ensure each of the important special folders we need already exist
        foreach (Geary.SpecialFolderType special in this.specials) {
            try {
                yield this.generic_account.ensure_special_folder_async(
                    remote, special, cancellable
                );
            } catch (Error e) {
                warning("Unable to ensure special folder %s: %s", special.to_string(), e.message);
            }
        }
    }

}

/**
 * Account operation that updates a folder's unseen message count.
 *
 * This performs a IMAP STATUS on the folder, but only if it is not
 * open - if it is open it is already maintaining its unseen count.
 */
internal class Geary.ImapEngine.RefreshFolderUnseen : FolderOperation {


    internal RefreshFolderUnseen(MinimalFolder folder,
                                 GenericAccount account) {
        base(account, folder);
    }

    public override async void execute(Cancellable cancellable) throws Error {
        GenericAccount account = (GenericAccount) this.account;
        if (this.folder.get_open_state() == Geary.Folder.OpenState.CLOSED) {
            Imap.AccountSession? remote = yield account.claim_account_session(
                cancellable
            );
            try {
                Imap.Folder remote_folder = yield remote.fetch_folder_async(
                    folder.path,
                    cancellable
                );

                // Implementation-specific hack: Although this is called
                // when the MinimalFolder is closed, we can safely use
                // local_folder since we are only using its properties,
                // and the properties were loaded when the folder was
                // first instantiated.
                ImapDB.Folder local_folder = ((MinimalFolder) this.folder).local_folder;

                if (remote_folder.properties.have_contents_changed(
                        local_folder.get_properties(),
                        this.folder.to_string())) {

                    yield local_folder.update_folder_status(
                        remote_folder.properties, true, cancellable
                    );

                    ((GenericAccount) this.account).update_folder(this.folder);
                }
            } finally {
                account.release_account_session(remote);
            }
        }
    }

}
