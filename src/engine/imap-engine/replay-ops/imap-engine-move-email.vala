/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MoveEmail : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_move = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;
    private Gee.Set<ImapDB.EmailIdentifier>? moved_ids = null;
    private int original_count = 0;

    public MoveEmail(MinimalFolder engine, Gee.List<ImapDB.EmailIdentifier> to_move, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("MoveEmail");

        this.engine = engine;

        this.to_move.add_all(to_move);
        this.destination = destination;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // don't bother updating on server or backing out locally
        if (moved_ids != null)
            moved_ids.remove_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_move.size <= 0)
            return ReplayOperation.Status.COMPLETED;
        
        int remote_count;
        int last_seen_remote_count;
        original_count = engine.get_remote_counts(out remote_count, out last_seen_remote_count);
        
        // as this value is only used for reporting, offer best-possible service
        if (original_count < 0)
            original_count = to_move.size;
        
        moved_ids = yield engine.local_folder.mark_removed_async(to_move, true, cancellable);
        if (moved_ids == null || moved_ids.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        engine.notify_email_removed(moved_ids);
        
        engine.notify_email_count_changed(Numeric.int_floor(original_count - to_move.size, 0),
            Geary.Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (moved_ids != null)
            ids.add_all(moved_ids);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (moved_ids.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // don't use Cancellable throughout I/O operations in order to assure transaction completes
        // fully
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("Move email to %s cancelled", engine.remote_folder.to_string());
        
        Imap.MessageSet msg_set = new Imap.MessageSet.uid_sparse(ImapDB.EmailIdentifier.to_uids(moved_ids).to_array());
        
        yield engine.remote_folder.copy_email_async(msg_set, destination, null);
        yield engine.remote_folder.remove_email_async(msg_set, null);
        
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(moved_ids, false, cancellable);
        
        engine.notify_email_inserted(moved_ids);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.INSERTED);
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_move.size, destination.to_string());
    }
}

