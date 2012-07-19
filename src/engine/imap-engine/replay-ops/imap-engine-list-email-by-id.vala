/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.ListEmailByID : Geary.ImapEngine.ListEmail {
    private Geary.EmailIdentifier initial_id;
    
    public ListEmailByID(GenericFolder engine, Geary.EmailIdentifier initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) {
        base(engine, 0, count, required_fields, flags, accumulator, cb, cancellable);
        
        name = "ListEmailByID";
        
        this.initial_id = initial_id;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        int local_count = yield engine.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
            cancellable);
        
        int initial_position = yield engine.local_folder.get_id_position_async(initial_id,
            ImapDB.Folder.ListFlags.NONE, cancellable);
        if (initial_position <= 0) {
            throw new EngineError.NOT_FOUND("Email ID %s in %s not known to local store",
                initial_id.to_string(), engine.to_string());
        }
        
        int remote_count;
        int last_seen_remote_count;
        int usable_remote_count = engine.get_remote_counts(out remote_count, out last_seen_remote_count);
        
        // use local count if both remote counts unavailable
        if (usable_remote_count < 0)
            usable_remote_count = local_count;
        
        // normalize the initial position to the remote folder's addressing
        initial_position = engine.local_position_to_remote_position(initial_position, local_count, usable_remote_count);
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
            high = (count != int.MAX) ? (initial_position + count - 1) : usable_remote_count;
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
        
        // Always return completed if the base class says so
        if ((yield base.replay_local_async()) == ReplayOperation.Status.COMPLETED)
            return ReplayOperation.Status.COMPLETED;
        
        // Only return CONTINUE if connected to the remote (otherwise possibility of mixing stale
        // and fresh email data in single call)
        return (remote_count >= 0) ? ReplayOperation.Status.CONTINUE : ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "%s initial_id=%s excl=%s".printf(base.describe_state(), initial_id.to_string(),
            excluding_id.to_string());
    }
}

