/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GenericFolder : Geary.AbstractFolder, Geary.FolderSupport.Copy,
    Geary.FolderSupport.Mark, Geary.FolderSupport.Move {
    internal const int REMOTE_FETCH_CHUNK_COUNT = 50;
    private const int NORMALIZATION_CHUNK_COUNT = 5000;
    
    private const Geary.Email.Field NORMALIZATION_FIELDS =
        Geary.Email.Field.PROPERTIES | Geary.Email.Field.FLAGS | ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION;
    private const Geary.Email.Field FAST_NORMALIZATION_FIELDS =
        Geary.Email.Field.PROPERTIES | ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION;
    
    private class EnginePositionToUIDConverter : Object, Imap.PositionToUIDConverter {
        public weak GenericFolder owner;
        
        public EnginePositionToUIDConverter(GenericFolder owner) {
            this.owner = owner;
        }
        
        public async Imap.UID? convert_async(Imap.MessageNumber pos, Cancellable? cancellable)
            throws Error {
            debug("convert_async: pos=%s", pos.to_string());
            
            int local_count = yield owner.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                cancellable);
            debug("convert_async: local_count=%d", local_count);
            if (local_count <= 0)
                return null;
            
            int local_pos = remote_position_to_local_position(pos.value, local_count,
                owner.remote_count);
            debug("convert_async: local_pos=%d", local_pos);
            if (local_pos < 0)
                return null;
            
            Gee.List<Geary.Email>? email = yield owner.local_folder.list_email_async(local_pos, 1,
                Geary.Email.Field.NONE, ImapDB.Folder.ListFlags.NONE, cancellable);
            debug("convert_async: email=%s", (email != null) ? email.size.to_string() : "(null)");
            if (email == null || email.size == 0)
                return null;
            
            Imap.EmailIdentifier id = (Imap.EmailIdentifier) email[0].id;
            
            debug("convert_async: uid=%s", id.uid.to_string());
            
            return id.uid;
        }
    }
    
    public override Account account { get { return _account; } }
    internal ImapDB.Folder local_folder  { get; protected set; }
    internal Imap.Folder? remote_folder { get; protected set; default = null; }
    internal EmailPrefetcher email_prefetcher { get; private set; }
    internal EmailFlagWatcher email_flag_watcher;
    
    private weak GenericAccount _account;
    private Imap.Account remote;
    private ImapDB.Account local;
    private SpecialFolderType special_folder_type;
    private int open_count = 0;
    private Nonblocking.ReportingSemaphore<bool>? remote_semaphore = null;
    private ReplayQueue? replay_queue = null;
    private Nonblocking.Mutex normalize_email_positions_mutex = new Nonblocking.Mutex();
    private int remote_count = -1;
    
    public GenericFolder(GenericAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        _account = account;
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        this.special_folder_type = special_folder_type;
        
        email_flag_watcher = new EmailFlagWatcher(this);
        email_flag_watcher.email_flags_changed.connect(on_email_flags_changed);
        
        email_prefetcher = new EmailPrefetcher(this);
    }
    
    ~EngineFolder() {
        if (open_count > 0)
            warning("Folder %s destroyed without closing", to_string());
    }
    
    public override Geary.FolderPath get_path() {
        return local_folder.get_path();
    }
    
    public override Geary.FolderProperties get_properties() {
        // Get properties in order of authoritativeness:
        // - From open remote folder
        // - Fetch from local store
        if (remote_folder != null && get_open_state() == OpenState.BOTH)
            return remote_folder.properties;
        
        return local_folder.get_properties();
    }
    
    public override Geary.SpecialFolderType get_special_folder_type() {
        return special_folder_type;
    }
    
    public void set_special_folder_type(SpecialFolderType new_type) {
        if (special_folder_type == new_type)
            return;
        
        Geary.SpecialFolderType old_type = special_folder_type;
        special_folder_type = new_type;
        
        notify_special_folder_type_changed(old_type, new_type);
    }
    
    public override Geary.Folder.OpenState get_open_state() {
        if (open_count == 0)
            return Geary.Folder.OpenState.CLOSED;
        
        if (local_folder.opened)
            return (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL;
        else if (remote_folder != null)
            return Geary.Folder.OpenState.REMOTE;
        
        // opened flag set but neither open; indicates opening state
        return Geary.Folder.OpenState.OPENING;
    }
    
    // Returns the synchronized remote count (-1 if not opened) and the last seen remote count (stored
    // locally, -1 if not available)
    //
    // Return value is the remote_count, unless the remote is unopened, in which case it's the
    // last_seen_remote_count (which may be -1).
    internal int get_remote_counts(out int remote_count, out int last_seen_remote_count) {
        remote_count = this.remote_count;
        last_seen_remote_count = local_folder.get_properties().select_examine_messages;
        if (last_seen_remote_count < 0)
            last_seen_remote_count = local_folder.get_properties().status_messages;
        
        return (remote_count >= 0) ? remote_count : last_seen_remote_count;
    }
    
    private async bool normalize_folders(Geary.Imap.Folder remote_folder, Geary.Folder.OpenFlags open_flags,
        Cancellable? cancellable) throws Error {
        bool is_fast_open = open_flags.is_any_set(Geary.Folder.OpenFlags.FAST_OPEN);
        if (is_fast_open)
            debug("fast-open normalize_folders %s", to_string());
        else
            debug("normalize_folders %s", to_string());
        
        Geary.Imap.FolderProperties local_properties = local_folder.get_properties();
        Geary.Imap.FolderProperties remote_properties = remote_folder.properties;
        
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
            error("UID validity changed: %s -> %s", local_properties.uid_validity.value.to_string(),
                remote_properties.uid_validity.value.to_string());
        }
        
        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        Geary.Imap.UID? earliest_uid = yield local_folder.get_earliest_uid_async(cancellable);
        Geary.Imap.UID? latest_uid = yield local_folder.get_latest_uid_async(cancellable);
        
        // verify still open
        check_open("normalize_folders (local earliest UID)");
        
        // if no earliest UID, that means no messages in local store, so nothing to update
        if (earliest_uid == null || !earliest_uid.is_valid() || latest_uid == null || !latest_uid.is_valid()) {
            debug("No earliest and/or latest UID in local %s, nothing to normalize", to_string());
            
            return true;
        }
        
        // if UIDNEXT has changed, that indicates messages have been appended (and possibly removed)
        int64 uidnext_diff = remote_properties.uid_next.value - local_properties.uid_next.value;
        
        // fast-open means no updating of flags, so if UIDNEXT is the same as last time AND the total count
        // of email is the same, then nothing has been added or removed (but flags may have changed)
        if (is_fast_open && uidnext_diff == 0 && local_properties.email_total == remote_properties.email_total) {
            debug("No messages added/removed in fast-open of %s, normalization completed", to_string());
            
            return true;
        }
        
        Gee.Collection<Geary.EmailIdentifier> all_appended_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Collection<Geary.EmailIdentifier> all_locally_appended_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Collection<Geary.EmailIdentifier> all_removed_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> all_flags_changed = new Gee.HashMap<Geary.EmailIdentifier,
            Geary.EmailFlags>();
        
        // to match all flags and find all removed interior to the local store's vector of messages, start from
        // local earliest message and work upwards
        Geary.Imap.EmailIdentifier current_start_id = new Geary.Imap.EmailIdentifier(earliest_uid, local_folder.get_path());
        
        // if fast-open and the difference in UIDNEXT values equals the difference in message count, then only
        // an append could have happened, so only pull in the new messages ... note that this is not foolproof,
        // as UIDs are not guaranteed to increase by 1; however, this is a standard implementation practice,
        // so it's worth looking for
        //
        // (Also, this cannot fail; if this situation exists, then it cannot by definition indicate another
        // situation, esp. messages being removed.)
        if (is_fast_open) {
            if (uidnext_diff == (remote_properties.select_examine_messages - local_properties.select_examine_messages)) {
                current_start_id = new Geary.Imap.EmailIdentifier(latest_uid.next(), local_folder.get_path());
                
                debug("fast-open %s: Messages only appended (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s), only gathering new mail at %s",
                    to_string(), local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
                    local_properties.select_examine_messages, remote_properties.select_examine_messages, uidnext_diff.to_string(),
                    current_start_id.to_string());
            } else {
                debug("fast-open %s: Messages appended/removed (local/remote UIDNEXT=%s/%s total=%d/%d diff=%s)", to_string(),
                    local_properties.uid_next.to_string(), remote_properties.uid_next.to_string(),
                    local_properties.select_examine_messages, remote_properties.select_examine_messages, uidnext_diff.to_string());
            }
        }
        
        Geary.Email.Field normalization_fields = is_fast_open ? FAST_NORMALIZATION_FIELDS : NORMALIZATION_FIELDS;
        
        for (;;) {
            // Get the local emails in the range ... use PARTIAL_OK to ensure all emails are normalized
            Gee.List<Geary.Email>? old_local = yield local_folder.list_email_by_id_async(
                current_start_id, NORMALIZATION_CHUNK_COUNT, normalization_fields,
                ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);
            
            // verify still open
            check_open("normalize_folders (list local)");
            
            // be sure they're sorted from earliest to latest
            if (old_local != null)
                old_local.sort(Geary.Email.compare_id_ascending);
            
            int local_length = (old_local != null) ? old_local.size : 0;
            
            // if nothing, keep going because there could be remote messages to pull down
            Geary.Imap.EmailIdentifier current_end_id = new Geary.Imap.EmailIdentifier(
                new Imap.UID(current_start_id.uid.value + NORMALIZATION_CHUNK_COUNT),
                current_start_id.get_folder_path());
            Imap.MessageSet msg_set = new Imap.MessageSet.uid_range(current_start_id.uid, current_end_id.uid);
            
            // Get the remote emails in the range to either add any not known, remove deleted messages,
            // and update the flags of the remainder
            Gee.List<Geary.Email>? old_remote = yield remote_folder.list_email_async(msg_set,
                normalization_fields, cancellable);
            
            // verify still open after I/O
            check_open("normalize_folders (list remote)");
            
            // sort earliest to latest
            if (old_remote != null)
                old_remote.sort(Geary.Email.compare_id_ascending);
            
            int remote_length = (old_remote != null) ? old_remote.size : 0;
            
            int remote_ctr = 0;
            int local_ctr = 0;
            Gee.ArrayList<Geary.Email> to_create_or_merge = new Gee.ArrayList<Geary.Email>();
            Gee.ArrayList<Geary.EmailIdentifier> appended_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
            Gee.ArrayList<Geary.EmailIdentifier> removed_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
            for (;;) {
                Geary.Email? remote_email = null;
                Geary.Imap.UID? remote_uid = null;
                if (old_remote != null && remote_ctr < remote_length) {
                    remote_email = old_remote[remote_ctr];
                    remote_uid = ((Geary.Imap.EmailIdentifier) remote_email.id).uid;
                }
                
                Geary.Email? local_email = null;
                Geary.Imap.UID? local_uid = null;
                if (old_local != null && local_ctr < local_length) {
                    local_email = old_local[local_ctr];
                    local_uid = ((Geary.Imap.EmailIdentifier) local_email.id).uid;
                }
                
                if (local_email == null && remote_email == null)
                    break;
                
                if (remote_uid != null && local_uid != null && remote_uid.value == local_uid.value) {
                    // only update flags if not doing a fast-open
                    if (!is_fast_open) {
                        // same, update flags (if changed) and move on
                        // Because local is PARTIAL_OK, EmailFlags may not be present
                        Geary.Imap.EmailFlags? local_email_flags = (Geary.Imap.EmailFlags) local_email.email_flags;
                        Geary.Imap.EmailFlags remote_email_flags = (Geary.Imap.EmailFlags) remote_email.email_flags;
                        
                        if ((local_email_flags == null) || !local_email_flags.equal_to(remote_email_flags)) {
                            // check before writebehind
                            if (replay_queue.query_local_writebehind_operation(ReplayOperation.WritebehindOperation.UPDATE_FLAGS,
                                remote_email.id, (Imap.EmailFlags) remote_email.email_flags)) {
                                to_create_or_merge.add(remote_email);
                                all_flags_changed.set(remote_email.id, remote_email.email_flags);
                                
                                Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: merging remote ID %s",
                                    to_string(), remote_email.id.to_string());
                            } else {
                                Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: writebehind cancelled for merge of %s",
                                    to_string(), remote_email.id.to_string());
                            }
                        }
                    }
                    
                    remote_ctr++;
                    local_ctr++;
                } else if (remote_uid != null && (local_uid == null || remote_uid.value < local_uid.value)) {
                    // remote we'd not seen before is present, add and move to next remote
                    // check for writebehind before doing
                    if (replay_queue.query_local_writebehind_operation(ReplayOperation.WritebehindOperation.CREATE,
                        remote_email.id, null)) {
                        to_create_or_merge.add(remote_email);
                        appended_ids.add(remote_email.id);
                        
                        Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: appending inside remote ID %s",
                            to_string(), remote_email.id.to_string());
                    } else {
                        Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: writebehind cancelled for inside append of %s",
                            to_string(), remote_email.id.to_string());
                    }
                    
                    remote_ctr++;
                } else {
                    if (remote_uid != null && local_uid != null)
                        assert(remote_uid.value > local_uid.value);
                    else
                        assert(local_uid != null);
                    
                    // local's email on the server has been removed, remove locally
                    // check writebehind first
                    if (replay_queue.query_local_writebehind_operation(ReplayOperation.WritebehindOperation.REMOVE,
                        local_email.id, null)) {
                        removed_ids.add(local_email.id);
                        
                        Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: removing inside local ID %s",
                            to_string(), local_email.id.to_string());
                    } else {
                        Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: writebehind cancelled for remove of %s",
                            to_string(), local_email.id.to_string());
                    }
                    
                    local_ctr++;
                }
            }
            
            // add newly-discovered emails to local store ... only report these as appended; earlier
            // CreateEmailOperations were updates of emails existing previously or additions of emails
            // that were on the server earlier but not stored locally (i.e. this value represents emails
            // added to the top of the stack)
            for (; remote_ctr < remote_length; remote_ctr++) {
                Geary.Email remote_email = old_remote[remote_ctr];
                
                // again, have to check for writebehind
                if (replay_queue.query_local_writebehind_operation(ReplayOperation.WritebehindOperation.CREATE,
                    remote_email.id, null)) {
                    to_create_or_merge.add(remote_email);
                    appended_ids.add(remote_email.id);
                    
                    Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: appending outside remote %s",
                        to_string(), remote_email.id.to_string());
                } else {
                    Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: writebehind cancelled for outside append of %s",
                        to_string(), remote_email.id.to_string());
                }
            }
            
            // remove anything left over ... use local count rather than remote as we're still in a stage
            // where only the local messages are available
            for (; local_ctr < local_length; local_ctr++) {
                Geary.Email local_email = old_local[local_ctr];
                
                // again, check for writebehind
                if (replay_queue.query_local_writebehind_operation(ReplayOperation.WritebehindOperation.REMOVE,
                    local_email.id, null)) {
                    removed_ids.add(local_email.id);
                    
                    Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: removing outside remote %s",
                        to_string(), local_email.id.to_string());
                } else {
                    Logging.debug(Logging.Flag.FOLDER_NORMALIZATION, "%s: writebehind cancelled for outside remove %s",
                        to_string(), local_email.id.to_string());
                }
            }
            
            // from here on the only write operations being performed on the folder are creating or updating
            // existing emails or removing them, both operations being performed using EmailIdentifiers
            // rather than positional addressing ... this means the order of operation is not important
            // and can be batched up rather than performed serially
            Nonblocking.Batch batch = new Nonblocking.Batch();
            
            CreateLocalEmailOperation? create_op = null;
            if (to_create_or_merge.size > 0) {
                create_op = new CreateLocalEmailOperation(local_folder, to_create_or_merge,
                    NORMALIZATION_FIELDS);
                batch.add(create_op);
            }
            
            if (removed_ids.size > 0)
                batch.add(new RemoveLocalEmailOperation(local_folder, removed_ids));
            
            // execute them all at once
            if (batch.size > 0) {
                yield batch.execute_all_async(cancellable);
                
                // check still open a third time
                check_open("normalize_folders (batch execute)");
            
                if (batch.get_first_exception_message() != null) {
                    debug("Error while preparing opened folder %s: %s", to_string(),
                        batch.get_first_exception_message());
                }
                
                // throw the first exception, if one occurred
                batch.throw_first_exception();
            }
            
            // add changes to master lists
            all_removed_ids.add_all(removed_ids);
            all_appended_ids.add_all(appended_ids);
            
            // look for local additions (email not known to the local store) to signal
            if (create_op != null) {
                foreach (Geary.Email email in create_op.created.keys) {
                    // true means created, not merged
                    if (create_op.created.get(email))
                        all_locally_appended_ids.add(email.id);
                }
            }
            
            // increment the next start id after the current end, as it now points to the last id examined
            current_start_id = new Geary.Imap.EmailIdentifier(current_end_id.uid.next(),
                current_start_id.folder_path);
            
            // if gone past both local and remote extremes, time to exit
            // TODO: If UIDNEXT isn't available on server, will need to fetch the highest UID
            if (current_start_id.uid.compare_to(latest_uid) >= 0
                && current_start_id.uid.compare_to(remote_properties.uid_next) >= 0)
                break;
        }
        
        // notify emails that have been removed (see note above about why not all Creates are
        // signalled)
        if (all_removed_ids.size > 0) {
            debug("Notifying of %d removed emails since %s last seen", all_removed_ids.size, to_string());
            notify_email_removed(all_removed_ids);
        }
        
        // notify local additions
        if (all_locally_appended_ids.size > 0) {
            debug("Notifying of %d locally appended emails since %s last seen", all_locally_appended_ids.size,
                to_string());
            notify_email_locally_appended(all_locally_appended_ids);
        }
        
        // notify additions
        if (all_appended_ids.size > 0) {
            debug("Notifying of %d appended emails since %s last seen", all_appended_ids.size, to_string());
            notify_email_appended(all_appended_ids);
        }
        
        // notify flag changes
        if (all_flags_changed.size > 0) {
            debug("Notifying of %d changed flags since %s last seen", all_flags_changed.size, to_string());
            notify_email_flags_changed(all_flags_changed);
        }
        
        debug("Completed normalize_folder %s", to_string());
        
        return true;
    }
    
    public override async void wait_for_open_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || remote_semaphore == null)
            throw new EngineError.OPEN_REQUIRED("wait_for_open_async() can only be called after open_async()");
        
        if (!yield remote_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.ALREADY_CLOSED("%s failed to open", to_string());
    }
    
    public override async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0)
            return false;
        
        remote_semaphore = new Geary.Nonblocking.ReportingSemaphore<bool>(false);
        
        // start the replay queue
        replay_queue = new ReplayQueue(get_path().to_string(), remote_semaphore);
        
        try {
            yield local_folder.open_async(cancellable);
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
        // wait_for_remote_ready_async(), which uses a NonblockingSemaphore to indicate that the remote
        // is open (or has failed to open).  This allows for early calls to list and fetch emails
        // can work out of the local cache until the remote is ready.
        open_remote_async.begin(open_flags, cancellable);
        
        return true;
    }
    
    private async void open_remote_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable) {
        try {
            debug("Opening remote %s", to_string());
            Imap.Folder folder = yield remote.fetch_folder_async(local_folder.get_path(),
                cancellable);
            
            yield folder.open_async(new EnginePositionToUIDConverter(this), cancellable);
            
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
            remote_semaphore.notify_result(remote != null, null);
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
        
        // notify any subscribers with similar information
        notify_opened(
            (remote_folder != null) ? Geary.Folder.OpenState.BOTH : Geary.Folder.OpenState.LOCAL,
            count);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || --open_count > 0)
            return;
        
        yield close_internal_async(CloseReason.LOCAL_CLOSE, CloseReason.REMOTE_CLOSE, cancellable);
    }
    
    // NOTE: This bypasses open_count and forces the Folder closed.
    private async void close_internal_async(Folder.CloseReason local_reason, Folder.CloseReason remote_reason,
        Cancellable? cancellable) {
        // force closed
        open_count = 0;
        
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
        
        // close local store
        try {
            yield local_folder.close_async(cancellable);
        } catch (Error local_err) {
            debug("Error closing %s local store: %s", to_string(), local_err.message);
        }
        
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
        
        notify_closed(CloseReason.FOLDER_CLOSED);
        
        debug("Folder %s closed", to_string());
    }
    
    private void clear_remote_folder() throws Error {
        remote_folder = null;
        remote_count = -1;
        
        remote_semaphore.reset();
        remote_semaphore.notify_result(false, null);
    }
    
    private void on_remote_appended(int total) {
        debug("on_remote_appended: total=%d", total);
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
        
        if (new_remote_count == remote_count) {
            debug("do_replay_appended_messages %s: no messages appended", to_string());
            
            return;
        }
        
        Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>();
        Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>();
        
        try {
            // If remote doesn't fully open, then don't fire signal, as we'll be unable to
            // normalize the folder
            if (!yield remote_semaphore.wait_for_result_async(null)) {
                debug("do_replay_appended_messages: remote never opened for %s", to_string());
                
                return;
            }
            
            // normalize starting at the message *after* the highest position of the local store,
            // which has now changed
            Imap.MessageSet msg_set = new Imap.MessageSet.range_by_first_last(remote_count + 1,
                new_remote_count);
            Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(
                msg_set, ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, null);
            if (list != null && list.size > 0) {
                debug("do_replay_appended_messages: %d new messages from %s in %s", list.size,
                    msg_set.to_string(), to_string());
                
                // need to report both if it was created (not known before) and appended (which
                // could mean created or simply a known email associated with this folder)
                Gee.Map<Geary.Email, bool> created_or_merged =
                    yield local_folder.create_or_merge_email_async(list, null);
                foreach (Geary.Email email in created_or_merged.keys) {
                    // true means created
                    if (created_or_merged.get(email)) {
                        created.add(email.id);
                    } else {
                        debug("do_replay_appended_messages: appended email ID %s already known in account, now associated with %s...",
                            email.id.to_string(), to_string());
                    }
                    
                    appended.add(email.id);
                }
            } else {
                debug("do_replay_appended_messages: no new messages in %s in %s", msg_set.to_string(),
                    to_string());
            }
        } catch (Error err) {
            debug("Unable to normalize local store of newly appended messages to %s: %s",
                to_string(), err.message);
        }
        
        // save new remote count internally and in local store
        remote_count = new_remote_count;
        try {
            yield local_folder.update_remote_selected_message_count(remote_count, null);
        } catch (Error update_err) {
            debug("Unable to save appended remote count for %s: %s", to_string(), update_err.message);
        }
        
        if (appended.size > 0)
            notify_email_appended(appended);
        
        if (created.size > 0)
            notify_email_locally_appended(created);
        
        notify_email_count_changed(remote_count, CountChangeReason.ADDED);
        
        debug("do_replay_appended_messages: completed for %s", to_string());
    }
    
    private void on_remote_removed(int pos, int total) {
        debug("on_remote_expunge: position=%d total=%d", pos, total);
        replay_queue.schedule(new ReplayRemoval(this, pos, total));
    }
    
    // This MUST only be called from ReplayRemoval.
    internal async void do_replay_remove_message(int remote_position, int new_remote_count) {
        debug("do_replay_remove_message: remote_position=%d remote_count=%d new_remote_count=%d",
            remote_position, remote_count, new_remote_count);
        
        assert(remote_position >= 1);
        assert(new_remote_count >= 0);
        
        int local_count = -1;
        int local_position = -1;
        
        Geary.EmailIdentifier? owned_id = null;
        try {
            local_count = yield local_folder.get_email_count_async(ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                null);
            // can't use remote_position_to_local_position() because local_count includes messages
            // marked for removal, which that helper function doesn't like
            local_position = remote_position - (remote_count - local_count);
            
            debug("do_replay_remove_message: local_count=%d local_position=%d", local_count, local_position);
            
             Gee.List<Geary.Email>? list = yield local_folder.list_email_async(local_position,
                1, Geary.Email.Field.NONE, ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
            if (list != null && list.size > 0)
                owned_id = list[0].id;
        } catch (Error err) {
            debug("Unable to determine ID of removed message #%d from %s: %s", remote_position,
                to_string(), err.message);
        }
        
        bool marked = false;
        if (owned_id != null) {
            debug("do_replay_remove_message: removing from local store Email ID %s", owned_id.to_string());
            try {
                // Reflect change in the local store and notify subscribers
                yield local_folder.remove_marked_email_async(owned_id, out marked, null);
            } catch (Error err2) {
                debug("Unable to remove message #%d from %s: %s", remote_position, to_string(),
                    err2.message);
            }
        } else {
            debug("do_replay_remove_message: remote_position=%d unknown in local store "
                + "(remote_count=%d new_remote_count=%d local_position=%d local_count=%d)",
                remote_position, remote_count, new_remote_count, local_position, local_count);
        }
        
        // for debugging
        int new_local_count = -1;
        try {
            new_local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
        } catch (Error new_count_err) {
            debug("Error fetching new local count for %s: %s", to_string(), new_count_err.message);
        }
        
        // save new remote count internally and in local store
        bool changed = (remote_count != new_remote_count);
        remote_count = new_remote_count;
        try {
            yield local_folder.update_remote_selected_message_count(remote_count, null);
        } catch (Error update_err) {
            debug("Unable to save removed remote count for %s: %s", to_string(), update_err.message);
        }
        
        // notify of change
        if (!marked && owned_id != null)
            notify_email_removed(new Collection.SingleItem<Geary.EmailIdentifier>(owned_id));
        
        if (!marked && changed)
            notify_email_count_changed(remote_count, CountChangeReason.REMOVED);
        
        debug("do_replay_remove_message: completed for %s "
            + "(remote_count=%d local_count=%d new_local_count=%d remote_position=%d local_position=%d marked=%s)",
            to_string(), remote_count, local_count, new_local_count, remote_position, local_position,
            marked.to_string());
    }
    
    private void on_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("on_remote_disconnected: reason=%s", reason.to_string());
        replay_queue.schedule(new ReplayDisconnect(this, reason));
    }
    
    internal async void do_replay_remote_disconnected(Imap.ClientSession.DisconnectReason reason) {
        debug("do_replay_remote_disconnected reason=%s", reason.to_string());
        
        Geary.Folder.CloseReason folder_reason = reason.is_error()
            ? Geary.Folder.CloseReason.REMOTE_CLOSE : Geary.Folder.CloseReason.REMOTE_ERROR;
        
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
    // list_email variants
    //
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_async("list_email_async", low, count, required_fields, flags, accumulator,
            null, cancellable);
        
        return (accumulator.size > 0) ? accumulator : null;
    }
    
    public override void lazy_list_email(int low, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable = null) {
        do_lazy_list_email_async.begin(low, count, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_async(int low, int count, Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable) {
        try {
            yield do_list_email_async("lazy_list_email", low, count, required_fields, flags,
                null, cb, cancellable);
        } catch (Error err) {
            cb(null, err);
        }
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
    
    //
    // list_email_by_id variants
    //
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_by_id_async("list_email_by_id_async", initial_id, count, required_fields,
            flags, accumulator, null, cancellable);
        
        return (accumulator.size > 0) ? accumulator : null;
    }
    
    public override void lazy_list_email_by_id(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb,
        Cancellable? cancellable = null) {
        do_lazy_list_email_by_id_async.begin(initial_id, count, required_fields, flags, cb, cancellable);
    }
    
    private async void do_lazy_list_email_by_id_async(Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, EmailCallback cb, Cancellable? cancellable) {
        try {
            yield do_list_email_by_id_async("lazy_list_email_by_id", initial_id, count, required_fields,
                flags, null, cb, cancellable);
        } catch (Error err) {
            cb(null, err);
        }
    }
    
    private async void do_list_email_by_id_async(string method, Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) throws Error {
        check_open(method);
        check_flags(method, flags);
        check_id(method, initial_id);
        
        if (count == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        // Schedule list operation and wait for completion.
        ListEmailByID op = new ListEmailByID(this, initial_id, count, required_fields, flags, accumulator,
            cb, cancellable);
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
        ListEmailBySparseID op = new ListEmailBySparseID(this, ids, required_fields, flags, accumulator,
            cb, cancellable);
        replay_queue.schedule(op);
        
        yield op.wait_for_ready_async(cancellable);
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        check_open("list_local_email_fields_async");
        check_ids("list_local_email_fields_async", ids);
        
        return yield local_folder.list_email_fields_by_id_async(ids, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        check_open("fetch_email_async");
        check_flags("fetch_email_async", flags);
        check_id("fetch_email_async", id);
        
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
    
    // Helper function for child classes dealing with the delete/archive question.  This method will
    // mark the message as deleted and expunge it.
    protected async void expunge_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        check_open("expunge_email_async");
        check_ids("expunge_email_async", email_ids);
        
        replay_queue.schedule(new ExpungeEmail(this, email_ids, cancellable));
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
        if (!(id is Imap.EmailIdentifier))
            throw new EngineError.BAD_PARAMETERS("Email ID %s is not IMAP Email ID", id.to_string());
    }
    
    private void check_ids(string method, Gee.Collection<EmailIdentifier> ids) throws EngineError {
        foreach (EmailIdentifier id in ids)
            check_id(method, id);
    }
    
    // Converts a remote position to a local position.  remote_pos is 1-based.
    //
    // Returns negative value if remote_count is smaller than local_count or remote_pos is out of
    // range.
    internal static int remote_position_to_local_position(int remote_pos, int local_count, int remote_count) {
        assert(remote_pos >= 1);
        assert(local_count >= 0);
        assert(remote_count >= 0);
        
        if (remote_count < local_count) {
            debug("remote_position_to_local_position: remote_count=%d < local_count=%d (remote_pos=%d)",
                remote_count, local_count, remote_pos);
        }
        
        if (remote_pos > remote_count) {
            debug("remote_position_to_local_position: remote_pos=%d > remote_count=%d (local_count=%d)",
                remote_pos, remote_count, local_count);
        }
        
        return (remote_pos <= remote_count) ? remote_pos - (remote_count - local_count) : -1;
    }
    
    // Converts a local position to a remote position.  local_pos is 1-based.
    //
    // Returns negative value if remote_count is smaller than local_count or if local_pos is out
    // of range.
    internal static int local_position_to_remote_position(int local_pos, int local_count, int remote_count) {
        assert(local_pos >= 1);
        assert(local_count >= 0);
        assert(remote_count >= 0);
        
        if (remote_count < local_count) {
            debug("local_position_to_remote_position: remote_count=%d < local_count=%d",
                remote_count, local_count);
        } else if (local_pos > local_count) {
            debug("local_position_to_remote_position: local_pos=%d > local_count=%d",
                local_pos, local_count);
        }
        
        return (local_pos <= local_count) ? remote_count - (local_count - local_pos) : -1;
    }
    
    // In order to maintain positions for all messages without storing all of them locally,
    // the database stores entries for the lowest requested email to the highest (newest), which
    // means there can be no gaps between the last in the database and the last on the server.
    // This method takes care of that if that range needs to expand.
    //
    // Note that this method doesn't return a remote_count because that's maintained by the
    // EngineFolder as a member variable.
    internal async void normalize_email_positions_async(int low, int count, out int local_count,
        Cancellable? cancellable) throws Error {
        if (!yield remote_semaphore.wait_for_result_async(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("no connection to %s", remote.to_string());
        
        int mutex_token = yield normalize_email_positions_mutex.claim_async(cancellable);
        
        Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();
        Error? error = null;
        try {
            local_count = yield local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                cancellable);
            
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
            
            // Normalize the local folder by fetching EmailIdentifiers for all missing email as well
            // as fields for duplicate detection
            Gee.List<Geary.Email>? list = yield remote_folder.list_email_async(
                new Imap.MessageSet.range_by_count(high, prefetch_count),
                ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, cancellable);
            if (list == null || list.size != prefetch_count) {
                throw new EngineError.BAD_PARAMETERS("Unable to prefetch %d email starting at %d in %s",
                    count, low, to_string());
            }
            
            Gee.Map<Geary.Email, bool> created_or_merged = yield local_folder.create_or_merge_email_async(
                list, cancellable);
            
            // Collect which EmailIdentifiers were created and report them
            foreach (Geary.Email email in created_or_merged.keys) {
                // true means created
                if (created_or_merged.get(email))
                    created_ids.add(email.id);
            }
        } catch (Error e) {
            local_count = 0; // prevent compiler warning
            error = e;
        }
        
        normalize_email_positions_mutex.release(ref mutex_token);
        
        // report created outside of mutex, to avoid reentrancy issues
        if (created_ids.size > 0)
            notify_email_locally_appended(created_ids);
        
        if (error != null)
            throw error;
    }
    
    public virtual async void mark_email_async(Gee.List<Geary.EmailIdentifier> to_mark,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) throws Error {
        check_open("mark_email_async");
        
        replay_queue.schedule(new MarkEmail(this, to_mark, flags_to_add, flags_to_remove,
            cancellable));
    }

    public virtual async void copy_email_async(Gee.List<Geary.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("copy_email_async");
        
        replay_queue.schedule(new CopyEmail(this, to_copy, destination));
    }

    public virtual async void move_email_async(Gee.List<Geary.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable = null) throws Error {
        check_open("move_email_async");
        
        replay_queue.schedule(new MoveEmail(this, to_move, destination));
    }
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> changed) {
        notify_email_flags_changed(changed);
    }
}

