/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

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
    
    public override async bool replay_local() throws Error {
        // Save original flags, then set new ones.
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        yield engine.local_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        // Notify using flags from DB.
        engine.notify_email_flags_changed(yield engine.local_folder.get_email_flags_async(to_mark,
            cancellable));
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        yield engine.remote_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        return true;
    }
    
    public override async void backout_local() throws Error {
        // Restore original flags.
        yield engine.local_folder.set_email_flags_async(original_flags, cancellable);
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
    
    public override async bool replay_local() throws Error {
        foreach (Geary.EmailIdentifier id in to_remove) {
            yield engine.local_folder.mark_removed_async(id, true, cancellable);
            engine.notify_email_removed(new Geary.Singleton<Geary.EmailIdentifier>(id));
        }
        
        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_remove.size,
            Geary.Folder.CountChangeReason.REMOVED);
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        // Remove from server. Note that this causes the receive replay queue to kick into
        // action, removing the e-mail but *NOT* firing a signal; the "remove marker" indicates
        // that the signal has already been fired.
        yield engine.remote_folder.remove_email_async(to_remove, cancellable);
        
        return true;
    }
    
    public override async void backout_local() throws Error {
        foreach (Geary.EmailIdentifier id in to_remove)
            yield engine.local_folder.mark_removed_async(id, false, cancellable);
        
        engine.notify_email_appended(to_remove);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }
}

private class Geary.ListEmail : Geary.SendReplayOperation {
    protected GenericImapFolder engine;
    protected int low;
    protected int count;
    protected Geary.Email.Field required_fields;
    protected Gee.List<Geary.Email>? accumulator = null;
    protected weak EmailCallback? cb;
    protected Cancellable? cancellable;
    protected bool local_only;
    protected bool remote_only;
    
    private Gee.List<Geary.Email>? local_list = null;
    private int local_list_size = 0;
    
    public ListEmail(GenericImapFolder engine, int low, int count, Geary.Email.Field required_fields,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable,
        bool local_only, bool remote_only) {
        base("ListEmail");
        
        this.engine = engine;
        this.low = low;
        this.count = count;
        this.required_fields = required_fields;
        this.accumulator = accumulator;
        this.cb = cb;
        this.cancellable = cancellable;
        this.local_only = local_only;
        this.remote_only = remote_only;
    }
    
    public override async bool replay_local() throws Error {
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
        int local_low;
        if (!local_only && (yield engine.wait_for_remote_to_open(cancellable)) &&
            engine.remote_count >= 0) {
            engine.normalize_span_specifiers(ref low, ref count, engine.remote_count);
            
            // because the local store caches messages starting from the newest (at the end of the list)
            // to the earliest fetched by the user, need to adjust the low value to match its offset
            // and range
            local_low = engine.remote_position_to_local_position(low, local_count);
        } else {
            engine.normalize_span_specifiers(ref low, ref count, local_count);
            local_low = low.clamp(1, local_count);
        }
        
        debug("ListEmail: low=%d count=%d local_count=%d remote_count=%d local_low=%d",
            low, count, local_count, engine.remote_count, local_low);
        
        if (!remote_only && local_low > 0) {
            try {
                local_list = yield engine.local_folder.list_email_async(local_low, count, required_fields,
                    Geary.Folder.ListFlags.NONE, cancellable);
            } catch (Error local_err) {
                if (cb != null && !(local_err is IOError.CANCELLED))
                    cb (null, local_err);
                throw local_err;
            }
        }
        
        local_list_size = (local_list != null) ? local_list.size : 0;
        
        debug("Fetched %d emails from local store for %s", local_list_size, engine.to_string());
        
        // fixup local email positions to match server's positions
        if (local_list_size > 0 && engine.remote_count > 0 && local_count < engine.remote_count) {
            int adjustment = engine.remote_count - local_count;
            foreach (Geary.Email email in local_list)
                email.update_position(email.position + adjustment);
        }
        
        // report list
        if (local_list_size > 0) {
            if (accumulator != null)
                accumulator.add_all(local_list);
            
            if (cb != null)
                cb(local_list, null);
        }
        
        // if local list matches total asked for, or if only returning local versions, exit
        if (local_list_size == count || local_only) {
            if (cb != null)
                cb(null, null);
            
            return true;
        }
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        // go through the positions from (low) to (low + count) and see if they're not already
        // present in local_list; whatever isn't present needs to be fetched
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
        
        if (needed_by_position.length == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return true;
        }
        
        Gee.List<Geary.Email>? remote_list = null;
        try {
            // if cb != null, it will be called by remote_list_email(), so don't call again with
            // returned list
            remote_list = yield engine.remote_list_email(needed_by_position, required_fields, cb,
                cancellable);
        } catch (Error remote_err) {
            if (cb != null)
                cb(null, remote_err);
            
            throw remote_err;
        }
        
        if (accumulator != null && remote_list != null && remote_list.size > 0)
            accumulator.add_all(remote_list);
        
        // signal finished
        if (cb != null)
            cb(null, null);
        
        return true;
    }
}

private class Geary.ListEmailByID : Geary.ListEmail {
    private Geary.EmailIdentifier initial_id;
    private bool excluding_id;
    
    public ListEmailByID(GenericImapFolder engine, Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Gee.List<Geary.Email>? accumulator, EmailCallback? cb,
        Cancellable? cancellable, bool local_only, bool remote_only, bool excluding_id) {
        base(engine, 0, count, required_fields, accumulator, cb, cancellable, local_only, remote_only);
        set_name("ListEmailByID");
        
        this.initial_id = initial_id;
        this.excluding_id = excluding_id;
    }
    
    public override async bool replay_local() throws Error {
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
            debug("ListEmailByID: no actual count to return (%d) (excluding=%s %s)",
                actual_count, excluding_id.to_string(), initial_id.to_string());
            
            if (cb != null)
                cb(null, null);
            
            return true;
        }
        
        debug("ListEmailByID: initial_id=%s initial_position=%d count=%d actual_count=%d low=%d high=%d local_count=%d remote_count=%d excl=%s",
            initial_id.to_string(), initial_position, count, actual_count, low, high, local_count,
            engine.remote_count, excluding_id.to_string());
        
        this.low = low;
        this.count = actual_count;
        return yield base.replay_local();
    }
}

private class Geary.ListEmailSparse : Geary.SendReplayOperation {
    private GenericImapFolder engine;
    private int[] by_position;
    private Geary.Email.Field required_fields;
    private Gee.List<Geary.Email>? accumulator = null;
    private weak EmailCallback? cb;
    private Cancellable? cancellable;
    private bool local_only;
    
    private int[] needed_by_position = new int[0];
    
    public ListEmailSparse(GenericImapFolder engine, int[] by_position, Geary.Email.Field required_fields,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable,
        bool local_only) {
        base("ListEmailSparse");
        
        this.engine = engine;
        this.by_position = by_position;
        this.required_fields = required_fields;
        this.accumulator = accumulator;
        this.cb = cb;
        this.cancellable = cancellable;
        this.local_only = local_only;
    }
    
    public override async bool replay_local() throws Error {
        int low, high;
        Arrays.int_find_high_low(by_position, out low, out high);
        
        int local_count, local_offset;
        if (!local_only) {
            // normalize the position (ordering) of what's available locally with the situation on
            // the server
            yield engine.normalize_email_positions_async(low, high - low + 1, out local_count,
                cancellable);
            
            local_offset = (engine.remote_count > local_count) ? (engine.remote_count - local_count
                - 1) : 0;
        } else {
            local_count = yield engine.local_folder.get_email_count_async(cancellable);
            local_offset = 0;
        }
        
        // Fixup all the positions to match the local store's notions
        if (local_offset > 0) {
            int[] local_by_position = new int[by_position.length];
            for (int ctr = 0; ctr < by_position.length; ctr++)
                local_by_position[ctr] = by_position[ctr] - local_offset;
            
            by_position = local_by_position;
        }
        
        Gee.List<Geary.Email>? local_list = null;
        try {
            local_list = yield engine.local_folder.list_email_sparse_async(by_position,
                required_fields, Folder.ListFlags.NONE, cancellable);
        } catch (Error local_err) {
            if (cb != null)
                cb(null, local_err);
            
            throw local_err;
        }
        
        int local_list_size = (local_list != null) ? local_list.size : 0;
        
        // reverse the process, fixing up all the returned messages to match the server's notions
        if (local_list_size > 0 && local_offset > 0) {
            foreach (Geary.Email email in local_list)
                email.update_position(email.position + local_offset);
        }
        
        if (local_list_size == by_position.length || local_only) {
            if (accumulator != null)
                accumulator.add_all(local_list);
            
            // report and signal finished
            if (cb != null) {
                cb(local_list, null);
                cb(null, null);
            }
            
            return true;
        }
        
        // go through the list looking for anything not already in the sparse by_position list
        // to fetch from the server; since by_position is not guaranteed to be sorted, the local
        // list needs to be searched each iteration.
        //
        // TODO: Optimize this, especially if large lists/sparse sets are supplied
        foreach (int position in by_position) {
            bool found = false;
            if (local_list != null) {
                foreach (Geary.Email email2 in local_list) {
                    if (email2.position == position) {
                        found = true;
                        
                        break;
                    }
                }
            }
            
            if (!found)
                needed_by_position += position;
        }
        
        if (needed_by_position.length == 0) {
            if (local_list != null && local_list.size > 0) {
                if (accumulator != null)
                    accumulator.add_all(local_list);
                
                if (cb != null)
                    cb(local_list, null);
            }
            
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return true;
        }
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        Gee.List<Geary.Email>? remote_list = null;
        try {
            // if cb != null, it will be called by remote_list_email(), so don't call again with
            // returned list
            remote_list = yield engine.remote_list_email(needed_by_position, required_fields, cb,
                cancellable);
        } catch (Error remote_err) {
            if (cb != null)
                cb(null, remote_err);
            
            throw remote_err;
        }
        
        if (accumulator != null && remote_list != null && remote_list.size > 0)
            accumulator.add_all(remote_list);
        
        // signal finished
        if (cb != null)
            cb(null, null);
        
        return true;
    }
}

