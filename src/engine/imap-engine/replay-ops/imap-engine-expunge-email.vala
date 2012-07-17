/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.ExpungeEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_remove;
    private Cancellable? cancellable;
    private int original_count = 0;
    
    public ExpungeEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_remove,
        Cancellable? cancellable = null) {
        base("ExpungeEmail");
        
        this.engine = engine;
        
        this.to_remove = to_remove;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(to_remove, true, cancellable);
        
        engine.notify_email_removed(to_remove);
        
        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_remove.size,
            Geary.Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        // Remove from server. Note that this causes the receive replay queue to kick into
        // action, removing the e-mail but *NOT* firing a signal; the "remove marker" indicates
        // that the signal has already been fired.
        yield engine.remote_folder.remove_email_async(new Imap.MessageSet.email_id_collection(to_remove),
            cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(to_remove, false, cancellable);
        
        engine.notify_email_appended(to_remove);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }
    
    public override string describe_state() {
        return "to_remove=%d".printf(to_remove.size);
    }
}

