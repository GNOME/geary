/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A @{link Geary.Revokable} for {@link MinimalFolder} move operations.
 *
 * This will delay executing the move until (a) the source Folder is closed or (b) a timeout passes.
 * Even then, it will fire its "committed" signal with a {@link RevokableCommittedMove} to allow
 * the user to undo the operation, albeit taking more time to connect, open the destination folder,
 * and move the mail back.
 */

private class Geary.ImapEngine.RevokableMove : Revokable {
    private const int COMMIT_TIMEOUT_SEC = 60;
    
    private GenericAccount account;
    private ImapEngine.MinimalFolder source;
    private FolderPath destination;
    private Gee.Set<ImapDB.EmailIdentifier> move_ids;
    
    public RevokableMove(GenericAccount account, ImapEngine.MinimalFolder source, FolderPath destination,
        Gee.Set<ImapDB.EmailIdentifier> move_ids) {
        base (COMMIT_TIMEOUT_SEC);
        
        this.account = account;
        this.source = source;
        this.destination = destination;
        this.move_ids = move_ids;
        
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        source.email_removed.connect(on_source_email_removed);
        source.marked_email_removed.connect(on_source_email_removed);
        source.closing.connect(on_source_closing);
    }
    
    ~RevokableMove() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        source.email_removed.disconnect(on_source_email_removed);
        source.marked_email_removed.disconnect(on_source_email_removed);
        source.closing.disconnect(on_source_closing);
        
        // if still valid, schedule operation so its executed
        if (valid && source.get_open_state() != Folder.OpenState.CLOSED) {
            debug("Freeing revokable, scheduling move %d emails from %s to %s", move_ids.size,
                source.path.to_string(), destination.to_string());
            
            try {
                source.schedule_op(new MoveEmailCommit(source, move_ids, destination, null));
            } catch (Error err) {
                debug("Move from %s to %s failed: %s", source.path.to_string(), destination.to_string(),
                    err.message);
            }
        } else if (valid) {
            debug("Not scheduling freed move revokable for %s, open_state=%s",
                source.path.to_string(), source.get_open_state().to_string());
        }
    }
    
    protected override async void internal_revoke_async(Cancellable? cancellable) throws Error {
        try {
            yield source.exec_op_async(new MoveEmailRevoke(source, move_ids, cancellable),
                cancellable);
            
            // valid must still be true before firing
            notify_revoked();
        } finally {
            set_invalid();
        }
    }
    
    protected override async void internal_commit_async(Cancellable? cancellable) throws Error {
        try {
            MoveEmailCommit op = new MoveEmailCommit(source, move_ids, destination, cancellable);
            yield source.exec_op_async(op, cancellable);
            
            // valid must still be true before firing
            notify_committed(new RevokableCommittedMove(account, source.path, destination, op.destination_uids));
        } finally {
            set_invalid();
        }
    }
    
    private void on_folders_available_unavailable(Gee.List<Folder>? available, Gee.List<Folder>? unavailable) {
        // look for either of the folders going away
        if (unavailable != null) {
            foreach (Folder folder in unavailable) {
                if (folder.path.equal_to(source.path) || folder.path.equal_to(destination)) {
                    set_invalid();
                    
                    break;
                }
            }
        }
    }
    
    private void on_source_email_removed(Gee.Collection<EmailIdentifier> ids) {
        // one-way switch
        if (!valid)
            return;
        
        foreach (EmailIdentifier id in ids)
            move_ids.remove((ImapDB.EmailIdentifier) id);
        
        if (move_ids.size <= 0)
            set_invalid();
    }
    
    private void on_source_closing(Gee.List<ReplayOperation> final_ops) {
        if (!valid)
            return;
        
        final_ops.add(new MoveEmailCommit(source, move_ids, destination, null));
        set_invalid();
    }
}

