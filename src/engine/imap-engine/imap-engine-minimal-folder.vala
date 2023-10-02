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

    public override Folder.SpecialUse used_as {
        get {
            return this._used_as;
        }
    }
    private Folder.SpecialUse _used_as;

    private ProgressMonitor _opening_monitor =
        new Geary.ReentrantProgressMonitor(Geary.ProgressType.ACTIVITY);
    public override Geary.ProgressMonitor opening_monitor {
        get {
            return _opening_monitor;
        }
    }

    /** The IMAP database representation of the folder. */
    internal ImapDB.Folder local_folder { get; private set; }

    internal ReplayQueue? replay_queue { get; private set; default = null; }
    internal ContactHarvester harvester { get; private set; }

    private weak GenericAccount _account;
    private Geary.AggregatedFolderProperties _properties =
        new Geary.AggregatedFolderProperties(false, false);
    private EmailPrefetcher email_prefetcher;

    private int open_count = 0;
    private Folder.OpenFlags open_flags = OpenFlags.NONE;
    private Cancellable? open_cancellable = null;
    private Nonblocking.Mutex lifecycle_mutex = new Nonblocking.Mutex();
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();

    private Imap.FolderSession? remote_session = null;
    private Nonblocking.Mutex remote_mutex = new Nonblocking.Mutex();
    private Nonblocking.ReportingSemaphore<bool> remote_wait_semaphore =
        new Nonblocking.ReportingSemaphore<bool>(false);
    private TimeoutManager remote_open_timer;

    private TimeoutManager update_flags_timer;

    private TimeoutManager refresh_unseen_timer;


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
                         Folder.SpecialUse use) {
        this._account = account;
        this.local_folder = local_folder;
        this.local_folder.email_complete.connect(on_email_complete);

        this._used_as = use;
        this._properties.add(local_folder.get_properties());
        this.email_prefetcher = new EmailPrefetcher(this);
        update_harvester();

        this.remote_open_timer = new TimeoutManager.seconds(
            FORCE_OPEN_REMOTE_TIMEOUT_SEC, () => { this.open_remote_session.begin(); }
        );

        this.update_flags_timer = new TimeoutManager.seconds(
            FLAG_UPDATE_TIMEOUT_SEC, on_update_flags
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

    public override void set_used_as_custom(bool enabled)
        throws EngineError.UNSUPPORTED {
        if (enabled) {
            if (this._used_as != NONE) {
                throw new EngineError.UNSUPPORTED(
                    "Folder already has special use"
                );
            }
            set_use(CUSTOM);
        } else {
            if (this._used_as != CUSTOM &&
                this._used_as != NONE) {
                throw new EngineError.UNSUPPORTED(
                    "Folder already has special use"
                );
            }
            set_use(NONE);
        }
    }

    public void set_use(Folder.SpecialUse new_use) {
        var old_use = this._used_as;
        this._used_as = new_use;
        if (old_use != new_use) {
            notify_use_changed(old_use, new_use);
            update_harvester();
        }
    }

    /** {@inheritDoc} */
    public override Geary.Folder.OpenState get_open_state() {
        if (this.open_count == 0)
            return Geary.Folder.OpenState.CLOSED;

        return (this.remote_session != null)
           ? Geary.Folder.OpenState.REMOTE
           : Geary.Folder.OpenState.LOCAL;
    }

    /** {@inheritDoc} */
    public override async bool open_async(Folder.OpenFlags open_flags,
                                          Cancellable? cancellable = null)
        throws Error {
        // Claim the lifecycle_mutex here so we don't try to re-open when
        // the folder is in the middle of being closed.
        bool opening = false;
        Error? open_err = null;
        try {
            int token = yield this.lifecycle_mutex.claim_async(cancellable);
            try {
                opening = yield open_locked(open_flags, cancellable);
            } catch (Error err) {
                open_err = err;
            }
            this.lifecycle_mutex.release(ref token);
        } catch (Error err) {
            // oh well
        }

        if (open_err != null) {
            throw open_err;
        }

        return opening;
    }

    /**
     * Returns a valid IMAP folder session when one is available.
     *
     * Implementations may use this to acquire an IMAP session for
     * performing folder-related work. The call will wait until a
     * connection is established then return the session.
     *
     * The session returned is guaranteed to be open upon return,
     * however may close afterwards due to this folder closing, or the
     * network connection going away.
     *
     * The folder must have been opened before calling this method.
     */
    public async Imap.FolderSession claim_remote_session(Cancellable? cancellable = null)
        throws Error {
        check_open("claim_remote_session");
        debug("Claiming folder session");


        // If remote has not yet been opened and we are not in the
        // process of closing the folder, open a session right away.
        if (this.remote_session == null && !this.open_cancellable.is_cancelled()) {
            this.open_remote_session.begin();
        }

        if (!yield this.remote_wait_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.ALREADY_CLOSED("%s failed to open", to_string());

        return this.remote_session;
    }

    /** {@inheritDoc} */
    public override async bool close_async(Cancellable? cancellable = null)
        throws Error {
        check_open("close_async");
        debug("Scheduling folder close");
        // Although it's inefficient in the case of just decrementing
        // the open count, pass all requests to close via the replay
        // queue so that other operations queued are interleaved in an
        // expected way, the same code path can be used to both test
        // and decrement the open count, and that the decrement can be
        // used under the same lock as actually closing the folder,
        // making it essentially an atomic operation.
        UserClose op = new UserClose(this, cancellable);
        this.replay_queue.schedule(op);
        yield op.wait_for_ready_async(cancellable);
        return op.is_closing.is_certain();
    }

    /** {@inheritDoc} */
    public override async void wait_for_close_async(Cancellable? cancellable = null)
        throws Error {
        yield this.closed_semaphore.wait_async(cancellable);
    }

    /** {@inheritDoc} */
    public override async void synchronise_remote(GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open("synchronise_remote");

        bool have_nooped = false;
        int retries = 3;
        while (!have_nooped && !cancellable.is_cancelled()) {
            // The normalisation process will pick up any missing
            // messages if closed, so ensure there is a remote
            // session.
            Imap.FolderSession? remote =
                yield claim_remote_session(cancellable);

            try {
                // Send a NOOP so the server can return an untagged
                // EXISTS if any new messages have arrived since the
                // remote was opened.
                //
                // This is important for servers like GMail that
                // automatically save sent mail, since the Sent folder
                // will already be open, but unless the client is also
                // showing the Sent folder, IDLE won't be enabled and
                // hence we won't get notified of the saved mail.
                yield remote.send_noop(cancellable);
                have_nooped = true;
            } catch (GLib.Error err) {
                retries =- 1;
                if (is_recoverable_failure(err) && retries > 0) {
                    // XXX In theory we should be able to just retry
                    // this immediately, but there's a race between
                    // the old connection being disposed and another
                    // being obtained that can make this into an
                    // infinite loop. So limit the maximum number of
                    // reties and set a timeout to help aid recovery.
                    debug("Recoverable error during remote sync: %s",
                          err.message);
                    GLib.Timeout.add_seconds(
                        1, this.synchronise_remote.callback
                    );
                    yield;
                } else {
                    throw err;
                }
            }
        }

        // Wait until the replay queue has processed all notifications
        // so the prefetcher becomes aware of the new mail
        this.replay_queue.flush_notifications();
        yield this.replay_queue.checkpoint(cancellable);

        // Finally, wait for the prefetcher to have finished
        // downloading the new mail.
        yield this.email_prefetcher.active_sem.wait_async(cancellable);
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

    /**
     * Synchronises the remote and local folders on session established.
     *
     * See [[https://tools.ietf.org/html/rfc4549|RFC 4549]] for an
     * overview of the process
     */
    private async void normalize_folders(Geary.Imap.FolderSession session,
                                         Cancellable cancellable)
        throws Error {
        debug("Begin normalizing remote and local folders");

        Geary.Imap.FolderProperties local_properties = this.local_folder.get_properties();
        Geary.Imap.FolderProperties remote_properties = session.folder.properties;

        /*
         * Step 1: Check UID validity. If there are any problems, we
         * can't continue, so either bail out completely or clear all
         * local messages and let the client start fetching them all
         * again.
         */

        // Both must have their next UID's - it's possible they don't
        // if it's a non-selectable folder.
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
            debug("UID validity changed, detaching all email: %s -> %s",
                local_properties.uid_validity.value.to_string(),
                remote_properties.uid_validity.value.to_string());
            yield detach_all_emails_async(cancellable);
            return;
        }

        /*
         * Step 2: Check the local folder. It may be empty, in which
         * case the client can just start fetching messages normally,
         * or it may be corrupt in which also clear it out and do
         * same.
         */

        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        ImapDB.EmailIdentifier? local_earliest_id = yield local_folder.get_earliest_id_async(cancellable);
        ImapDB.EmailIdentifier? local_latest_id = yield local_folder.get_latest_id_async(cancellable);

        // verify still open; this is required throughout after each yield, as a close_async() can
        // come in ay any time since this does not run in the context of open_async()
        check_open("normalize_folders (local earliest/latest UID)");

        // if no earliest UID, that means no messages in local store, so nothing to update
        if (local_earliest_id == null || local_latest_id == null) {
            debug("local store empty, nothing to normalize");
            return;
        }

        // If any messages are still marked for removal from last
        // time, that means the EXPUNGE never arrived from the server,
        // in which case the folder is "dirty" and needs a full
        // normalization. However, there may be enqueued
        // ReplayOperations waiting to remove messages on the server
        // that marked some or all of those messages, Don't consider
        // those already marked as "already marked" if they were not
        // leftover from the last open of this folder
        Gee.Set<ImapDB.EmailIdentifier>? already_marked_ids = yield local_folder.get_marked_ids_async(
            cancellable);
        Gee.HashSet<ImapDB.EmailIdentifier> to_be_removed = new Gee.HashSet<ImapDB.EmailIdentifier>();
        replay_queue.get_ids_to_be_remote_removed(to_be_removed);
        if (already_marked_ids != null)
            already_marked_ids.remove_all(to_be_removed);

        bool is_dirty = (already_marked_ids != null && already_marked_ids.size > 0);
        if (is_dirty)
            debug("%d remove markers found, folder is dirty",
                  already_marked_ids.size);

        // a full normalize works from the highest possible UID on the remote and work down to the lowest UID on
        // the local; this covers all messages appended since last seen as well as any removed
        Imap.UID last_uid = remote_properties.uid_next.previous(true);

        // if either local UID is out of range of the current highest UID, then something very wrong
        // has occurred; the only recourse is to wipe all associations and start over
        if (local_earliest_id.uid.compare_to(last_uid) > 0 || local_latest_id.uid.compare_to(last_uid) > 0) {
            debug("Local UID(s) higher than remote UIDNEXT, detaching all email: %s/%s remote=%s",
                  local_earliest_id.uid.to_string(),
                  local_latest_id.uid.to_string(),
                  last_uid.to_string());
            yield detach_all_emails_async(cancellable);
            return;
        }

        /*
         * Step 3: Check remote folder, work out what has changed.
         */

        // if UIDNEXT has changed, that indicates messages have been appended (and possibly removed)
        int64 uidnext_diff = remote_properties.uid_next.value - local_properties.uid_next.value;

        int local_message_count = (local_properties.select_examine_messages >= 0)
            ? local_properties.select_examine_messages : 0;
        int remote_message_count = (remote_properties.select_examine_messages >= 0)
            ? remote_properties.select_examine_messages : 0;

        // if UIDNEXT is the same as last time AND the total count of
        // email is the same, then nothing has been added or removed,
        // and we're done.
        if (!is_dirty && uidnext_diff == 0 && local_message_count == remote_message_count) {
            debug("No messages added/removed since last opened, normalization completed");
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

            debug("Messages only appended (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s), gathering mail UIDs %s:%s",
                local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
                local_properties.select_examine_messages, remote_properties.select_examine_messages, uidnext_diff.to_string(),
                first_uid.to_string(), last_uid.to_string());
        } else {
            first_uid = local_earliest_id.uid;

            debug("Messages appended/removed (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s), gathering mail UIDs %s:%s",
                local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
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
        Gee.Set<Imap.UID>? remote_uids = yield session.list_uids_async(
            new Imap.MessageSet.uid_range(first_uid, last_uid), cancellable);
        if (remote_uids == null)
            remote_uids = new Gee.HashSet<Imap.UID>();

        check_open("normalize_folders (list remote)");

        debug("Loaded local (%d) and remote (%d) UIDs, normalizing...",
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

        debug("Changes since last seen: removed=%d appended=%d inserted=%d",
              removed_uids.size, appended_uids.size, inserted_uids.size);

        /*
         * Step 4: Synchronise local folder with remote
         */

        // fetch from the server the local store's required flags for all appended/inserted messages
        // (which is simply equal to all remaining remote UIDs)
        Gee.List<Geary.Email> to_create = new Gee.ArrayList<Geary.Email>();
        if (remote_uids.size > 0) {
            // for new messages, get the local store's required fields (which provide duplicate
            // detection)
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(remote_uids);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                Gee.List<Geary.Email>? list = yield session.list_email_async(msg_set,
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
            // Don't update the unread count here, since it'll get
            // updated once normalisation has finished anyway. See
            // also Issue #213.
            Gee.Map<Email, bool>? created_or_merged =
                yield local_folder.create_or_merge_email_async(
                    to_create, false, this.harvester, cancellable
                );
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

            debug("Finished creating/merging %d emails", created_or_merged.size);
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

        if (cancellable.is_cancelled()) {
            return;
        }


        /*
         * Step 5: Notify subscribers of what has happened.
         */

        Folder.CountChangeReason count_change_reason = Folder.CountChangeReason.NONE;

        if (removed_ids != null && removed_ids.size > 0) {
            // there may be operations pending on the remote queue for these removed emails; notify
            // operations that the email has shuffled off this mortal coil
            replay_queue.notify_remote_removed_ids(removed_ids);

            // notify subscribers about emails that have been removed
            debug("Notifying of %d removed emails since last opened",
                  removed_ids.size);
            notify_email_removed(removed_ids);

            count_change_reason |= Folder.CountChangeReason.REMOVED;
        }

        // notify inserted (new email located somewhere inside the local vector)
        if (inserted_ids.size > 0) {
            debug("Notifying of %d inserted emails since last opened",
                  inserted_ids.size);
            notify_email_inserted(inserted_ids);

            count_change_reason |= Folder.CountChangeReason.INSERTED;
        }

        // notify inserted (new email located somewhere inside the local vector that had to be
        // created, i.e. no portion was stored locally)
        if (locally_inserted_ids.size > 0) {
            debug("Notifying of %d locally inserted emails since last opened",
                  locally_inserted_ids.size);
            notify_email_locally_inserted(locally_inserted_ids);

            count_change_reason |= Folder.CountChangeReason.INSERTED;
        }

        // notify appended (new email added since the folder was last opened)
        if (appended_ids.size > 0) {
            debug("Notifying of %d appended emails since last opened",
                  appended_ids.size);
            notify_email_appended(appended_ids);

            count_change_reason |= Folder.CountChangeReason.APPENDED;
        }

        // notify locally appended (new email never seen before added
        // since the folder was last opened)
        if (locally_appended_ids.size > 0) {
            debug("Notifying of %d locally appended emails since last opened",
                  locally_appended_ids.size);
            notify_email_locally_appended(locally_appended_ids);

            count_change_reason |= Folder.CountChangeReason.APPENDED;
        }

        if (count_change_reason != Folder.CountChangeReason.NONE) {
            debug("Notifying of %Xh count change reason (%d remote messages)",
                  count_change_reason, remote_message_count);
            notify_email_count_changed(remote_message_count, count_change_reason);
        }

        debug("Completed normalize_folder");
    }

    /**
     * Closes the folder and the remote session.
     *
     * This should only be called from the replay queue.
     */
    internal async bool close_internal(Folder.CloseReason local_reason,
                                       Folder.CloseReason remote_reason,
                                       Cancellable? cancellable) {
        bool is_closing = false;
        try {
            int token = yield this.lifecycle_mutex.claim_async(cancellable);
            // Don't ever decrement to zero here,
            // close_internal_locked will do that later when it's
            // appropriate to do so, after having flushed the replay
            // queue. For the same reason, if we're actually going to
            // do the close here, we need to hold the lock until it's
            // done so that it's not possible to re-open half way
            // through.
            if (this.open_count == 1) {
                is_closing = true;
                this.close_internal_locked.begin(
                    local_reason, remote_reason, cancellable,
                    (obj, res) => {
                        this.close_internal_locked.end(res);
                        try {
                            this.lifecycle_mutex.release(ref token);
                        } catch (Error err) {
                            // oh well
                        }
                    }
                );
            } else {
                if (this.open_count > 1) {
                    this.open_count -= 1;
                } else {
                    is_closing = true;
                }
                this.lifecycle_mutex.release(ref token);
            }
        } catch (Error err) {
            // oh well
        }
        return is_closing;
    }

    /**
     * Unhooks the IMAP folder session and returns it to the account.
     */
    private async void close_remote_session(Folder.CloseReason remote_reason) {
        // Since the remote session has is/has gone away, we need to
        // let waiters know. In the case of the folder being closed,
        // notify that no more remotes will ever come back, otherwise
        // reset the semaphore to keep them waiting, in case it does.
        //
        // We use open_cancellable to determine if the folder is open
        // since that is cancelled before the replay queue is flushed,
        // and open_count is only set to zero only afterwards. This is
        // important since we need to let replay queue ops that are
        // being flushed know if the session goes away so they wake
        // up.
        if (this.open_cancellable.is_cancelled()) {
            notify_remote_waiters(false);
        } else {
            this.remote_wait_semaphore.reset();
        }

        Imap.FolderSession? session = this.remote_session;
        this.remote_session = null;
        if (session != null) {
            session.appended.disconnect(on_remote_appended);
            session.updated.disconnect(on_remote_updated);
            session.removed.disconnect(on_remote_removed);
            session.disconnected.disconnect(on_remote_disconnected);
            this._properties.remove(session.folder.properties);
            yield this._account.release_folder_session(session);

            notify_closed(remote_reason);
        }
    }

    // Must be called when lifecycle_mutex is locked, i.e. from
    // open_async().
    private async bool open_locked(Folder.OpenFlags open_flags,
                                   Cancellable cancellable)
        throws Error {
        if (this.open_count++ > 0) {
            // even if opened or opening, or if forcing a re-open,
            // respect the NO_DELAY flag
            if (open_flags.is_all_set(OpenFlags.NO_DELAY)) {
                // add NO_DELAY flag if it forces an open
                if (this.remote_session == null)
                    this.open_flags |= OpenFlags.NO_DELAY;

                this.open_remote_session.begin();
            }
            return false;
        }

        // first open gets to name the flags, but see note above
        this.open_flags = open_flags;

        // reset to force waiting in wait_for_close_async()
        this.closed_semaphore.reset();

        // reset unseen count refresh since it will be updated when
        // the remote opens
        this.refresh_unseen_timer.reset();

        // Construct objects needed when open
        this.open_cancellable = new Cancellable();
        this.replay_queue = new ReplayQueue(this);

        // Notify the email prefetcher
        this.email_prefetcher.open();

        // notify about the local open
        notify_opened(
            Geary.Folder.OpenState.LOCAL,
            this.local_folder.get_properties().email_total
        );

        // Unless NO_DELAY is set, do NOT open the remote side here;
        // wait for a folder session to be claimed ... this allows for
        // fast local-only operations to occur, local-only either
        // because (a) the folder has all the information required
        // (for a list or fetch operation), or (b) the operation was
        // de facto local-only.  In particular, EmailStore will open
        // and close lots of folders, causing a lot of connection
        // setup and teardown
        //
        // However, we want to eventually open, otherwise if there's
        // no user interaction (i.e. a second account Inbox they don't
        // manipulate), no remote connection will ever be made,
        // meaning that folder normalization never happens and
        // unsolicited notifications never arrive
        this._account.imap.notify["current-status"].connect(
            on_remote_status_notify
        );
        if (open_flags.is_all_set(OpenFlags.NO_DELAY)) {
            this.open_remote_session.begin();
        } else {
            this.remote_open_timer.start();
        }

        debug("Folder opened");
        return true;
    }

    /**
     * Closes the folder regardless of the open count.
     *
     * This only useful when an unrecoverable error has occurred. No
     * cancellable argument is provided since the close must complete.
     */
    private async void force_close(Folder.CloseReason local_reason,
                                   Folder.CloseReason remote_reason) {
        try {
            int token = yield this.lifecycle_mutex.claim_async(null);
            // Check we actually need to do the close in case the
            // folder was in the process of closing anyway
            if (this.open_count > 0) {
                yield close_internal_locked(local_reason, remote_reason, null);
            }
            this.lifecycle_mutex.release(ref token);
        } catch (Error err) {
            // oh well
        }
    }

    // Must be called when lifecycle_mutex is locked, i.e. from
    // close_internal() or force_close().
    private async void close_internal_locked(Folder.CloseReason local_reason,
                                             Folder.CloseReason remote_reason,
                                             Cancellable? cancellable) {
        debug("Folder closing");

        // Ensure we don't attempt to start opening a remote while
        // closing
        this._account.imap.notify["current-status"].disconnect(
            on_remote_status_notify
        );
        this.remote_open_timer.reset();

        // Stop any internal tasks from running
        this.open_cancellable.cancel();
        this.email_prefetcher.close();
        this.update_flags_timer.reset();

        // Once we get to this point, either there will be a remote
        // session open already, or none will ever get opened - no
        // more attempts to open a session will be made. We can't
        // block access to any remote session here however since
        // pending replay operations may need it still. Instead, rely
        // on the replay queue itself to reject any new operations
        // being queued once we close it.

        // Only flush pending operations if the remote is open (if
        // closed they will deadlock waiting for one to open), and if
        // this is a "clean" close, that is not forced due to error.
        bool flush_pending = (
            this.remote_session != null &&
            !local_reason.is_error() &&
            !remote_reason.is_error()
        );

        if (flush_pending) {
            // Since we are flushing the queue, gather operations
            // from Revokables to give them a chance to schedule their
            // commit operations before going down
            Gee.List<ReplayOperation> final_ops = new Gee.ArrayList<ReplayOperation>();
            notify_closing(final_ops);
            foreach (ReplayOperation op in final_ops)
                replay_queue.schedule(op);
        }

        // Close the replay queues; if a "clean" close, flush pending
        // operations so everything gets a chance to run; if forced
        // close, drop everything outstanding
        debug("Closing replay queue for (flush_pending=%s): %s",
              flush_pending.to_string(), this.replay_queue.to_string());
        try {
            yield this.replay_queue.close_async(flush_pending);
            debug("Closed replay queue: %s", this.replay_queue.to_string());
        } catch (Error err) {
            warning("Error closing replay queue: %s", err.message);
        }

        // Actually close the remote folder
        yield close_remote_session(remote_reason);

        // Since both the remote session and replay queue have shut
        // down, we can reset the folder's internal state.
        this.remote_wait_semaphore.reset();
        this.replay_queue = null;
        this.open_cancellable = null;
        this.open_flags = OpenFlags.NONE;

        // Officially marks the folder as closed. Beyond this point it
        // may start to re-open again if open_async is called.
        this.open_count = 0;

        // need to call these every time, even if remote was not fully
        // opened, as some callers rely on order of signals
        notify_closed(local_reason);
        notify_closed(CloseReason.FOLDER_CLOSED);

        // Notify waiting tasks
        this.closed_semaphore.blind_notify();

        debug("Folder closed");
    }

    /**
     * Establishes a new IMAP session, normalising local and remote folders.
     */
    private async void open_remote_session() {
        try {
            int token = yield this.remote_mutex.claim_async(this.open_cancellable);

            // Ensure we are open already and guard against someone
            // else having called this just before we did.
            if (this.open_count > 0 &&
                this._account.imap.current_status == CONNECTED &&
                this.remote_session == null) {

                this.opening_monitor.notify_start();
                yield open_remote_session_locked(this.open_cancellable);
                this.opening_monitor.notify_finish();
            }

            this.remote_mutex.release(ref token);
        } catch (Error err) {
            // Lock error
        }
    }

    // Should only be called when remote_mutex is locked, i.e. use open_remote_session()
    private async void open_remote_session_locked(Cancellable? cancellable) {
        debug("Opening remote session");

        // Note that any IOError.CANCELLED errors caught below do not
        // cause any error signals to be fired and do not force
        // closing the folder, because the only time opening the
        // session is cancelled is when the folder is already being
        // closed, which is the desired result.

        // Don't try to re-open again
        this.remote_open_timer.reset();

        // Phase 1: Acquire a new session

        Imap.FolderSession? session = null;
        try {
#if WITH_DELAYED_REPLAY_QUEUE
            // When folder session is claimed, that can lock for some ms.
            // It can be tricky to debug issues happening during this small
            // random delay. Use this build option to force the delay.
            yield Geary.Scheduler.sleep_async(1);
#endif
            session = yield this._account.claim_folder_session(
                this.path, cancellable
            );
        } catch (IOError.CANCELLED err) {
            // Fine, just bail out
            return;
        } catch (EngineError.NOT_FOUND err) {
            debug("Remote folder not found, forcing closed");
            yield force_close(
                CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR
            );
            return;
        } catch (ImapError.NOT_SUPPORTED err) {
            debug("Remote folder not selectable, forcing closed");
            yield force_close(
                CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR
            );
            return;
        } catch (Error err) {
            ErrorContext context = new ErrorContext(err);
            if (!is_recoverable_failure(err)) {
                debug("Unrecoverable failure opening remote, forcing closed: %s",
                      context.format_full_error());
                yield force_close(
                    CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR
                );
            } else {
                debug("Recoverable error opening remote: %s",
                      context.format_full_error());
                notify_open_failed(Folder.OpenFailed.REMOTE_ERROR, err);
            }
            return;
        }

        // Phase 2: Update local state based on the remote session

        // Replay signals need to be hooked up before normalisation to
        // avoid there being a race between that and new messages
        // arriving, being removed, etc. This is safe since
        // normalisation only issues FETCH commands for messages based
        // on the state of the remote right after being selected, so
        // any untagged EXIST and FETCH responses will be handled
        // later by their replay ops, and no untagged EXPUNGE
        // responses will be received since they are forbidden to be
        // issued for FETCH commands.
        //
        // Note we don't need to unhook from these signals if an error
        // occurs below since they won't be called once the session
        // has been released.
        session.appended.connect(on_remote_appended);
        session.updated.connect(on_remote_updated);
        session.removed.connect(on_remote_removed);

        try {
            yield normalize_folders(session, cancellable);
        } catch (Error err) {
            // Normalisation failed, so we have a pretty serious
            // problem and should not try to use the folder further,
            // unless the open was simply cancelled. So clean up, and
            // force the folder closed.
            yield this._account.release_folder_session(session);
            if (!(err is IOError.CANCELLED)) {
                Folder.CloseReason local_reason = CloseReason.LOCAL_ERROR;
                Folder.CloseReason remote_reason = CloseReason.REMOTE_CLOSE;
                if (!is_remote_error(err)) {
                    notify_open_failed(OpenFailed.LOCAL_ERROR, err);
                } else {
                    notify_open_failed(OpenFailed.REMOTE_ERROR, err);
                    local_reason =  CloseReason.LOCAL_CLOSE;
                    remote_reason = CloseReason.REMOTE_ERROR;
                }
                yield force_close(local_reason, remote_reason);
            }
            return;
        }

        // Some emails may have been marked as read locally while
        // claiming folder session, handle the diff here.
        session.folder.properties.set_status_unseen(
            session.folder.properties.unseen +
            this.replay_queue.pending_unread_change()
        );

        // Update the local folder's totals and UID values after
        // normalisation, so it does not mistake the remote's current
        // state with our previous state
        try {
            yield local_folder.update_folder_select_examine(
                session.folder.properties, cancellable
            );
        } catch (Error err) {
            // Database failed, which is also a pretty serious
            // problem, so handle as per above.
            yield this._account.release_folder_session(session);
            if (!(err is IOError.CANCELLED)) {
                notify_open_failed(Folder.OpenFailed.LOCAL_ERROR, err);
                yield force_close(CloseReason.LOCAL_ERROR, CloseReason.REMOTE_CLOSE);
            }
            return;
        }

        // All done, can now hook up the session to the folder
        this.remote_session = session;
        this._properties.add(session.folder.properties);
        session.disconnected.connect(on_remote_disconnected);

        // Enable IDLE now that the local and remote folders are in
        // sync. Can't do this earlier since we might get untagged
        // EXPUNGE responses during normalisation, which would be
        // Bad™. Do it in the background to avoid delay notifying
        session.enable_idle.begin(cancellable);

        // Phase 3: Notify tasks waiting for the connection

        // notify any subscribers with similar information
        notify_opened(
            Geary.Folder.OpenState.REMOTE,
            session.folder.properties.email_total
        );

        // notify any threads of execution waiting for the remote
        // folder to open that the result of that operation is ready
        notify_remote_waiters(true);

        // Update flags once the remote has opened. We will receive
        // notifications of changes as long as the session remains
        // open, so only need to do this once
        this.update_flags_timer.start();
    }

    private void on_email_complete(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        notify_email_locally_complete(email_ids);
    }

    private void on_remote_appended(Imap.FolderSession session, int appended) {
        // Use the session param rather than remote_session attr since
        // it may not be available yet
        int remote_count = session.folder.properties.email_total;
        debug("on_remote_appended: remote_count=%d appended=%d",
              remote_count, appended);

        // from the new remote total and the old remote total, glean the SequenceNumbers of the
        // new email(s)
        Gee.List<Imap.SequenceNumber> positions = new Gee.ArrayList<Imap.SequenceNumber>();
        for (int pos = remote_count - appended + 1; pos <= remote_count; pos++)
            positions.add(new Imap.SequenceNumber(pos));

        if (positions.size > 0) {
            // We don't pass in open_cancellable here since we want
            // the op to still run when closing and flushing the queue
            ReplayAppend op = new ReplayAppend(this, remote_count, positions, null);
            op.email_appended.connect(notify_email_appended);
            op.email_locally_appended.connect(notify_email_locally_appended);
            op.email_count_changed.connect(notify_email_count_changed);
            this.replay_queue.schedule_server_notification(op);
        }
    }

    private void on_remote_updated(Imap.FolderSession session,
                                   Imap.SequenceNumber position,
                                   Imap.FetchedData data) {
        // Use the session param rather than remote_session attr since
        // it may not be available yet
        int remote_count = session.folder.properties.email_total;
        debug("on_remote_updated: remote_count=%d position=%s",
              remote_count, position.to_string());

        this.replay_queue.schedule_server_notification(
            new ReplayUpdate(this, remote_count, position, data)
        );
    }

    private void on_remote_removed(Imap.FolderSession session,
                                   Imap.SequenceNumber position) {
        // Use the session param rather than remote_session attr since
        // it may not be available yet
        int remote_count = session.folder.properties.email_total;
        debug("on_remote_removed: remote_count=%d position=%s",
              remote_count, position.to_string());

        // notify of removal to all pending replay operations
        replay_queue.notify_remote_removed_position(position);

        ReplayRemoval op = new ReplayRemoval(this, remote_count, position);
        op.email_removed.connect(notify_email_removed);
        op.marked_email_removed.connect(notify_marked_email_removed);
        op.email_count_changed.connect(notify_email_count_changed);
        this.replay_queue.schedule_server_notification(op);
    }

    /** {@inheritDoc} */
    public override async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        check_open("contains_identifiers");
        return yield this.local_folder.contains_identifiers(ids, cancellable);
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

    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open("fetch_email_async");
        check_flags("fetch_email_async", flags);
        check_id("fetch_email_async", id);

        FetchEmail op = new FetchEmail(
            this,
            (ImapDB.EmailIdentifier) id,
            required_fields,
            flags,
            cancellable
        );
        replay_queue.schedule(op);

        yield op.wait_for_ready_async(cancellable);
        return op.email;
    }

    // Helper function for child classes dealing with the
    // delete/archive question.  This method will mark the message as
    // deleted and expunge it.
    protected async void
        expunge_email_async(Gee.Collection<Geary.EmailIdentifier> to_expunge,
                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        check_open("expunge_email_async");
        check_ids("expunge_email_async", to_expunge);

        RemoveEmail remove = new RemoveEmail(
            this,
            (Gee.Collection<ImapDB.EmailIdentifier>) to_expunge,
            cancellable
        );
        replay_queue.schedule(remove);

        yield remove.wait_for_ready_async(cancellable);
    }

    protected async void expunge_all_async(Cancellable? cancellable = null) throws Error {
        check_open("expunge_all_async");

        EmptyFolder op = new EmptyFolder(this, cancellable);
        this.replay_queue.schedule(op);
        yield op.wait_for_ready_async(cancellable);

        // Checkpoint the replay queue, so it and the folder remains
        // open while processing first the flag updates then the
        // expunge from the remote
        yield this.replay_queue.checkpoint(cancellable);

        yield this._account.local.db.run_gc(NONE, null, cancellable);
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

    public virtual async void
        mark_email_async(Gee.Collection<Geary.EmailIdentifier> to_mark,
                         Geary.EmailFlags? flags_to_add,
                         Geary.EmailFlags? flags_to_remove,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open("mark_email_async");
        check_ids("mark_email_async", to_mark);

        MarkEmail mark = new MarkEmail(
            this,
            (Gee.Collection<ImapDB.EmailIdentifier>)
            to_mark,
            flags_to_add,
            flags_to_remove,
            cancellable
        );
        replay_queue.schedule(mark);

        yield mark.wait_for_ready_async(cancellable);

        // Cancel any remote update, we just updated locally unread_count,
        // incoming data will have an invalid unseen value
        this.account.cancel_remote_update();
    }

    public virtual async void
        copy_email_async(Gee.Collection<Geary.EmailIdentifier> to_copy,
                         Geary.FolderPath destination,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Geary.Folder target = this._account.get_folder(destination);
        yield copy_email_uids_async(to_copy, destination, cancellable);
        this._account.update_folder(target);
    }

    /**
     * Returns the destination folder's UIDs for the copied messages.
     */
    protected async Gee.Set<Imap.UID>?
        copy_email_uids_async(Gee.Collection<Geary.EmailIdentifier> to_copy,
                              Geary.FolderPath destination,
                              GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open("copy_email_uids_async");
        check_ids("copy_email_uids_async", to_copy);

        // watch for copying to this folder, which is treated as a no-op
        if (destination.equal_to(path))
            return null;

        CopyEmail copy = new CopyEmail(
            this,
            (Gee.List<ImapDB.EmailIdentifier>)
            traverse(to_copy).to_array_list(),
            destination
        );
        replay_queue.schedule(copy);

        yield copy.wait_for_ready_async(cancellable);

        return copy.destination_uids.size > 0 ? copy.destination_uids : null;
    }

    public virtual async Geary.Revokable? move_email_async(
        Gee.Collection<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination,
        Cancellable? cancellable = null)
    throws Error {
        check_open("move_email_async");
        check_ids("move_email_async", to_move);

        // watch for moving to this folder, which is treated as a no-op
        if (destination.equal_to(path))
            return null;

        MoveEmailPrepare prepare = new MoveEmailPrepare(
            this, (Gee.Collection<ImapDB.EmailIdentifier>) to_move, cancellable
        );
        replay_queue.schedule(prepare);

        yield prepare.wait_for_ready_async(cancellable);

        if (prepare.prepared_for_move == null || prepare.prepared_for_move.size == 0)
            return null;

        Geary.Folder target = this._account.get_folder(destination);
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

    /** {@inheritDoc} */
    public override Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%s, open_count=%d, remote_opened=%s",
            this.path.to_string(),
            this.open_count,
            (this.remote_session != null).to_string()
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

    protected async EmailIdentifier?
        create_email_async(RFC822.Message rfc822,
                           EmailFlags? flags,
                           DateTime? date_received,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open("create_email_async");
        CreateEmail op = new CreateEmail(
            this, rfc822, flags, date_received, cancellable
        );
        replay_queue.schedule(op);
        yield op.wait_for_ready_async(cancellable);
        this._account.update_folder(this);

        if (op.created_id != null) {
            // Server returned a UID for the new message. It was saved
            // locally possibly before the server notified that the
            // message exists. As such, fetch any missing parts from
            // the remote to ensure it is properly filled in.
            yield list_email_by_id_async(
                op.created_id, 1, ALL, INCLUDING_ID, cancellable
            );
        } else {
            // The server didn't return a UID for the new email, so do
            // a sync now to ensure it shows up immediately.
            yield synchronise_remote(cancellable);
        }
        return op.created_id;
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
    private async void update_flags(Cancellable cancellable) throws Error {
        // Update this to use CHANGEDSINCE FETCH when available, when
        // we support IMAP CONDSTORE (Bug 713117).
        int chunk_size = FLAG_UPDATE_START_CHUNK;
        Geary.EmailIdentifier? lowest = null;
        while (get_open_state() != Geary.Folder.OpenState.CLOSED) {
            Gee.List<Geary.Email>? list_local = yield list_email_by_id_async(
                lowest, chunk_size,
                Geary.Email.Field.FLAGS,
                Geary.Folder.ListFlags.LOCAL_ONLY,
                cancellable
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
            debug("Fetching %d flags", local_map.keys.size);
            Gee.List<Geary.Email>? list_remote = yield list_email_by_sparse_id_async(
                local_map.keys,
                Email.Field.FLAGS,
                Folder.ListFlags.FORCE_UPDATE |
                // Updating read/unread count here breaks the unread
                // count, so don't do it. See issue #213.
                Folder.ListFlags.NO_UNREAD_UPDATE,
                cancellable
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

            if (!cancellable.is_cancelled() && changed_map.size > 0)
                notify_email_flags_changed(changed_map);

            chunk_size *= 2;
            if (chunk_size > FLAG_UPDATE_MAX_CHUNK) {
                chunk_size = FLAG_UPDATE_MAX_CHUNK;
            }
        }
    }

    private void update_harvester() {
        this.harvester = new ContactHarvesterImpl(
            this.account.contact_store,
            this._used_as,
            this.account.information.sender_mailboxes
        );
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

    private void on_update_flags() {
        this.update_flags.begin(
            this.open_cancellable,
            (obj, res) => {
                try {
                    this.update_flags.end(res);
                } catch (IOError.CANCELLED err) {
                    // all good
                } catch (Error err) {
                    debug("Error updating flags: %s", err.message);
                }
            }
        );
    }

    private void on_remote_status_notify() {
        if (this._account.imap.current_status == CONNECTED) {
            this.open_remote_session.begin();
        }
    }

    private void on_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        bool is_error = reason.is_error();

        // Need to close the remote session immediately to avoid a
        // race with it opening again
        Geary.Folder.CloseReason remote_reason = is_error
            ? Geary.Folder.CloseReason.REMOTE_ERROR
            : Geary.Folder.CloseReason.REMOTE_CLOSE;
        this.close_remote_session.begin(
            remote_reason,
            (obj, res) => {
                this.close_remote_session.end(res);
                // Once closed, if we are closing because an error
                // occurred, but the folder is still open and so is
                // the pool, try re-establishing the connection.
                if (is_error &&
                    this._account.imap.current_status == CONNECTED &&
                    !this.open_cancellable.is_cancelled()) {
                    this.open_remote_session.begin();
                }
            });
    }

}
