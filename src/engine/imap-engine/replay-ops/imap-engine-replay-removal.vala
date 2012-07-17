/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.ReplayRemoval : Geary.ImapEngine.ReceiveReplayOperation {
    public GenericFolder owner;
    public int position;
    public int new_remote_count;
    
    public ReplayRemoval(GenericFolder owner, int position, int new_remote_count) {
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

