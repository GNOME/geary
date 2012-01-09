/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.MarkEmail : Geary.SendReplayOperation {
    private EngineFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_mark;
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;
        
    public MarkEmail(EngineFolder engine, Gee.List<Geary.EmailIdentifier> to_mark, 
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, 
        Cancellable? cancellable = null) {
        base("MarkEmail");
        
        this.engine = engine;
        
        this.to_mark = to_mark;
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }
    
    public override async bool replay_local() throws Error {
        // Save original flags, then set new ones.
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        yield engine.local_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        // Notify using flags from DB.
        engine.notify_email_flags_changed(yield engine.local_folder.get_email_flags_async(to_mark,
            cancellable));
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        yield engine.remote_folder.mark_email_async(to_mark, flags_to_add, flags_to_remove,
            cancellable);
        
        return true;
    }
    
    public override async void backout_local() throws Error {
        // Restore original flags.
        yield engine.local_folder.set_email_flags_async(original_flags, cancellable);
    }
}

private class Geary.RemoveEmail : Geary.SendReplayOperation {
    private EngineFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_remove;
    private Cancellable? cancellable;
    private int original_count = 0;
    
    public RemoveEmail(EngineFolder engine, Gee.List<Geary.EmailIdentifier> to_remove,
        Cancellable? cancellable = null) {
        base("RemoveEmail");
        
        this.engine = engine;
        
        this.to_remove = to_remove;
        this.cancellable = cancellable;
    }
    
    public override async bool replay_local() throws Error {
        foreach (Geary.EmailIdentifier id in to_remove) {
            yield engine.local_folder.mark_removed_async(id, true, cancellable);
            engine.notify_message_removed(id);
        }
        
        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_remove.size,
            Geary.Folder.CountChangeReason.REMOVED);
        
        return false;
    }
    
    public override async bool replay_remote() throws Error {
        // Remove from server. Note that this causes the receive replay queue to kick into
        // action, removing the e-mail but *NOT* firing a signal; the "remove marker" indicates
        // that the signal has already been fired.
        yield engine.remote_folder.remove_email_async(to_remove, cancellable);
        
        return true;
    }
    
    public override async void backout_local() throws Error {
        foreach (Geary.EmailIdentifier id in to_remove)
            yield engine.local_folder.mark_removed_async(id, false, cancellable);
        
        engine.notify_messages_appended(to_remove.size);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.REMOVED);
    }
}

