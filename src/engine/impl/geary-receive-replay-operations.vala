/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private abstract class Geary.ReceiveReplayOperation : Geary.ReplayOperation {
    public ReceiveReplayOperation(string name) {
        base (name, ReplayOperation.Scope.LOCAL_ONLY);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        debug("Warning: ReceiveReplayOperation.replay_remote_async() called");
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        debug("Warning: ReceiveReplayOperation.backout_local_async() called");
    }
}

private class Geary.ReplayAppend : Geary.ReceiveReplayOperation {
    public GenericImapFolder owner;
    public int new_remote_count;
    
    public ReplayAppend(GenericImapFolder owner, int new_remote_count) {
        base ("Append");
        
        this.owner = owner;
        this.new_remote_count = new_remote_count;
    }
    
    public override async ReplayOperation.Status replay_local_async() {
        yield owner.do_replay_appended_messages(new_remote_count);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "new_remote_count=%d".printf(new_remote_count);
    }
}

private class Geary.ReplayRemoval : Geary.ReceiveReplayOperation {
    public GenericImapFolder owner;
    public int position;
    public int new_remote_count;
    
    public ReplayRemoval(GenericImapFolder owner, int position, int new_remote_count) {
        base ("Removal");
        
        this.owner = owner;
        this.position = position;
        this.new_remote_count = new_remote_count;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        yield owner.do_replay_remove_message(position, new_remote_count);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "position=%d new_remote_count=%d".printf(position, new_remote_count);
    }
}

private class Geary.ReplayDisconnect : Geary.ReceiveReplayOperation {
    public GenericImapFolder owner;
    public Geary.Folder.CloseReason reason;
    
    public ReplayDisconnect(GenericImapFolder owner, Geary.Folder.CloseReason reason) {
        base ("Disconnect");
        
        this.owner = owner;
        this.reason = reason;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        yield owner.do_replay_remote_disconnected(reason);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "reason=%s".printf(reason.to_string());
    }
}
