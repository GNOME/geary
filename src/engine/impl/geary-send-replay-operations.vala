/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.SendReplayOperation : Geary.ReplayOperation {
    public SendReplayOperation(string name) {
        base (name, ReplayOperation.Scope.LOCAL_AND_REMOTE);
    }
    
    public SendReplayOperation.only_remote(string name) {
        base (name, ReplayOperation.Scope.REMOTE_ONLY);
    }
}

private class Geary.MarkEmail : Geary.SendReplayOperation {
    private GenericImapFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_mark;
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;
    
    public MarkEmail(GenericImapFolder engine, Gee.List<Geary.EmailIdentifier> to_mark, 
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) {
        base("MarkEmail");
        
        this.engine = engine;
        
        this.to_mark = to_mark;
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // Save original flags, then set new ones.
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        yield engine.local_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        // Notify using flags from DB.
        engine.notify_email_flags_changed(yield engine.local_folder.get_email_flags_async(to_mark,
            cancellable));
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.remote_folder.mark_email_async(new Imap.MessageSet.email_id_collection(to_mark),
            flags_to_add, flags_to_remove, cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // Restore original flags (if fetched, which may not have occurred if an error happened
        // during transaction)
        if (original_flags != null)
            yield engine.local_folder.set_email_flags_async(original_flags, cancellable);
    }
    
    public override string describe_state() {
        return "to_mark=%d flags_to_add=%s flags_to_remove=%s".printf(to_mark.size,
            (flags_to_add != null) ? flags_to_add.to_string() : "(none)",
            (flags_to_remove != null) ? flags_to_remove.to_string() : "(none)");
    }
}

private class Geary.RemoveEmail : Geary.SendReplayOperation {
    private GenericImapFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_remove;
    private Cancellable? cancellable;
    private int original_count = 0;
    
    public RemoveEmail(GenericImapFolder engine, Gee.List<Geary.EmailIdentifier> to_remove,
        Cancellable? cancellable = null) {
        base("RemoveEmail");
        
        this.engine = engine;
        
        this.to_remove = to_remove;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // TODO: Use a local_folder method that operates on all messages at once
        foreach (Geary.EmailIdentifier id in to_remove)
            yield engine.local_folder.mark_removed_async(id, true, cancellable);
        
        engine.notify_email_removed(to_remove);
        
        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_remove.size,
            Geary.Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // Remove from server. Note that this causes the receive replay queue to kick into
        // action, removing the e-mail but *NOT* firing a signal; the "remove marker" indicates
        // that the signal has already been fired.
        yield engine.remote_folder.remove_email_async(new Imap.MessageSet.email_id_collection(to_remove),
            cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // TODO: Use a local_folder method that operates on all messages at once
        foreach (Geary.EmailIdentifier id in to_remove)
            yield engine.local_folder.mark_removed_async(id, false, cancellable);
        
        engine.notify_email_appended(to_remove);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }
    
    public override string describe_state() {
        return "to_remove=%d".printf(to_remove.size);
    }
}

private class Geary.ListEmail : Geary.SendReplayOperation {
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
    
    protected GenericImapFolder engine;
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
    
    public ListEmail(GenericImapFolder engine, int low, int count, Geary.Email.Field required_fields,
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
            this.required_fields |= Sqlite.Folder.REQUIRED_FOR_DUPLICATE_DETECTION;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        int local_count;
        if (!local_only) {
            // normalize the position (ordering) of what's available locally with the situation on
            // the server ... this involves prefetching the PROPERTIES of the missing emails from
            // the server and caching them locally
            yield engine.normalize_email_positions_async(low, count, out local_count, cancellable);
        } else {
            // local_only means just that
            local_count = yield engine.local_folder.get_email_count_async(cancellable);
        }
        
        // normalize the arguments so they reflect cardinal positions ... remote_count can be -1
        // if the folder is in the process of opening
        int local_low = 0;
        if (!local_only && yield engine.wait_for_remote_to_open(cancellable)) {
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
                    Sqlite.Folder.ListFlags.PARTIAL_OK, cancellable);
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
        if (!yield engine.wait_for_remote_to_open(cancellable))
            return;
        
        // pull in reverse order because callers to this method tend to order messages from oldest
        // to newest, but for user satisfaction, should be fetched from newest to oldest
        int remaining = needed_by_position.length;
        while (remaining > 0) {
            // if a callback is specified, pull the messages down in chunks, so they can be reported
            // incrementally
            int[] list;
            if (cb != null) {
                int list_count = int.min(GenericImapFolder.REMOTE_FETCH_CHUNK_COUNT, remaining);
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
        if (!yield engine.wait_for_remote_to_open(cancellable))
            return;
        
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

private class Geary.ListEmailByID : Geary.ListEmail {
    private Geary.EmailIdentifier initial_id;
    
    public ListEmailByID(GenericImapFolder engine, Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) {
        base(engine, 0, count, required_fields, flags, accumulator, cb, cancellable);
        
        name = "ListEmailByID";
        
        this.initial_id = initial_id;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        int local_count = yield engine.local_folder.get_email_count_async(cancellable);
        
        int initial_position = yield engine.local_folder.get_id_position_async(initial_id, cancellable);
        if (initial_position <= 0) {
            throw new EngineError.NOT_FOUND("Email ID %s in %s not known to local store",
                initial_id.to_string(), engine.to_string());
        }
        
        // normalize the initial position to the remote folder's addressing
        initial_position = engine.local_position_to_remote_position(initial_position, local_count);
        if (initial_position <= 0) {
            throw new EngineError.NOT_FOUND("Cannot map email ID %s in %s to remote folder",
                initial_id.to_string(), engine.to_string());
        }
        
        // since count can also indicate "to earliest" or "to latest", normalize
        // (count is exclusive of initial_id, hence adding/substracting one, meaning that a count
        // of zero or one are accepted)
        int low, high;
        if (count < 0) {
            low = (count != int.MIN) ? (initial_position + count + 1) : 1;
            high = excluding_id ? initial_position - 1 : initial_position;
        } else if (count > 0) {
            low = excluding_id ? initial_position + 1 : initial_position;
            high = (count != int.MAX) ? (initial_position + count - 1) : engine.remote_count;
        } else {
            // count == 0
            low = initial_position;
            high = initial_position;
        }
        
        // low should never be -1, so don't need to check for that
        low = low.clamp(1, int.MAX);
        
        int actual_count = ((high - low) + 1);
        
        // one more check
        if (actual_count == 0) {
            Logging.debug(Logging.Flag.REPLAY,
                "ListEmailByID %s: no actual count to return (%d) (excluding=%s %s)",
                engine.to_string(), actual_count, excluding_id.to_string(), initial_id.to_string());
            
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        this.low = low;
        this.count = actual_count;
        
        return yield base.replay_local_async();
    }
    
    public override string describe_state() {
        return "%s initial_id=%s excl=%s".printf(base.describe_state(), initial_id.to_string(),
            excluding_id.to_string());
    }
}

private class Geary.ListEmailBySparseID : Geary.SendReplayOperation {
    private class LocalBatchOperation : NonblockingBatchOperation {
        public GenericImapFolder owner;
        public Geary.EmailIdentifier id;
        public Geary.Email.Field required_fields;
        
        public LocalBatchOperation(GenericImapFolder owner, Geary.EmailIdentifier id,
            Geary.Email.Field required_fields) {
            this.owner = owner;
            this.id = id;
            this.required_fields = required_fields;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            try {
                return yield owner.local_folder.fetch_email_async(id, required_fields,
                    Sqlite.Folder.ListFlags.PARTIAL_OK, cancellable);
            } catch (Error err) {
                // only throw errors that are not NOT_FOUND and INCOMPLETE_MESSAGE, as these two
                // are recoverable
                if (!(err is Geary.EngineError.NOT_FOUND) && !(err is Geary.EngineError.INCOMPLETE_MESSAGE))
                    throw err;
            }
            
            return null;
        }
    }
    
    private class RemoteBatchOperation : NonblockingBatchOperation {
        public GenericImapFolder owner;
        public Imap.MessageSet msg_set;
        public Geary.Email.Field unfulfilled_fields;
        public Geary.Email.Field required_fields;
        
        public RemoteBatchOperation(GenericImapFolder owner, Imap.MessageSet msg_set,
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
            
            // create all locally and merge results if required
            for (int ctr = 0; ctr < list.size; ctr++) {
                Geary.Email email = list[ctr];
                
                yield owner.local_folder.create_email_async(email, cancellable);
                
                // if remote email doesn't fulfills all required fields, fetch full and return that
                if (!email.fields.fulfills(required_fields)) {
                    email = yield owner.local_folder.fetch_email_async(email.id, required_fields,
                        Sqlite.Folder.ListFlags.NONE, cancellable);
                    list[ctr] = email;
                }
            }
            
            return list;
        }
    }
    
    private GenericImapFolder owner;
    private Gee.HashSet<Geary.EmailIdentifier> ids = new Gee.HashSet<Geary.EmailIdentifier>(
        Hashable.hash_func, Equalable.equal_func);
    private Geary.Email.Field required_fields;
    private Folder.ListFlags flags;
    private bool local_only;
    private bool force_update;
    private Gee.Collection<Geary.Email>? accumulator;
    private unowned EmailCallback cb;
    private Cancellable? cancellable;
    private Gee.HashMultiMap<Geary.Email.Field, Geary.EmailIdentifier> unfulfilled = new Gee.HashMultiMap<
        Geary.Email.Field, Geary.EmailIdentifier>(null, null, Hashable.hash_func, Equalable.equal_func);
    
    public ListEmailBySparseID(GenericImapFolder owner, Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback cb, Cancellable? cancellable) {
        base ("ListEmailBySparseID");
        
        this.owner = owner;
        this.ids.add_all(ids);
        this.required_fields = required_fields;
        this.flags = flags;
        this.accumulator = accumulator;
        this.cb = cb;
        this.cancellable = cancellable;
        
        local_only = flags.is_all_set(Folder.ListFlags.LOCAL_ONLY);
        force_update = flags.is_all_set(Folder.ListFlags.FORCE_UPDATE);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (force_update) {
            foreach (EmailIdentifier id in ids)
                unfulfilled.set(required_fields, id);
            
            return ReplayOperation.Status.CONTINUE;
        }
        
        NonblockingBatch batch = new NonblockingBatch();
        
        // Fetch emails by ID from local store all at once
        foreach (Geary.EmailIdentifier id in ids)
            batch.add(new LocalBatchOperation(owner, id, required_fields));
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        // Build list of emails fully fetched from local store and table of remaining emails by
        // their lack of completeness
        Gee.List<Geary.Email> fulfilled = new Gee.ArrayList<Geary.Email>();
        foreach (int batch_id in batch.get_ids()) {
            LocalBatchOperation local_op = (LocalBatchOperation) batch.get_operation(batch_id);
            Geary.Email? email = (Geary.Email?) batch.get_result(batch_id);
            
            if (email == null)
                unfulfilled.set(required_fields, local_op.id);
            else if (!email.fields.fulfills(required_fields))
                unfulfilled.set(required_fields.clear(email.fields), local_op.id);
            else
                fulfilled.add(email);
        }
        
        if (fulfilled.size > 0) {
            if (accumulator != null)
                accumulator.add_all(fulfilled);
            
            if (cb != null)
                cb(fulfilled, null);
        }
        
        if (local_only || unfulfilled.size == 0) {
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (!yield owner.wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", owner.to_string());
        
        NonblockingBatch batch = new NonblockingBatch();
        
        // schedule operations to remote for each set of email with unfulfilled fields and merge
        // in results, pulling out the entire email
        foreach (Geary.Email.Field unfulfilled_fields in unfulfilled.get_keys()) {
            Imap.MessageSet msg_set = new Imap.MessageSet.email_id_collection(
                unfulfilled.get(unfulfilled_fields));
            RemoteBatchOperation remote_op = new RemoteBatchOperation(owner, msg_set, unfulfilled_fields,
                required_fields);
            batch.add(remote_op);
        }
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        Gee.ArrayList<Geary.Email> result_list = new Gee.ArrayList<Geary.Email>();
        foreach (int batch_id in batch.get_ids()) {
            Gee.List<Geary.Email>? list = (Gee.List<Geary.Email>?) batch.get_result(batch_id);
            if (list != null && list.size > 0)
                result_list.add_all(list);
        }
        
        // report merged emails
        if (result_list.size > 0) {
            if (accumulator != null)
                accumulator.add_all(result_list);
            
            if (cb != null)
                cb(result_list, null);
        }
        
        // done
        if (cb != null)
            cb(null, null);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, nothing to backout
    }
    
    public override string describe_state() {
        return "ids.size=%d required_fields=%Xh flags=%Xh".printf(ids.size, required_fields, flags);
    }
}

private class Geary.FetchEmail : Geary.SendReplayOperation {
    public Email? email = null;
    
    private GenericImapFolder engine;
    private EmailIdentifier id;
    private Email.Field required_fields;
    private Email.Field remaining_fields;
    private Folder.ListFlags flags;
    private Cancellable? cancellable;
    
    public FetchEmail(GenericImapFolder engine, EmailIdentifier id, Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        base ("FetchEmail");
        
        this.engine = engine;
        this.id = id;
        this.required_fields = required_fields;
        remaining_fields = required_fields;
        this.flags = flags;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // If forcing an update, skip local operation and go direct to replay_remote()
        if (flags.is_all_set(Folder.ListFlags.FORCE_UPDATE))
            return ReplayOperation.Status.CONTINUE;
        
        try {
            email = yield engine.local_folder.fetch_email_async(id, required_fields,
                Sqlite.Folder.ListFlags.PARTIAL_OK, cancellable);
        } catch (Error err) {
            // If NOT_FOUND or INCOMPLETE_MESSAGE, then fall through, otherwise return to sender
            if (!(err is Geary.EngineError.NOT_FOUND) && !(err is Geary.EngineError.INCOMPLETE_MESSAGE))
                throw err;
        }
        
        // If returned in full, done
        if (email != null && email.fields.fulfills(required_fields))
            return ReplayOperation.Status.COMPLETED;
        
        // If local only and not found fully in local store, throw NOT_FOUND; there is no fallback
        if (flags.is_all_set(Folder.ListFlags.LOCAL_ONLY)) {
            throw new EngineError.NOT_FOUND("Email %s with fields %Xh not found in %s", id.to_string(),
                required_fields, to_string());
        }
        
        // only fetch what's missing
        if (email != null)
            remaining_fields = required_fields.clear(email.fields);
        else
            remaining_fields = required_fields;
        
        assert(remaining_fields != 0);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (!yield engine.wait_for_remote_to_open(cancellable))
            throw new EngineError.SERVER_UNAVAILABLE("No connection to %s", engine.to_string());
        
        // fetch only the remaining fields from the remote folder (if only pulling partial information,
        // will merge at end of this method)
        Gee.List<Geary.Email>? list = yield engine.remote_folder.list_email_async(
            new Imap.MessageSet.email_id(id), remaining_fields, cancellable);
        
        if (list == null || list.size != 1)
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s", id.to_string(), engine.to_string());
        
        // save to local store
        email = list[0];
        assert(email != null);
        if (yield engine.local_folder.create_email_async(email, cancellable))
            engine.notify_email_locally_appended(new Geary.Singleton<Geary.EmailIdentifier>(email.id));
        
        // if remote_email doesn't fulfill all required, pull from local database, which should now
        // be able to do all of that
        if (!email.fields.fulfills(required_fields)) {
            email = yield engine.local_folder.fetch_email_async(id, required_fields,
                Sqlite.Folder.ListFlags.NONE, cancellable);
            assert(email != null);
        }
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // read-only
    }
    
    public override string describe_state() {
        return "id=%s required_fields=%Xh remaining_fields=%Xh flags=%Xh".printf(id.to_string(),
            required_fields, remaining_fields, flags);
    }
}

private class Geary.CopyEmail : Geary.SendReplayOperation {
    private GenericImapFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_copy;
    private Geary.FolderPath destination;
    private Cancellable? cancellable;

    public CopyEmail(GenericImapFolder engine, Gee.List<Geary.EmailIdentifier> to_copy, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("CopyEmail");

        this.engine = engine;

        this.to_copy = to_copy;
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        // The local DB will be updated when the remote folder is opened and we see a new message
        // existing there.
        return ReplayOperation.Status.CONTINUE;
    }

    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.remote_folder.copy_email_async(new Imap.MessageSet.email_id_collection(to_copy),
            destination, cancellable);

        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        // Nothing to undo.
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_copy.size, destination.to_string());
    }
}

private class Geary.MoveEmail : Geary.SendReplayOperation {
    private GenericImapFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_move;
    private Geary.FolderPath destination;
    private Cancellable? cancellable;
    private int original_count = 0;

    public MoveEmail(GenericImapFolder engine, Gee.List<Geary.EmailIdentifier> to_move, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("MoveEmail");

        this.engine = engine;

        this.to_move = to_move;
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        // Remove the email from the folder.
        // TODO: Use a local_folder method that operates on all messages at once
        foreach (Geary.EmailIdentifier id in to_move)
            yield engine.local_folder.mark_removed_async(id, true, cancellable);
        engine.notify_email_removed(to_move);

        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_move.size,
            Geary.Folder.CountChangeReason.REMOVED);

        return ReplayOperation.Status.CONTINUE;
    }

    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.remote_folder.move_email_async(new Imap.MessageSet.email_id_collection(to_move),
            destination, cancellable);

        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        // Add the email back in.
        // TODO: Use a local_folder method that operates on all messages at once
        foreach (Geary.EmailIdentifier id in to_move)
            yield engine.local_folder.mark_removed_async(id, false, cancellable);

        engine.notify_email_appended(to_move);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_move.size, destination.to_string());
    }
}

