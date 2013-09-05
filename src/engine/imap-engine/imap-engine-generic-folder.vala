/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GenericFolder : Geary.AbstractFolder, Geary.FolderSupport.Copy,
    Geary.FolderSupport.Mark, Geary.FolderSupport.Move {
    private const int FORCE_OPEN_REMOTE_TIMEOUT_SEC = 10;
    
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
    
    internal ImapDB.Folder local_folder  { get; protected set; }
    internal Imap.Folder? remote_folder { get; protected set; default = null; }
    internal EmailPrefetcher email_prefetcher { get; private set; }
    internal EmailFlagWatcher email_flag_watcher;
    
    private weak GenericAccount _account;
    private Geary.AggregatedFolderProperties _properties = new Geary.AggregatedFolderProperties();
    private Imap.Account remote;
    private ImapDB.Account local;
    private Folder.OpenFlags open_flags = OpenFlags.NONE;
    private int open_count = 0;
    private bool remote_opened = false;
    private Nonblocking.ReportingSemaphore<bool>? remote_semaphore = null;
    private ReplayQueue? replay_queue = null;
    private int remote_count = -1;
    private uint open_remote_timer_id = 0;
    
    public GenericFolder(GenericAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        _account = account;
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        _special_folder_type = special_folder_type;
        _properties.add(local_folder.get_properties());
        
        email_flag_watcher = new EmailFlagWatcher(this);
        email_flag_watcher.email_flags_changed.connect(on_email_flags_changed);
        
        email_prefetcher = new EmailPrefetcher(this);
        
        local_folder.email_complete.connect(on_email_complete);
    }
    
    ~EngineFolder() {
        if (open_count > 0)
            warning("Folder %s destroyed without closing", to_string());
        
        local_folder.email_complete.disconnect(on_email_complete);
    }
    
    public void set_special_folder_type(SpecialFolderType new_type) {
        SpecialFolderType old_type = _special_folder_type;
        _special_folder_type = new_type;
        if(old_type != new_type)
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
    
    private async bool normalize_folders(Geary.Imap.Folder remote_folder, Geary.Folder.OpenFlags open_flags,
        Cancellable? cancellable) throws Error {
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
            
            yield local_folder.detach_all_emails_async(cancellable);
            
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
        int remove_markers = yield local_folder.get_marked_for_remove_count_async(cancellable);
        bool is_dirty = (remove_markers != 0);
        
        if (is_dirty)
            debug("%s: %d remove markers found, folder is dirty", to_string(), remove_markers);
        
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
        
        // a full normalize works from the highest possible UID on the remote and work down to the lowest UID on
        // the local; this covers all messages appended since last seen as well as any removed
        Imap.UID last_uid = remote_properties.uid_next.previous();
        
        // if the difference in UIDNEXT values equals the difference in message count, then only
        // an append could have happened, so only pull in the new messages ... note that this is not foolproof,
        // as UIDs are not guaranteed to increase by 1; however, this is a standard implementation practice,
        // so it's worth looking for
        //
        // (Also, this cannot fail; if this situation exists, then it cannot by definition indicate another
        // situation, esp. messages being removed.)
        Imap.UID first_uid;
        if (!is_dirty && uidnext_diff == (remote_message_count - local_message_count)) {
            first_uid = local_latest_id.uid.next();
            
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
            local_uids = Gee.Set.empty<Imap.UID>();
        
        check_open("normalize_folders (list local)");
        
        // Do the same on the remote ... make non-null for ease of use later
        Gee.Set<Imap.UID>? remote_uids = yield remote_folder.list_uids_async(
            new Imap.MessageSet.uid_range(first_uid, last_uid), cancellable);
        if (remote_uids == null)
            local_uids = Gee.Set.empty<Imap.UID>();
        
        check_open("normalize_folders (list remote)");
        
        debug("%s: Loaded local (%d) and remote (%d) UIDs, normalizing...", to_string(),
            local_uids.size, remote_uids.size);
        
        Gee.HashSet<Imap.UID> removed_uids = new Gee.HashSet<Imap.UID>();
        Gee.HashSet<Imap.UID> appended_uids = new Gee.HashSet<Imap.UID>();
        Gee.HashSet<Imap.UID> discovered_uids = new Gee.HashSet<Imap.UID>();
        
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
                    discovered_uids.add(remote_uid);
            }
        }, cancellable);
        
        debug("%s: changes since last seen: removed=%d appended=%d discovered=%d", to_string(),
            removed_uids.size, appended_uids.size, discovered_uids.size);
        
        // fetch from the server the local store's required flags for all appended/inserted messages
        // (which is simply equal to all remaining remote UIDs)
        Gee.List<Geary.Email>? to_create = null;
        if (remote_uids.size > 0) {
            // for new messages, get the local store's required fields (which provide duplicate
            // detection)
            to_create = yield remote_folder.list_email_async(
                new Imap.MessageSet.uid_sparse(remote_uids.to_array()), ImapDB.Folder.REQUIRED_FIELDS,
                cancellable);
        }
        
        check_open("normalize_folders (list remote appended/inserted required fields)");
        
        // store new messages and add IDs to the appended/discovered EmailIdentifier buckets
        Gee.Set<ImapDB.EmailIdentifier> appended_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        Gee.Set<ImapDB.EmailIdentifier> locally_appended_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        Gee.Set<ImapDB.EmailIdentifier> discovered_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        if (to_create != null && to_create.size > 0) {
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
                    } else if (discovered_uids.contains(id.uid) && created) {
                        discovered_ids.add(id);
                    }
                }
            }, cancellable);
            
            debug("%s: Finished creating/merging %d emails", to_string(), created_or_merged.size);
        }
        
        check_open("normalize_folders (created/merged appended/discovered emails)");
        
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
        
        // remove any extant remove markers, as everything is accounted for now
        yield local_folder.clear_remove_markers_async(cancellable);
        
        check_open("normalize_folders (clear remove markers)");
        
        //
        // now normalized
        // notify subscribers of changes
        //
        
        if (removed_ids != null && removed_ids.size > 0) {
            // there may be operations pending on the remote queue for these removed emails; notify
            // operations that the email has shuffled off this mortal coil
            replay_queue.notify_remote_removed_ids(removed_ids);
            
            // notify subscribers about emails that have been removed
            debug("%s: Notifying of %d removed emails since last opened", to_string(), removed_ids.size);
            notify_email_removed(removed_ids);
        }
        
        // notify local discovered (i.e. emails that are in the interior of the vector not seen
        // before -- this can happen during vector expansion when the app crashes or closes before
        // writing out everything)
        if (discovered_ids.size > 0) {
            debug("%s: Notifying of %d discovered emails since last opened", to_string(), discovered_ids.size);
            notify_email_discovered(discovered_ids);
        }
        
        // notify appended (new email added since the folder was last opened)
        if (appended_ids.size > 0) {
            debug("%s: Notifying of %d appended emails since last opened", to_string(), appended_ids.size);
            notify_email_appended(appended_ids);
        }
        
        // notify locally appended (new email never seen before added since the folder was last
        // opened)
        if (locally_appended_ids.size > 0) {
            debug("%s: Notifying of %d locally appended emails since last opened", to_string(),
                locally_appended_ids.size);
            notify_email_locally_appended(locally_appended_ids);
        }
        
        debug("%s: Completed normalize_folder", to_string());
        
        return true;
    }
    
    public override async void wait_for_open_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || remote_semaphore == null)
            throw new EngineError.OPEN_REQUIRED("wait_for_open_async() can only be called after open_async()");
        
        // if remote has not yet been opened, do it now ... this bool can go true only once after
        // an open_async, it's reset at close time
        if (!remote_opened) {
            debug("wait_for_open_async %s: opening remote on demand...", to_string());
            
            remote_opened = true;
            open_remote_async.begin(open_flags, null);
        }
        
        if (!yield remote_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.ALREADY_CLOSED("%s failed to open", to_string());
    }
    
    public override async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0) {
            debug("Not opening %s: already open (open_count=%d)", to_string(), open_count);
            
            return false;
        }
        
        this.open_flags = open_flags;
        remote_semaphore = new Geary.Nonblocking.ReportingSemaphore<bool>(false);
        
        // start the replay queue
        replay_queue = new ReplayQueue(this);
        
        // do NOT open the remote side here; wait for the ReplayQueue to require a remote connection
        // or wait_for_open_async() to be called ... this allows for fast local-only operations
        // to occur, local-only either because (a) the folder has all the information required
        // (for a list or fetch operation), or (b) the operation was de facto local-only.
        // In particular, EmailStore will open and close lots of folders, causing a lot of
        // connection setup and teardown
        
        // However, want to eventually open, otherwise if there's no user interaction (i.e. a
        // second account Inbox they don't manipulate), no remote connection will ever be made,
        // meaning that folder normalization never happens and unsolicited notifications never
        // arrive
        start_remote_open_timer();
        
        return true;
    }
    
    private void start_remote_open_timer() {
        if (open_remote_timer_id != 0)
            Source.remove(open_remote_timer_id);
        
        open_remote_timer_id = Timeout.add_seconds(FORCE_OPEN_REMOTE_TIMEOUT_SEC, on_open_remote_timeout);
    }
    
    private void cancel_remote_open_timer() {
        if (open_remote_timer_id == 0)
            return;
        
        Source.remove(open_remote_timer_id);
        open_remote_timer_id = 0;
    }
    
    private bool on_open_remote_timeout() {
        open_remote_timer_id = 0;
        
        // remote was not forced open due to caller, so open now
        wait_for_open_async.begin();
        
        return false;
    }
    
    private async void open_remote_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable) {
        cancel_remote_open_timer();
        
        // watch for folder closing before this call got a chance to execute
        if (open_count == 0)
            return;
        
        try {
            debug("Fetching information for remote folder %s", to_string());
            Imap.Folder folder = yield remote.fetch_folder_async(local_folder.get_path(),
                cancellable);
            
            debug("Opening remote folder %s", folder.to_string());
            yield folder.open_async(cancellable);
            
            // allow subclasses to examine the opened folder and resolve any vital
            // inconsistencies
            if (yield normalize_folders(folder, open_flags, cancellable)) {
                // update flags, properties, etc.
                yield local.update_folder_select_examine_async(folder, cancellable);
                
                // signals
                folder.appended.connect(on_remote_appended);
                folder.removed.connect(on_remote_removed);
                folder.disconnected.connect(on_remote_disconnected);
            
                // state
                remote_count = folder.properties.email_total;
                
                // all set; bless the remote folder as opened
                remote_folder = folder;
            } else {
                debug("Unable to prepare remote folder %s: normalize_folders() failed", to_string());
                notify_open_failed(Geary.Folder.OpenFailed.REMOTE_FAILED, null);
                
                // schedule immediate close
                close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR, cancellable);
                
                return;
            }
        } catch (Error open_err) {
            debug("Unable to open or prepare remote folder %s: %s", to_string(), open_err.message);
            notify_open_failed(Geary.Folder.OpenFailed.REMOTE_FAILED, open_err);
            
            // schedule immediate close
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR, cancellable);
            
            return;
        }
        
        int count;
        try {
            count = (remote_folder != null)
                ? remote_count
                : yield local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE, cancellable);
        } catch (Error count_err) {
            debug("Unable to fetch count from local folder: %s", count_err.message);
            
            count = 0;
        }
        
        // notify any threads of execution waiting for the remote folder to open that the result
        // of that operation is ready
        try {
            remote_semaphore.notify_result(remote_folder != null, null);
        } catch (Error notify_err) {
            debug("Unable to fire semaphore notifying remote folder ready/not ready: %s",
                notify_err.message);
            
            // do this now rather than wait for close_internal_async() to execute to ensure that
            // any replay operations already queued don't attempt to run
            try {
                clear_remote_folder();
            } catch (Error err) {
                debug("Unable to clear and signal remote folder due to failed open: %s", err.message);
                
                // fall through
            }
            
            notify_open_failed(Geary.Folder.OpenFailed.REMOTE_FAILED, notify_err);
            
            // schedule immediate close
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR, cancellable);
            
            return;
        }
        
        _properties.add(remote_folder.properties);
        
        // notify any subscribers with similar information
        notify_opened(
            (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL,
            count);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || --open_count > 0)
            return;
        
        if (remote_folder != null)
            _properties.remove(remote_folder.properties);
        
        yield close_internal_async(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_CLOSE, cancellable);
    }
    
    // NOTE: This bypasses open_count and forces the Folder closed.
    private async void close_internal_async(Folder.CloseReason local_reason, Folder.CloseReason remote_reason,
        Cancellable? cancellable) {
        // force closed
        open_count = 0;
        
        cancel_remote_open_timer();
        
        // Notify all callers waiting for the remote folder that it's not coming available
        Imap.Folder? closing_remote_folder = remote_folder;
        try {
            clear_remote_folder();
        } catch (Error err) {
            debug("close_internal_async: Unable to fire remote semaphore: %s", err.message);
        }
        
        if (closing_remote_folder != null) {
            closing_remote_folder.appended.disconnect(on_remote_appended);
            closing_remote_folder.removed.disconnect(on_remote_removed);
            closing_remote_folder.disconnected.disconnect(on_remote_disconnected);
            
            // to avoid keeping the caller waiting while the remote end closes, close it in the
            // background
            //
            // TODO: Problem with this is that we cannot effectively signal or report a close error,
            // because by the time this operation completes the folder is considered closed.  That
            // may not be important to most callers, however.
            closing_remote_folder.close_async.begin(cancellable);
        }
        
        // use remote_reason even if remote_folder was null; it could be that the error occurred
        // while opening and remote_folder was yet unassigned ... also, need to call this every
        // time, even if remote was not fully opened, as some callers rely on order of signals
        notify_closed(remote_reason);
        
        // see above note for why this must be called every time
        notify_closed(local_reason);
        
        // Close the replay queues *after* the folder has been closed (in case any final upcalls
        // come and can be handled)
        try {
            if (replay_queue != null) {
                debug("Closing replay queue for %s...", to_string());
                yield replay_queue.close_async();
                debug("Closed replay queue for %s", to_string());
            }
        } catch (Error replay_queue_err) {
            debug("Error closing %s replay queue: %s", to_string(), replay_queue_err.message);
        }
        
        replay_queue = null;
        remote_opened = false;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
        
        debug("Folder %s closed", to_string());
    }
    
    private void clear_remote_folder() throws Error {
        remote_folder = null;
        remote_count = -1;
        
        remote_semaphore.reset();
        remote_semaphore.notify_result(false, null);
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
    
    private void on_remote_appended(int new_remote_count) {
        debug("%s on_remote_appended: new_remote_count=%d", to_string(), new_remote_count);
        
        // from the new remote total and the old remote total, glean the SequenceNumbers of the
        // new email(s)
        Gee.List<Imap.SequenceNumber> positions = new Gee.ArrayList<Imap.SequenceNumber>();
        for (int pos = remote_count + 1; pos <= new_remote_count; pos++)
            positions.add(new Imap.SequenceNumber(pos));
        
        if (positions.size > 0)
            replay_queue.schedule_server_notification(new ReplayAppend(this, positions));
    }
    
    // Need to prefetch at least an EmailIdentifier (and duplicate detection fields) to create a
    // normalized placeholder in the local database of the message, so all positions are
    // properly relative to the end of the message list; once this is done, notify user of new
    // messages.  If duplicates, create_email_async() will fall through to an updated merge,
    // which is exactly what we want.
    //
    // This MUST only be called from ReplayAppend.
    internal async void do_replay_appended_messages(Gee.List<Imap.SequenceNumber> remote_positions) {
        StringBuilder positions_builder = new StringBuilder("( ");
        foreach (Imap.SequenceNumber remote_position in remote_positions)
            positions_builder.append_printf("%s ", remote_position.to_string());
        positions_builder.append(")");
        
        debug("%s do_replay_appended_message: remote_count=%d remote_positions=%s", to_string(),
            remote_count, positions_builder.str);
        
        if (remote_positions.size == 0)
            return;
        
        Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>();
        Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>();
        try {
            // If remote doesn't fully open, then don't fire signal, as we'll be unable to
            // normalize the folder
            if (!yield remote_semaphore.wait_for_result_async(null)) {
                debug("%s do_replay_appended_message: remote never opened", to_string());
                
                return;
            }
            
            Imap.MessageSet msg_set = new Imap.MessageSet.sparse(remote_positions.to_array());
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
        } catch (Error err) {
            debug("%s do_replay_appended_message: Unable to process: %s",
                to_string(), err.message);
        }
        
        // save new remote count internally and in local store
        // NOTE: use remote_positions size, not created/appended, as the former is a true indication
        // of the count on the server
        remote_count += remote_positions.size;
        try {
            yield local_folder.update_remote_selected_message_count(remote_count, null);
        } catch (Error err) {
            debug("%s do_replay_appended_message: Unable to save appended remote count %d: %s",
                to_string(), remote_count, err.message);
        }
        
        if (appended.size > 0)
            notify_email_appended(appended);
        
        if (created.size > 0) {
            notify_email_locally_appended(created);
            notify_email_discovered(created);
        }
        
        notify_email_count_changed(remote_count, CountChangeReason.APPENDED);
        
        debug("%s do_replay_appended_message: completed remote_count=%d", to_string(), remote_count);
    }
    
    private void on_remote_removed(Imap.SequenceNumber position, int new_remote_count) {
        debug("%s on_remote_removed: position=%s new_remote_count=%d", to_string(), position.to_string(),
            new_remote_count);
        
        // notify of removal to all pending replay operations
        replay_queue.notify_remote_removed_position(position);
        
        replay_queue.schedule_server_notification(new ReplayRemoval(this, position));
    }
    
    // This MUST only be called from ReplayRemoval.
    internal async void do_replay_removed_message(Imap.SequenceNumber remote_position) {
        debug("%s do_replay_removed_message: remote_position=%d remote_count=%d",
            to_string(), remote_position.value, remote_count);
        
        if (!remote_position.is_valid()) {
            debug("%s do_replay_removed_message: ignoring, invalid remote position or count",
                to_string());
            
            return;
        }
        
        int local_count = -1;
        int local_position = -1;
        
        ImapDB.EmailIdentifier? owned_id = null;
        try {
            // need total count, including those marked for removal, to accurately calculate position
            // from server's point of view, not client's
            local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
            local_position = remote_position.value - (remote_count - local_count);
            
            // zero or negative means the message exists beyond the local vector's range, so
            // nothing to do there
            if (local_position > 0) {
                debug("%s do_replay_removed_message: local_count=%d local_position=%d", to_string(),
                    local_count, local_position);
                
                owned_id = yield local_folder.get_id_at_async(local_position, null);
            } else {
                debug("%s do_replay_removed_message: message not stored locally (local_count=%d local_position=%d)",
                    to_string(), local_count, local_position);
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
            replay_queue.notify_remote_removed_ids(new Collection.SingleItem<ImapDB.EmailIdentifier>(owned_id));
        } else {
            debug("%s do_replay_removed_message: remote_position=%d unknown in local store "
                + "(remote_count=%d local_position=%d local_count=%d)",
                to_string(), remote_position.value, remote_count, local_position, local_count);
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
        
        // something to note at this point: the ExpungeEmail operation marks messages as removed,
        // then signals they're removed and reports an adjusted count in its replay_local_async().
        // remote_count is *not* updated, which is why it's safe to do that here without worry.
        // similarly, signals are only fired here if marked, so the same EmailIdentifier isn't
        // reported twice
        
        // save new remote count internally and in local store
        remote_count = Numeric.int_floor(remote_count - 1, 0);
        try {
            yield local_folder.update_remote_selected_message_count(remote_count, null);
        } catch (Error err) {
            debug("%s do_replay_removed_message: unable to save removed remote count: %s", to_string(),
                err.message);
        }
        
        // notify of change
        if (!marked && owned_id != null)
            notify_email_removed(new Collection.SingleItem<Geary.EmailIdentifier>(owned_id));
        
        if (!marked)
            notify_email_count_changed(remote_count, CountChangeReason.REMOVED);
        
        debug("%s do_replay_remove_message: completed "
            + "(remote_count=%d local_count=%d starting local_count=%d remote_position=%d local_position=%d marked=%s)",
            to_string(), remote_count, new_local_count, local_count, remote_position.value, local_position,
            marked.to_string());
    }
    
    private void on_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("on_remote_disconnected: reason=%s", reason.to_string());
        replay_queue.schedule(new ReplayDisconnect(this, reason));
    }
    
    internal async void do_replay_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("do_replay_remote_disconnected reason=%s", reason.to_string());
        
        Geary.Folder.CloseReason folder_reason = reason.is_error()
            ? Geary.Folder.CloseReason.REMOTE_ERROR : Geary.Folder.CloseReason.REMOTE_CLOSE;
        
        // because close_internal_async() issues ReceiveReplayQueue.close_async() (which cannot
        // be called from within a ReceiveReplayOperation), schedule the close rather than
        // yield for it ... can't simply call the async .begin variant because, depending on
        // the situation, it may not yield until it attempts to close the ReceiveReplayQueue,
        // which is the problem we're attempting to work around
        Idle.add(() => {
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, folder_reason, null);
            
            return false;
        });
    }
    
    //
    // list_email_by_id variants
    //
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_by_id_async("list_email_by_id_async", initial_id, count, required_fields,
            flags, accumulator, null, cancellable);
        
        return !accumulator.is_empty ? accumulator : null;
    }
    
    public override void lazy_list_email_by_id(Geary.EmailIdentifier? initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_id_async.begin(initial_id, count, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_id_async(Geary.EmailIdentifier? initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable) {
        try {
            yield do_list_email_by_id_async("lazy_list_email_by_id", initial_id, count, required_fields,
                flags, null, cb, cancellable);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    private async void do_list_email_by_id_async(string method, Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable) throws Error {
        check_open(method);
        check_flags(method, flags);
        if (initial_id != null)
            check_id(method, initial_id);
        
        if (count == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        // Schedule list operation and wait for completion.
        ListEmailByID op = new ListEmailByID(this, (ImapDB.EmailIdentifier) initial_id, count,
            required_fields, flags, accumulator, cb, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
    }
    
    //
    // list_email_by_sparse_id variants
    //
    
    public async override Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        Gee.ArrayList<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_by_sparse_id_async("list_email_by_sparse_id_async", ids, required_fields,
            flags, accumulator, null, cancellable);
        
        return (accumulator.size > 0) ? accumulator : null;
    }
    
    public override void lazy_list_email_by_sparse_id(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        do_lazy_list_email_by_sparse_id_async.begin(ids, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable) {
        try {
            yield do_list_email_by_sparse_id_async("lazy_list_email_by_sparse_id", ids, required_fields,
                flags, null, cb, cancellable);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    private async void do_list_email_by_sparse_id_async(string method,
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable = null) throws Error {
        check_open(method);
        check_flags(method, flags);
        check_ids(method, ids);
        
        if (ids.size == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        // Schedule list operation and wait for completion.
        // TODO: Break up requests to avoid hogging the queue
        ListEmailBySparseID op = new ListEmailBySparseID(this, (Gee.Collection<ImapDB.EmailIdentifier>) ids,
            required_fields, flags, accumulator, cb, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
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
        Cancellable? cancellable = null) throws Error {
        check_open("expunge_email_async");
        check_ids("expunge_email_async", email_ids);
        
        ExpungeEmail expunge = new ExpungeEmail(this, (Gee.List<ImapDB.EmailIdentifier>) email_ids,
            cancellable);
        replay_queue.schedule(expunge);
        
        yield expunge.wait_for_ready_async(cancellable);
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
        check_open("copy_email_async");
        check_ids("copy_email_async", to_copy);
        
        CopyEmail copy = new CopyEmail(this, (Gee.List<ImapDB.EmailIdentifier>) to_copy, destination);
        replay_queue.schedule(copy);
        yield copy.wait_for_ready_async(cancellable);
    }

    public virtual async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("move_email_async");
        check_ids("move_email_async", to_move);
        
        MoveEmail move = new MoveEmail(this, (Gee.List<ImapDB.EmailIdentifier>) to_move, destination);
        replay_queue.schedule(move);
        yield move.wait_for_ready_async(cancellable);
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
                new Imap.MessageSet.uid_range(new Imap.UID(Imap.UID.MIN), before_uid.previous())));
        }
        
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        ServerSearchEmail op = new ServerSearchEmail(this, criteria, Geary.Email.Field.NONE,
            accumulator, cancellable);
        
        replay_queue.schedule(op);
        
        if (!yield op.wait_for_ready_async(cancellable))
            return null;
        
        // find earliest ID; because all Email comes from Folder, UID should always be present
        ImapDB.EmailIdentifier? earliest_id = null;
        foreach (Geary.Email email in accumulator) {
            ImapDB.EmailIdentifier email_id = (ImapDB.EmailIdentifier) email.id;
            
            if (earliest_id == null || email_id.uid.compare_to(earliest_id.uid) < 0)
                earliest_id = email_id;
        }
        
        return earliest_id;
    }
    
    internal async Geary.EmailIdentifier create_email_async(RFC822.Message rfc822, Geary.EmailFlags? flags,
        DateTime? date_received, Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error {
        check_open("create_email_async");
        if (id != null)
            check_id("create_email_async", id);
        
        // TODO: Move this into a ReplayQueue operation
        yield wait_for_open_async(cancellable);
        
        // use IMAP APPEND command on remote folders, which doesn't require opening a folder
        Geary.EmailIdentifier? ret = yield remote_folder.create_email_async(rfc822, flags,
            date_received, cancellable);
        if (ret != null) {
            // TODO: need to prevent gaps that may occur here
            Geary.Email created = new Geary.Email(ret);
            Gee.Map<Geary.Email, bool> results = yield local_folder.create_or_merge_email_async(
                new Collection.SingleItem<Geary.Email>(created), cancellable);
            if (results.size > 0)
                ret = Collection.get_first<Geary.Email>(results.keys).id;
            else
                ret = null;
        }
        
        // Remove old message.
        if (id != null) {
            Geary.FolderSupport.Remove? remove_folder = this as Geary.FolderSupport.Remove;
            if (remove_folder != null)
                yield remove_folder.remove_single_email_async(id, cancellable);
        }
        
        return ret;
    }
}

