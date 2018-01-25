/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayDisconnect : Geary.ImapEngine.ReplayOperation {
    private MinimalFolder owner;
    private Imap.ClientSession.DisconnectReason reason;
    private bool flush_pending;
    private Cancellable? cancellable;
    
    public ReplayDisconnect(MinimalFolder owner, Imap.ClientSession.DisconnectReason reason,
        bool flush_pending, Cancellable? cancellable) {
        base ("Disconnect", Scope.LOCAL_ONLY);
        
        this.owner = owner;
        this.reason = reason;
        this.flush_pending = flush_pending;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        debug("%s ReplayDisconnect reason=%s", owner.to_string(), reason.to_string());

        Geary.Folder.CloseReason remote_reason = reason.is_error()
            ? Geary.Folder.CloseReason.REMOTE_ERROR
            : Geary.Folder.CloseReason.REMOTE_CLOSE;

        this.owner.close_remote_session.begin(remote_reason);
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // should not be called
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "reason=%s".printf(reason.to_string());
    }
}
