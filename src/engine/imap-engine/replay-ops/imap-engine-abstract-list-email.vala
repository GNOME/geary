/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.AbstractListEmail : Geary.ImapEngine.SendReplayOperation {
    private static int total_fetches_avoided = 0;
    
    private class RemoteBatchOperation : Nonblocking.BatchOperation {
        // IN
        public MinimalFolder owner;
        public Imap.MessageSet msg_set;
        public Geary.Email.Field unfulfilled_fields;
        public Geary.Email.Field required_fields;
        
        // OUT
        public Gee.Set<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();
        
        public RemoteBatchOperation(MinimalFolder owner, Imap.MessageSet msg_set,
            Geary.Email.Field unfulfilled_fields, Geary.Email.Field required_fields) {
            this.owner = owner;
            this.msg_set = msg_set;
            this.unfulfilled_fields = unfulfilled_fields;
            this.required_fields = required_fields;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            // fetch from remote folder
            Gee.List<Geary.Email>? list = yield owner.remote_folder.list_email_async(msg_set,
                unfulfilled_fields, cancellable);
            if (list == null || list.size == 0)
                return null;
            
            // TODO: create_or_merge_email_async() should only write if something has changed
            Gee.Map<Geary.Email, bool> created_or_merged = yield owner.local_folder.create_or_merge_email_async(
                list, cancellable);
            for (int ctr = 0; ctr < list.size; ctr++) {
                Geary.Email email = list[ctr];
                
                // if created, add to id pool
                if (created_or_merged.get(email))
                    created_ids.add(email.id);
                
                // if remote email doesn't fulfills all required fields, fetch full and return that
                // TODO: Need a sparse ID fetch in ImapDB.Folder to do this all at once
                if (!email.fields.fulfills(required_fields)) {
                    email = yield owner.local_folder.fetch_email_async((ImapDB.EmailIdentifier) email.id,
                        required_fields, ImapDB.Folder.ListFlags.NONE, cancellable);
                    list[ctr] = email;
                }
            }
            
            return list;
        }
    }
    
    // The accumulated Email from the list operation.  Should only be accessed once the operation
    // has completed.
    public Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
    
    protected MinimalFolder owner;
    protected Geary.Email.Field required_fields;
    protected Cancellable? cancellable;
    protected Folder.ListFlags flags;
    
    private Gee.HashMap<Imap.UID, Geary.Email.Field> unfulfilled = new Gee.HashMap<Imap.UID, Geary.Email.Field>();
    
    public AbstractListEmail(string name, MinimalFolder owner, Geary.Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        base(name, OnError.IGNORE);
        
        this.owner = owner;
        this.required_fields = required_fields;
        this.cancellable = cancellable;
        this.flags = flags;
    }
    
    protected void add_unfulfilled_fields(Imap.UID? uid, Geary.Email.Field unfulfilled_fields) {
        assert(uid != null);
        assert(uid.is_valid());
        
        if (!unfulfilled.has_key(uid))
            unfulfilled.set(uid, unfulfilled_fields);
        else
            unfulfilled.set(uid, unfulfilled.get(uid) | unfulfilled_fields);
    }
    
    protected void add_many_unfulfilled_fields(Gee.Collection<Imap.UID>? uids,
        Geary.Email.Field unfulfilled_fields) {
        if (uids != null) {
            foreach (Imap.UID uid in uids)
                add_unfulfilled_fields(uid, unfulfilled_fields);
        }
    }
    
    protected int get_unfulfilled_count() {
        return unfulfilled.size;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // remove email already picked up from local store ... for email reported via the
        // callback, too late
        Collection.remove_if<Geary.Email>(accumulator, (email) => {
            return ids.contains((ImapDB.EmailIdentifier) email.id);
        });
        
        // remove from unfulfilled list, as there's now nothing to fetch from the server
        // NOTE: Requires UID to work; this *should* always work, as the EmailIdentifier should
        // be originating from the database, not the Imap.Folder layer
        foreach (ImapDB.EmailIdentifier id in ids) {
            if (id.has_uid())
                unfulfilled.unset(id.uid);
        }
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    // Child class should execute its own calls *before* calling this base method
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // only deal with unfulfilled email, child class must deal with everything else
        if (unfulfilled.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // since list and search commands ahead of this one in the queue may have fulfilled some of
        // the emails thought to be unfulfilled when first checked locally, look for them now
        int fetches_avoided = yield remove_fulfilled_uids_async();
        if (fetches_avoided > 0) {
            total_fetches_avoided += fetches_avoided;
            
            debug("[%s] %d previously-fulfilled fetches avoided in list operation, %d total",
                owner.to_string(), fetches_avoided, total_fetches_avoided);
            
            // if all fulfilled, emails were added to accumulator in remove call, so done
            if (unfulfilled.size == 0)
                return ReplayOperation.Status.COMPLETED;
        }
        
        // convert UID -> needed fields mapping to needed fields -> UIDs, as they can be grouped
        // and submitted at same time
        Gee.HashMultiMap<Geary.Email.Field, Imap.UID> reverse_unfulfilled = new Gee.HashMultiMap<
            Geary.Email.Field, Imap.UID>();
        foreach (Imap.UID uid in unfulfilled.keys)
            reverse_unfulfilled.set(unfulfilled.get(uid), uid);
        
        // schedule operations to remote for each set of email with unfulfilled fields and merge
        // in results, pulling out the entire email
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (Geary.Email.Field unfulfilled_fields in reverse_unfulfilled.get_keys()) {
            Gee.Collection<Imap.UID> unfulfilled_uids = reverse_unfulfilled.get(unfulfilled_fields);
            if (unfulfilled_uids.size == 0)
                continue;
            
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(unfulfilled_uids);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                RemoteBatchOperation remote_op = new RemoteBatchOperation(owner, msg_set,
                    unfulfilled_fields, required_fields);
                batch.add(remote_op);
            }
        }
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        Gee.ArrayList<Geary.Email> result_list = new Gee.ArrayList<Geary.Email>();
        Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (int batch_id in batch.get_ids()) {
            Gee.List<Geary.Email>? list = (Gee.List<Geary.Email>?) batch.get_result(batch_id);
            if (list != null && list.size > 0) {
                result_list.add_all(list);
                
                RemoteBatchOperation op = (RemoteBatchOperation) batch.get_operation(batch_id);
                created_ids.add_all(op.created_ids);
            }
        }
        
        // report merged emails
        if (result_list.size > 0)
            accumulator.add_all(result_list);
        
        // signal
        if (created_ids.size > 0) {
            owner.replay_notify_email_inserted(created_ids);
            owner.replay_notify_email_locally_inserted(created_ids);
        }
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    protected async Trillian is_fully_expanded_async() throws Error {
        int remote_count;
        owner.get_remote_counts(out remote_count, null);
        
        // if unknown (unconnected), say so
        if (remote_count < 0)
            return Trillian.UNKNOWN;
        
        // include marked for removed in the count in case this is being called while a removal
        // is in process, in which case don't want to expand vector this moment because the
        // vector is in flux
        int local_count_with_marked = yield owner.local_folder.get_email_count_async(
            ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
        
        return Trillian.from_boolean(local_count_with_marked >= remote_count);
    }
    
    // Adds everything in the expansion to the unfulfilled set with ImapDB's field requirements ...
    // UIDs are returned if anything else needs to be added to them
    protected async Gee.Set<Imap.UID>? expand_vector_async(Imap.UID? initial_uid, int count) throws Error {
        // watch out for situations where the entire folder is represented locally (i.e. no
        // expansion necessary)
        int remote_count = owner.get_remote_counts(null, null);
        if (remote_count < 0)
            return null;
        
        // include marked for removed in the count in case this is being called while a removal
        // is in process, in which case don't want to expand vector this moment because the
        // vector is in flux
        int local_count = yield owner.local_folder.get_email_count_async(
            ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
        
        // watch out for attempts to expand vector when it's expanded as far as it will go
        if (local_count >= remote_count)
            return null;
        
        // determine low and high position for expansion ... default in most code paths for high
        // is the SequenceNumber just below the lowest known message, unless no local messages
        // are present
        Imap.SequenceNumber? low_pos = null;
        Imap.SequenceNumber? high_pos = null;
        if (local_count > 0)
            high_pos = new Imap.SequenceNumber(Numeric.int_floor(remote_count - local_count, 1));
        
        if (flags.is_oldest_to_newest()) {
            if (initial_uid == null) {
                // if oldest to newest and initial-id is null, then start at the bottom
                low_pos = new Imap.SequenceNumber(Imap.SequenceNumber.MIN);
            } else {
                Gee.Map<Imap.UID, Imap.SequenceNumber>? map = yield owner.remote_folder.uid_to_position_async(
                    new Imap.MessageSet.uid(initial_uid), cancellable);
                if (map == null || map.size == 0 || !map.has_key(initial_uid)) {
                    debug("%s: Unable to expand vector for initial_uid=%s: unable to convert to position",
                        to_string(), initial_uid.to_string());
                    
                    return null;
                }
                
                low_pos = map.get(initial_uid);
            }
        } else {
            // newest to oldest
            //
            // if initial_id is null or no local earliest UID, then vector expansion is simple:
            // merely count backwards from the top of the locally available vector
            if (initial_uid == null || local_count == 0) {
                low_pos = new Imap.SequenceNumber(Numeric.int_floor((remote_count - local_count) - count, 1));
                
                // don't set high_pos, leave null to use symbolic "highest" in MessageSet
                high_pos = null;
            } else {
                // not so simple; need to determine the *remote* position of the earliest local
                // UID and count backward from that; if no UIDs present, then it's as if no initial_id
                // is specified.
                //
                // low position: count backwards; note that it's possible this will overshoot and
                // pull in more email than technically required, but without a round-trip to the
                // server to determine the position number of a particular UID, this makes sense
                assert(high_pos != null);
                low_pos = new Imap.SequenceNumber(
                    Numeric.int64_floor((high_pos.value - count) + 1, 1));
            }
        }
        
        // low_pos must be defined by this point
        assert(low_pos != null);
        
        if (high_pos != null && low_pos.value > high_pos.value) {
            debug("%s: Aborting vector expansion, low_pos=%s > high_pos=%s", owner.to_string(),
                low_pos.to_string(), high_pos.to_string());
            
            return null;
        }
        
        Imap.MessageSet msg_set;
        int64 actual_count = -1;
        if (high_pos != null) {
            msg_set = new Imap.MessageSet.range_by_first_last(low_pos, high_pos);
            actual_count = (high_pos.value - low_pos.value) + 1;
        } else {
            msg_set = new Imap.MessageSet.range_to_highest(low_pos);
        }
        
        debug("%s: Performing vector expansion using %s for initial_uid=%s count=%d actual_count=%s local_count=%d remote_count=%d oldest_to_newest=%s",
            owner.to_string(), msg_set.to_string(),
            (initial_uid != null) ? initial_uid.to_string() : "(null)", count, actual_count.to_string(),
            local_count, remote_count, flags.is_oldest_to_newest().to_string());
        
        Gee.List<Geary.Email>? list = yield owner.remote_folder.list_email_async(msg_set,
            Geary.Email.Field.NONE, cancellable);
        
        Gee.Set<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        if (list != null) {
            // add all the new email to the unfulfilled list, which ensures (when replay_remote_async
            // is called) that the fields are downloaded and added to the database
            foreach (Geary.Email email in list)
                uids.add(((ImapDB.EmailIdentifier) email.id).uid);
            
            // remove any already stored locally
            Gee.Collection<ImapDB.EmailIdentifier>? ids =
                yield owner.local_folder.get_ids_async(uids, ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                    cancellable);
            if (ids != null && ids.size > 0) {
                foreach (ImapDB.EmailIdentifier id in ids) {
                    assert(id.has_uid());
                    uids.remove(id.uid);
                }
            }
            
            // for the remainder (not in local store), fetch the required fields
            add_many_unfulfilled_fields(uids, ImapDB.Folder.REQUIRED_FIELDS);
        }
        
        debug("%s: Vector expansion completed (%d new email)", owner.to_string(),
            (uids != null) ? uids.size : 0);
        
        return uids != null && uids.size > 0 ? uids : null;
    }
    
    private async int remove_fulfilled_uids_async() throws Error {
        // if the update is forced, don't rely on cached database, have to go to the horse's mouth
        if (flags.is_force_update())
            return 0;
        
        ImapDB.Folder.ListFlags list_flags = ImapDB.Folder.ListFlags.from_folder_flags(flags);
        
        Gee.Set<ImapDB.EmailIdentifier>? unfulfilled_ids = yield owner.local_folder.get_ids_async(
            unfulfilled.keys, list_flags, cancellable);
        if (unfulfilled_ids == null || unfulfilled_ids.size == 0)
            return 0;
        
        Gee.Map<ImapDB.EmailIdentifier, Email.Field>? local_fields =
            yield owner.local_folder.list_email_fields_by_id_async(unfulfilled_ids, list_flags,
                cancellable);
        if (local_fields == null || local_fields.size == 0)
            return 0;
        
        // For each identifier, if now fulfilled in the database, fetch it, add it to the accumulator,
        // and remove it from the unfulfilled map -- one network operation saved
        int fetch_avoided = 0;
        foreach (ImapDB.EmailIdentifier id in local_fields.keys) {
            if (!local_fields.get(id).fulfills(required_fields))
                continue;
            
            try {
                Email email = yield owner.local_folder.fetch_email_async(id, required_fields, list_flags,
                    cancellable);
                accumulator.add(email);
            } catch (Error err) {
                if (err is IOError.CANCELLED)
                    throw err;
                
                // some problem locally, do the network round-trip
                continue;
            }
            
            // got it, don't fetch from remote
            unfulfilled.unset(id.uid);
            fetch_avoided++;
        }
        
        return fetch_avoided;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, no backout
    }
    
    public override string describe_state() {
        return "required_fields=%Xh local_only=%s force_update=%s".printf(required_fields,
            flags.is_local_only().to_string(), flags.is_force_update().to_string());
    }
}

