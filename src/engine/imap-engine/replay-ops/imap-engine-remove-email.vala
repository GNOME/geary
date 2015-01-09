/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.RemoveEmail : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_remove = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Cancellable? cancellable;
    private Gee.Set<ImapDB.EmailIdentifier>? removed_ids = null;
    private int original_count = 0;
    
    public RemoveEmail(MinimalFolder engine, Gee.List<ImapDB.EmailIdentifier> to_remove,
        Cancellable? cancellable = null) {
        base("RemoveEmail");
        
        this.engine = engine;
        
        this.to_remove.add_all(to_remove);
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (removed_ids != null)
            removed_ids.remove_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // if performing a full expunge, need to move on to replay_remote_async() for that
        if (to_remove.size <= 0)
            return ReplayOperation.Status.COMPLETED;
        
        int remote_count;
        int last_seen_remote_count;
        original_count = engine.get_remote_counts(out remote_count, out last_seen_remote_count);
        
        // because this value is only used for reporting count changes, offer best-possible service
        if (original_count < 0)
            original_count = to_remove.size;
        
        removed_ids = yield engine.local_folder.mark_removed_async(to_remove, true, cancellable);
        if (removed_ids == null || removed_ids.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        engine.notify_email_removed(removed_ids);
        
        engine.notify_email_count_changed(Numeric.int_floor(original_count - removed_ids.size, 0),
            Geary.Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (removed_ids != null)
            ids.add_all(removed_ids);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // Remove from server. Note that this causes the receive replay queue to kick into
        // action, removing the e-mail but *NOT* firing a signal; the "remove marker" indicates
        // that the signal has already been fired.
        Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(
            ImapDB.EmailIdentifier.to_uids(removed_ids));
        yield engine.remote_folder.remove_email_async(msg_sets, cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        if (removed_ids != null && removed_ids.size > 0) {
            yield engine.local_folder.mark_removed_async(removed_ids, false, cancellable);
            engine.notify_email_inserted(removed_ids);
        }
        
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.INSERTED);
    }
    
    public override string describe_state() {
        return "to_remove.size=%d removed_ids.size=%d".printf(to_remove.size,
            (removed_ids != null) ? removed_ids.size : 0);
    }
}

