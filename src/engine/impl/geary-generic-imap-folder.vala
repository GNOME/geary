/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapFolder : Geary.AbstractFolder {
    private const int REMOTE_FETCH_CHUNK_COUNT = 50;
    
    internal Sqlite.Folder local_folder  { get; protected set; }
    internal Imap.Folder? remote_folder { get; protected set; default = null; }
    internal SpecialFolder? special_folder { get; protected set; default = null; }
    internal int remote_count { get; private set; default = -1; }
    
    private Imap.Account remote;
    private Sqlite.Account local;
    private EmailFlagWatcher email_flag_watcher;
    private EmailPrefetcher email_prefetcher;
    private bool opened = false;
    private NonblockingSemaphore remote_semaphore;
    private ReceiveReplayQueue? recv_replay_queue = null;
    private SendReplayQueue? send_replay_queue = null;
    private NonblockingMutex normalize_email_positions_mutex = new NonblockingMutex();
    
    public GenericImapFolder(Imap.Account remote, Sqlite.Account local, Sqlite.Folder local_folder,
        SpecialFolder? special_folder) {
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
    
    public override async bool create_email_async(Geary.Email email, Cancellable? cancellable) throws Error {
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
            debug("No earliest UID in %s, nothing to update", to_string());
            
            return true;
        }
        
        int64 full_uid_count = local_properties.uid_next.value - 1 - earliest_uid.value;
        
        // If no UID's, nothing to update
        if (full_uid_count <= 0 || (full_uid_count > int.MAX)) {
            debug("No valid UID range in local folder %s (count=%lld), nothing to update", to_string(),
                full_uid_count);
            
            return true;
        }
        
        Geary.Imap.EmailIdentifier earliest_id = new Geary.Imap.EmailIdentifier(earliest_uid);
        
        // Get the local emails in the range
        Gee.List<Geary.Email>? old_local = yield local_folder.list_email_by_id_async(
            earliest_id, int.MAX, Geary.Email.Field.PROPERTIES, Geary.Folder.ListFlags.NONE,
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
            new Imap.MessageSet.uid_range_to_highest(earliest_uid), Geary.Email.Field.PROPERTIES,
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
                    batch.add(new CreateLocalEmailOperation(local_folder, remote_email));
                    flags_changed.set(remote_email.id, remote_email.properties.email_flags);
                }
                
                remote_ctr++;
                local_ctr++;
            } else if (remote_uid.value < local_uid.value) {
                // one we'd not seen before is present, add and move to next remote
                batch.add(new CreateLocalEmailOperation(local_folder, remote_email));
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
            batch.add(new CreateLocalEmailOperation(local_folder, old_remote[remote_ctr]));
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
        
        remote_semaphore = new Geary.NonblockingSemaphore();
        
        // start the replay queues
        recv_replay_queue = new ReceiveReplayQueue();
        send_replay_queue = new SendReplayQueue();
        
        yield local_folder.open_async(readonly, cancellable);
        
        // Rather than wait for the remote folder to open (which blocks completion of this method),
        // attempt to open in the background and treat this folder as "opened".  If the remote
        // doesn't open, this folder remains open but only able to work with the local cache.
        //
        // Note that any use of remote_folder in this class should first call
        // wait_for_remote_to_open(), which uses a NonblockingSemaphore to indicate that the remote
        // is open (or has failed to open).  This allows for early calls to list and fetch emails
        // can work out of the local cache until the remote is ready.
        open_remote_async.begin(readonly, cancellable);
        
        opened = true;
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
                
                // state
                remote_count = folder.get_email_count();
                
                // all set; bless the remote folder as opened
                remote_folder = folder;
            } else {
                debug("Unable to prepare remote folder %s: prepare_opened_file() failed", to_string());
            }
        } catch (Error open_err) {
            debug("Unable to open or prepare remote folder %s: %s", to_string(), open_err.message);
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
        Error error = null;
        try {
            yield local_folder.close_async(cancellable);
            
            // if the remote folder is open, close it in the background so the caller isn't waiting for
            // this method to complete (much like open_async())
            if (remote_folder != null) {
                yield remote_semaphore.wait_async();
                
                Imap.Folder? folder = remote_folder;
                remote_folder = null;
                
                // signals
                folder.messages_appended.disconnect(on_remote_messages_appended);
                folder.message_at_removed.disconnect(on_remote_message_at_removed);
                
                folder.close_async.begin(cancellable);
            }
        } catch (Error e) {
            error = e;
        }
        
        // Close the replay queues *after* the folder has been closed (in case any final upcalls
        // come and can be handled)
        try {
            if (recv_replay_queue != null)
                yield recv_replay_queue.close_async();
        } catch (Error e) {
            if (error != null)
                error = e;
        }
        
        try {
            if (send_replay_queue != null)
                yield send_replay_queue.close_async();
        } catch (Error e) {
            if (error != null)
                error = e;
        }
        
        recv_replay_queue = null;
        send_replay_queue = null;
        
        notify_closed(CloseReason.FOLDER_CLOSED);
        
        opened = false;
        
        if (error != null)
            throw error;
    }
    
    private void on_remote_messages_appended(int total) {
        debug("on_remote_messages_appended: total=%d", total);
        recv_replay_queue.schedule(new ReplayAppend(this, total));
    }
    
    // Need to prefetch at least an EmailIdentifier (and duplicate detection fields) to create a
    // normalized placeholder in the local database of the message, so all positions are
    // properly relative to the end of the message list; once this is done, notify user of new
    // messages.  If duplicates, create_email_async() will fall through to an updated merge,
    // which is exactly what we want.
    //
    // This MUST only be called from ReplayAppend.
    internal async void do_replay_appended_messages(int new_remote_count) {
        // this only works when the list is grown
        if (remote_count >= new_remote_count) {
            debug("Message reported appended by server but remote count %d already known",
                remote_count);
            
            return;
        }
        
        try {
            // If remote doesn't fully open, then don't fire signal, as we'll be unable to
            // normalize the folder
            if (!yield wait_for_remote_to_open())
                return;
            
            // normalize starting at the message *after* the highest position of the local store,
            // which has now changed
            Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(
                new Imap.MessageSet.range_to_highest(remote_count + 1),
                Geary.Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, null);
            assert(list != null && list.size > 0);
            
            Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>(
                Hashable.hash_func, Equalable.equal_func);
            Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>(
                Hashable.hash_func, Equalable.equal_func);
            foreach (Geary.Email email in list) {
                debug("Creating Email ID %s", email.id.to_string());
                
                // need to report both if it was created (not known before) and appended (which
                // could mean created or simply a known email associated with this folder)
                if (yield local_folder.create_email_async(email, null))
                    created.add(email.id);
                
                appended.add(email.id);
            }
            
            // save new remote count
            remote_count = new_remote_count;
            
            notify_email_appended(appended);
            if (created.size > 0)
                notify_email_locally_appended(created);
        } catch (Error err) {
            debug("Unable to normalize local store of newly appended messages to %s: %s",
                to_string(), err.message);
        }
    }
    
    private void on_remote_message_at_removed(int position, int total) {
        debug("on_remote_message_at_removed: position=%d total=%d", position, total);
        recv_replay_queue.schedule(new ReplayRemoval(this, position, total));
    }
    
    // This MUST only be called from ReplayRemoval.
    internal async void do_replay_remove_message(int remote_position, int new_remote_count,
        Geary.EmailIdentifier? id) {
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
            debug("Removing from local store Email ID %s", owned_id.to_string());
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
        remote_count = new_remote_count;
        
        if (!marked)
            notify_email_count_changed(remote_count, CountChangeReason.REMOVED);
    }
    
    public override async int get_email_count_async(Cancellable? cancellable = null) throws Error {
        // TODO: Use monitoring to avoid round-trip to the server
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
        
        // if connected, use stashed remote count (which is always kept current once remote folder
        // is opened)
        if (yield wait_for_remote_to_open(cancellable))
            return remote_count;
        
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
        yield do_list_email_async(low, count, required_fields, accumulator, null, cancellable,
            flags.is_any_set(Folder.ListFlags.LOCAL_ONLY), flags.is_any_set(Folder.ListFlags.FORCE_UPDATE));
        
        return accumulator;
    }
    
    // TODO: Capture Error and report via EmailCallback.
    public override void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        // schedule do_list_email_async(), using the callback to drive availability of email
        do_list_email_async.begin(low, count, required_fields, null, cb, cancellable,
            flags.is_all_set(Folder.ListFlags.LOCAL_ONLY), flags.is_any_set(Folder.ListFlags.FORCE_UPDATE));
    }
    
    // TODO: A great optimization would be to fetch message "fragments" from the local database
    // (retrieve all stored fields that match required_fields, although not all of required_fields
    // are present) and only fetch the missing parts from the remote; to do this right, requests
    // would have to be parallelized.
    private async void do_list_email_async(int low, int count, Geary.Email.Field required_fields,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable,
        bool local_only, bool remote_only) throws Error {
        check_span_specifiers(low, count);
        
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
        
        if (local_only && remote_only)
            throw new EngineError.BAD_PARAMETERS("local_only and remote_only are mutually exlusive");
        
        if (count == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        // Schedule list operation and wait for completion.
        ListEmail op = new ListEmail(this, low, count, required_fields, accumulator, cb, cancellable,
            local_only, remote_only);
        send_replay_queue.schedule(op);
        yield op.wait_for_ready();
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_by_id_async(initial_id, count, required_fields, list, null, cancellable,
            flags.is_all_set(Folder.ListFlags.LOCAL_ONLY), flags.is_all_set(Folder.ListFlags.FORCE_UPDATE),
            flags.is_all_set(Folder.ListFlags.EXCLUDING_ID));
        
        return (list.size > 0) ? list : null;
    }
    
    public override void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_id_async.begin(initial_id, count, required_fields, cb, cancellable,
            flags.is_all_set(Folder.ListFlags.LOCAL_ONLY), flags.is_all_set(Folder.ListFlags.FORCE_UPDATE),
            flags.is_all_set(Folder.ListFlags.EXCLUDING_ID));
    }
    
    private async void do_lazy_list_email_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, EmailCallback cb, Cancellable? cancellable, bool local_only,
        bool remote_only, bool excluding_id) {
        try {
            yield do_list_email_by_id_async(initial_id, count, required_fields, null, cb, cancellable,
                local_only, remote_only, excluding_id);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    private async void do_list_email_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Gee.List<Geary.Email>? accumulator, EmailCallback? cb,
        Cancellable? cancellable, bool local_only, bool remote_only, bool excluding_id) throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
        
        // listing by ID requires the remote to be open and fully synchronized, as there's no
        // reliable way to determine certain counts and positions without it
        //
        // TODO: Need to deal with this in a sane manner when offline
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("Must be synchronized with server for listing by ID");
        
        assert(remote_count >= 0);
        
        // Schedule list operation and wait for completion.
        ListEmailByID op = new ListEmailByID(this, initial_id, count, required_fields, accumulator,
            cb, cancellable, local_only, remote_only, excluding_id);
        send_replay_queue.schedule(op);
        yield op.wait_for_ready();
    }
    
    internal async Gee.List<Geary.Email>? remote_list_email(int[] needed_by_position,
        Geary.Email.Field required_fields, EmailCallback? cb, Cancellable? cancellable) throws Error {
        // possible to call remote multiple times, wait for it to open once and go
        if (!yield wait_for_remote_to_open(cancellable))
            return null;
        
        debug("Background fetching %d emails for %s", needed_by_position.length, to_string());
        
        // Always get the flags for normalization and whatever the local store requires for duplicate
        // detection
        Geary.Email.Field full_fields =
            required_fields | Geary.Email.Field.PROPERTIES | Geary.Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION;
        
        Gee.List<Geary.Email> full = new Gee.ArrayList<Geary.Email>();
        
        // pull in reverse order because callers to this method tend to order messages from oldest
        // to newest, but for user satisfaction, should be fetched from newest to oldest
        int remaining = needed_by_position.length;
        while (remaining > 0) {
            // if a callback is specified, pull the messages down in chunks, so they can be reported
            // incrementally
            int[] list;
            if (cb != null) {
                int list_count = int.min(REMOTE_FETCH_CHUNK_COUNT, remaining);
                list = needed_by_position[remaining - list_count:remaining];
                assert(list.length == list_count);
            } else {
                list = needed_by_position;
            }
            
            // pull from server
            Gee.List<Geary.Email>? remote_list = yield remote_folder.list_email_async(
                new Imap.MessageSet.sparse(list), full_fields, cancellable);
            
            if (remote_list == null || remote_list.size == 0)
                break;
            
            // if any were fetched, store locally ... must be stored before they can be reported
            // via the callback because if, in the context of the callback, these messages are
            // requested, they won't be found in the database, causing another remote fetch to
            // occur
            NonblockingBatch batch = new NonblockingBatch();
            
            foreach (Geary.Email email in remote_list)
                batch.add(new CreateLocalEmailOperation(local_folder, email));
            
            yield batch.execute_all_async(cancellable);
            
            batch.throw_first_exception();
            
            // report locally added (non-duplicate, not unknown) emails
            Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>(
                Hashable.hash_func, Equalable.equal_func);
            foreach (int id in batch.get_ids()) {
                CreateLocalEmailOperation? op = batch.get_operation(id) as CreateLocalEmailOperation;
                if (op != null && op.created)
                    created_ids.add(op.email.id);
            }
            
            if (created_ids.size > 0)
                notify_email_locally_appended(created_ids);
            
            if (cb != null)
                cb(remote_list, null);
            
            full.add_all(remote_list);
            
            remaining -= list.length;
        }
        
        return full;
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", to_string());
        
        return yield local_folder.list_email_fields_by_id_async(ids, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", to_string());
        
        // If not forcing an update, see if the email is present in the local store
        if (!flags.is_all_set(ListFlags.FORCE_UPDATE)) {
            try {
                return yield local_folder.fetch_email_async(id, fields, cancellable);
            } catch (Error err) {
                // If NOT_FOUND or INCOMPLETE_MESSAGE, then fall through, otherwise return to sender
                if (!(err is Geary.EngineError.NOT_FOUND) && !(err is Geary.EngineError.INCOMPLETE_MESSAGE))
                    throw err;
            }
        }
        
        // If local only and not found in local store, throw NOT_FOUND; there is no fallback and
        // this method does not return null
        if (flags.is_all_set(ListFlags.LOCAL_ONLY)) {
            throw new EngineError.NOT_FOUND("Email %s with fields %Xh not found in %s", id.to_string(),
                fields, to_string());
        }
        
        // To reach here indicates either the local version does not have all the requested fields
        // or it's simply not present.  If it's not present, want to ensure that the Message-ID
        // is requested, as that's a good way to manage duplicate messages in the system
        Geary.Email.Field available_fields;
        bool is_present = yield local_folder.is_email_present_async(id, out available_fields,
            cancellable);
        if (!is_present)
            fields = fields.set(Geary.Email.Field.REFERENCES);
        
        // fetch from network
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());
        
        Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(new Imap.MessageSet.email_id(id),
            fields, cancellable);
        
        if (list == null || list.size != 1)
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s", id.to_string(), to_string());
        
        // save to local store
        Geary.Email email = list[0];
        if (yield local_folder.create_email_async(email, cancellable))
            notify_email_locally_appended(new Geary.Singleton<Geary.EmailIdentifier>(email.id));
        
        return email;
    }
    
    public override async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", to_string());
        
        send_replay_queue.schedule(new RemoveEmail(this, email_ids, cancellable));
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
            
            foreach (Geary.Email email in list)
                batch.add(new CreateLocalEmailOperation(local_folder, email));
            
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
        if (!yield wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", remote.to_string());
        
        send_replay_queue.schedule(new MarkEmail(this, to_mark, flags_to_add, flags_to_remove,
            cancellable));
    }
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> changed) {
        notify_email_flags_changed(changed);
    }
}

