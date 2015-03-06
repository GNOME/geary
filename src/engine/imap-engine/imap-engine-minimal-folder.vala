/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MinimalFolder : Geary.Folder, Geary.FolderSupport.Copy,
    Geary.FolderSupport.Mark, Geary.FolderSupport.Move {
    private const int FORCE_OPEN_REMOTE_TIMEOUT_SEC = 10;
    private const int DEFAULT_REESTABLISH_DELAY_MSEC = 500;
    private const int MAX_REESTABLISH_DELAY_MSEC = 60 * 1000;
    
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
    internal Imap.Folder? remote_folder { get; protected set; default = null; }
    internal EmailPrefetcher email_prefetcher { get; private set; }
    internal EmailFlagWatcher email_flag_watcher;
    
    private weak GenericAccount _account;
    private Geary.AggregatedFolderProperties _properties = new Geary.AggregatedFolderProperties(
        false, false);
    private Imap.Account remote;
    private ImapDB.Account local;
    private Folder.OpenFlags open_flags = OpenFlags.NONE;
    private int open_count = 0;
    private bool remote_opened = false;
    private Nonblocking.ReportingSemaphore<bool> remote_semaphore =
        new Nonblocking.ReportingSemaphore<bool>(false);
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();
    private ReplayQueue replay_queue;
    private int remote_count = -1;
    private uint open_remote_timer_id = 0;
    private int reestablish_delay_msec = DEFAULT_REESTABLISH_DELAY_MSEC;
    private Nonblocking.Mutex open_mutex = new Nonblocking.Mutex();
    private Nonblocking.Mutex close_mutex = new Nonblocking.Mutex();
    
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
    
    public MinimalFolder(GenericAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        _account = account;
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        _special_folder_type = special_folder_type;
        _properties.add(local_folder.get_properties());
        replay_queue = new ReplayQueue(this);
        
        email_flag_watcher = new EmailFlagWatcher(this);
        email_flag_watcher.email_flags_changed.connect(on_email_flags_changed);
        
        email_prefetcher = new EmailPrefetcher(this);
        
        local_folder.email_complete.connect(on_email_complete);
    }
    
    ~MinimalFolder() {
        if (open_count > 0)
            warning("Folder %s destroyed without closing", to_string());
        
        cancel_remote_open_timer();
        
        local_folder.email_complete.disconnect(on_email_complete);
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
        if (open_count == 0)
            return Geary.Folder.OpenState.CLOSED;
        
        return (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL;
    }
    
    // Returns the synchronized remote count (-1 if not opened) and the last seen remote count (stored
    // locally, -1 if not available)
    //
    // Return value is the remote_count, unless the remote is unopened, in which case it's the
    // last_seen_remote_count (which may be -1).
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
    
    private async bool normalize_folders(Geary.Imap.Folder remote_folder, Cancellable? cancellable)
        throws Error {
        debug("%s: Begin normalizing remote and local folders", to_string());
        
        Geary.Imap.FolderProperties local_properties = local_folder.get_properties();
        Geary.Imap.FolderProperties remote_properties = remote_folder.properties;
        
        // and both must have their next UID's (it's possible they don't if it's a non-selectable
        // folder)
        if (local_properties.uid_next == null || local_properties.uid_validity == null) {
            debug("%s: Unable to verify UIDs: missing local UIDNEXT (%s) and/or UIDVALIDITY (%s)",
                to_string(), (local_properties.uid_next == null).to_string(),
                (local_properties.uid_validity == null).to_string());
            
            return false;
        }
        
        if (remote_properties.uid_next == null || remote_properties.uid_validity == null) {
            debug("%s: Unable to verify UIDs: missing remote UIDNEXT (%s) and/or UIDVALIDITY (%s)",
                to_string(), (remote_properties.uid_next == null).to_string(),
                (remote_properties.uid_validity == null).to_string());
            
            return false;
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
            
            return true;
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
            
            return true;
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
            
            return true;
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
            
            return true;
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
        
        return true;
    }
    
    public override async void wait_for_open_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("wait_for_open_async() can only be called after open_async()");
        
        // if remote has not yet been opened, do it now ... this bool can go true only once after
        // an open_async, it's reset at close time
        if (!remote_opened) {
            debug("wait_for_open_async %s: opening remote on demand...", to_string());
            
            start_remote_open_now();
        }
        
        if (!yield remote_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.ALREADY_CLOSED("%s failed to open", to_string());
    }
    
    public override async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0) {
            // even if opened or opening, or if forcing a re-open, respect the NO_DELAY flag
            if (open_flags.is_all_set(OpenFlags.NO_DELAY)) {
                // add NO_DELAY flag if it forces an open
                if (!remote_opened)
                    this.open_flags |= OpenFlags.NO_DELAY;
                
                start_remote_open_now();
            }
            
            debug("Not opening %s: already open", to_string());
            
            return false;
        }
        
        // first open gets to name the flags, but see note above
        this.open_flags = open_flags;
        
        // reset to force waiting in wait_for_open_async()
        remote_semaphore.reset();
        
        // reset to force waiting in wait_for_close_async()
        closed_semaphore.reset();
        
        // Unless NO_DELAY is set, do NOT open the remote side here; wait for the ReplayQueue to
        // require a remote connection or wait_for_open_async() to be called ... this allows for
        // fast local-only operations to occur, local-only either because (a) the folder has all
        // the information required (for a list or fetch operation), or (b) the operation was de
        // facto local-only.  In particular, EmailStore will open and close lots of folders,
        // causing a lot of connection setup and teardown
        //
        // However, want to eventually open, otherwise if there's no user interaction (i.e. a
        // second account Inbox they don't manipulate), no remote connection will ever be made,
        // meaning that folder normalization never happens and unsolicited notifications never
        // arrive
        if (open_flags.is_all_set(OpenFlags.NO_DELAY))
            start_remote_open_now();
        else
            start_remote_open_timer();
        
        return true;
    }
    
    private void start_remote_open_timer() {
        if (open_remote_timer_id != 0)
            Source.remove(open_remote_timer_id);
        
        open_remote_timer_id = Timeout.add_seconds(FORCE_OPEN_REMOTE_TIMEOUT_SEC, () => {
            start_remote_open_now();
            
            return false;
        });
    }
    
    private void start_remote_open_now() {
        if (remote_opened)
            return;
        
        cancel_remote_open_timer();
        remote_opened = true;
        
        open_remote_async.begin(null);
    }
    
    private void cancel_remote_open_timer() {
        if (open_remote_timer_id == 0)
            return;
        
        Source.remove(open_remote_timer_id);
        open_remote_timer_id = 0;
    }
    
    // Open the remote connection using a Mutex to prevent concurrency.
    //
    // start_remote_open_now() *should* prevent more than one open from occurring at the same time,
    // but it's still wise to use a nonblocking primitive to prevent it if that does occur to at
    // least keep Folder state cogent.
    private async void open_remote_async(Cancellable? cancellable) {
        int token;
        try {
            token = yield open_mutex.claim_async(cancellable);
        } catch (Error err) {
            return;
        }
        
        yield open_remote_locked_async(cancellable);
        
        try {
            open_mutex.release(ref token);
        } catch (Error err) {
        }
    }
    
    // Should only be called when open_mutex is locked, i.e. use open_remote_async()
    private async void open_remote_locked_async(Cancellable? cancellable) {
        // watch for folder closing before this call got a chance to execute
        if (open_count == 0)
            return;
        
        // to ensure this isn't running when open_remote_async() is called again (due to a connection
        // reestablishment), stop this monitoring from running *before* launching close_internal_async
        // ... in essence, guard against reentrancy, which is possible
        opening_monitor.notify_start();
        
        // following blocks of code are fairly tricky because if the remote open fails need to
        // carefully back out and possibly retry
        Imap.Folder? opening_folder = null;
        try {
            debug("Fetching STATUS for remote %s from local", to_string());
            Imap.StatusData local_status = yield local_folder.fetch_status_data(
                ImapDB.Folder.ListFlags.NONE, cancellable);
            
            debug("Fetching information for remote folder %s", to_string());
            opening_folder = yield remote.fetch_folder_async(local_folder.get_path(), null, local_status,
                cancellable);
            
            debug("Opening remote folder %s", opening_folder.to_string());
            yield opening_folder.open_async(cancellable);
            
            // allow subclasses to examine the opened folder and resolve any vital
            // inconsistencies
            if (yield normalize_folders(opening_folder, cancellable)) {
                // update flags, properties, etc.
                yield local.update_folder_select_examine_async(opening_folder, cancellable);
                
                // signals
                opening_folder.appended.connect(on_remote_appended);
                opening_folder.removed.connect(on_remote_removed);
                opening_folder.disconnected.connect(on_remote_disconnected);
                
                // state
                remote_count = opening_folder.properties.email_total;
                
                // all set; bless the remote folder as opened (don't do this until completely
                // open, as other functions rely on this to determine folder-open state)
                remote_folder = opening_folder;
            } else {
                debug("Unable to prepare remote folder %s: normalize_folders() failed", to_string());
                notify_open_failed(Geary.Folder.OpenFailed.REMOTE_FAILED, null);
                
                // be sure to close opening_folder, close_internal_async won't do it
                try {
                    yield opening_folder.close_async(null);
                } catch (Error err) {
                    debug("%s: Error closing remote folder %s: %s", to_string(), opening_folder.to_string(),
                        err.message);
                    
                    // fall through
                }
                
                // stop before starting the close
                opening_monitor.notify_finish();
                
                // normalize_folders() returning false indicates a soft error, but hard in the sense
                // that opening cannot proceed, even with a connection retry
                open_count = 0;
                
                // schedule immediate close
                close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_CLOSE, false,
                    cancellable);
                
                return;
            }
        } catch (Error open_err) {
            bool hard_failure;
            bool is_cancellation = false;
            if (open_err is ImapError || open_err is EngineError) {
                // "hard" error in the sense of network conditions make connection impossible
                // at the moment, "soft" error in the sense that some logical error prevented
                // connect (like bad credentials)
                hard_failure = is_hard_failure(open_err);
            } else if (open_err is IOError.CANCELLED) {
                // user cancelled open, treat like soft error
                hard_failure = false;
                is_cancellation = true;
            } else {
                // a different IOError, a hard failure
                hard_failure = true;
            }
            
            Folder.CloseReason remote_reason;
            if (hard_failure) {
                // hard failure, retry
                debug("Hard failure opening or preparing remote folder %s, retrying: %s", to_string(),
                    open_err.message);
                
                remote_reason = CloseReason.REMOTE_ERROR;
            } else {
                // soft failure, treat as failure to open
                debug("Soft failure opening or preparing remote folder %s, closing: %s", to_string(),
                    open_err.message);
                notify_open_failed(
                    is_cancellation ? Folder.OpenFailed.CANCELLED : Folder.OpenFailed.REMOTE_FAILED,
                    open_err);
                
                remote_reason = CloseReason.REMOTE_CLOSE;
                
                // clear open_count to ensure that close_internal_async() doesn't attempt to
                // reestablish the connection
                open_count = 0;
            }
            
            // be sure to close opening_folder if it was fetched or opened
            try {
                if (opening_folder != null)
                    yield opening_folder.close_async(null);
            } catch (Error err) {
                debug("%s: Error closing remote folder %s: %s", to_string(), opening_folder.to_string(),
                    err.message);
            }
            
            // stop before starting the close
            opening_monitor.notify_finish();
            
            // schedule immediate close (and possible connection reestablishment)
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, remote_reason, false, null);
            
            return;
        }
        
        opening_monitor.notify_finish();
        
        // open success, reset reestablishment delay
        reestablish_delay_msec = DEFAULT_REESTABLISH_DELAY_MSEC;
        
        // at this point, remote_folder should be set; there's no notion of a local-only open (yet)
        assert(remote_folder != null);
        
        // notify any threads of execution waiting for the remote folder to open that the result
        // of that operation is ready
        try {
            remote_semaphore.notify_result(true, null);
        } catch (Error notify_err) {
            // This should only happen if cancelled, which can't happen without a Cancellable
            warning("%s: Unable to fire semaphore notifying remote folder ready/not ready: %s",
                to_string(), notify_err.message);
        }
        
        _properties.add(remote_folder.properties);
        
        // notify any subscribers with similar information
        notify_opened(Geary.Folder.OpenState.BOTH, remote_count);
    }
    
    public override async bool close_async(Cancellable? cancellable = null) throws Error {
        // Check open_count but only decrement inside of replay queue
        if (open_count <= 0)
            return false;
        
        UserClose user_close = new UserClose(this, cancellable);
        replay_queue.schedule(user_close);
        
        yield user_close.wait_for_ready_async(cancellable);
        
        return user_close.closing;
    }
    
    public override async void wait_for_close_async(Cancellable? cancellable = null) throws Error {
        yield closed_semaphore.wait_async(cancellable);
    }
    
    internal async bool user_close_async(Cancellable? cancellable) {
        // decrement open_count and, if zero, continue closing Folder
        if (open_count == 0 || --open_count > 0)
            return false;
        
        if (remote_folder != null)
            _properties.remove(remote_folder.properties);
        
        // block anyone from wait_until_open_async(), as this is no longer open
        remote_semaphore.reset();
        
        // don't yield here, close_internal_async() needs to be called outside of the replay queue
        // the open_count protects against this path scheduling it more than once
        close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_CLOSE, true, cancellable);
        
        return true;
    }
    
    // Close the remote connection and, if open_count is zero, the Folder itself.  A Mutex is used
    // to prevent concurrency.
    //
    // This is best called using a ReplayDisconnect operation, which ensures an orderly disconnect
    // by going through the ReplayQueue.  There are certain situations in open_remote_async() where
    // this is not possible (because the queue hasn't been started).
    //
    // NOTE: This bypasses open_count and forces the Folder closed, reestablishing a connection if
    // open_count is greater than zero
    internal async void close_internal_async(Folder.CloseReason local_reason, Folder.CloseReason remote_reason,
        bool flush_pending, Cancellable? cancellable) {
        // make sure no open is waiting in the wings to start; close_internal_locked_async() will
        // reestablish a connection if necessary
        cancel_remote_open_timer();
        
        int token;
        try {
            token = yield close_mutex.claim_async(cancellable);
        } catch (Error err) {
            return;
        }
        
        yield close_internal_locked_async(local_reason, remote_reason, flush_pending, cancellable);
        
        try {
            close_mutex.release(ref token);
        } catch (Error err) {
        }
    }
    
    // Should only be called when close_mutex is locked, i.e. use close_internal_async()
    private async void close_internal_locked_async(Folder.CloseReason local_reason,
        Folder.CloseReason remote_reason, bool flush_pending, Cancellable? cancellable) {
        // only flushing pending ReplayOperations if this is a "clean" close, not forced due to
        // error and if specified by caller (could be a non-error close on the server, i.e. "BYE",
        // but the connection is dropping, so don't flush pending)
        flush_pending = flush_pending && !remote_reason.is_error();
        
        // If closing due to error, notify all operations waiting for the remote that it's not
        // coming available ... this wakes up any ReplayOperation blocking on wait_for_open_async(),
        // necessary in order to finish ReplayQueue.close_async (i.e. to prevent deadlock); this
        // is necessary because it's possible for this method to be called before the remote_folder
        // has even had a chance to open.
        //
        // Note that we don't want to do this for a clean close, because we want to flush out
        // pending operations first
        Imap.Folder? closing_remote_folder = null;
        if (!flush_pending)
            closing_remote_folder = clear_remote_folder();
        
        // That said, only flush, close, and destroy the ReplayQueue if fully closing and not
        // preparing for a connection reestablishment
        if (open_count <= 0) {
            // if closing and flushing the queue, give Revokables a chance to schedule their
            // commit operations before going down
            if (flush_pending) {
                Gee.List<ReplayOperation> final_ops = new Gee.ArrayList<ReplayOperation>();
                notify_closing(final_ops);
                
                foreach (ReplayOperation op in final_ops)
                    replay_queue.schedule(op);
            }
            
            // Close the replay queues; if a "clean" close, flush pending operations so everything
            // gets a chance to run; if forced close, drop everything outstanding
            try {
                // swap out the ReplayQueue while closing so, if re-opened, future commands can
                // be queued on the new queue
                ReplayQueue closing_replay_queue = replay_queue;
                replay_queue = new ReplayQueue(this);
                
                debug("Closing replay queue for %s (flush_pending=%s): %s", to_string(),
                    flush_pending.to_string(), closing_replay_queue.to_string());
                yield closing_replay_queue.close_async(flush_pending);
                debug("Closed replay queue for %s: %s", to_string(), closing_replay_queue.to_string());
            } catch (Error replay_queue_err) {
                debug("Error closing %s replay queue: %s", to_string(), replay_queue_err.message);
            }
        }
        
        // if a "clean" close, now go ahead and close the folder
        if (flush_pending)
            closing_remote_folder = clear_remote_folder();
        
        // now treat remote as closed, i.e. a call to open_async() will reinitiate opening and not fall
        // through (unless open_count is > 0) ... do this before close_remote_folder_async() since
        // it's *possible* for it to loop back to open_async() before returning
        remote_opened = false;
        
        // use background call to (a) close remote if necessary and/or (b) reestablish connection if
        // necessary ... store reestablish condition now, before scheduling close_remote_folder_async(),
        // as it touches open_count
        bool reestablish = open_count > 0;
        if (closing_remote_folder != null || reestablish) {
            // to avoid keeping the caller waiting while the remote end closes (i.e. drops the
            // connection or performs an IMAP CLOSE operation), close it in the background and
            // reestablish connection there, if necessary
            //
            // TODO: Problem with this is that we cannot effectively signal or report a close error,
            // because by the time this operation completes the folder is considered closed.  That
            // may not be important to most callers, however.
            //
            // It also means the reference to the Folder must be maintained until completely
            // closed.  Also not a problem, as GenericAccount does that internally.  However, this
            // might be an issue if GenericAccount removes this folder due to a user command or
            // detection on the server, so this background op keeps a reference to the Folder
            close_remote_folder_async.begin(this, closing_remote_folder);
        }
        
        // if reestablishing in close_remote_folder_async(), go no further
        if (reestablish)
            return;
        
        // forced closed one way or another, so reset state
        open_flags = OpenFlags.NONE;
        reestablish_delay_msec = DEFAULT_REESTABLISH_DELAY_MSEC;
        
        // use remote_reason even if remote_folder was null; it could be that the error occurred
        // while opening and remote_folder was yet unassigned ... also, need to call this every
        // time, even if remote was not fully opened, as some callers rely on order of signals
        notify_closed(remote_reason);
        
        // see above note for why this must be called every time
        notify_closed(local_reason);
        
        notify_closed(CloseReason.FOLDER_CLOSED);
        
        // If not closing in the background, do it here
        if (closing_remote_folder == null)
            closed_semaphore.blind_notify();
        
        debug("Folder %s closed", to_string());
    }
    
    // Returns the remote_folder, if it was set
    private Imap.Folder? clear_remote_folder() {
        if (remote_folder != null) {
            // disconnect signals before ripping out reference
            remote_folder.appended.disconnect(on_remote_appended);
            remote_folder.removed.disconnect(on_remote_removed);
            remote_folder.disconnected.disconnect(on_remote_disconnected);
        }
        
        Imap.Folder? old_remote_folder = remote_folder;
        remote_folder = null;
        remote_count = -1;
        
        // only signal waiters in wait_for_open_async() that the open failed if there is no cx
        // reestablishment to occur
        if (open_count <= 0) {
            try {
                remote_semaphore.notify_result(false, null);
            } catch (Error err) {
                debug("Error attempting to notify that remote folder %s is now closed: %s", to_string(),
                    err.message);
            }
        }
        
        return old_remote_folder;
    }
    
    // See note in close_async() for why this method is static and uses an owned ref
    private static async void close_remote_folder_async(owned MinimalFolder folder,
        owned Imap.Folder? remote_folder) {
        // force the remote closed; if due to a remote disconnect and plan on reopening, *still*
        // need to do this ... don't set remote_folder to null, as that will make some code paths
        // think the folder is closing or closed when in fact it will be re-opening in a moment
        try {
            if (remote_folder != null)
                yield remote_folder.close_async(null);
        } catch (Error err) {
            debug("Unable to close remote %s: %s", remote_folder.to_string(), err.message);
            
            // fallthrough
        }
        
        if (folder.open_count <= 0) {
            debug("Not reestablishing connection to %s: closed", folder.to_string());
            
            // need to do it here if not done in close_internal_locked_async()
            if (remote_folder != null)
                folder.closed_semaphore.blind_notify();
            
            return;
        }
        
        // reestablish connection (which requires renormalizing the remote with the local) if
        // close was in error
        debug("Reestablishing broken connection to %s in %dms", folder.to_string(),
            folder.reestablish_delay_msec);
        
        yield Scheduler.sleep_ms_async(folder.reestablish_delay_msec);
        
        if (folder.open_count <= 0) {
            debug("Not reestablishing connection to %s: closed after delay", folder.to_string());
            
            return;
        }
        
        try {
            // double timer now, reset to init value when cleanly opened
            folder.reestablish_delay_msec = (folder.reestablish_delay_msec * 2).clamp(
                DEFAULT_REESTABLISH_DELAY_MSEC, MAX_REESTABLISH_DELAY_MSEC);
            
            // since open_async() increments open_count, artificially decrement here to
            // prevent driving the value up
            folder.open_count = Numeric.int_floor(folder.open_count - 1, 0);
            
            debug("Reestablishing broken connection to %s", folder.to_string());
            yield folder.open_async(OpenFlags.NO_DELAY, null);
        } catch (Error err) {
            debug("Error reestablishing broken connection to %s: %s", folder.to_string(), err.message);
        }
    }
    
    public override async void find_boundaries_async(Gee.Collection<Geary.EmailIdentifier> ids,
        out Geary.EmailIdentifier? low, out Geary.EmailIdentifier? high,
        Cancellable? cancellable = null) throws Error {
        low = null;
        high = null;
        
        // Get paths for all email identifiers
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? map
            = yield account.get_containing_folders_async(ids, cancellable);
        if (map == null || map.size == 0)
            return;
        
        // only deal with email identifiers in this folder
        Gee.ArrayList<Geary.EmailIdentifier> in_folder = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.EmailIdentifier id in map.get_keys()) {
            if (path in map.get(id))
                in_folder.add(id);
        }
        
        if (in_folder.size == 0)
            return;
        
        // get new Emails for these; they will have their UIDs and can be sorted properly
        Gee.List<Email>? list = yield local_folder.list_email_by_sparse_id_async(in_folder,
            Email.Field.NONE, ImapDB.Folder.ListFlags.NONE, cancellable);
        if (list == null || list.size == 0)
            return;
        
        Gee.HashSet<EmailIdentifier> db_ids = traverse<Email>(list)
            .map<EmailIdentifier>(email => email.id)
            .to_hash_set();
        
        Gee.SortedSet<Geary.EmailIdentifier> sorted = Geary.EmailIdentifier.sort(db_ids);
        
        low = sorted.first();
        high = sorted.last();
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
        remote_count = reported_remote_count;
        
        if (positions.size > 0)
            replay_queue.schedule_server_notification(new ReplayAppend(this, reported_remote_count, positions));
    }
    
    // Need to prefetch at least an EmailIdentifier (and duplicate detection fields) to create a
    // normalized placeholder in the local database of the message, so all positions are
    // properly relative to the end of the message list; once this is done, notify user of new
    // messages.  If duplicates, create_email_async() will fall through to an updated merge,
    // which is exactly what we want.
    //
    // This MUST only be called from ReplayAppend.
    internal async void do_replay_appended_messages(int reported_remote_count,
        Gee.List<Imap.SequenceNumber> remote_positions) {
        StringBuilder positions_builder = new StringBuilder("( ");
        foreach (Imap.SequenceNumber remote_position in remote_positions)
            positions_builder.append_printf("%s ", remote_position.to_string());
        positions_builder.append(")");
        
        debug("%s do_replay_appended_message: current remote_count=%d reported_remote_count=%d remote_positions=%s",
            to_string(), remote_count, reported_remote_count, positions_builder.str);
        
        if (remote_positions.size == 0)
            return;
        
        Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>();
        Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>();
        try {
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.sparse(remote_positions);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(msg_set,
                    ImapDB.Folder.REQUIRED_FIELDS, null);
                if (list != null && list.size > 0) {
                    debug("%s do_replay_appended_message: %d new messages in %s", to_string(),
                        list.size, msg_set.to_string());
                    
                    // need to report both if it was created (not known before) and appended (which
                    // could mean created or simply a known email associated with this folder)
                    Gee.Map<Geary.Email, bool> created_or_merged =
                        yield local_folder.create_or_merge_email_async(list, null);
                    foreach (Geary.Email email in created_or_merged.keys) {
                        // true means created
                        if (created_or_merged.get(email)) {
                            debug("%s do_replay_appended_message: appended email ID %s added",
                                to_string(), email.id.to_string());
                            
                            created.add(email.id);
                        } else {
                            debug("%s do_replay_appended_message: appended email ID %s associated",
                                to_string(), email.id.to_string());
                        }
                        
                        appended.add(email.id);
                    }
                } else {
                    debug("%s do_replay_appended_message: no new messages in %s", to_string(),
                        msg_set.to_string());
                }
            }
        } catch (Error err) {
            debug("%s do_replay_appended_message: Unable to process: %s",
                to_string(), err.message);
        }
        
        // store the reported count, *not* the current count (which is updated outside the of
        // the queue) to ensure that updates happen serially and reflect committed local changes
        try {
            yield local_folder.update_remote_selected_message_count(reported_remote_count, null);
        } catch (Error err) {
            debug("%s do_replay_appended_message: Unable to save appended remote count %d: %s",
                to_string(), reported_remote_count, err.message);
        }
        
        if (appended.size > 0)
            notify_email_appended(appended);
        
        if (created.size > 0)
            notify_email_locally_appended(created);
        
        notify_email_count_changed(reported_remote_count, CountChangeReason.APPENDED);
        
        debug("%s do_replay_appended_message: completed, current remote_count=%d reported_remote_count=%d",
            to_string(), remote_count, reported_remote_count);
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
        remote_count = reported_remote_count;
        
        replay_queue.schedule_server_notification(new ReplayRemoval(this, reported_remote_count, position));
    }
    
    // This MUST only be called from ReplayRemoval.
    internal async void do_replay_removed_message(int reported_remote_count, Imap.SequenceNumber remote_position) {
        debug("%s do_replay_removed_message: current remote_count=%d remote_position=%s reported_remote_count=%d",
            to_string(), remote_count, remote_position.value.to_string(), reported_remote_count);
        
        if (!remote_position.is_valid()) {
            debug("%s do_replay_removed_message: ignoring, invalid remote position or count",
                to_string());
            
            return;
        }
        
        int local_count = -1;
        int64 local_position = -1;
        
        ImapDB.EmailIdentifier? owned_id = null;
        try {
            // need total count, including those marked for removal, to accurately calculate position
            // from server's point of view, not client's
            local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
            local_position = remote_position.value - (reported_remote_count + 1 - local_count);
            
            // zero or negative means the message exists beyond the local vector's range, so
            // nothing to do there
            if (local_position > 0) {
                debug("%s do_replay_removed_message: local_count=%d local_position=%s", to_string(),
                    local_count, local_position.to_string());
                
                owned_id = yield local_folder.get_id_at_async(local_position, null);
            } else {
                debug("%s do_replay_removed_message: message not stored locally (local_count=%d local_position=%s)",
                    to_string(), local_count, local_position.to_string());
            }
        } catch (Error err) {
            debug("%s do_replay_removed_message: unable to determine ID of removed message %s: %s",
                to_string(), remote_position.to_string(), err.message);
        }
        
        bool marked = false;
        if (owned_id != null) {
            debug("%s do_replay_removed_message: detaching from local store Email ID %s", to_string(),
                owned_id.to_string());
            try {
                // Reflect change in the local store and notify subscribers
                yield local_folder.detach_single_email_async(owned_id, out marked, null);
            } catch (Error err) {
                debug("%s do_replay_removed_message: unable to remove message #%s: %s", to_string(),
                    remote_position.to_string(), err.message);
            }
            
            // Notify queued replay operations that the email has been removed (by EmailIdentifier)
            replay_queue.notify_remote_removed_ids(
                Geary.iterate<ImapDB.EmailIdentifier>(owned_id).to_array_list());
        } else {
            debug("%s do_replay_removed_message: remote_position=%d unknown in local store "
                + "(reported_remote_count=%d local_position=%d local_count=%d)",
                to_string(), remote_position.value, reported_remote_count, local_position, local_count);
        }
        
        // for debugging
        int new_local_count = -1;
        try {
            new_local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
        } catch (Error err) {
            debug("%s do_replay_removed_message: error fetching new local count: %s", to_string(),
                err.message);
        }
        
        // as with on_remote_appended(), only update in local store inside a queue operation, to
        // ensure serial commits
        try {
            yield local_folder.update_remote_selected_message_count(reported_remote_count, null);
        } catch (Error err) {
            debug("%s do_replay_removed_message: unable to save removed remote count: %s", to_string(),
                err.message);
        }
        
        // notify of change ... use "marked-email-removed" for marked email to allow internal code
        // to be notified when a removed email is "really" removed
        if (owned_id != null) {
            Gee.List<EmailIdentifier> removed = Geary.iterate<Geary.EmailIdentifier>(owned_id).to_array_list();
            if (!marked)
                notify_email_removed(removed);
            else
                marked_email_removed(removed);
        }
        
        if (!marked)
            notify_email_count_changed(reported_remote_count, CountChangeReason.REMOVED);
        
        debug("%s do_replay_remove_message: completed, current remote_count=%d "
            + "(reported_remote_count=%d local_count=%d starting local_count=%d remote_position=%d local_position=%d marked=%s)",
            to_string(), remote_count, reported_remote_count, new_local_count, local_count, remote_position.value,
            local_position, marked.to_string());
    }
    
    private void on_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("on_remote_disconnected: reason=%s", reason.to_string());
        
        // reset remote_semaphore to indicate that callers must again wait for the remote to open...
        // do this now to avoid race conditions w/ wait_for_open_async()
        remote_semaphore.reset();
        
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
        
        MarkEmail mark = new MarkEmail(this, to_mark, flags_to_add, flags_to_remove, cancellable);
        replay_queue.schedule(mark);
        
        yield mark.wait_for_ready_async(cancellable);
    }
    
    public virtual async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        yield copy_email_uids_async(to_copy, destination, cancellable);
    }
    
    /**
     * Returns the destination folder's UIDs for the copied messages.
     */
    public async Gee.Set<Imap.UID>? copy_email_uids_async(Gee.List<Geary.EmailIdentifier> to_copy,
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
        
        return new RevokableMove(_account, this, destination, prepare.prepared_for_move);
    }
    
    public void schedule_op(ReplayOperation op) throws Error {
        check_open("schedule_op");
        
        replay_queue.schedule(op);
    }
    
    public async void exec_op_async(ReplayOperation op, Cancellable? cancellable) throws Error {
        schedule_op(op);
        yield op.wait_for_ready_async(cancellable);
    }
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> changed) {
        notify_email_flags_changed(changed);
    }
    
    // TODO: A proper public search mechanism; note that this always round-trips to the remote,
    // doesn't go through the replay queue, and doesn't deal with messages marked for deletion
    internal async Geary.EmailIdentifier? find_earliest_email_async(DateTime datetime,
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
        
        debug("%s: find_earliest_email_async: %s", to_string(), criteria.to_string());
        
        ServerSearchEmail op = new ServerSearchEmail(this, criteria, Geary.Email.Field.NONE,
            cancellable);
        
        // need to check again due to the yield in the above conditional block
        check_open("find_earliest_email_async.schedule operation");
        
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
        
        // find earliest ID; because all Email comes from Folder, UID should always be present
        ImapDB.EmailIdentifier? earliest_id = null;
        foreach (Geary.Email email in op.accumulator) {
            ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
            
            if (earliest_id == null || email_id.uid.compare_to(earliest_id.uid) < 0)
                earliest_id = email_id;
        }
        
        debug("%s: find_earliest_email_async: found %s", to_string(),
            earliest_id != null ? earliest_id.to_string() : "(null)");
        
        return earliest_id;
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
        
        return ret;
    }
    
    public override string to_string() {
        return "%s (open_count=%d remote_opened=%s)".printf(base.to_string(), open_count,
            remote_opened.to_string());
    }
}

