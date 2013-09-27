/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayRemoval : Geary.ImapEngine.ReceiveReplayOperation {
    public GenericFolder owner;
    public Imap.SequenceNumber position;
    
    public ReplayRemoval(GenericFolder owner, Imap.SequenceNumber position) {
        base ("Removal");
        
        this.owner = owner;
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
        yield owner.do_replay_removed_message(position);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "position=%s".printf(position.to_string());
    }
}

