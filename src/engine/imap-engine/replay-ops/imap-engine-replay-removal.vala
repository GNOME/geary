/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayRemoval : Geary.ImapEngine.ReplayOperation {
    private MinimalFolder owner;
    private int remote_count;
    private Imap.SequenceNumber position;
    
    public ReplayRemoval(MinimalFolder owner, int remote_count, Imap.SequenceNumber position) {
        // remote error will cause folder to reconnect and re-normalize, making this remove moot
        base ("Removal", Scope.LOCAL_AND_REMOTE, OnError.IGNORE);
        
        this.owner = owner;
        this.remote_count = remote_count;
        this.position = position;
    }
    
    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
        // although using positional addressing, don't update state; EXPUNGEs that happen after
        // other EXPUNGEs have no affect on those ahead of it
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // this operation deals only in positional addressing
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // this ReplayOperation doesn't do remote removes, it reacts to them
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // Although technically a local-only operation, must treat as remote to ensure it's
        // processed in-order with ReplayAppend operations
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield owner.do_replay_removed_message(remote_count, position);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "position=%s".printf(position.to_string());
    }
}

