/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Stage two of a {@link RevokableMove}: move messages from folder to destination.
 */

private class Geary.ImapEngine.MoveEmailCommit : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<Imap.UID> destination_uids = new Gee.HashSet<Imap.UID>();
    
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_move = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;
    private Gee.List<Imap.MessageSet>? remaining_msg_sets = null;
    
    public MoveEmailCommit(MinimalFolder engine, Gee.Collection<ImapDB.EmailIdentifier> to_move,
        Geary.FolderPath destination, Cancellable? cancellable) {
        base.only_remote("MoveEmailCommit", OnError.RETRY);
        
        this.engine = engine;
        
        this.to_move.add_all(to_move);
        this.destination = destination;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        to_move.remove_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        ids.add_all(to_move);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (to_move.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // Remaining MessageSets are persisted in case of network retries
        if (remaining_msg_sets == null)
            remaining_msg_sets = Imap.MessageSet.uid_sparse(ImapDB.EmailIdentifier.to_uids(to_move));
        
        if (remaining_msg_sets == null || remaining_msg_sets.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        Gee.Iterator<Imap.MessageSet> iter = remaining_msg_sets.iterator();
        while (iter.next()) {
            // don't use Cancellable throughout I/O operations in order to assure transaction completes
            // fully
            if (cancellable != null && cancellable.is_cancelled())
                throw new IOError.CANCELLED("Move email to %s cancelled", engine.remote_folder.to_string());
            
            Imap.MessageSet msg_set = iter.get();
            
            Gee.Map<Imap.UID, Imap.UID>? map = yield engine.remote_folder.copy_email_async(msg_set,
                destination, null);
            if (map != null)
                destination_uids.add_all(map.values);
            
            yield engine.remote_folder.remove_email_async(msg_set.to_list(), null);
            
            // completed successfully, remove from list in case of retry
            iter.remove();
        }
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        if (to_move.size == 0)
            return;
        
        yield engine.local_folder.mark_removed_async(to_move, false, cancellable);
        
        int count = engine.get_remote_counts(null, null);
        
        engine.replay_notify_email_inserted(to_move);
        engine.replay_notify_email_count_changed(count + to_move.size, Folder.CountChangeReason.INSERTED);
    }
    
    public override string describe_state() {
        return "%d email IDs to %s".printf(to_move.size, destination.to_string());
    }
}

