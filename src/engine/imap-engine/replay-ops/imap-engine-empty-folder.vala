/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Similar to RemoveEmail, except this command ''always'' issues the command to remove all mail,
 * ensuring the entire folder is emptied even if only a portion of it is synchronized locally.
 */

private class Geary.ImapEngine.EmptyFolder : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Cancellable? cancellable;
    private Gee.Set<ImapDB.EmailIdentifier>? removed_ids = null;
    private int original_count = 0;
    
    public EmptyFolder(MinimalFolder engine, Cancellable? cancellable) {
        base("EmptyFolder", OnError.RETRY);
        
        this.engine = engine;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        original_count = engine.get_remote_counts(null, null);
        
        // because this value is only used for reporting count changes, offer best-possible service
        if (original_count < 0)
            original_count = 0;
        
        // mark everything in the folder as removed
        removed_ids = yield engine.local_folder.mark_removed_async(null, true, cancellable);
        
        // if local folder is not empty, report all as being removed
        if (removed_ids != null) {
            if (removed_ids.size > 0)
                engine.replay_notify_email_removed(removed_ids);
            
            int new_count = Numeric.int_floor(original_count - removed_ids.size, 0);
            if (new_count != original_count)
                engine.replay_notify_email_count_changed(new_count, Geary.Folder.CountChangeReason.REMOVED);
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (removed_ids != null)
            ids.add_all(removed_ids);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // STORE and EXPUNGE using positional addressing: "1:*"
        Imap.MessageSet msg_set = new Imap.MessageSet.range_to_highest(
            new Imap.SequenceNumber(Imap.SequenceNumber.MIN));
        
        yield engine.remote_folder.remove_email_async(msg_set.to_list(), cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        if (removed_ids != null && removed_ids.size > 0) {
            yield engine.local_folder.mark_removed_async(removed_ids, false, cancellable);
            engine.replay_notify_email_inserted(removed_ids);
        }
        
        engine.replay_notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.INSERTED);
    }
    
    public override string describe_state() {
        return "removed_ids.size=%d".printf((removed_ids != null) ? removed_ids.size : 0);
    }
}

