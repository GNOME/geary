/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapFolder : Geary.AbstractFolder {
    internal const int REMOTE_FETCH_CHUNK_COUNT = 50;
    
    private const Geary.Email.Field NORMALIZATION_FIELDS = Geary.Email.Field.PROPERTIES;
    
    internal Sqlite.Folder local_folder  { get; protected set; }
    internal Imap.Folder? remote_folder { get; protected set; default = null; }
    internal SpecialFolder? special_folder { get; protected set; default = null; }
    internal int remote_count { get; private set; default = -1; }
    
    private weak GenericImapAccount account;
    private Imap.Account remote;
    private Sqlite.Account local;
    private EmailFlagWatcher email_flag_watcher;
    private EmailPrefetcher email_prefetcher;
    private bool opened = false;
    private NonblockingSemaphore remote_semaphore;
    private ReplayQueue? replay_queue = null;
    private NonblockingMutex normalize_email_positions_mutex = new NonblockingMutex();
    
    public GenericImapFolder(GenericImapAccount account, Imap.Account remote, Sqlite.Account local,
        Sqlite.Folder local_folder, SpecialFolder? special_folder) {
        this.account = account;
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        this.special_folder = special_folder;
        
        email_flag_watcher = new EmailFlagWatcher(this);
        email_flag_watcher.email_flags_changed.connect(on_email_flags_changed);
        
        email_prefetcher = new EmailPrefetcher(this);
    }
    
    ~EngineFolder() {
        if (opened)
            warning("Folder %s destroyed without closing", to_string());
    }
    
    public override Geary.FolderPath get_path() {
        return local_folder.get_path();
    }
    
    public override Geary.SpecialFolderType? get_special_folder_type() {
        if (special_folder == null) {
            return null;
        } else {
            return special_folder.folder_type;
        }
    }
    
    private Imap.FolderProperties? get_folder_properties() {
        Imap.FolderProperties? properties = null;
        
        // Get properties in order of authoritativeness:
        // - Ask open remote folder
        // - Query account object if it's seen them in its traversals
        // - Fetch from local store
        if (remote_folder != null)
            properties = remote_folder.get_properties();
        
        if (properties == null)
            properties = account.get_properties_for_folder(local_folder.get_path());
        
        if (properties == null)
            properties = local_folder.get_properties();
        
        return properties;
    }
    
    public override Geary.Trillian has_children() {
        Imap.FolderProperties? properties = get_folder_properties();
        
        return (properties != null) ? properties.has_children : Trillian.UNKNOWN;
    }
    
    public override Geary.Folder.OpenState get_open_state() {
        if (!opened)
            return Geary.Folder.OpenState.CLOSED;
        
        if (local_folder.opened)
            return (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL;
        else if (remote_folder != null)
            return Geary.Folder.OpenState.REMOTE;
        
        // opened flag set but neither open; indicates opening state
        return Geary.Folder.OpenState.OPENING;
    }
    
    public override async bool create_email_async(Geary.Email email, Cancellable? cancellable) throws Error {
        check_open("create_email_async");
        
        throw new EngineError.READONLY("Engine currently read-only");
    }
    
    private async bool normalize_folders(Geary.Imap.Folder remote_folder, Cancellable? cancellable) throws Error {
        debug("normalize_folders %s", to_string());
        
        Geary.Imap.FolderProperties? local_properties = local_folder.get_properties();
        Geary.Imap.FolderProperties? remote_properties = remote_folder.get_properties();
        
        // both sets of properties must be available
        if (local_properties == null) {
            debug("Unable to verify UID validity for %s: missing local properties", get_path().to_string());
            
            return false;
        }
        
        if (remote_properties == null) {
            debug("Unable to verify UID validity for %s: missing remote properties", get_path().to_string());
            
            return false;
        }
        
        // and both must have their next UID's (it's possible they don't if it's a non-selectable
        // folder)
        if (local_properties.uid_next == null || local_properties.uid_validity == null) {
            debug("Unable to verify UID next for %s: missing local UID next (%s) and/or validity (%s)",
                get_path().to_string(), (local_properties.uid_next == null).to_string(),
                (local_properties.uid_validity == null).to_string());
            
            return false;
        }
        
        if (remote_properties.uid_next == null || remote_properties.uid_validity == null) {
            debug("Unable to verify UID next for %s: missing remote UID next (%s) and/or validity (%s)",
                get_path().to_string(), (remote_properties.uid_next == null).to_string(),
                (remote_properties.uid_validity == null).to_string());
            
            return false;
        }
        
        if (local_properties.uid_validity.value != remote_properties.uid_validity.value) {
            // TODO: Don't deal with UID validity changes yet
            error("UID validity changed: %lld -> %lld", local_properties.uid_validity.value,
                remote_properties.uid_validity.value);
        }
        
        // from here on the only write operations being performed on the folder are creating or updating
        // existing emails or removing them, both operations being performed using EmailIdentifiers
        // rather than positional addressing ... this means the order of operation is not important
        // and can be batched up rather than performed serially
        NonblockingBatch batch = new NonblockingBatch();
        
        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        Geary.Imap.UID? earliest_uid = yield local_folder.get_earliest_uid_async(cancellable);
        
        // if no earliest UID, that means no messages in local store, so nothing to update
        if (earliest_uid == null || !earliest_uid.is_valid()) {
            debug("No earliest UID in %s, nothing to normalize", to_string());
            
            return true;
        }
        
        Geary.Imap.EmailIdentifier earliest_id = new Geary.Imap.EmailIdentifier(earliest_uid);
        
        // Get the local emails in the range
        Gee.List<Geary.Email>? old_local = yield local_folder.list_email_by_id_async(
            earliest_id, int.MAX, NORMALIZATION_FIELDS, Geary.Folder.ListFlags.NONE, false,
            cancellable);
        
        // be sure they're sorted from earliest to latest
        if (old_local != null)
            old_local.sort(Geary.Email.compare_id_ascending);
        
        int local_length = (old_local != null) ? old_local.size : 0;
        
        // as before, if empty folder, nothing to update
        if (local_length == 0) {
            debug("Folder %s empty, nothing to update", to_string());
            
            return true;
        }
        
        // Get the remote emails in the range to either add any not known, remove deleted messages,
        // and update the flags of the remainder
        Gee.List<Geary.Email>? old_remote = yield remote_folder.list_email_async(
            new Imap.MessageSet.uid_range_to_highest(earliest_uid), NORMALIZATION_FIELDS,
            cancellable);
        
        // sort earliest to latest
        if (old_remote != null)
            old_remote.sort(Geary.Email.compare_id_ascending);
        
        int remote_length = (old_remote != null) ? old_remote.size : 0;
        
        int remote_ctr = 0;
        int local_ctr = 0;
        Gee.ArrayList<Geary.EmailIdentifier> appended_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.ArrayList<Geary.EmailIdentifier> removed_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> flags_changed = new Gee.HashMap<Geary.EmailIdentifier,
            Geary.EmailFlags>();
        for (;;) {
            if (local_ctr >= local_length || remote_ctr >= remote_length)
                break;
            
            Geary.Email remote_email = old_remote[remote_ctr];
            Geary.Email local_email = old_local[local_ctr];
            
            Geary.Imap.UID remote_uid = ((Geary.Imap.EmailIdentifier) remote_email.id).uid;
            Geary.Imap.UID local_uid = ((Geary.Imap.EmailIdentifier) local_email.id).uid;
            
            if (remote_uid.value == local_uid.value) {
                // same, update flags (if changed) and move on
                Geary.Imap.EmailProperties local_email_properties =
                    (Geary.Imap.EmailProperties) local_email.properties;
                Geary.Imap.EmailProperties remote_email_properties =
                    (Geary.Imap.EmailProperties) remote_email.properties;
                
                if (!local_email_properties.equals(remote_email_properties)) {
                    batch.add(new CreateLocalEmailOperation(local_folder, remote_email, NORMALIZATION_FIELDS));
                    flags_changed.set(remote_email.id, remote_email.properties.email_flags);
                }
                
                remote_ctr++;
                local_ctr++;
            } else if (remote_uid.value < local_uid.value) {
                // one we'd not seen before is present, add and move to next remote
                batch.add(new CreateLocalEmailOperation(local_folder, remote_email, NORMALIZATION_FIELDS));
                appended_ids.add(remote_email.id);
                
                remote_ctr++;
            } else {
                assert(remote_uid.value > local_uid.value);
                
                // local's email on the server has been removed, remove locally
                batch.add(new RemoveLocalEmailOperation(local_folder, local_email.id));
                removed_ids.add(local_email.id);
                
                local_ctr++;
            }
        }
        
        // add newly-discovered emails to local store ... only report these as appended; earlier
        // CreateEmailOperations were updates of emails existing previously or additions of emails
        // that were on the server earlier but not stored locally (i.e. this value represents emails
        // added to the top of the stack)
        for (; remote_ctr < remote_length; remote_ctr++) {
            batch.add(new CreateLocalEmailOperation(local_folder, old_remote[remote_ctr],
                NORMALIZATION_FIELDS));
            appended_ids.add(old_remote[remote_ctr].id);
        }
        
        // remove anything left over ... use local count rather than remote as we're still in a stage
        // where only the local messages are available
        for (; local_ctr < local_length; local_ctr++) {
            batch.add(new RemoveLocalEmailOperation(local_folder, old_local[local_ctr].id));
            removed_ids.add(old_local[local_ctr].id);
        }
        
        // execute them all at once
        yield batch.execute_all_async(cancellable);
        
        if (batch.get_first_exception_message() != null) {
            debug("Error while preparing opened folder %s: %s", to_string(),
                batch.get_first_exception_message());
        }
        
        // throw the first exception, if one occurred
        batch.throw_first_exception();
        
        // notify emails that have been removed (see note above about why not all Creates are
        // signalled)
        if (removed_ids.size > 0) {
            debug("Notifying of %d removed emails since %s last seen", removed_ids.size, to_string());
            notify_email_removed(removed_ids);
        }
        
        // notify additions
        if (appended_ids.size > 0) {
            debug("Notifying of %d appended emails since %s last seen", appended_ids.size, to_string());
            notify_email_appended(appended_ids);
        }
        
        // notify flag changes
        if (flags_changed.size > 0) {
            debug("Notifying of %d changed flags since %s last seen", flags_changed.size, to_string());
            notify_email_flags_changed(flags_changed);
        }
        
        debug("Completed normalize_folder %s", to_string());
        
        return true;
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (opened)
            throw new EngineError.ALREADY_OPEN("Folder %s already open", to_string());
        
        opened = true;
        
        remote_semaphore = new Geary.NonblockingSemaphore();
        
        // start the replay queue
        replay_queue = new ReplayQueue(get_path().to_string());
        
        try {
            yield local_folder.open_async(readonly, cancellable);
        } catch (Error err) {
            notify_open_failed(OpenFailed.LOCAL_FAILED, err);
            
            // schedule close now
            close_internal_async.begin(CloseReason.LOCAL_ERROR, CloseReason.REMOTE_CLOSE, cancellable);
            
            throw err;
        }
        
        // Rather than wait for the remote folder to open (which blocks completion of this method),
        // attempt to open in the background and treat this folder as "opened".  If the remote
        // doesn't open, this folder remains open but only able to work with the local cache.
        //
        // Note that any use of remote_folder in this class should first call
        // wait_for_remote_to_open(), which uses a NonblockingSemaphore to indicate that the remote
        // is open (or has failed to open).  This allows for early calls to list and fetch emails
        // can work out of the local cache until the remote is ready.
        open_remote_async.begin(readonly, cancellable);
    }
    
    private async void open_remote_async(bool readonly, Cancellable? cancellable) {
        try {
            debug("Opening remote %s", local_folder.get_path().to_string());
            Imap.Folder folder = (Imap.Folder) yield remote.fetch_folder_async(local_folder.get_path(),
                cancellable);
            
            yield folder.open_async(readonly, cancellable);
            
            // allow subclasses to examine the opened folder and resolve any vital
            // inconsistencies
            if (yield normalize_folders(folder, cancellable)) {
                // update flags, properties, etc.
                yield local.update_folder_async(folder, cancellable);
                
                // signals
                folder.messages_appended.connect(on_remote_messages_appended);
                folder.message_at_removed.connect(on_remote_message_at_removed);
                folder.disconnected.connect(on_remote_disconnected);
                
                // state
                remote_count = folder.get_email_count();
                
                // all set; bless the remote folder as opened
                remote_folder = folder;
            } else {
                debug("Unable to prepare remote folder %s: prepare_opened_file() failed", to_string());
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
                : yield local_folder.get_email_count_async(cancellable);
        } catch (Error count_err) {
            debug("Unable to fetch count from local folder: %s", count_err.message);
            
            count = 0;
        }
        
        // notify any threads of execution waiting for the remote folder to open that the result
        // of that operation is ready
        try {
            remote_semaphore.notify();
        } catch (Error notify_err) {
            debug("Unable to fire semaphore notifying remote folder ready/not ready: %s",
                notify_err.message);
            
            remote_folder = null;
            remote_count = -1;
            
            notify_open_failed(Geary.Folder.OpenFailed.REMOTE_FAILED, notify_err);
            
            // schedule immediate close
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_ERROR, cancellable);
            
            return;
        }
        
        // notify any subscribers with similar information
        notify_opened(
            (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL,
            count);
    }
    
    // Returns true if the remote folder is ready, false otherwise
    internal async bool wait_for_remote_to_open(Cancellable? cancellable = null) throws Error {
        if (remote_folder != null)
            return true;
        
        yield remote_semaphore.wait_async(cancellable);
        
        return (remote_folder != null);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        yield close_internal_async(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_CLOSE, cancellable);
    }
    
    private async void close_internal_async(Folder.CloseReason local_reason, Folder.CloseReason remote_reason,
        Cancellable? cancellable) throws Error {
        if (!opened)
            return;
        
        // set this now to avoid multiple close_async(), particularly nested inside one of the signals
        // fired here
        opened = false;
        
        // Notify all callers waiting for the remote folder that it's not coming available
        Imap.Folder? closing_remote_folder = remote_folder;
        remote_folder = null;
        remote_count = -1;
        
        try {
            remote_semaphore.notify();
        } catch (Error err) {
            debug("close_internal_async: Unable to fire remote semaphore: %s", err.message);
        }
        
        if (closing_remote_folder != null) {
            closing_remote_folder.messages_appended.disconnect(on_remote_messages_appended);
            closing_remote_folder.message_at_removed.disconnect(on_remote_message_at_removed);
            closing_remote_folder.disconnected.disconnect(on_remote_disconnected);
            
            // to avoid keeping the caller waiting while the remote end closes, close it in the
            // background
            //
            // TODO: Problem with this is that we cannot effectively signal or report a close error,
            // because by the time this operation completes the folder is considered closed.  That
            // may not be important to most callers, however.
            if (remote_reason == CloseReason.REMOTE_CLOSE)
                closing_remote_folder.close_async.begin(cancellable);
            
            notify_closed(remote_reason);
        } else {
            notify_closed(Geary.Folder.CloseReason.REMOTE_CLOSE);
        }
        
        // close local store
        try {
            if (local_reason == CloseReason.LOCAL_CLOSE)
                yield local_folder.close_async(cancellable);
            
            notify_closed(local_reason);
        } catch (Error local_err) {
            debug("Error closing %s local store: %s", to_string(), local_err.message);
        }
        
        // Close the replay queues *after* the folder has been closed (in case any final upcalls
        // come and can be handled)
        try {
            if (replay_queue != null)
                yield replay_queue.close_async();
        } catch (Error replay_queue_err) {
            debug("Error closing %s replay queue: %s", to_string(), replay_queue_err.message);
        }
        
        replay_queue = null;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
    }
    
    private void on_remote_messages_appended(int total) {
        debug("on_remote_messages_appended: total=%d", total);
        replay_queue.schedule(new ReplayAppend(this, total));
    }
    
    // Need to prefetch at least an EmailIdentifier (and duplicate detection fields) to create a
    // normalized placeholder in the local database of the message, so all positions are
    // properly relative to the end of the message list; once this is done, notify user of new
    // messages.  If duplicates, create_email_async() will fall through to an updated merge,
    // which is exactly what we want.
    //
    // This MUST only be called from ReplayAppend.
    internal async void do_replay_appended_messages(int new_remote_count) {
        debug("do_replay_appended_messages %s: remote_count=%d new_remote_count=%d", to_string(),
            remote_count, new_remote_count);
        
        try {
            // If remote doesn't fully open, then don't fire signal, as we'll be unable to
            // normalize the folder
            if (!yield wait_for_remote_to_open())
                return;
            
            // normalize starting at the message *after* the highest position of the local store,
            // which has now changed
            Imap.MessageSet msg_set = new Imap.MessageSet.range_to_highest(remote_count + 1);
            Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(
                msg_set, Geary.Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, null);
            if (list != null && list.size > 0) {
                debug("do_replay_appended_messages: %d new messages from %s in %s", list.size,
                    msg_set.to_string(), to_string());
                
                // add new messages to local store
                Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>(
                    Hashable.hash_func, Equalable.equal_func);
                Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>(
                    Hashable.hash_func, Equalable.equal_func);
                foreach (Geary.Email email in list) {
                    // need to report both if it was created (not known before) and appended (which
                    // could mean created or simply a known email associated with this folder)
                    if (yield local_folder.create_email_async(email, null)) {
                        created.add(email.id);
                    } else {
                        debug("do_replay_appended_messages: appended email ID %s already known in account, associating with %s...",
                            email.id.to_string(), to_string());
                    }
                    
                    appended.add(email.id);
                }
                
                // save new remote count
                bool changed = (remote_count != new_remote_count);
                remote_count = new_remote_count;
                
                if (appended.size > 0)
                    notify_email_appended(appended);
                
                if (created.size > 0)
                    notify_email_locally_appended(created);
                
                if (changed)
                    notify_email_count_changed(remote_count, CountChangeReason.ADDED);
            } else {
                debug("do_replay_appended_messages: no new messages in %s in %s",
                    msg_set.to_string(), to_string());
            }
        } catch (Error err) {
            debug("Unable to normalize local store of newly appended messages to %s: %s",
                to_string(), err.message);
        }
    }
    
    private void on_remote_message_at_removed(int position, int total) {
        debug("on_remote_message_at_removed: position=%d total=%d", position, total);
        replay_queue.schedule(new ReplayRemoval(this, position, total));
    }
    
    // This MUST only be called from ReplayRemoval.
    internal async void do_replay_remove_message(int remote_position, int new_remote_count,
        Geary.EmailIdentifier? id) {
        debug("do_replay_remove_message: remote_position=%d new_remote_count=%d id=%s",
            remote_position, new_remote_count, (id != null) ? id.to_string() : "(null)");
        
        if (remote_position < 1)
            assert(id != null);
        else
            assert(new_remote_count >= 0);
        
        Geary.EmailIdentifier? owned_id = id;
        if (owned_id == null) {
            try {
                owned_id = yield local_folder.id_from_remote_position(remote_position, remote_count);
            } catch (Error err) {
                debug("Unable to determine ID of removed message #%d from %s: %s", remote_position,
                    to_string(), err.message);
            }
        }
        
        bool marked = false;
        if (owned_id != null) {
            debug("do_replay_remove_message: removing from local store Email ID %s", owned_id.to_string());
            try {
                // Reflect change in the local store and notify subscribers
                yield local_folder.remove_marked_email_async(owned_id, out marked, null);
                
                if (!marked)
                    notify_email_removed(new Geary.Singleton<Geary.EmailIdentifier>(owned_id));
            } catch (Error err2) {
                debug("Unable to remove message #%d from %s: %s", remote_position, to_string(),
                    err2.message);
            }
        }
        
        // save new remote count and notify of change
        bool changed = (remote_count != new_remote_count);
        remote_count = new_remote_count;
        
        if (!marked && changed)
            notify_email_count_changed(remote_count, CountChangeReason.REMOVED);
    }
    
    private void on_remote_disconnected(Geary.Folder.CloseReason reason) {
        debug("on_remote_disconnected: reason=%s", reason.to_string());
        replay_queue.schedule(new ReplayDisconnect(this, reason));
    }
    
    internal async void do_replay_remote_disconnected(Geary.Folder.CloseReason reason) {
        debug("do_replay_remote_disconnected reason=%s", reason.to_string());
        assert(reason == CloseReason.REMOTE_CLOSE || reason == CloseReason.REMOTE_ERROR);
        
        // because close_internal_async() issues ReceiveReplayQueue.close_async() (which cannot
        // be called from within a ReceiveReplayOperation), schedule the close rather than
        // yield for it ... can't simply call the async .begin variant because, depending on
        // the situation, it may not yield until it attempts to close the ReceiveReplayQueue,
        // which is the problem we're attempting to work around
        Idle.add(() => {
            close_internal_async.begin(CloseReason.LOCAL_CLOSE, reason, null);
            
            return false;
        });
    }
    
    public override async int get_email_count_async(Cancellable? cancellable = null) throws Error {
        check_open("get_email_count_async");
        
        // if connected or connecting, use stashed remote count (which is always kept current once
        // remote folder is opened)
        if (opened) {
            if (yield wait_for_remote_to_open(cancellable))
                return remote_count;
        }
        
        return yield local_folder.get_email_count_async(cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        if (count == 0)
            return null;
        
        // block on do_list_email_async(), using an accumulator to gather the emails and return
        // them all at once to the caller
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_async("list_email_async", low, count, required_fields, flags, accumulator,
            null, cancellable);
        
        return accumulator;
    }
    
    // TODO: Capture Error and report via EmailCallback.
    public override void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        // schedule do_list_email_async(), using the callback to drive availability of email
        do_list_email_async.begin("lazy_list_email", low, count, required_fields, flags, null, cb,
            cancellable);
    }
    
    private async void do_list_email_async(string method, int low, int count, Geary.Email.Field required_fields,
        Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator, EmailCallback? cb,
        Cancellable? cancellable) throws Error {
        check_open(method);
        check_flags(method, flags);
        check_span_specifiers(low, count);
        
        if (count == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        // Schedule list operation and wait for completion.
        ListEmail op = new ListEmail(this, low, count, required_fields, flags, accumulator, cb,
            cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_by_id_async("list_email_by_id_async", initial_id, count, required_fields,
            flags, list, null, cancellable);
        
        return (list.size > 0) ? list : null;
    }
    
    // TODO: Capture Error and report via EmailCallback.
    public override void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_id_async.begin("lazy_list_email_by_id", initial_id, count, required_fields,
            flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_id_async(string method, Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable) {
        try {
            yield do_list_email_by_id_async(method, initial_id, count, required_fields, flags, null, cb,
                cancellable);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    private async void do_list_email_by_id_async(string method, Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) throws Error {
        check_open(method);
        check_flags(method, flags);
        
        // listing by ID requires the remote to be open and fully synchronized, as there's no
        // reliable way to determine certain counts and positions without it
        //
        // TODO: Need to deal with this in a sane manner when offline
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("Must be synchronized with server for listing by ID");
        assert(remote_count >= 0);
        
        // Schedule list operation and wait for completion.
        ListEmailByID op = new ListEmailByID(this, initial_id, count, required_fields, flags, accumulator,
            cb, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        check_open("list_local_email_fields_async");
        
        return yield local_folder.list_email_fields_by_id_async(ids, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open("fetch_email_async");
        check_flags("fetch_email_async", flags);
        
        FetchEmail op = new FetchEmail(this, id, required_fields, flags, cancellable);
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
    
    public override async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        check_open("remove_email_async");
        
        replay_queue.schedule(new RemoveEmail(this, email_ids, cancellable));
    }
    
    private void check_open(string method) throws EngineError {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s failed: folder %s is not open", method, to_string());
    }
    
    private void check_flags(string method, Folder.ListFlags flags) throws EngineError {
        if (flags.is_all_set(Folder.ListFlags.LOCAL_ONLY) && flags.is_all_set(Folder.ListFlags.FORCE_UPDATE)) {
            throw new EngineError.BAD_PARAMETERS("%s %s failed: LOCAL_ONLY and FORCE_UPDATE are mutually exclusive",
                to_string(), method);
        }
    }
    
    // Converts a remote position to a local position, assuming that the remote has been completely
    // opened.  local_count must be supplied because that's not held by EngineFolder (unlike
    // remote_count).
    //
    // Returns a negative value if not available in local folder or remote is not open yet.
    internal int remote_position_to_local_position(int remote_pos, int local_count) {
        return (remote_count >= 0) ? remote_pos - (remote_count - local_count) : -1;
    }
    
    // Converts a local position to a remote position, assuming that the remote has been completely
    // opened.  See remote_position_to_local_position for more caveats.
    //
    // Returns a negative value if remote is not open.
    internal int local_position_to_remote_position(int local_pos, int local_count) {
        return (remote_count >= 0) ? remote_count - (local_count - local_pos) : -1;
    }
    
    // In order to maintain positions for all messages without storing all of them locally,
    // the database stores entries for the lowest requested email to the highest (newest), which
    // means there can be no gaps between the last in the database and the last on the server.
    // This method takes care of that.
    //
    // Note that this method doesn't return a remote_count because that's maintained by the
    // EngineFolder as a member variable.
    internal async void normalize_email_positions_async(int low, int count, out int local_count,
        Cancellable? cancellable) throws Error {
        if (!yield wait_for_remote_to_open(cancellable)) {
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());
        }
        
        int mutex_token = yield normalize_email_positions_mutex.claim_async(cancellable);
        
        Error? error = null;
        try {
            local_count = yield local_folder.get_email_count_async(cancellable);
            
            // fixup span specifier
            normalize_span_specifiers(ref low, ref count, remote_count);
            
            // Only prefetch properties for messages not being asked for by the user
            // (any messages that may be between the user's high and the remote's high, assuming that
            // all messages in local_count are contiguous from the highest email position, which is
            // taken care of my prepare_opened_folder_async())
            int high = (low + (count - 1)).clamp(1, remote_count);
            int local_low = (local_count > 0) ? (remote_count - local_count) + 1 : remote_count;
            if (high >= local_low) {
                normalize_email_positions_mutex.release(ref mutex_token);
                return;
            }
            
            int prefetch_count = local_low - high;
            
            debug("prefetching %d (%d) for %s (local_low=%d)", high, prefetch_count, to_string(),
                local_low);
            
            // Normalize the local folder by fetching EmailIdentifiers for all missing email as well
            // as fields for duplicate detection
            Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(
                new Imap.MessageSet.range(high, prefetch_count),
                Geary.Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, cancellable);
            if (list == null || list.size != prefetch_count) {
                throw new EngineError.BAD_PARAMETERS("Unable to prefetch %d email starting at %d in %s",
                    count, low, to_string());
            }
            
            NonblockingBatch batch = new NonblockingBatch();
            
            foreach (Geary.Email email in list) {
                batch.add(new CreateLocalEmailOperation(local_folder, email,
                    Geary.Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION));
            }
            
            yield batch.execute_all_async(cancellable);
            batch.throw_first_exception();
            
            // Collect which EmailIdentifiers were created and report them
            Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>(
                Hashable.hash_func, Equalable.equal_func);
            foreach (int id in batch.get_ids()) {
                CreateLocalEmailOperation? op = batch.get_operation(id) as CreateLocalEmailOperation;
                if (op != null && op.created)
                    created_ids.add(op.email.id);
            }
            
            if (created_ids.size > 0)
                notify_email_locally_appended(created_ids);
        } catch (Error e) {
            local_count = 0; // prevent compiler warning
            error = e;
        }
        
        normalize_email_positions_mutex.release(ref mutex_token);
        
        if (error != null)
            throw error;
    }
    
    public override async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) throws Error {
        check_open("mark_email_async");
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());

        replay_queue.schedule(new MarkEmail(this, to_mark, flags_to_add, flags_to_remove,
            cancellable));
    }

    public override async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("copy_email_async");
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());

        replay_queue.schedule(new CopyEmail(this, to_copy, destination));
    }

    public override async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("move_email_async");
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());

        replay_queue.schedule(new MoveEmail(this, to_move, destination));
    }

    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> changed) {
        notify_email_flags_changed(changed);
    }
}

