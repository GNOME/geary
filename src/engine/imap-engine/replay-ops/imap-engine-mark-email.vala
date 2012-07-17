/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.MarkEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_mark;
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;
    
    public MarkEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_mark, 
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) {
        base("MarkEmail");
        
        this.engine = engine;
        
        this.to_mark = to_mark;
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // Save original flags, then set new ones.
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        yield engine.local_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        // Notify using flags from DB.
        engine.notify_email_flags_changed(yield engine.local_folder.get_email_flags_async(to_mark,
            cancellable));
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        yield engine.remote_folder.mark_email_async(new Imap.MessageSet.email_id_collection(to_mark),
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

