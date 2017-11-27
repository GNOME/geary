/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.GenericAccount : Geary.Account {

    private const int REFRESH_FOLDER_LIST_SEC = 2 * 60;
    private const Geary.SpecialFolderType[] SUPPORTED_SPECIAL_FOLDERS = {
        Geary.SpecialFolderType.DRAFTS,
        Geary.SpecialFolderType.SENT,
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
        Geary.SpecialFolderType.ARCHIVE,
    };

    private static Geary.FolderPath? outbox_path = null;
    private static Geary.FolderPath? search_path = null;

    protected Imap.Account remote { get; private set; }
    protected ImapDB.Account local { get; private set; }

    private bool open = false;
    private Gee.HashMap<FolderPath, MinimalFolder> folder_map = new Gee.HashMap<
        FolderPath, MinimalFolder>();
    private Gee.HashMap<FolderPath, Folder> local_only = new Gee.HashMap<FolderPath, Folder>();
    private AccountProcessor? processor;
    private AccountSynchronizer sync;
    private TimeoutManager refresh_folder_timer;

    private Gee.Map<Geary.SpecialFolderType, Gee.List<string>> special_search_names =
        new Gee.HashMap<Geary.SpecialFolderType, Gee.List<string>>();


    public GenericAccount(string name, Geary.AccountInformation information,
        Imap.Account remote, ImapDB.Account local) {
        base (name, information);

        this.remote = remote;
        this.remote.report_problem.connect(notify_report_problem);

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
        
        if (outbox_path == null) {
            outbox_path = new SmtpOutboxFolderRoot();
        }
        
        if (search_path == null) {
            search_path = new ImapDB.SearchFolderRoot();
        }

        this.sync = new AccountSynchronizer(this, this.remote);

        compile_special_search_names();
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
        debug("%s: Enqueuing: %s", this.to_string(), op.to_string());
        this.processor.enqueue(op);
    }

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

    protected override void notify_email_appended(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_appended(folder, ids);
        schedule_unseen_update(folder);
    }

    protected override void notify_email_inserted(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_inserted(folder, ids);
        schedule_unseen_update(folder);
    }

    protected override void notify_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        base.notify_email_removed(folder, ids);
        schedule_unseen_update(folder);
    }

    protected override void notify_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        base.notify_email_flags_changed(folder, flag_map);
        schedule_unseen_update(folder);
    }

    private void check_open() throws EngineError {
        if (!open)
            throw new EngineError.OPEN_REQUIRED("Account %s not opened", to_string());
    }
    
    public override async void open_async(Cancellable? cancellable = null) throws Error {
        if (open)
            throw new EngineError.ALREADY_OPEN("Account %s already opened", to_string());
        
        opening_monitor.notify_start();
        
        Error? throw_err = null;
        try {
            yield internal_open_async(cancellable);
        } catch (Error err) {
            throw_err = err;
        }
        
        opening_monitor.notify_finish();
        
        if (throw_err != null)
            throw throw_err;
    }
    
    private async void internal_open_async(Cancellable? cancellable) throws Error {
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
        
        // outbox is now available
        local.outbox.report_problem.connect(notify_report_problem);
        local_only.set(outbox_path, local.outbox);
        
        // Search folder.
        local_only.set(search_path, local.search_folder);
        
        // To prevent spurious connection failures, we make sure we have the
        // IMAP password before attempting a connection.  This might have to be
        // reworked when we allow passwordless logins.
        if (!information.imap_credentials.is_complete())
            yield information.get_passwords_async(ServiceFlag.IMAP);

        // need to back out local.open_async() if remote fails
        try {
            yield remote.open_async(cancellable);
        } catch (Error err) {
            // back out
            try {
                yield local.close_async(cancellable);
            } catch (Error close_err) {
                // ignored
            }
            
            throw err;
        }

        this.open = true;

        notify_opened();
        notify_folders_available_unavailable(sort_by_path(local_only.values), null);

        this.queue_operation(
            new LoadFolders(this, this.local, get_supported_special_folders())
        );

        this.remote.ready.connect(on_remote_ready);
        if (this.remote.is_ready) {
            this.update_remote_folders();
        }
    }

    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!open)
            return;

        this.remote.ready.disconnect(on_remote_ready);

        // Halt internal tasks early so they stop using local and
        // remote connections.
        this.processor.stop();
        this.sync.stop();

        this.refresh_folder_timer.reset();

        // Notify folders and ensure they are closed

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

        this.local.outbox.report_problem.disconnect(notify_report_problem);

        // Close accounts
        Error? local_err = null;
        try {
            yield local.close_async(cancellable);
        } catch (Error lclose_err) {
            local_err = lclose_err;
        }
        
        Error? remote_err = null;
        try {
            yield remote.close_async(cancellable);
        } catch (Error rclose_err) {
            remote_err = rclose_err;
        }

        this.open = false;

        notify_closed();

        if (local_err != null)
            throw local_err;
        
        if (remote_err != null)
            throw remote_err;
    }
    
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
     * This starts the outbox postman running.
     */
    public override async void start_outgoing_client()
        throws Error {
        check_open();
        this.local.outbox.start_postman_async.begin();
    }

    /**
     * This closes then reopens the IMAP account.
     */
    public override async void start_incoming_client()
        throws Error {
        check_open();
        try {
            yield this.remote.close_async();
        } catch (Error err) {
            debug("Ignoring error closing IMAP account for restart: %s", err.message);
        }

        yield this.remote.open_async();
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

    public override async bool folder_exists_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        if (yield local.folder_exists_async(path, cancellable))
            return true;
        
        return yield remote.folder_exists_async(path, cancellable);
    }

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

    /**
     * Returns an Imap.Folder that is not connected (is detached) to a MinimalFolder or any other
     * ImapEngine container.
     *
     * This is useful for one-shot operations that need to bypass the heavyweight synchronization
     * routines inside MinimalFolder.  This also means that operations performed on this Folder will
     * not be reflected in the local database unless there's a separate connection to the server
     * that is notified or detects these changes.
     *
     * The returned Folder must be opened prior to use and closed once completed.  ''Leaving a
     * Folder open will cause a connection leak.''
     *
     * It is not recommended this object be held open long-term, or that its status or notifications
     * be directly written to the database unless you know exactly what you're doing.  ''Caveat
     * implementor.''
     */
    public async Imap.Folder fetch_detached_folder_async(Geary.FolderPath path, Cancellable? cancellable)
        throws Error {
        check_open();

        if (local_only.has_key(path)) {
            throw new EngineError.NOT_FOUND("%s: path %s points to local-only folder, not IMAP",
                to_string(), path.to_string());
        }

        return yield remote.fetch_folder_async(path, cancellable);
    }

    public override async Geary.Folder get_required_special_folder_async(Geary.SpecialFolderType special,
        Cancellable? cancellable) throws Error {
        if (!(special in get_supported_special_folders())) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid special folder type %s passed to get_required_special_folder_async",
                special.to_string());
        }
        check_open();

        return yield ensure_special_folder_async(special, cancellable);
    }

    public override async void send_email_async(Geary.ComposedEmail composed,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO: we should probably not use someone else's FQDN in something
        // that's supposed to be globally unique...
        Geary.RFC822.Message rfc822 = new Geary.RFC822.Message.from_composed_email(
            composed, GMime.utils_generate_message_id(information.get_smtp_endpoint().remote_address.hostname));
        
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

    // Subclasses with specific SearchFolder implementations should override
    // this to return the correct subclass.
    internal virtual SearchFolder new_search_folder() {
        return new ImapDB.SearchFolder(this);
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
     * seen before and the {@link folders_added} signal is not fired.
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
     * Fires appropriate signals for folders have been altered.
     */
    internal void update_folders(Gee.Collection<Geary.Folder> folders) {
        if (!folders.is_empty) {
            notify_folders_contents_altered(sort_by_path(folders));
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
     * Returns the folder for the given special type, creating it if needed.
     */
    internal async Geary.Folder ensure_special_folder_async(Geary.SpecialFolderType special,
                                                            Cancellable? cancellable)
        throws Error {
        Geary.Folder? folder = get_special_folder(special);
        if (folder != null)
            return folder;

        MinimalFolder? minimal_folder = null;
        Geary.FolderPath? path = information.get_special_folder_path(special);
        if (path != null) {
            debug("Previously used %s for special folder %s", path.to_string(), special.to_string());
        } else {
            // This is the first time we're turning a non-special folder into a special one.
            // After we do this, we'll record which one we picked in the account info.

            Geary.FolderPath root = yield remote.get_default_personal_namespace(cancellable);
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
            yield information.store_async(cancellable);
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

        minimal_folder.set_special_folder_type(special);
        return minimal_folder;
    }

    // Subclasses should implement this to return their flavor of a MinimalFolder with the
    // appropriate interfaces attached.  The returned folder should have its SpecialFolderType
    // set using either the properties from the local folder or its path.
    //
    // This won't be called to build the Outbox or search folder, but for all others (including Inbox) it will.
    protected abstract MinimalFolder new_folder(ImapDB.Folder local_folder);

    /**
     * Hooks up and queues an {@link UpdateRemoteFolders} operation.
     */
    private void update_remote_folders() {
        this.refresh_folder_timer.reset();

        UpdateRemoteFolders op = new UpdateRemoteFolders(
            this,
            this.remote,
            this.local,
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

    private void on_remote_ready() {
        this.update_remote_folders();
    }

    private void on_operation_error(AccountOperation op, Error error) {
        if (error is ImapError) {
            notify_service_problem(ProblemType.SERVER_ERROR, Service.IMAP, error);
        } else if (error is IOError) {
            // IOErrors could be network related or disk related, need
            // to work out the difference and send a service problem
            // if definitely network related
            notify_account_problem(ProblemType.for_ioerror((IOError) error), error);
        } else {
            notify_account_problem(ProblemType.GENERIC_ERROR, error);
        }
    }

}


/**
 * Account operation for loading local folders from the database.
 */
internal class Geary.ImapEngine.LoadFolders : AccountOperation {


    private weak GenericAccount account;
    private weak ImapDB.Account local;
    private Geary.SpecialFolderType[] specials;


    internal LoadFolders(GenericAccount account,
                         ImapDB.Account local,
                         Geary.SpecialFolderType[] specials) {
        this.account = account;
        this.local = local;
        this.specials = specials;
    }

    public override async void execute(Cancellable cancellable) throws Error {
        Gee.List<ImapDB.Folder> folders = new Gee.LinkedList<ImapDB.Folder>();
        yield enumerate_local_folders_async(folders, null, cancellable);
        debug("%s: found %u folders", to_string(), folders.size);
        this.account.add_folders(folders, true);

        if (!folders.is_empty) {
            // If we have some folders to load, then this isn't the
            // first run, and hence the special folders should already
            // exist
            foreach (Geary.SpecialFolderType special in this.specials) {
                try {
                    yield this.account.ensure_special_folder_async(special, cancellable);
                } catch (Error e) {
                    warning("Unable to ensure special folder %s: %s", special.to_string(), e.message);
                }
            }
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
}


/**
 * Account operation that updates folders from the remote.
 */
internal class Geary.ImapEngine.UpdateRemoteFolders : AccountOperation {


    private weak GenericAccount account;
    private weak Imap.Account remote;
    private weak ImapDB.Account local;
    private Gee.Collection<FolderPath> local_folders;
    private Geary.SpecialFolderType[] specials;


    internal UpdateRemoteFolders(GenericAccount account,
                                 Imap.Account remote,
                                 ImapDB.Account local,
                                 Gee.Collection<FolderPath> local_folders,
                                 Geary.SpecialFolderType[] specials) {
        this.account = account;
        this.remote = remote;
        this.local = local;
        this.local_folders = local_folders;
        this.specials = specials;
    }

    public override async void execute(Cancellable cancellable) throws Error {
        Gee.Map<FolderPath, Geary.Folder> existing_folders =
            Geary.traverse<Geary.Folder>(this.account.list_folders())
            .to_hash_map<FolderPath>(f => f.path);
        Gee.Map<FolderPath, Imap.Folder> remote_folders =
            new Gee.HashMap<FolderPath, Imap.Folder>();
        bool is_suspect = yield enumerate_remote_folders_async(
            remote_folders, null, cancellable
        );

        // pair the local and remote folders and make sure everything is up-to-date
        yield update_folders_async(existing_folders, remote_folders, is_suspect, cancellable);
    }

    private async bool enumerate_remote_folders_async(Gee.Map<FolderPath, Imap.Folder> folders,
                                                      Geary.FolderPath? parent,
                                                      Cancellable? cancellable)
        throws Error {
        bool results_suspect = false;

        Gee.List<Imap.Folder>? children = null;
        try {
            children = yield this.remote.fetch_child_folders_async(parent, cancellable);
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
                    yield enumerate_remote_folders_async(folders, path, cancellable)) {
                    results_suspect = true;
                }
            }
        }

        return results_suspect;
    }

    private async void update_folders_async(Gee.Map<FolderPath, Geary.Folder> existing_folders,
        Gee.Map<FolderPath, Imap.Folder> remote_folders, bool remote_folders_suspect, Cancellable? cancellable) {
        // update all remote folders properties in the local store and active in the system
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
                yield this.local.update_folder_status_async(remote_folder, false, false, cancellable);
            } catch (Error update_error) {
                debug("Unable to update local folder %s with remote properties: %s",
                    remote_folder.to_string(), update_error.message);
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
                to_build.add(yield this.local.fetch_folder_async(remote_folder.path, cancellable));
            } catch (Error convert_err) {
                // This isn't fatal, but irksome ... in the future, when local folders are
                // removed, it's possible for one to disappear between cloning it and fetching
                // it
                debug("Unable to fetch local folder after cloning: %s", convert_err.message);
            }
        }
        this.account.add_folders(to_build, false);

        if (remote_folders_suspect) {
            debug("Skipping removing folders due to prior errors");
        } else {
            Gee.List<MinimalFolder> removed = this.account.remove_folders(to_remove);

            // Sort by path length descending, so we always remove children first.
            removed.sort((a, b) => b.path.get_path_length() - a.path.get_path_length());
            foreach (Geary.Folder folder in removed) {
                try {
                    debug("Locally deleting removed folder %s", folder.to_string());
                    yield this.local.delete_folder_async(folder, cancellable);
                } catch (Error e) {
                    debug("Unable to locally delete removed folder %s: %s", folder.to_string(), e.message);
                }
            }

            // Let the remote know as well
            this.remote.folders_removed(
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
            this.account.update_folders(altered);
        }

        // Ensure each of the important special folders we need already exist
        foreach (Geary.SpecialFolderType special in this.specials) {
            try {
                yield this.account.ensure_special_folder_async(special, cancellable);
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
internal class Geary.ImapEngine.RefreshFolderUnseen : AccountOperation {


    private weak Geary.Folder folder;
    private weak Imap.Account remote;
    private weak ImapDB.Account local;


    internal RefreshFolderUnseen(Geary.Folder folder,
                                 Imap.Account remote,
                                 ImapDB.Account local) {
        this.folder = folder;
        this.remote = remote;
        this.local = local;
    }

    public override bool equal_to(AccountOperation op) {
        return (
            base.equal_to(op) &&
            this.folder.path.equal_to(((RefreshFolderUnseen) op).folder.path)
        );
    }

    public override string to_string() {
        return "%s(%s)".printf(base.to_string(), folder.path.to_string());
    }

    public override async void execute(Cancellable cancellable) throws Error {
        if (this.folder.get_open_state() == Geary.Folder.OpenState.CLOSED) {
            Imap.Folder remote_folder = yield remote.fetch_folder_cached_async(
                folder.path,
                true,
                cancellable
            );

            yield local.update_folder_status_async(
                remote_folder, false, true, cancellable
            );
        }
    }

}
