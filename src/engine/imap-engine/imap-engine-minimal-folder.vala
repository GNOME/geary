/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Base implementation of {@link Geary.Folder}.
 *
 * This class maintains both a local database and a remote IMAP
 * session and mediates between the two using the replay queue. Events
 * generated locally (message move, folder close, etc) are placed in
 * the local replay queue for execution, IMAP server messages (new
 * message delivered, etc) are placed in the remote replay queue. The
 * queue ensures that message state changes caused by server messages
 * are interleaved correctly with local operations.
 *
 * The remote folder connection is not always automatically
 * established, depending on flags passed to `open_async`. In any case
 * the remote connection may go away if the network changes while the
 * folder is still held open. In this case, the folder's remote
 * connection is reestablished when the a `ready` signal is received
 * from the IMAP stack, i.e. when connectivity to the server has been
 * restored.
 */
private class Geary.ImapEngine.MinimalFolder : Geary.Folder, Geary.FolderSupport.Copy,
    Geary.FolderSupport.Mark, Geary.FolderSupport.Move {


    private const int FLAG_UPDATE_TIMEOUT_SEC = 2;
    private const int FLAG_UPDATE_START_CHUNK = 20;
    private const int FLAG_UPDATE_MAX_CHUNK = 100;
    private const int FORCE_OPEN_REMOTE_TIMEOUT_SEC = 10;
    private const int REFRESH_UNSEEN_TIMEOUT_SEC = 1;


    public override Account account { get { return _account; } }
    
    public override FolderProperties properties { get { return _properties; } }
    
    public override FolderPath path {
        get {
            return local_folder.get_path();
        }
    }
    
    private SpecialFolderType _special_folder_type;
    public override SpecialFolderType special_folder_type {
        get {
            return _special_folder_type;
        }
    }
    
    private ProgressMonitor _opening_monitor = new Geary.ReentrantProgressMonitor(Geary.ProgressType.ACTIVITY);
    public override Geary.ProgressMonitor opening_monitor { get { return _opening_monitor; } }

    internal ImapDB.Folder local_folder  { get; protected set; }
    internal Imap.FolderSession? remote_folder { get; protected set; default = null; }
    internal int remote_count { get; private set; default = -1; }

    internal ReplayQueue replay_queue { get; private set; }
    internal EmailPrefetcher email_prefetcher { get; private set; }

    private weak GenericAccount _account;
    private Geary.AggregatedFolderProperties _properties =
        new Geary.AggregatedFolderProperties(false, false);

    private Folder.OpenFlags open_flags = OpenFlags.NONE;
    private int open_count = 0;

    private TimeoutManager remote_open_timer;
    private Nonblocking.ReportingSemaphore<bool> remote_wait_semaphore =
        new Nonblocking.ReportingSemaphore<bool>(false);
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();
    private Nonblocking.Mutex open_mutex = new Nonblocking.Mutex();
    private Nonblocking.Mutex close_mutex = new Nonblocking.Mutex();
    private TimeoutManager update_flags_timer;
    private TimeoutManager refresh_unseen_timer;
    private Cancellable? open_cancellable = null;


    /**
     * Called when the folder is closing (and not reestablishing a connection) and will be flushing
     * the replay queue.  Subscribers may add ReplayOperations to the list, which will be enqueued
     * before the queue is flushed.
     *
     * Note that this is ''not'' fired if the queue is not being flushed.
     */
    public signal void closing(Gee.List<ReplayOperation> final_ops);
    
    /**
     * Fired when an {@link EmailIdentifier} that was marked for removal is actually reported as
     * removed (expunged) from the server.
     *
     * Marked messages are reported as removed when marked in the database, to make the operation
     * appear speedy to the caller.  When the message is finally acknowledged as removed by the
     * server, "email-removed" is not fired to avoid double-reporting.
     *
     * Some internal code (especially Revokables) mark messages for removal but delay the network
     * operation.  They need to know if the message is removed by another client, however.
     */
    public signal void marked_email_removed(Gee.Collection<Geary.EmailIdentifier> removed);
    
    /** Emitted to notify the account that some problem has occurred. */
    internal signal void report_problem(Geary.ProblemReport problem);


    public MinimalFolder(GenericAccount account,
                         ImapDB.Folder local_folder,
                         SpecialFolderType special_folder_type) {
        this._account = account;
        this.local_folder = local_folder;
        this.local_folder.email_complete.connect(on_email_complete);

        this._special_folder_type = special_folder_type;
        this._properties.add(local_folder.get_properties());
        this.replay_queue = new ReplayQueue(this);
        this.email_prefetcher = new EmailPrefetcher(this);

        this.remote_open_timer = new TimeoutManager.seconds(
            FORCE_OPEN_REMOTE_TIMEOUT_SEC, () => { this.open_remote_session.begin(); }
        );

        this.update_flags_timer = new TimeoutManager.seconds(
            FLAG_UPDATE_TIMEOUT_SEC, () => { on_update_flags.begin(); }
        );

        this.refresh_unseen_timer = new TimeoutManager.seconds(
            REFRESH_UNSEEN_TIMEOUT_SEC, on_refresh_unseen
        );

        // Notify now to ensure that wait_for_close_async does not
        // block if never opened.
        this.closed_semaphore.blind_notify();
    }

    ~MinimalFolder() {
        if (open_count > 0)
            warning("Folder %s destroyed without closing", to_string());
        this.local_folder.email_complete.disconnect(on_email_complete);
    }

    protected virtual void notify_closing(Gee.List<ReplayOperation> final_ops) {
        closing(final_ops);
    }
    
    /*
     * These signal notifiers are marked public (note this is a private class) so the various
     * ReplayOperations can directly fire the associated signals while within the queue.
     */
    
    public void replay_notify_email_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        notify_email_inserted(ids);
    }
    
    public void replay_notify_email_locally_inserted(Gee.Collection<Geary.EmailIdentifier> ids) {
        notify_email_locally_inserted(ids);
    }
    
    public void replay_notify_email_removed(Gee.Collection<Geary.EmailIdentifier> ids) {
        notify_email_removed(ids);
    }
    
    public void replay_notify_email_count_changed(int new_count, Folder.CountChangeReason reason) {
        notify_email_count_changed(new_count, reason);
    }
    
    public void replay_notify_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flag_map) {
        notify_email_flags_changed(flag_map);
    }
    
    public void set_special_folder_type(SpecialFolderType new_type) {
        SpecialFolderType old_type = _special_folder_type;
        _special_folder_type = new_type;
        if (old_type != new_type)
            notify_special_folder_type_changed(old_type, new_type);
    }

    public override Geary.Folder.OpenState get_open_state() {
        if (this.open_count == 0)
            return Geary.Folder.OpenState.CLOSED;

        return (this.remote_folder != null)
           ? Geary.Folder.OpenState.BOTH
           : Geary.Folder.OpenState.LOCAL;
    }

    // Returns the synchronized remote count (-1 if not opened) and the last seen remote count (stored
    // locally, -1 if not available)
    //
    // Return value is the remote_count, unless the remote is unopened, in which case it's the
    // last_seen_remote_count (which may also be -1).
    //
    // remote_count, last_seen_remote_count, and returned value do not reflect any notion of
    // messages marked for removal
    internal int get_remote_counts(out int remote_count, out int last_seen_remote_count) {
        remote_count = this.remote_count;
        last_seen_remote_count = local_folder.get_properties().select_examine_messages;
        if (last_seen_remote_count < 0)
            last_seen_remote_count = local_folder.get_properties().status_messages;

        return (remote_count >= 0) ? remote_count : last_seen_remote_count;
    }

    /** {@inheritDoc} */
    public override async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0) {
            // even if opened or opening, or if forcing a re-open, respect the NO_DELAY flag
            if (open_flags.is_all_set(OpenFlags.NO_DELAY)) {
                // add NO_DELAY flag if it forces an open
                if (this.remote_folder == null)
                    this.open_flags |= OpenFlags.NO_DELAY;

                this.open_remote_session.begin();
            }
            return false;
        }

        // first open gets to name the flags, but see note above
        this.open_flags = open_flags;

        // reset to force waiting in wait_for_remote_async()
        this.remote_wait_semaphore.reset();

        // reset to force waiting in wait_for_close_async()
        this.closed_semaphore.reset();

        // reset unseen count refresh since it will be updated when
        // the remote opens
        this.refresh_unseen_timer.reset();

        this.open_cancellable = new Cancellable();

        // Notify the email prefetcher
        this.email_prefetcher.open();

        // notify about the local open
        int local_count = 0;
        get_remote_counts(null, out local_count);
        notify_opened(Geary.Folder.OpenState.LOCAL, local_count);

        // Unless NO_DELAY is set, do NOT open the remote side here; wait for the ReplayQueue to
        // require a remote connection or wait_for_remote_async() to be called ... this allows for
        // fast local-only operations to occur, local-only either because (a) the folder has all
        // the information required (for a list or fetch operation), or (b) the operation was de
        // facto local-only.  In particular, EmailStore will open and close lots of folders,
        // causing a lot of connection setup and teardown
        //
        // However, want to eventually open, otherwise if there's no user interaction (i.e. a
        // second account Inbox they don't manipulate), no remote connection will ever be made,
        // meaning that folder normalization never happens and unsolicited notifications never
        // arrive
        this._account.session_pool.ready.connect(on_remote_ready);
        if (open_flags.is_all_set(OpenFlags.NO_DELAY)) {
            this.open_remote_session.begin();
        } else {
            this.remote_open_timer.start();
        }
        return true;
    }

    /** {@inheritDoc} */
    public override async void wait_for_remote_async(Cancellable? cancellable = null) throws Error {
        check_open("wait_for_remote_async");

        // if remote has not yet been opened, do it now ...
        if (this.remote_folder == null) {
            this.open_remote_session.begin();
        }

        if (!yield this.remote_wait_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.ALREADY_CLOSED("%s failed to open", to_string());
    }

    /** {@inheritDoc} */
    public override async bool close_async(Cancellable? cancellable = null) throws Error {
        // Check open_count but only decrement inside of replay queue
        if (open_count <= 0)
            return false;

        UserClose user_close = new UserClose(this, cancellable);
        this.replay_queue.schedule(user_close);

        yield user_close.wait_for_ready_async(cancellable);
        return user_close.closing;
    }

    /** {@inheritDoc} */
    public override async void wait_for_close_async(Cancellable? cancellable = null)
        throws Error {
        yield this.closed_semaphore.wait_async(cancellable);
    }

    // used by normalize_folders() during the normalization process; should not be used elsewhere
    private async void detach_all_emails_async(Cancellable? cancellable) throws Error {
        Gee.List<Email>? all = yield local_folder.list_email_by_id_async(null, -1,
            Geary.Email.Field.NONE, ImapDB.Folder.ListFlags.NONE, cancellable);
        
        yield local_folder.detach_all_emails_async(cancellable);
        
        if (all != null && all.size > 0) {
            Gee.List<EmailIdentifier> ids =
                traverse<Email>(all).map<EmailIdentifier>((email) => email.id).to_array_list();
            notify_email_removed(ids);
            notify_email_count_changed(0, Folder.CountChangeReason.REMOVED);
        }
    }

    private async void normalize_folders(Geary.Imap.FolderSession remote_folder,
                                         Cancellable? cancellable)
        throws Error {
        debug("%s: Begin normalizing remote and local folders", to_string());

        Geary.Imap.FolderProperties local_properties = this.local_folder.get_properties();
        Geary.Imap.FolderProperties remote_properties = remote_folder.folder.properties;

        // and both must have their next UID's (it's possible they don't if it's a non-selectable
        // folder)
        if (local_properties.uid_next == null || local_properties.uid_validity == null) {
            throw new ImapError.NOT_SUPPORTED(
                "%s: Unable to verify UIDs: missing local UIDNEXT (%s) and/or UIDVALIDITY (%s)",
                to_string(),
                (local_properties.uid_next == null).to_string(),
                (local_properties.uid_validity == null).to_string()
            );
        }

        if (remote_properties.uid_next == null || remote_properties.uid_validity == null) {
            throw new ImapError.NOT_SUPPORTED(
                "%s: Unable to verify UIDs: missing remote UIDNEXT (%s) and/or UIDVALIDITY (%s)",
                to_string(),
                (remote_properties.uid_next == null).to_string(),
                (remote_properties.uid_validity == null).to_string()
            );
        }

        // If UIDVALIDITY changes, all email in the folder must be removed as the UIDs are now
        // invalid ... we merely detach the emails (leaving their contents behind) so duplicate
        // detection can fix them up.  But once all UIDs are removed, it's much like the next
        // if case where no earliest UID available, so simply exit.
        //
        // see http://tools.ietf.org/html/rfc3501#section-2.3.1.1
        if (local_properties.uid_validity.value != remote_properties.uid_validity.value) {
            debug("%s: UID validity changed, detaching all email: %s -> %s", to_string(),
                local_properties.uid_validity.value.to_string(),
                remote_properties.uid_validity.value.to_string());
            yield detach_all_emails_async(cancellable);
            return;
        }

        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        ImapDB.EmailIdentifier? local_earliest_id = yield local_folder.get_earliest_id_async(cancellable);
        ImapDB.EmailIdentifier? local_latest_id = yield local_folder.get_latest_id_async(cancellable);
        
        // verify still open; this is required throughout after each yield, as a close_async() can
        // come in ay any time since this does not run in the context of open_async()
        check_open("normalize_folders (local earliest/latest UID)");

        // if no earliest UID, that means no messages in local store, so nothing to update
        if (local_earliest_id == null || local_latest_id == null) {
            debug("%s: local store empty, nothing to normalize", to_string());
            return;
        }

        assert(local_earliest_id.has_uid());
        assert(local_latest_id.has_uid());
        
        // if any messages are still marked for removal from last time, that means the EXPUNGE
        // never arrived from the server, in which case the folder is "dirty" and needs a full
        // normalization
        Gee.Set<ImapDB.EmailIdentifier>? already_marked_ids = yield local_folder.get_marked_ids_async(
            cancellable);
        
        // however, there may be enqueue ReplayOperations waiting to remove messages on the server
        // that marked some or all of those messages
        Gee.HashSet<ImapDB.EmailIdentifier> to_be_removed = new Gee.HashSet<ImapDB.EmailIdentifier>();
        replay_queue.get_ids_to_be_remote_removed(to_be_removed);
        
        // don't consider those already marked as "already marked" if they were not leftover from
        // the last open of this folder
        if (already_marked_ids != null)
            already_marked_ids.remove_all(to_be_removed);
        
        bool is_dirty = (already_marked_ids != null && already_marked_ids.size > 0);
        
        if (is_dirty)
            debug("%s: %d remove markers found, folder is dirty", to_string(), already_marked_ids.size);
        
        // a full normalize works from the highest possible UID on the remote and work down to the lowest UID on
        // the local; this covers all messages appended since last seen as well as any removed
        Imap.UID last_uid = remote_properties.uid_next.previous(true);
        
        // if either local UID is out of range of the current highest UID, then something very wrong
        // has occurred; the only recourse is to wipe all associations and start over
        if (local_earliest_id.uid.compare_to(last_uid) > 0 || local_latest_id.uid.compare_to(last_uid) > 0) {
            debug("%s: Local UID(s) higher than remote UIDNEXT, detaching all email: %s/%s remote=%s",
                to_string(), local_earliest_id.uid.to_string(), local_latest_id.uid.to_string(),
                last_uid.to_string());
            yield detach_all_emails_async(cancellable);
            return;
        }

        // if UIDNEXT has changed, that indicates messages have been appended (and possibly removed)
        int64 uidnext_diff = remote_properties.uid_next.value - local_properties.uid_next.value;
        
        int local_message_count = (local_properties.select_examine_messages >= 0)
            ? local_properties.select_examine_messages : 0;
        int remote_message_count = (remote_properties.select_examine_messages >= 0)
            ? remote_properties.select_examine_messages : 0;
        
        // if UIDNEXT is the same as last time AND the total count of email is the same, then
        // nothing has been added or removed
        if (!is_dirty && uidnext_diff == 0 && local_message_count == remote_message_count) {
            debug("%s: No messages added/removed since last opened, normalization completed", to_string());
            return;
        }

        // if the difference in UIDNEXT values equals the difference in message count, then only
        // an append could have happened, so only pull in the new messages ... note that this is not foolproof,
        // as UIDs are not guaranteed to increase by 1; however, this is a standard implementation practice,
        // so it's worth looking for
        //
        // (Also, this cannot fail; if this situation exists, then it cannot by definition indicate another
        // situation, esp. messages being removed.)
        Imap.UID first_uid;
        if (!is_dirty && uidnext_diff == (remote_message_count - local_message_count)) {
            first_uid = local_latest_id.uid.next(true);
            
            debug("%s: Messages only appended (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s), gathering mail UIDs %s:%s",
                to_string(), local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
                local_properties.select_examine_messages, remote_properties.select_examine_messages, uidnext_diff.to_string(),
                first_uid.to_string(), last_uid.to_string());
        } else {
            first_uid = local_earliest_id.uid;
            
            debug("%s: Messages appended/removed (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s), gathering mail UIDs %s:%s",
                to_string(), local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
                local_properties.select_examine_messages, remote_properties.select_examine_messages, uidnext_diff.to_string(),
                first_uid.to_string(), last_uid.to_string());
        }
        
        // get all the UIDs in said range from the local store, sorted; convert to non-null
        // for ease of use later
        Gee.Set<Imap.UID>? local_uids = yield local_folder.list_uids_by_range_async(
            first_uid, last_uid, true, cancellable);
        if (local_uids == null)
            local_uids = new Gee.HashSet<Imap.UID>();
        
        check_open("normalize_folders (list local)");
        
        // Do the same on the remote ... make non-null for ease of use later
        Gee.Set<Imap.UID>? remote_uids = yield remote_folder.list_uids_async(
            new Imap.MessageSet.uid_range(first_uid, last_uid), cancellable);
        if (remote_uids == null)
            remote_uids = new Gee.HashSet<Imap.UID>();
        
        check_open("normalize_folders (list remote)");
        
        debug("%s: Loaded local (%d) and remote (%d) UIDs, normalizing...", to_string(),
            local_uids.size, remote_uids.size);
        
        Gee.HashSet<Imap.UID> removed_uids = new Gee.HashSet<Imap.UID>();
        Gee.HashSet<Imap.UID> appended_uids = new Gee.HashSet<Imap.UID>();
        Gee.HashSet<Imap.UID> inserted_uids = new Gee.HashSet<Imap.UID>();
        
        // Because the number of UIDs being processed can be immense in large folders, process
        // in a background thread
        yield Nonblocking.Concurrent.global.schedule_async(() => {
            // walk local UIDs looking for UIDs no longer on remote, removing those that are available
            // make the next pass that much shorter
            foreach (Imap.UID local_uid in local_uids) {
                // if in local but not remote, consider removed from remote
                if (!remote_uids.remove(local_uid))
                    removed_uids.add(local_uid);
            }
            
            // everything remaining in remote has been added since folder last seen ... whether they're
            // discovered (inserted) or appended depends on the highest local UID
            foreach (Imap.UID remote_uid in remote_uids) {
                if (remote_uid.compare_to(local_latest_id.uid) > 0)
                    appended_uids.add(remote_uid);
                else
                    inserted_uids.add(remote_uid);
            }
            
            // the UIDs marked for removal are going to be re-inserted into the vector once they're
            // cleared, so add them here as well
            if (already_marked_ids != null) {
                foreach (ImapDB.EmailIdentifier id in already_marked_ids) {
                    assert(id.has_uid());
                    
                    if (!appended_uids.contains(id.uid))
                        inserted_uids.add(id.uid);
                }
            }
        }, cancellable);
        
        debug("%s: changes since last seen: removed=%d appended=%d inserted=%d", to_string(),
            removed_uids.size, appended_uids.size, inserted_uids.size);
        
        // fetch from the server the local store's required flags for all appended/inserted messages
        // (which is simply equal to all remaining remote UIDs)
        Gee.List<Geary.Email> to_create = new Gee.ArrayList<Geary.Email>();
        if (remote_uids.size > 0) {
            // for new messages, get the local store's required fields (which provide duplicate
            // detection)
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(remote_uids);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(msg_set,
                    ImapDB.Folder.REQUIRED_FIELDS, cancellable);
                if (list != null && list.size > 0)
                    to_create.add_all(list);
            }
        }
        
        check_open("normalize_folders (list remote appended/inserted required fields)");
        
        // store new messages and add IDs to the appended/discovered EmailIdentifier buckets
        Gee.Set<ImapDB.EmailIdentifier> appended_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        Gee.Set<ImapDB.EmailIdentifier> locally_appended_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        Gee.Set<ImapDB.EmailIdentifier> inserted_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        Gee.Set<ImapDB.EmailIdentifier> locally_inserted_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        if (to_create.size > 0) {
            Gee.Map<Email, bool>? created_or_merged = yield local_folder.create_or_merge_email_async(
                to_create, cancellable);
            assert(created_or_merged != null);
            
            // it's possible a large number of messages have come in, so process them in the
            // background
            yield Nonblocking.Concurrent.global.schedule_async(() => {
                foreach (Email email in created_or_merged.keys) {
                    ImapDB.EmailIdentifier id = (ImapDB.EmailIdentifier) email.id;
                    bool created = created_or_merged.get(email);
                    
                    // report all appended email, but separate out email never seen before (created)
                    // as locally-appended
                    if (appended_uids.contains(id.uid)) {
                        appended_ids.add(id);
                        
                        if (created)
                            locally_appended_ids.add(id);
                    } else if (inserted_uids.contains(id.uid)) {
                        inserted_ids.add(id);
                        
                        if (created)
                            locally_inserted_ids.add(id);
                    }
                }
            }, cancellable);
            
            debug("%s: Finished creating/merging %d emails", to_string(), created_or_merged.size);
        }
        
        check_open("normalize_folders (created/merged appended/inserted emails)");
        
        // Convert removed UIDs into EmailIdentifiers and detach immediately
        Gee.Set<ImapDB.EmailIdentifier>? removed_ids = null;
        if (removed_uids.size > 0) {
            removed_ids = yield local_folder.get_ids_async(removed_uids,
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
            if (removed_ids != null && removed_ids.size > 0) {
                yield local_folder.detach_multiple_emails_async(removed_ids, cancellable);
            }
        }
        
        check_open("normalize_folders (removed emails)");
        
        // remove any extant remove markers, as everything is accounted for now, except for those
        // waiting to be removed in the queue
        yield local_folder.clear_remove_markers_async(to_be_removed, cancellable);
        
        check_open("normalize_folders (clear remove markers)");
        
        //
        // now normalized
        // notify subscribers of changes
        //
        
        Folder.CountChangeReason count_change_reason = Folder.CountChangeReason.NONE;
        
        if (removed_ids != null && removed_ids.size > 0) {
            // there may be operations pending on the remote queue for these removed emails; notify
            // operations that the email has shuffled off this mortal coil
            replay_queue.notify_remote_removed_ids(removed_ids);
            
            // notify subscribers about emails that have been removed
            debug("%s: Notifying of %d removed emails since last opened", to_string(), removed_ids.size);
            notify_email_removed(removed_ids);
            
            count_change_reason |= Folder.CountChangeReason.REMOVED;
        }
        
        // notify inserted (new email located somewhere inside the local vector)
        if (inserted_ids.size > 0) {
            debug("%s: Notifying of %d inserted emails since last opened", to_string(), inserted_ids.size);
            notify_email_inserted(inserted_ids);
            
            count_change_reason |= Folder.CountChangeReason.INSERTED;
        }
        
        // notify inserted (new email located somewhere inside the local vector that had to be
        // created, i.e. no portion was stored locally)
        if (locally_inserted_ids.size > 0) {
            debug("%s: Notifying of %d locally inserted emails since last opened", to_string(),
                locally_inserted_ids.size);
            notify_email_locally_inserted(locally_inserted_ids);
            
            count_change_reason |= Folder.CountChangeReason.INSERTED;
        }
        
        // notify appended (new email added since the folder was last opened)
        if (appended_ids.size > 0) {
            debug("%s: Notifying of %d appended emails since last opened", to_string(), appended_ids.size);
            notify_email_appended(appended_ids);
            
            count_change_reason |= Folder.CountChangeReason.APPENDED;
        }
        
        // notify locally appended (new email never seen before added since the folder was last
        // opened)
        if (locally_appended_ids.size > 0) {
            debug("%s: Notifying of %d locally appended emails since last opened", to_string(),
                locally_appended_ids.size);
            notify_email_locally_appended(locally_appended_ids);
            
            count_change_reason |= Folder.CountChangeReason.APPENDED;
        }
        
        if (count_change_reason != Folder.CountChangeReason.NONE) {
            debug("%s: Notifying of %Xh count change reason (%d remote messages)", to_string(),
                count_change_reason, remote_message_count);
            notify_email_count_changed(remote_message_count, count_change_reason);
        }

        debug("%s: Completed normalize_folder", to_string());
    }

    /**
     * Unhooks the IMAP folder session and returns it to the account.
     */
    internal async void close_remote_session(Folder.CloseReason remote_reason) {
        // Block anyone calling wait_for_remote_async(), as the session
        // will no longer available.
        this.remote_wait_semaphore.reset();

        Imap.FolderSession session = this.remote_folder;
        this.remote_folder = null;
        this.remote_count = -1;

        if (session != null) {
            session.appended.disconnect(on_remote_appended);
            session.updated.disconnect(on_remote_updated);
            session.removed.disconnect(on_remote_removed);
            session.disconnected.disconnect(on_remote_disconnected);
            this._account.release_folder_session(session);

            notify_closed(remote_reason);
        }
    }

    /**
     * Starts closing the folder, called from {@link UserClose}.
     */
    internal async bool user_close_async(Cancellable? cancellable) {
        // decrement open_count and, if zero, continue closing Folder
        if (open_count == 0 || --open_count > 0)
            return false;

        // Close the prefetcher early so it stops using the remote ASAP
        this.email_prefetcher.close();

        if (this.remote_folder != null)
            _properties.remove(this.remote_folder.folder.properties);

        // block anyone from wait_for_remote_async(), as this is no longer open
        this.remote_wait_semaphore.reset();

        // don't yield here, close_internal_async() needs to be called outside of the replay queue
        // the open_count protects against this path scheduling it more than once
        this.close_internal_async.begin(
            CloseReason.LOCAL_CLOSE,
            CloseReason.REMOTE_CLOSE,
            true,
            cancellable
        );

        return true;
    }

    /**
     * Forces closes the folder.
     *
     * NOTE: This bypasses open_count and forces the Folder closed.
     */
    internal async void close_internal_async(Folder.CloseReason local_reason,
                                             Folder.CloseReason remote_reason,
                                             bool flush_pending,
                                             Cancellable? cancellable) {
        try {
            int token = yield this.close_mutex.claim_async(cancellable);
            yield close_internal_locked_async(
                local_reason, remote_reason, flush_pending, cancellable
            );
            this.close_mutex.release(ref token);
        } catch (Error err) {
            // oh well
        }
    }

    // Should only be called when close_mutex is locked, i.e. use close_internal_async()
    private async void close_internal_locked_async(Folder.CloseReason local_reason,
                                                   Folder.CloseReason remote_reason,
                                                   bool flush_pending,
                                                   Cancellable? cancellable) {
        // Ensure we don't attempt to start opening a remote while
        // closing
        this._account.session_pool.ready.disconnect(on_remote_ready);
        this.remote_open_timer.reset();

        // only flushing pending ReplayOperations if this is a "clean" close, not forced due to
        // error and if specified by caller (could be a non-error close on the server, i.e. "BYE",
        // but the connection is dropping, so don't flush pending)
        flush_pending = (
            flush_pending &&
            !local_reason.is_error() &&
            !remote_reason.is_error()
        );

        if (flush_pending) {
            // We are flushing the queue, so gather operations from
            // Revokables to give them a chance to schedule their
            // commit operations before going down
            Gee.List<ReplayOperation> final_ops = new Gee.ArrayList<ReplayOperation>();
            notify_closing(final_ops);
            foreach (ReplayOperation op in final_ops)
                replay_queue.schedule(op);
        } else {
            // Not flushing the queue, so notify all operations
            // waiting for the remote that it's not coming available
            // ... this wakes up any ReplayOperation blocking on
            // wait_for_remote_async(), necessary in order to finish
            // ReplayQueue.close_async (i.e. to prevent deadlock);
            // this is necessary because it's possible for this method
            // to be called before a session has even had a chance to
            // open.
            //
            // We don't want to do this for a clean close yet, because
            // some pending operations may still need to use the
            // session.
            notify_remote_waiters(false);
        }

        // swap out the ReplayQueue while closing so, if re-opened,
        // future commands can be queued on the new queue
        ReplayQueue closing_replay_queue = this.replay_queue;
        this.replay_queue = new ReplayQueue(this);

        // Close the replay queues; if a "clean" close, flush pending operations so everything
        // gets a chance to run; if forced close, drop everything outstanding
        try {
            debug("Closing replay queue for %s (flush_pending=%s): %s", to_string(),
                  flush_pending.to_string(), closing_replay_queue.to_string());
            yield closing_replay_queue.close_async(flush_pending);
            debug("Closed replay queue for %s: %s", to_string(), closing_replay_queue.to_string());
        } catch (Error replay_queue_err) {
            debug("Error closing %s replay queue: %s", to_string(), replay_queue_err.message);
        }

        // If flushing, now notify waiters that the queue has bee flushed
        if (flush_pending) {
            notify_remote_waiters(false);
        }

        // forced closed one way or another, so reset state
        this.open_count = 0;
        this.open_flags = OpenFlags.NONE;

        // Actually close the remote folder
        yield close_remote_session(remote_reason);

        // need to call these every time, even if remote was not fully
        // opened, as some callers rely on order of signals
        notify_closed(local_reason);
        notify_closed(CloseReason.FOLDER_CLOSED);

        // Notify waiting tasks
        this.closed_semaphore.blind_notify();

        debug("Folder %s closed", to_string());
    }

    /**
     * Establishes a new IMAP session, normalising local and remote folders.
     */
    private async void open_remote_session() {
        try {
            int token = yield this.open_mutex.claim_async(this.open_cancellable);

            // Ensure we are open already and guard against someone
            // else having called this just before we did.
            if (this.open_count > 0 &&
                this._account.session_pool.is_ready &&
                this.remote_folder == null) {

                this.opening_monitor.notify_start();
                yield open_remote_session_locked(this.open_cancellable);
                this.opening_monitor.notify_finish();
            }

            this.open_mutex.release(ref token);
        } catch (Error err) {
            // Lock error
        }
    }

    // Should only be called when open_mutex is locked, i.e. use open_remote_session()
    private async void open_remote_session_locked(Cancellable? cancellable) {
        debug("%s: Opening remote session", to_string());

        // Don't try to re-open again
        this.remote_open_timer.reset();

        // Phase 1: Acquire a new session

        Imap.FolderSession? session = null;
        try {
            session = yield this._account.open_folder_session(this.path, cancellable);
        } catch (Error err) {
            // Notify that there was a connection error, but don't
            // force the folder closed, since it might come good again
            // if the user fixes an auth problem or the network comes
            // back or whatever.
            notify_open_failed(Folder.OpenFailed.REMOTE_ERROR, err);
            return;
        }

        // Phase 2: Update local state based on the remote session

        // Signals need to be hooked up before normalisation so that
        // notifications of state changes are not lost when that is
        // running.
        session.appended.connect(on_remote_appended);
        session.updated.connect(on_remote_updated);
        session.removed.connect(on_remote_removed);
        session.disconnected.connect(on_remote_disconnected);

        try {
            yield normalize_folders(session, cancellable);
        } catch (Error err) {
            // Normalisation failed, which is also a serious problem
            // so treat as in the error case above, after resolving if
            // the issue was local or remote.
            this._account.release_folder_session(session);
            if (err is IOError.CANCELLED) {
                notify_open_failed(OpenFailed.LOCAL_ERROR, err);
            } else {
                Folder.CloseReason local_reason = CloseReason.LOCAL_ERROR;
                Folder.CloseReason remote_reason = CloseReason.REMOTE_CLOSE;
                if (!is_remote_error(err)) {
                    notify_open_failed(OpenFailed.LOCAL_ERROR, err);
                } else {
                    notify_open_failed(OpenFailed.REMOTE_ERROR, err);
                    local_reason =  CloseReason.LOCAL_CLOSE;
                    remote_reason = CloseReason.REMOTE_ERROR;
                }

                this.close_internal_async.begin(
                    local_reason,
                    remote_reason,
                    false,
                    null // Don't pass cancellable, close must complete
                );
            }
            return;
        }

        try {
            yield local_folder.update_folder_select_examine(
                session.folder.properties, cancellable
            );
            this.remote_count = session.folder.properties.email_total;
        } catch (Error err) {
            // Database failed, so we have a pretty serious problem
            // and should not try to use the folder further, unless
            // the open was simply cancelled. So clean up, and force
            // the folder closed if needed.
            this._account.release_folder_session(session);
            notify_open_failed(Folder.OpenFailed.LOCAL_ERROR, err);
            if (!(err is IOError.CANCELLED)) {
                this.close_internal_async.begin(
                    CloseReason.LOCAL_ERROR,
                    CloseReason.REMOTE_CLOSE,
                    false,
                    null // Don't pass cancellable, close must complete
                );
            }
            return;
        }

        // Phase 3: Move in place and notify waiters

        this.remote_folder = session;

        // notify any subscribers with similar information
        notify_opened(Geary.Folder.OpenState.BOTH, this.remote_count);

        // notify any threads of execution waiting for the remote
        // folder to open that the result of that operation is ready
        notify_remote_waiters(true);

        // Update flags once the folder has opened. We will receive
        // notifications of changes as long as the session remains
        // open, so only need to do this once
        this.update_flags_timer.start();
    }

    public override async void find_boundaries_async(Gee.Collection<Geary.EmailIdentifier> ids,
        out Geary.EmailIdentifier? low, out Geary.EmailIdentifier? high,
        Cancellable? cancellable = null) throws Error {
        low = null;
        high = null;
        
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? map
            = yield account.get_containing_folders_async(ids, cancellable);
        
        if (map != null) {
            Gee.ArrayList<Geary.EmailIdentifier> in_folder = new Gee.ArrayList<Geary.EmailIdentifier>();
            foreach (Geary.EmailIdentifier id in map.get_keys()) {
                if (path in map.get(id))
                    in_folder.add(id);
            }
            
            if (in_folder.size > 0) {
                Gee.SortedSet<Geary.EmailIdentifier> sorted = Geary.EmailIdentifier.sort(in_folder);
                
                low = sorted.first();
                high = sorted.last();
            }
        }
    }
    
    private void on_email_complete(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        notify_email_locally_complete(email_ids);
    }
    
    private void on_remote_appended(int reported_remote_count) {
        debug("%s on_remote_appended: remote_count=%d reported_remote_count=%d", to_string(), remote_count,
            reported_remote_count);
        
        if (reported_remote_count < 0)
            return;
        
        // from the new remote total and the old remote total, glean the SequenceNumbers of the
        // new email(s)
        Gee.List<Imap.SequenceNumber> positions = new Gee.ArrayList<Imap.SequenceNumber>();
        for (int pos = remote_count + 1; pos <= reported_remote_count; pos++)
            positions.add(new Imap.SequenceNumber(pos));

        // store the remote count NOW, as further appended messages could arrive before the
        // ReplayAppend executes
        this.remote_count = reported_remote_count;

        if (positions.size > 0) {
            ReplayAppend op = new ReplayAppend(this, reported_remote_count, positions);
            op.email_appended.connect(notify_email_appended);
            op.email_locally_appended.connect(notify_email_locally_appended);
            op.email_count_changed.connect(notify_email_count_changed);
            this.replay_queue.schedule_server_notification(op);
        }
    }

    private void on_remote_updated(Imap.SequenceNumber position, Imap.FetchedData data) {
        debug("%s on_remote_updated: remote_count=%d position=%s", to_string(),
              this.remote_count, position.to_string());

        this.replay_queue.schedule_server_notification(
            new ReplayUpdate(this, this.remote_count, position, data)
        );
    }

    private void on_remote_removed(Imap.SequenceNumber position, int reported_remote_count) {
        debug("%s on_remote_removed: remote_count=%d position=%s reported_remote_count=%d", to_string(),
            remote_count, position.to_string(), reported_remote_count);
        
        if (reported_remote_count < 0)
            return;
        
        // notify of removal to all pending replay operations
        replay_queue.notify_remote_removed_position(position);
        
        // update remote count NOW, as further appended and removed messages can arrive before
        // ReplayRemoval executes
        //
        // something to note at this point: the ExpungeEmail operation marks messages as removed,
        // then signals they're removed and reports an adjusted count in its replay_local_async().
        // remote_count is *not* updated, which is why it's safe to do that here without worry.
        // similarly, signals are only fired here if marked, so the same EmailIdentifier isn't
        // reported twice
        this.remote_count = reported_remote_count;

        ReplayRemoval op = new ReplayRemoval(this, reported_remote_count, position);
        op.email_removed.connect(notify_email_removed);
        op.marked_email_removed.connect(notify_marked_email_removed);
        op.email_count_changed.connect(notify_email_count_changed);
        this.replay_queue.schedule_server_notification(op);
    }

    private void on_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("on_remote_disconnected: reason=%s", reason.to_string());
        replay_queue.schedule(new ReplayDisconnect(this, reason, false, null));
    }

    //
    // list email variants
    //
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        check_open("list_email_by_id_async");
        check_flags("list_email_by_id_async", flags);
        if (initial_id != null)
            check_id("list_email_by_id_async", initial_id);
        
        if (count == 0)
            return null;
        
        // Schedule list operation and wait for completion.
        ListEmailByID op = new ListEmailByID(this, (ImapDB.EmailIdentifier) initial_id, count,
            required_fields, flags, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
        
        return !op.accumulator.is_empty ? op.accumulator : null;
    }
    
    public async override Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        check_open("list_email_by_sparse_id_async");
        check_flags("list_email_by_sparse_id_async", flags);
        check_ids("list_email_by_sparse_id_async", ids);
        
        if (ids.size == 0)
            return null;
        
        // Schedule list operation and wait for completion.
        // TODO: Break up requests to avoid hogging the queue
        ListEmailBySparseID op = new ListEmailBySparseID(this, (Gee.Collection<ImapDB.EmailIdentifier>) ids,
            required_fields, flags, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
        
        return !op.accumulator.is_empty ? op.accumulator : null;
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        check_open("list_local_email_fields_async");
        check_ids("list_local_email_fields_async", ids);
        
        return yield local_folder.list_email_fields_by_id_async(
            (Gee.Collection<Geary.ImapDB.EmailIdentifier>) ids, ImapDB.Folder.ListFlags.NONE, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open("fetch_email_async");
        check_flags("fetch_email_async", flags);
        check_id("fetch_email_async", id);
        
        FetchEmail op = new FetchEmail(this, (ImapDB.EmailIdentifier) id, required_fields, flags,
            cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
        
        if (op.email == null) {
            throw new EngineError.NOT_FOUND("Email %s not found in %s", id.to_string(), to_string());
        } else if (!op.email.fields.fulfills(required_fields)) {
            throw new EngineError.INCOMPLETE_MESSAGE("Email %s in %s does not fulfill required fields %Xh (has %Xh)",
                id.to_string(), to_string(), required_fields, op.email.fields);
        }
        
        return op.email;
    }
    
    // Helper function for child classes dealing with the delete/archive question.  This method will
    // mark the message as deleted and expunge it.
    protected async void expunge_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable) throws Error {
        check_open("expunge_email_async");
        check_ids("expunge_email_async", email_ids);
        
        RemoveEmail remove = new RemoveEmail(this, (Gee.List<ImapDB.EmailIdentifier>) email_ids,
            cancellable);
        replay_queue.schedule(remove);
        
        yield remove.wait_for_ready_async(cancellable);
    }
    
    protected async void expunge_all_async(Cancellable? cancellable = null) throws Error {
        check_open("expunge_all_async");
        
        EmptyFolder empty_folder = new EmptyFolder(this, cancellable);
        replay_queue.schedule(empty_folder);
        
        yield empty_folder.wait_for_ready_async(cancellable);
    }
    
    private void check_open(string method) throws EngineError {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("%s failed: folder %s is not open", method, to_string());
    }
    
    private void check_flags(string method, Folder.ListFlags flags) throws EngineError {
        if (flags.is_all_set(Folder.ListFlags.LOCAL_ONLY) && flags.is_all_set(Folder.ListFlags.FORCE_UPDATE)) {
            throw new EngineError.BAD_PARAMETERS("%s %s failed: LOCAL_ONLY and FORCE_UPDATE are mutually exclusive",
                to_string(), method);
        }
    }
    
    private void check_id(string method, EmailIdentifier id) throws EngineError {
        if (!(id is ImapDB.EmailIdentifier))
            throw new EngineError.BAD_PARAMETERS("Email ID %s is not IMAP Email ID", id.to_string());
    }
    
    private void check_ids(string method, Gee.Collection<EmailIdentifier> ids) throws EngineError {
        foreach (EmailIdentifier id in ids)
            check_id(method, id);
    }
    
    public virtual async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove,
        Cancellable? cancellable = null) throws Error {
        check_open("mark_email_async");
        check_ids("mark_email_async", to_mark);

        MarkEmail mark = new MarkEmail(this, (Gee.List<ImapDB.EmailIdentifier>) to_mark, flags_to_add, flags_to_remove, cancellable);
        replay_queue.schedule(mark);
        
        yield mark.wait_for_ready_async(cancellable);
    }

    public virtual async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
                                               Geary.FolderPath destination,
                                               Cancellable? cancellable = null)
        throws Error {
        Geary.Folder target = yield this._account.fetch_folder_async(destination);
        yield copy_email_uids_async(to_copy, destination, cancellable);
        this._account.update_folder(target);
    }

    /**
     * Returns the destination folder's UIDs for the copied messages.
     */
    protected async Gee.Set<Imap.UID>? copy_email_uids_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("copy_email_uids_async");
        check_ids("copy_email_uids_async", to_copy);
        
        // watch for copying to this folder, which is treated as a no-op
        if (destination.equal_to(path))
            return null;
        
        CopyEmail copy = new CopyEmail(this, (Gee.List<ImapDB.EmailIdentifier>) to_copy, destination);
        replay_queue.schedule(copy);
        
        yield copy.wait_for_ready_async(cancellable);
        
        return copy.destination_uids.size > 0 ? copy.destination_uids : null;
    }

    public virtual async Geary.Revokable? move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("move_email_async");
        check_ids("move_email_async", to_move);
        
        // watch for moving to this folder, which is treated as a no-op
        if (destination.equal_to(path))
            return null;
        
        MoveEmailPrepare prepare = new MoveEmailPrepare(this, (Gee.List<ImapDB.EmailIdentifier>) to_move,
            cancellable);
        replay_queue.schedule(prepare);
        
        yield prepare.wait_for_ready_async(cancellable);
        
        if (prepare.prepared_for_move == null || prepare.prepared_for_move.size == 0)
            return null;

        Geary.Folder target = yield this._account.fetch_folder_async(destination);
        return new RevokableMove(
            _account, this, target, prepare.prepared_for_move
        );
    }

    public void schedule_op(ReplayOperation op) throws Error {
        check_open("schedule_op");
        
        replay_queue.schedule(op);
    }
    
    public async void exec_op_async(ReplayOperation op, Cancellable? cancellable) throws Error {
        schedule_op(op);
        yield op.wait_for_ready_async(cancellable);
    }

    public override string to_string() {
        return "%s (open_count=%d remote_opened=%s)".printf(
            base.to_string(), open_count, (remote_folder != null).to_string()
        );
    }

    /**
     * Schedules a refresh of the unseen count for the folder.
     *
     * This will only refresh folders that are not open, since if they
     * are open or opening, they will already be updated. Hence it is safe to be called on closed folders.
     */
    internal void refresh_unseen() {
        if (this.open_count == 0) {
            this.refresh_unseen_timer.start();
        }
    }

    // TODO: A proper public search mechanism; note that this always round-trips to the remote,
    // doesn't go through the replay queue, and doesn't deal with messages marked for deletion
    internal async Geary.Email? find_earliest_email_async(DateTime datetime,
        Geary.EmailIdentifier? before_id, Cancellable? cancellable) throws Error {
        check_open("find_earliest_email_async");
        if (before_id != null)
            check_id("find_earliest_email_async", before_id);
        
        Imap.SearchCriteria criteria = new Imap.SearchCriteria();
        criteria.is_(Imap.SearchCriterion.since_internaldate(new Imap.InternalDate.from_date_time(datetime)));
        
        // if before_id available, only search for messages before it
        if (before_id != null) {
            Imap.UID? before_uid = yield local_folder.get_uid_async((ImapDB.EmailIdentifier) before_id,
                ImapDB.Folder.ListFlags.NONE, cancellable);
            if (before_uid == null) {
                throw new EngineError.NOT_FOUND("before_id %s not found in %s", before_id.to_string(),
                    to_string());
            }
            
            criteria.and(Imap.SearchCriterion.message_set(
                new Imap.MessageSet.uid_range(new Imap.UID(Imap.UID.MIN), before_uid.previous(true))));
        }

        ServerSearchEmail op = new ServerSearchEmail(this, criteria, Geary.Email.Field.NONE,
            cancellable);
        
        // need to check again due to the yield in the above conditional block
        check_open("find_earliest_email_async.schedule operation");
        
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);

        // find earliest ID; because all Email comes from Folder, UID should always be present
        Geary.Email? earliest = null;
        ImapDB.EmailIdentifier? earliest_id = null;
        foreach (Geary.Email email in op.accumulator) {
            ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
            if (earliest_id == null || email_id.uid.compare_to(earliest_id.uid) < 0) {
                earliest = email;
                earliest_id = email_id;
            }
        }
        return earliest;
    }

    protected async Geary.EmailIdentifier? create_email_async(RFC822.Message rfc822,
        Geary.EmailFlags? flags, DateTime? date_received, Geary.EmailIdentifier? id,
        Cancellable? cancellable = null) throws Error {
        check_open("create_email_async");
        if (id != null)
            check_id("create_email_async", id);
        
        Error? cancel_error = null;
        Geary.EmailIdentifier? ret = null;
        try {
            CreateEmail create = new CreateEmail(this, rfc822, flags, date_received, cancellable);
            replay_queue.schedule(create);
            yield create.wait_for_ready_async(cancellable);
            
            ret = create.created_id;
        } catch (Error e) {
            if (e is IOError.CANCELLED)
                cancel_error = e;
            else
                throw e;
        }
        
        Geary.FolderSupport.Remove? remove_folder = this as Geary.FolderSupport.Remove;
        
        // Remove old message.
        if (id != null && remove_folder != null)
            yield remove_folder.remove_email_async(iterate<EmailIdentifier>(id).to_array_list());
        
        // If the user cancelled the operation, throw the error here.
        if (cancel_error != null)
            throw cancel_error;
        
        // If the caller cancelled during the remove operation, delete the newly created message to
        // safely back out.
        if (cancellable != null && cancellable.is_cancelled() && ret != null && remove_folder != null)
            yield remove_folder.remove_email_async(iterate<EmailIdentifier>(ret).to_array_list());

        this._account.update_folder(this);

        return ret;
    }

    /** Fires a {@link report_problem} signal for a service for this folder. */
    protected virtual void notify_service_problem(ProblemType type, Service service_type, Error? err) {
        report_problem(new ServiceProblemReport(
                           type, this._account.information, service_type, err
                       ));
    }

    /** Fires a {@link marked_email_removed} signal for this folder. */
    protected virtual void notify_marked_email_removed(Gee.Collection<Geary.EmailIdentifier> removed) {
        marked_email_removed(removed);
    }

    private inline void notify_remote_waiters(bool successful) {
        try {
            this.remote_wait_semaphore.notify_result(successful, null);
        } catch (Error err) {
            // Can't happen because semaphore has no cancellable
        }
    }

    /**
     * Checks for changes to {@link EmailFlags} after a folder opens.
     */
    private async void on_update_flags() throws Error {
        // Update this to use CHANGEDSINCE FETCH when available, when
        // we support IMAP CONDSTORE (Bug 713117).
        int chunk_size = FLAG_UPDATE_START_CHUNK;
        Geary.EmailIdentifier? lowest = null;
        for (;;) {
            yield wait_for_remote_async(this.open_cancellable);
            Gee.List<Geary.Email>? list_local = yield list_email_by_id_async(
                lowest, chunk_size,
                Geary.Email.Field.FLAGS,
                Geary.Folder.ListFlags.LOCAL_ONLY,
                this.open_cancellable
            );
            if (list_local == null || list_local.is_empty)
                break;

            // find the lowest for the next iteration
            lowest = Geary.EmailIdentifier.sort_emails(list_local).first().id;

            // Get all email identifiers in the local folder mapped to their EmailFlags
            Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> local_map =
                new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>();
            foreach (Geary.Email e in list_local)
                local_map.set(e.id, e.email_flags);

            // Fetch e-mail from folder using force update, which will cause the cache to be bypassed
            // and the latest to be gotten from the server (updating the cache in the process)
            debug("%s: fetching %d flags", this.to_string(), local_map.keys.size);
            Gee.List<Geary.Email>? list_remote = yield list_email_by_sparse_id_async(
                local_map.keys,
                Email.Field.FLAGS,
                Geary.Folder.ListFlags.FORCE_UPDATE,
                this.open_cancellable
            );
            if (list_remote == null || list_remote.is_empty)
                break;

            // Build map of emails that have changed.
            Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> changed_map =
                new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>();
            foreach (Geary.Email e in list_remote) {
                if (!local_map.has_key(e.id))
                    continue;

                if (!local_map.get(e.id).equal_to(e.email_flags))
                    changed_map.set(e.id, e.email_flags);
            }

            if (!this.open_cancellable.is_cancelled() && changed_map.size > 0)
                notify_email_flags_changed(changed_map);

            chunk_size *= 2;
            if (chunk_size > FLAG_UPDATE_MAX_CHUNK) {
                chunk_size = FLAG_UPDATE_MAX_CHUNK;
            }
        }
    }

    private void on_refresh_unseen() {
        // We queue an account operation since the folder itself is
        // closed and hence does not have a connection to use for it.
        RefreshFolderUnseen op = new RefreshFolderUnseen(this, this._account);
        try {
            this._account.queue_operation(op);
        } catch (Error err) {
            // oh well
        }
    }

    private void on_remote_ready() {
        this.open_remote_session.begin();
    }

}
