/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MarkEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_mark = new Gee.ArrayList<Geary.EmailIdentifier>();
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;
    
    public MarkEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_mark, 
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) {
        base("MarkEmail");
        
        this.engine = engine;
        
        this.to_mark.add_all(to_mark);
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_mark.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // Save original flags, then set new ones.
        // TODO: Make this atomic (otherwise there stands a chance backout_local_async() will
        // reapply the wrong flags): should get the original flags and the new flags in the same
        // operation as the marking procedure, so original flags and reported flags are correct
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        if (original_flags == null || original_flags.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        yield engine.local_folder.mark_email_async(original_flags.keys, flags_to_add, flags_to_remove,
            cancellable);
        
        // Notify using flags from DB.
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? map = yield engine.local_folder.get_email_flags_async(
            original_flags.keys, cancellable);
        if (map != null && map.size > 0)
            engine.notify_email_flags_changed(map);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
        EmailIdentifier id, Imap.EmailFlags? flags) {
        ImapDB.EmailIdentifier? imapdb_id = id as ImapDB.EmailIdentifier;
        if (imapdb_id == null)
            return true;
        
        if (!original_flags.has_key(imapdb_id))
            return true;
        
        switch (op) {
            case ReplayOperation.WritebehindOperation.REMOVE:
                // don't bother updating on server
                original_flags.unset(imapdb_id);
                
                return true;
            
            case ReplayOperation.WritebehindOperation.UPDATE_FLAGS:
                // user's mark operation takes precedence over server's, update supplied flags
                // and continue
                if (flags_to_add != null && flags != null)
                    flags.add_all(flags_to_add);
                
                if (flags_to_remove != null && flags != null)
                    flags.remove_all(flags_to_remove);
                
                return true;
            
            case ReplayOperation.WritebehindOperation.CREATE:
            default:
                // not interested in other operations
                return true;
        }
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // potentially empty due to writebehind operation
        if (original_flags.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        yield engine.remote_folder.mark_email_async(
            new Imap.MessageSet.uid_sparse(ImapDB.EmailIdentifier.to_uids(original_flags.keys).to_array()),
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

