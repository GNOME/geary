/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ExpungeEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_remove = new Gee.ArrayList<EmailIdentifier>(
        Equalable.equal_func);
    private Cancellable? cancellable;
    private int original_count = 0;
    
    public ExpungeEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_remove,
        Cancellable? cancellable = null) {
        base("ExpungeEmail");
        
        this.engine = engine;
        
        this.to_remove.add_all(to_remove);
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_remove.size <= 0)
            return ReplayOperation.Status.COMPLETED;
        
        int remote_count;
        int last_seen_remote_count;
        original_count = engine.get_remote_counts(out remote_count, out last_seen_remote_count);
        
        // because this value is only used for reporting count changes, offer best-possible service
        if (original_count < 0)
            original_count = to_remove.size;
        
        yield engine.local_folder.mark_removed_async(to_remove, true, cancellable);
        
        engine.notify_email_removed(to_remove);
        
        engine.notify_email_count_changed(original_count - to_remove.size,
            Geary.Folder.CountChangeReason.REMOVED);
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
        EmailIdentifier id, Imap.EmailFlags? flags) {
        if (!to_remove.contains(id))
            return true;
        
        switch (op) {
            case ReplayOperation.WritebehindOperation.CREATE:
                // don't allow for the message to be created, it will be removed on the server by
                // this operation
                return false;
            
            case ReplayOperation.WritebehindOperation.REMOVE:
                // removed locally, to be removed remotely, don't bother writing locally
                return false;
            
            default:
                // ignored
                return true;
        }
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
        yield engine.local_folder.mark_removed_async(to_remove, false, cancellable);
        
        engine.notify_email_appended(to_remove);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }
    
    public override string describe_state() {
        return "to_remove=%d".printf(to_remove.size);
    }
}

