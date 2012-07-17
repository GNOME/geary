/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.ListEmail : Geary.ImapEngine.SendReplayOperation {
    private class RemoteListPositional : NonblockingBatchOperation {
        private ListEmail owner;
        private int[] needed_by_position;
        
        public RemoteListPositional(ListEmail owner, int[] needed_by_position) {
            this.owner = owner;
            this.needed_by_position = needed_by_position;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            yield owner.remote_list_positional(needed_by_position);
            
            return null;
        }
    }
    
    private class RemoteListPartial : NonblockingBatchOperation {
        private ListEmail owner;
        private Geary.Email.Field remaining_fields;
        private Gee.Collection<EmailIdentifier> ids;
        
        public RemoteListPartial(ListEmail owner, Geary.Email.Field remaining_fields,
            Gee.Collection<EmailIdentifier> ids) {
            this.owner = owner;
            this.remaining_fields = remaining_fields;
            this.ids = ids;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            yield owner.remote_list_partials(ids, remaining_fields);
            
            return null;
        }
    }
    
    protected GenericFolder engine;
    protected int low;
    protected int count;
    protected Geary.Email.Field required_fields;
    protected Gee.List<Geary.Email>? accumulator = null;
    protected weak EmailCallback? cb;
    protected Cancellable? cancellable;
    protected Folder.ListFlags flags;
    protected bool local_only;
    protected bool remote_only;
    protected bool excluding_id;
    
    private Gee.List<Geary.Email>? local_list = null;
    private int local_list_size = 0;
    private Gee.HashMultiMap<Geary.Email.Field, Geary.EmailIdentifier> unfulfilled = new Gee.HashMultiMap<
        Geary.Email.Field, Geary.EmailIdentifier>();
    
    public ListEmail(GenericFolder engine, int low, int count, Geary.Email.Field required_fields,
        Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable) {
        base("ListEmail");
        
        this.engine = engine;
        this.low = low;
        this.count = count;
        this.required_fields = required_fields;
        this.accumulator = accumulator;
        this.cb = cb;
        this.cancellable = cancellable;
        this.flags = flags;
        
        local_only = flags.is_all_set(Folder.ListFlags.LOCAL_ONLY);
        remote_only = flags.is_all_set(Folder.ListFlags.FORCE_UPDATE);
        excluding_id = flags.is_all_set(Folder.ListFlags.EXCLUDING_ID);
        
        // always fetch required fields unless a modified list, in which case only fetch the fields
        // requested by user ... this ensures the local store is seeded with certain fields required
        // for it to operate properly
        if (!remote_only && !local_only)
            this.required_fields |= ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        int local_count;
        if (!local_only) {
            // normalize the position (ordering) of what's available locally with the situation on
            // the server ... this involves fetching the PROPERTIES of the missing emails from
            // the server and caching them locally
            yield engine.normalize_email_positions_async(low, count, out local_count, cancellable);
        } else {
            // local_only means just that
            local_count = yield engine.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                cancellable);
        }
        
        // normalize the arguments so they reflect cardinal positions ... remote_count can be -1
        // if the folder is in the process of opening
        int local_low = 0;
        if (!local_only && yield engine.wait_for_remote_ready_async(cancellable)) {
            engine.normalize_span_specifiers(ref low, ref count, engine.remote_count);
            
            // because the local store caches messages starting from the newest (at the end of the list)
            // to the earliest fetched by the user, need to adjust the low value to match its offset
            // and range
            if (low > 0)
                local_low = engine.remote_position_to_local_position(low, local_count);
        } else {
            engine.normalize_span_specifiers(ref low, ref count, local_count);
            if (low > 0)
                local_low = low.clamp(1, local_count);
        }
        
        Logging.debug(Logging.Flag.REPLAY,
            "ListEmail.replay_local %s: low=%d count=%d local_count=%d remote_count=%d local_low=%d",
            engine.to_string(), low, count, local_count, engine.remote_count, local_low);
        
        if (!remote_only && local_low > 0) {
            try {
                local_list = yield engine.local_folder.list_email_async(local_low, count, required_fields,
                    ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);
            } catch (Error local_err) {
                if (cb != null && !(local_err is IOError.CANCELLED))
                    cb (null, local_err);
                throw local_err;
            }
        }
        
        local_list_size = (local_list != null) ? local_list.size : 0;
        
        // fixup local email positions to match server's positions
        if (local_list_size > 0 && engine.remote_count > 0 && local_count < engine.remote_count) {
            int adjustment = engine.remote_count - local_count;
            foreach (Geary.Email email in local_list)
                email.update_position(email.position + adjustment);
        }
        
        // Break into two pools: a list of emails where all field requirements are met and a hash
        // table of messages keyed by what fields are required
        Gee.List<Geary.Email> fulfilled = new Gee.ArrayList<Geary.Email>();
        if (local_list_size > 0) {
            foreach (Geary.Email email in local_list) {
                if (email.fields.fulfills(required_fields)) {
                    fulfilled.add(email);
                } else {
                    // strip fulfilled fields so only remaining are fetched from server
                    Geary.Email.Field remaining = required_fields.clear(email.fields);
                    unfulfilled.set(remaining, email.id);
                }
            }
        }
        
        // report fulfilled
        if (fulfilled.size > 0) {
            if (accumulator != null)
                accumulator.add_all(fulfilled);
            
            if (cb != null)
                cb(fulfilled, null);
        }
        
        // if local list matches total asked for, or if only returning local versions, exit
        if (fulfilled.size == count || local_only) {
            if (!local_only)
                assert(unfulfilled.size == 0);
            
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        // go through the positions from (low) to (low + count) and see if they're not already
        // present in local_list; whatever isn't present needs to be fetched in full
        //
        // TODO: This is inefficient because we can't assume the returned emails are sorted or
        // contiguous (it's possible local email is present but doesn't fulfill all the fields).
        // A better search method is probably possible, but this will do for now
        int[] needed_by_position = new int[0];
        for (int position = low; position <= (low + (count - 1)); position++) {
            bool found = false;
            for (int ctr = 0; ctr < local_list_size; ctr++) {
                if (local_list[ctr].position == position) {
                    found = true;
                    
                    break;
                }
            }
            
            if (!found)
                needed_by_position += position;
        }
        
        Logging.debug(Logging.Flag.REPLAY, "ListEmail.replay_remote %s: %d by position, %d unfulfilled",
            engine.to_string(), needed_by_position.length, unfulfilled.get_values().size);
        
        NonblockingBatch batch = new NonblockingBatch();
        
        // fetch in full whatever is needed wholesale
        if (needed_by_position.length > 0)
            batch.add(new RemoteListPositional(this, needed_by_position));
        
        // fetch the partial emails that do not fulfill all required fields, getting only those
        // fields that are missing for each email
        if (unfulfilled.size > 0) {
            foreach (Geary.Email.Field remaining_fields in unfulfilled.get_keys())
                batch.add(new RemoteListPartial(this, remaining_fields, unfulfilled.get(remaining_fields)));
        }
        
        Logging.debug(Logging.Flag.REPLAY, "ListEmail.replay_remote %s: Scheduling %d FETCH operations",
            engine.to_string(), batch.size);
        
        yield batch.execute_all_async(cancellable);
        
        // Notify of first error encountered before throwing
        if (cb != null && batch.first_exception != null)
            cb(null, batch.first_exception);
        
        batch.throw_first_exception();
        
        // signal finished
        if (cb != null)
            cb(null, null);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, no backout
    }
    
    private async void remote_list_positional(int[] needed_by_position) throws Error {
        // possible to call remote multiple times, wait for it to open once and go
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        // pull in reverse order because callers to this method tend to order messages from oldest
        // to newest, but for user satisfaction, should be fetched from newest to oldest
        int remaining = needed_by_position.length;
        while (remaining > 0) {
            // if a callback is specified, pull the messages down in chunks, so they can be reported
            // incrementally
            int[] list;
            if (cb != null) {
                int list_count = int.min(GenericFolder.REMOTE_FETCH_CHUNK_COUNT, remaining);
                list = needed_by_position[remaining - list_count:remaining];
                assert(list.length == list_count);
            } else {
                list = needed_by_position;
            }
            
            // pull from server
            Gee.List<Geary.Email>? remote_list = yield engine.remote_folder.list_email_async(
                new Imap.MessageSet.sparse(list), required_fields, cancellable);
            if (remote_list == null || remote_list.size == 0)
                break;
            
            // if any were fetched, store locally ... must be stored before they can be reported
            // via the callback because if, in the context of the callback, these messages are
            // requested, they won't be found in the database, causing another remote fetch to
            // occur
            remote_list = yield merge_emails(remote_list, cancellable);
            
            if (accumulator != null && remote_list != null && remote_list.size > 0)
                accumulator.add_all(remote_list);
            
            if (cb != null)
                cb(remote_list, null);
            
            remaining -= list.length;
        }
    }
    
    private async void remote_list_partials(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field remaining_fields) throws Error {
        // possible to call remote multiple times, wait for it to open once and go
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        Imap.MessageSet msg_set = new Imap.MessageSet.email_id_collection(ids);
        
        Gee.List<Geary.Email>? remote_list = yield engine.remote_folder.list_email_async(msg_set,
            remaining_fields, cancellable);
        if (remote_list == null || remote_list.size == 0)
            return;
        
        remote_list = yield merge_emails(remote_list, cancellable);
        
        if (accumulator != null && remote_list != null && remote_list.size > 0)
            accumulator.add_all(remote_list);
        
        if (cb != null)
            cb(remote_list, null);
    }
    
    private async Gee.List<Geary.Email> merge_emails(Gee.List<Geary.Email> list,
        Cancellable? cancellable) throws Error {
        NonblockingBatch batch = new NonblockingBatch();
        foreach (Geary.Email email in list)
            batch.add(new CreateLocalEmailOperation(engine.local_folder, email, required_fields));
        
        yield batch.execute_all_async(cancellable);
        
        batch.throw_first_exception();
        
        // report locally added (non-duplicate, not unknown) emails & collect emails post-merge
        Gee.List<Geary.Email> merged_email = new Gee.ArrayList<Geary.Email>();
        Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>(
            Hashable.hash_func, Equalable.equal_func);
        foreach (int id in batch.get_ids()) {
            CreateLocalEmailOperation? op = batch.get_operation(id) as CreateLocalEmailOperation;
            if (op != null) {
                if (op.created)
                    created_ids.add(op.email.id);
                
                assert(op.merged != null);
                merged_email.add(op.merged);
            }
        }
        
        if (created_ids.size > 0)
            engine.notify_email_locally_appended(created_ids);
        
        if (cb != null)
            cb(merged_email, null);
        
        return merged_email;
    }
    
    public override string describe_state() {
        return "low=%d count=%d required_fields=%Xh local_only=%s remote_only=%s".printf(low, count,
            required_fields, local_only.to_string(), remote_only.to_string());
    }
}

