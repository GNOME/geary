/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayDisconnect : Geary.ImapEngine.ReplayOperation {
    public MinimalFolder owner;
    public Imap.ClientSession.DisconnectReason reason;
    
    public ReplayDisconnect(MinimalFolder owner, Imap.ClientSession.DisconnectReason reason) {
        base ("Disconnect", Scope.LOCAL_ONLY);
        
        this.owner = owner;
        this.reason = reason;
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
            ? Geary.Folder.CloseReason.REMOTE_ERROR : Geary.Folder.CloseReason.REMOTE_CLOSE;
        
        // because close_internal_async() may schedule a ReplayOperation before its first yield,
        // that means a ReplayOperation is scheduling a ReplayOperation, which isn't something
        // we want to encourage, so use the Idle queue to schedule close_internal_async
        Idle.add(() => {
            // ReplayDisconnect is only used when remote disconnects, so never flush pending, the
            // connection is down or going down
            owner.close_internal_async.begin(Geary.Folder.CloseReason.LOCAL_CLOSE, remote_reason,
                false, null);
            
            return false;
        });
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // shot not be called
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "reason=%s".printf(reason.to_string());
    }
}

