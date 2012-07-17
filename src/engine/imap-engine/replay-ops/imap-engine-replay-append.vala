/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.ReplayAppend : Geary.ImapEngine.ReceiveReplayOperation {
    public GenericFolder owner;
    public int new_remote_count;
    
    public ReplayAppend(GenericFolder owner, int new_remote_count) {
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

