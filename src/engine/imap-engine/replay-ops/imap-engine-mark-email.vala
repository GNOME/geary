/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MarkEmail : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_mark = new Gee.ArrayList<Geary.EmailIdentifier>();
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;
    
    public MarkEmail(MinimalFolder engine, Gee.List<Geary.EmailIdentifier> to_mark, 
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) {
        base("MarkEmail", OnError.RETRY);
        
        this.engine = engine;
        
        this.to_mark.add_all(to_mark);
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // don't bother updating on server or backing out locally
        if (original_flags != null)
            Collection.map_unset_all_keys<ImapDB.EmailIdentifier, Geary.EmailFlags>(original_flags, ids);
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
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
            engine.replay_notify_email_flags_changed(map);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // potentially empty due to writebehind operation
        if (original_flags.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(
            ImapDB.EmailIdentifier.to_uids(original_flags.keys));
        yield engine.remote_folder.mark_email_async(msg_sets, flags_to_add, flags_to_remove,
            cancellable);
        
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

