/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ReplayAppend : Geary.ReceiveReplayOperation {
    public GenericImapFolder owner;
    public int new_remote_count;
    
    public ReplayAppend(GenericImapFolder owner, int new_remote_count) {
        base ("Append");
        
        this.owner = owner;
        this.new_remote_count = new_remote_count;
    }
    
    public override async void replay() {
        yield owner.do_replay_appended_messages(new_remote_count);
    }
}

private class Geary.ReplayRemoval : Geary.ReceiveReplayOperation {
    public GenericImapFolder owner;
    public int position;
    public int new_remote_count;
    public EmailIdentifier? id;
    
    public ReplayRemoval(GenericImapFolder owner, int position, int new_remote_count) {
        base ("Removal");
        
        this.owner = owner;
        this.position = position;
        this.new_remote_count = new_remote_count;
        this.id = null;
    }
    
    public ReplayRemoval.with_id(GenericImapFolder owner, EmailIdentifier id) {
        base ("Removal.with_id");
        
        this.owner = owner;
        position = -1;
        new_remote_count = -1;
        this.id = id;
    }
    
    public override async void replay() {
        yield owner.do_replay_remove_message(position, new_remote_count, id);
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
    
    public override async void replay() {
        yield owner.do_replay_remote_disconnected(reason);
    }
}
