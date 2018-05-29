/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>.
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

    /** This account's IMAP session pool. */
    public Imap.ClientSessionManager session_pool { get; private set; }

    internal ImapDB.Account local { get; private set; }

    private bool open = false;
    private Cancellable? open_cancellable = null;
    private Nonblocking.Semaphore? remote_ready_lock = null;

    private Geary.SearchFolder? search_folder { get; private set; default = null; }

    private Gee.HashMap<FolderPath, MinimalFolder> folder_map = new Gee.HashMap<
        FolderPath, MinimalFolder>();
    private Gee.HashMap<FolderPath, Folder> local_only = new Gee.HashMap<FolderPath, Folder>();

    private AccountProcessor? processor;
    private AccountSynchronizer sync;
    private TimeoutManager refresh_folder_timer;

    private uint authentication_failures = 0;


    private Gee.Map<Geary.SpecialFolderType, Gee.List<string>> special_search_names =
        new Gee.HashMap<Geary.SpecialFolderType, Gee.List<string>>();


    public GenericAccount(string name,
                          Geary.AccountInformation information,
                          ImapDB.Account local) {
        base(name, information);

        this.session_pool = new Imap.ClientSessionManager(
            this.information.id,
            this.information.imap.endpoint,
            this.information.imap.credentials
        );
        this.session_pool.min_pool_size = IMAP_MIN_POOL_SIZE;
        this.session_pool.ready.connect(on_pool_session_ready);
        this.session_pool.connection_failed.connect(on_pool_connection_failed);
        this.session_pool.login_failed.connect(on_pool_login_failed);

        this.local = local;
        this.local.contacts_loaded.connect(() => { contacts_loaded(); });
        this.local.email_sent.connect(on_email_sent);

        this.refresh_folder_timer = new TimeoutManager.seconds(
            REFRESH_FOLDER_LIST_SEC,
            () => { this.update_remote_folders(); }
         );

        search_upgrade_monitor = local.search_index_monitor;
        db_upgrade_monitor = local.upgrade_monitor;
        db_vacuum_monitor = local.vacuum_monitor;
        opening_monitor = new Geary.ReentrantProgressMonitor(Geary.ProgressType.ACTIVITY);
        sending_monitor = local.sending_monitor;

        this.sync = new AccountSynchronizer(this);

        compile_special_search_names();
    }

    /** {@inheritDoc} */
    public override async void open_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account %s already opened", to_string());

        opening_monitor.notify_start();
        try {
            yield internal_open_async(cancellable);
        } finally {
            opening_monitor.notify_finish();
        }
    }

    private async void internal_open_async(Cancellable? cancellable) throws Error {
        this.open_cancellable = new Cancellable();
        this.remote_ready_lock = new Nonblocking.Semaphore(this.open_cancellable);

        // Reset this so we start trying to authenticate again
        this.authentication_failures = 0;

        // To prevent spurious connection failures, we make sure we
        // have the IMAP password before attempting a connection.
        if (yield this.information.load_imap_credentials(cancellable)) {
            this.session_pool.credentials_updated(
                this.information.imap.credentials
            );
        }

        // This will cause the session manager to open at least one
        // connection if we are online
        yield this.session_pool.open_async(cancellable);

        this.processor = new AccountProcessor(this.to_string());
        this.processor.operation_error.connect(on_operation_error);

        try {
            yield local.open_async(information.data_dir, Engine.instance.resource_dir.get_child("sql"),
                cancellable);
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

        // Local folders

        local.outbox.report_problem.connect(notify_report_problem);
        local_only.set(new SmtpOutboxFolderRoot(), local.outbox);

        this.search_folder = new_search_folder();
        local_only.set(new ImapDB.SearchFolderRoot(), this.search_folder);

        this.open = true;
        notify_opened();
        notify_folders_available_unavailable(sort_by_path(local_only.values), null);

        this.queue_operation(
            new LoadFolders(this, this.local, get_supported_special_folders())
        );
    }

    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;

        // Block obtaining and reusing IMAP server connections
        this.remote_ready_lock.reset();
        this.session_pool.discard_returned_sessions = true;

        // Halt internal tasks early so they stop using local and
        // remote connections.
        this.refresh_folder_timer.reset();
        this.open_cancellable.cancel();
        this.processor.stop();

        // Close folders and ensure they do in fact close

        Gee.List<Geary.Folder> locals = sort_by_path(this.local_only.values);
        Gee.List<Geary.Folder> remotes = sort_by_path(this.folder_map.values);

        this.local_only.clear();
        this.folder_map.clear();

        notify_folders_available_unavailable(null, locals);
        notify_folders_available_unavailable(null, remotes);

        foreach (Geary.Folder folder in locals) {
            debug("%s: Waiting for local to close: %s", to_string(), folder.to_string());
            yield folder.wait_for_close_async();
        }
        foreach (Geary.Folder folder in remotes) {
            debug("%s: Waiting for remote to close: %s", to_string(), folder.to_string());
            yield folder.wait_for_close_async();
        }

        // Close remote infrastructure

        try {
            yield this.session_pool.close_async(cancellable);
        } catch (Error err) {
            debug("%s: Error closing IMAP session pool: %s",
                  to_string(),
                  this.session_pool.to_string()
            );
        }
        this.remote_ready_lock = null;

        // Close local infrastructure

        this.search_folder = null;
        this.local.outbox.report_problem.disconnect(notify_report_problem);
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

    public override async void rebuild_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account cannot be open during rebuild");
        
        message("%s: Rebuilding account local data", to_string());
        
        // get all the storage locations associated with this Account
        File db_file;
        File attachments_dir;
        ImapDB.Account.get_imap_db_storage_locations(information.data_dir, out db_file,
            out attachments_dir);
        
        if (yield Files.query_exists_async(db_file, cancellable)) {
            message("%s: Deleting database file %s...", to_string(), db_file.get_path());
            yield db_file.delete_async(Priority.DEFAULT, cancellable);
        }
        
        if (yield Files.query_exists_async(attachments_dir, cancellable)) {
            message("%s: Deleting attachments directory %s...", to_string(), attachments_dir.get_path());
            yield Files.recursive_delete_async(attachments_dir, cancellable);
        }
        
        message("%s: Rebuild complete", to_string());
    }

    /**
     * Starts the outbox postman running.
     */
    public override async void start_outgoing_client()
        throws Error {
        check_open();
        this.local.outbox.start_postman_async.begin();
    }

    /**
     * Closes then reopens the IMAP account if it is not ready.
     */
    public override async void start_incoming_client()
        throws Error {
        check_open();
        if (!this.session_pool.is_ready) {
            try {
                yield this.session_pool.close_async(this.open_cancellable);
            } catch (Error err) {
                debug("Ignoring error closing IMAP session pool for restart: %s",
                      err.message);
            }

            yield this.session_pool.open_async(this.open_cancellable);
        }
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
        debug("%s: Enqueuing operation: %s", this.to_string(), op.to_string());
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
        debug("%s: Acquiring account session", this.to_string());
        yield this.remote_ready_lock.wait_async(cancellable);
        Imap.ClientSession client =
            yield this.session_pool.claim_authorized_session_async(cancellable);
        return new Imap.AccountSession(this.information.id, client);
    }

    /**
     * Returns an IMAP account session to the pool for re-use.
     */
    public void release_account_session(Imap.AccountSession session) {
        debug("%s: Releasing account session", this.to_string());
        Imap.ClientSession? old_session = session.close();
        if (old_session != null) {
            this.session_pool.release_session_async.begin(
                old_session,
                (obj, res) => {
                    try {
                        this.session_pool.release_session_async.end(res);
                    } catch (Error err) {
                        debug("%s: Error releasing account session: %s",
                              to_string(),
                              err.message);
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
        debug("%s: Acquiring folder session", this.to_string());
        yield this.remote_ready_lock.wait_async(cancellable);

        // We manually construct an account session here and then
        // reuse it for the folder session so we only need to claim as
        // single session from the pool, not two.

        Imap.ClientSession? client =
            yield this.session_pool.claim_authorized_session_async(cancellable);
        Imap.AccountSession account = new Imap.AccountSession(
            this.information.id, client
        );

        Imap.Folder? folder = null;
        GLib.Error? folder_err = null;
        try {
            folder = yield account.fetch_folder_async(path, cancellable);
        } catch (Error err) {
            folder_err = err;
        }

        account.close();

        if (folder_err != null) {
            try {
                yield this.session_pool.release_session_async(client);
            } catch (Error release_err) {
                debug("Error releasing folder session: %s", release_err.message);
            }

            throw folder_err;
        }

        return yield new Imap.FolderSession(
            this.information.id, client, folder, cancellable
        );
    }

    /**
     * Returns an IMAP folder session to the pool for cleanup and re-use.
     */
    public async void release_folder_session(Imap.FolderSession session) {
        debug("%s: Releasing folder session", this.to_string());
        Imap.ClientSession? old_session = session.close();
        if (old_session != null) {
            try {
                yield this.session_pool.release_session_async(old_session);
            } catch (Error err) {
                debug("%s: Error releasing %s session: %s",
                      to_string(),
                      session.folder.path.to_string(),
                      err.message);
            }
        }
    }

    public override Gee.Collection<Geary.Folder> list_matching_folders(Geary.FolderPath? parent)
        throws Error {
        check_open();

        return Geary.traverse<FolderPath>(folder_map.keys)
            .filter(p => {
                FolderPath? path_parent = p.get_parent();
                return ((parent == null && path_parent == null) ||
                    (parent != null && path_parent != null && path_parent.equal_to(parent)));
            })
            .map<Geary.Folder>(p => folder_map.get(p))
            .to_array_list();
    }

    public override Gee.Collection<Geary.Folder> list_folders() throws Error {
        check_open();
        Gee.HashSet<Geary.Folder> all_folders = new Gee.HashSet<Geary.Folder>();
        all_folders.add_all(folder_map.values);
        all_folders.add_all(local_only.values);
        
        return all_folders;
    }

    public override Geary.ContactStore get_contact_store() {
        return local.contact_store;
    }

    /** {@inheritDoc} */
    public override async bool folder_exists_async(Geary.FolderPath path,
                                                   Cancellable? cancellable = null)
        throws Error {
        check_open();
        return this.local_only.has_key(path) || this.folder_map.has_key(path);
    }

    /** {@inheritDoc} */
    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
                                                          Cancellable? cancellable = null)
        throws Error {
        check_open();

        Geary.Folder? folder = this.local_only.get(path);
        if (folder == null) {
            folder = this.folder_map.get(path);

            if (folder == null) {
                throw new EngineError.NOT_FOUND(path.to_string());
            }
        }
        return folder;
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

    public override async void send_email_async(Geary.ComposedEmail composed,
        Cancellable? cancellable = null) throws Error {
        check_open();

        // TODO: we should probably not use someone else's FQDN in something
        // that's supposed to be globally unique...
        Geary.RFC822.Message rfc822 = new Geary.RFC822.Message.from_composed_email(
            composed, GMime.utils_generate_message_id(
                information.smtp.endpoint.remote_address.hostname
            ));

        // don't use create_email_async() as that requires the folder be open to use
        yield local.outbox.enqueue_email_async(rfc822, cancellable);
    }

    private void on_email_sent(Geary.RFC822.Message rfc822) {
        notify_email_sent(rfc822);
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
    
    public override Geary.SearchQuery open_search(string query, SearchQuery.Strategy strategy) {
        return new ImapDB.SearchQuery(local, query, strategy);
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
    
    public override async Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? get_containing_folders_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        return yield local.get_containing_folders_async(ids, cancellable);
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
    internal Gee.List<Geary.Folder> add_folders(Gee.Collection<ImapDB.Folder> db_folders,
                                                bool are_existing) {
        Gee.List<Geary.Folder> built_folders = new Gee.ArrayList<Geary.Folder>();
        foreach(ImapDB.Folder db_folder in db_folders) {
            if (!this.folder_map.has_key(db_folder.get_path())) {
                MinimalFolder folder = new_folder(db_folder);
                folder.report_problem.connect(notify_report_problem);
                built_folders.add(folder);
                this.folder_map.set(folder.path, folder);
            }
        }

        if (built_folders.size > 0) {
            built_folders = sort_by_path(built_folders);
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
        debug("Contents altered!");
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
                minimal.set_special_folder_type(special);
                changed.add(minimal);

                MinimalFolder? existing = null;
                try {
                    existing = get_special_folder(special) as MinimalFolder;
                } catch (Error err) {
                    debug("%s: Error getting special folder: %s",
                          to_string(), err.message);
                }

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
    internal Gee.List<MinimalFolder> remove_folders(Gee.Collection<Geary.Folder> folders) {
        Gee.List<MinimalFolder> removed = new Gee.ArrayList<MinimalFolder>();
        foreach(Geary.Folder folder in folders) {
            MinimalFolder? impl = this.folder_map.get(folder.path);
            if (impl != null) {
                this.folder_map.unset(folder.path);
                removed.add(impl);
            }
        }

        if (!removed.is_empty) {
            removed = (Gee.List<MinimalFolder>) sort_by_path(removed);
            notify_folders_available_unavailable(null, removed);
            notify_folders_deleted(removed);
        }

        return removed;
    }

    /**
     * Locates a special folder, creating it if needed.
     */
    internal async Geary.Folder ensure_special_folder_async(Imap.AccountSession remote,
                                                            Geary.SpecialFolderType special,
                                                            Cancellable? cancellable)
        throws Error {
        MinimalFolder? minimal_folder = null;
        Geary.FolderPath? path = information.get_special_folder_path(special);
        if (path != null) {
            debug("Previously used %s for special folder %s", path.to_string(), special.to_string());
        } else {
            // This is the first time we're turning a non-special folder into a special one.
            // After we do this, we'll record which one we picked in the account info.
            Geary.FolderPath root =
                yield remote.get_default_personal_namespace(cancellable);
            Gee.List<string> search_names = special_search_names.get(special);
            foreach (string search_name in search_names) {
                Geary.FolderPath search_path = root.get_child(search_name);
                foreach (Geary.FolderPath test_path in folder_map.keys) {
                    if (test_path.compare_normalized_ci(search_path) == 0) {
                        path = search_path;
                        break;
                    }
                }
                if (path != null)
                    break;
            }

            if (path == null)
                path = root.get_child(search_names[0]);

            information.set_special_folder_path(special, path);
        }

        if (path in folder_map.keys) {
            debug("Promoting %s to special folder %s", path.to_string(), special.to_string());
            minimal_folder = folder_map.get(path);
        } else {
            debug("Creating %s to use as special folder %s", path.to_string(), special.to_string());
            // TODO: ignore error due to already existing.
            yield remote.create_folder_async(path, special, cancellable);
            minimal_folder = (MinimalFolder) yield fetch_folder_async(path, cancellable);
        }

        Gee.Map<Geary.SpecialFolderType,Geary.Folder> specials =
            new Gee.HashMap<Geary.SpecialFolderType,Geary.Folder>();
        specials.set(special, minimal_folder);
        promote_folders(specials);

        return minimal_folder;
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

    /**
     * Constructs a concrete search folder implementation.
     *
     * Subclasses with specific SearchFolder implementations should
     * override this to return the correct subclass.
     */
    protected virtual SearchFolder new_search_folder() {
        return new ImapDB.SearchFolder(this);
    }

    /** {@inheritDoc} */
    protected override void notify_folders_available_unavailable(Gee.List<Geary.Folder>? available,
        Gee.List<Geary.Folder>? unavailable) {
        base.notify_folders_available_unavailable(available, unavailable);
        if (available != null) {
            foreach (Geary.Folder folder in available) {
                folder.email_appended.connect(notify_email_appended);
                folder.email_inserted.connect(notify_email_inserted);
                folder.email_removed.connect(notify_email_removed);
                folder.email_locally_complete.connect(notify_email_locally_complete);
                folder.email_flags_changed.connect(notify_email_flags_changed);
            }
        }
        if (unavailable != null) {
            foreach (Geary.Folder folder in unavailable) {
                folder.email_appended.disconnect(notify_email_appended);
                folder.email_inserted.disconnect(notify_email_inserted);
                folder.email_removed.disconnect(notify_email_removed);
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
    protected override void notify_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        base.notify_email_flags_changed(folder, flag_map);
        schedule_unseen_update(folder);
    }

    /** Fires a {@link Account.report_problem} signal for an IMAP service. */
    protected void notify_imap_problem(Geary.ProblemType type, Error? err) {
        notify_service_problem(type, this.information.imap, err);
    }

    /**
     * Hooks up and queues an {@link UpdateRemoteFolders} operation.
     */
    private void update_remote_folders() {
        this.refresh_folder_timer.reset();

        UpdateRemoteFolders op = new UpdateRemoteFolders(
            this,
            this.local_only.keys,
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
        if (error is ImapError) {
            notify_service_problem(
                ProblemType.SERVER_ERROR, this.information.imap, error
            );
        } else if (error is IOError) {
            // IOErrors could be network related or disk related, need
            // to work out the difference and send a service problem
            // if definitely network related
            notify_account_problem(ProblemType.for_ioerror((IOError) error), error);
        } else {
            notify_account_problem(ProblemType.GENERIC_ERROR, error);
        }
    }

    private void on_pool_session_ready(bool is_ready) {
        if (is_ready) {
            // Now have a valid session, so credentials must be good
            this.authentication_failures = 0;
            this.remote_ready_lock.blind_notify();
            update_remote_folders();
        } else {
            this.remote_ready_lock.reset();
            this.refresh_folder_timer.reset();
        }
    }

    private void on_pool_connection_failed(Error error) {
        this.remote_ready_lock.reset();
        if (error is ImapError.UNAUTHENTICATED) {
            // This is effectively a login failure
            on_pool_login_failed(null);
        } else {
            notify_imap_problem(ProblemType.CONNECTION_ERROR, error);
        }
    }

    private void on_pool_login_failed(Geary.Imap.StatusResponse? response) {
        this.remote_ready_lock.reset();
        this.authentication_failures++;
        if (this.authentication_failures >= Geary.Account.AUTH_ATTEMPTS_MAX) {
            // We have tried auth too many times, so bail out
            notify_imap_problem(ProblemType.LOGIN_FAILED, null);
        } else {
            // login can fail due to an invalid password hence we
            // should re-ask it, but it can also fail due to server
            // inaccessibility, for instance "[UNAVAILABLE] / Maximum
            // number of connections from user+IP exceeded". In that
            // case, resetting password seems unneeded.
            bool reask_password = false;
            Error? login_error = null;
            try {
                reask_password = (
                    response == null ||
                    response.response_code == null ||
                    response.response_code.get_response_code_type().value != Geary.Imap.ResponseCodeType.UNAVAILABLE
                );
            } catch (ImapError err) {
                login_error = err;
                debug("Unable to parse ResponseCode %s: %s", response.response_code.to_string(),
                      err.message);
            }

            if (!reask_password) {
                // Either the server was unavailable, or we were unable to
                // parse the login response. Either way, indicate a
                // non-login error.
                notify_imap_problem(ProblemType.SERVER_ERROR, login_error);
            } else {
                // Now, we should ask the user for their password
                this.information.prompt_imap_credentials.begin(
                    this.open_cancellable,
                    (obj, ret) => {
                        try {
                            if (this.information.prompt_imap_credentials.end(ret)) {
                                // Have a new password, so try that
                                this.session_pool.credentials_updated(
                                    this.information.imap.credentials
                                );
                            } else {
                                // User cancelled, so indicate a login problem
                                notify_imap_problem(ProblemType.LOGIN_FAILED, null);
                            }
                        } catch (Error err) {
                            notify_imap_problem(ProblemType.GENERIC_ERROR, err);
                        }
                    });
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

        yield enumerate_local_folders_async(folders, null, cancellable);
        generic.add_folders(folders, true);
        if (!folders.is_empty) {
            // If we have some folders to load, then this isn't the
            // first run, and hence the special folders should already
            // exist
            yield check_special_folders(cancellable);
        }
    }

    private async void enumerate_local_folders_async(Gee.List<ImapDB.Folder> folders,
                                                     Geary.FolderPath? parent,
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

    private async void check_special_folders(Cancellable cancellable)
        throws Error {
        GenericAccount generic = (GenericAccount) this.account;
        Gee.Map<Geary.SpecialFolderType,Geary.Folder> specials =
            new Gee.HashMap<Geary.SpecialFolderType,Geary.Folder>();
        foreach (Geary.SpecialFolderType special in this.specials) {
            Geary.FolderPath? path = generic.information.get_special_folder_path(special);
            if (path != null) {
                try {
                    Geary.Folder target = yield generic.fetch_folder_async(path, cancellable);
                    specials.set(special, target);
                } catch (Error err) {
                    debug("%s: Previously used special folder %s does not exist: %s",
                          generic.information.id, special.to_string(), err.message);
                }
            }
        }

        generic.promote_folders(specials);
    }

}


/**
 * Account operation that updates folders from the remote.
 */
internal class Geary.ImapEngine.UpdateRemoteFolders : AccountOperation {


    private weak GenericAccount generic_account;
    private Gee.Collection<FolderPath> local_folders;
    private Geary.SpecialFolderType[] specials;


    internal UpdateRemoteFolders(GenericAccount account,
                                 Gee.Collection<FolderPath> local_folders,
                                 Geary.SpecialFolderType[] specials) {
        base(account);
        this.generic_account = account;
        this.local_folders = local_folders;
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
                remote, remote_folders, null, cancellable
            );

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
                    remote_folder.properties, false, false, cancellable
                );
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.path.to_string(), update_error.message);
            }

            // set the engine folder's special type
            // (but only promote, not demote, since getting the special folder type via its
            // properties relies on the optional XLIST extension)
            // use this iteration to add discovered properties to map
            if (minimal_folder.special_folder_type == SpecialFolderType.NONE)
                minimal_folder.set_special_folder_type(remote_folder.properties.attrs.get_special_folder_type());
        }

        // If path in remote but not local, need to add it
        Gee.ArrayList<Imap.Folder> to_add = Geary.traverse<Imap.Folder>(remote_folders.values)
            .filter(f => !existing_folders.has_key(f.path))
            .to_array_list();

        // If path in local but not remote (and isn't local-only, i.e. the Outbox), need to remove it
        Gee.ArrayList<Geary.Folder> to_remove
            = Geary.traverse<Gee.Map.Entry<FolderPath,Geary.Folder>>(existing_folders)
            .filter(e => !remote_folders.has_key(e.key) && !this.local_folders.contains(e.key))
            .map<Geary.Folder>(e => (Geary.Folder) e.value)
            .to_array_list();

        // For folders to add, clone them and their properties locally
        ImapDB.Account local = ((GenericAccount) this.account).local;
        foreach (Geary.Imap.Folder remote_folder in to_add) {
            try {
                yield local.clone_folder_async(remote_folder, cancellable);
            } catch (Error err) {
                debug("Unable to add/remove folder %s to local store: %s", remote_folder.path.to_string(),
                    err.message);
            }
        }

        // Create Geary.Folder objects for all added folders
        Gee.ArrayList<ImapDB.Folder> to_build = new Gee.ArrayList<ImapDB.Folder>();
        foreach (Geary.Imap.Folder remote_folder in to_add) {
            try {
                to_build.add(yield local.fetch_folder_async(remote_folder.path, cancellable));
            } catch (Error convert_err) {
                // This isn't fatal, but irksome ... in the future, when local folders are
                // removed, it's possible for one to disappear between cloning it and fetching
                // it
                debug("Unable to fetch local folder after cloning: %s", convert_err.message);
            }
        }
        this.generic_account.add_folders(to_build, false);

        if (remote_folders_suspect) {
            debug("Skipping removing folders due to prior errors");
        } else {
            Gee.List<MinimalFolder> removed =
                this.generic_account.remove_folders(to_remove);

            // Sort by path length descending, so we always remove children first.
            removed.sort((a, b) => b.path.get_path_length() - a.path.get_path_length());
            foreach (Geary.Folder folder in removed) {
                try {
                    debug("Locally deleting removed folder %s", folder.to_string());
                    yield local.delete_folder_async(folder, cancellable);
                } catch (Error e) {
                    debug("Unable to locally delete removed folder %s: %s", folder.to_string(), e.message);
                }
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
                if (this.generic_account.get_special_folder(special) == null) {
                    yield this.generic_account.ensure_special_folder_async(
                        remote, special, cancellable
                    );
                }
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
                        remote_folder.properties, false, true, cancellable
                    );

                    ((GenericAccount) this.account).update_folder(this.folder);
                }
            } finally {
                account.release_account_session(remote);
            }
        }
    }

}
