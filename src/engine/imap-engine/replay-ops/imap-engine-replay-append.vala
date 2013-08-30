/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayAppend : Geary.ImapEngine.ReceiveReplayOperation {
    public GenericFolder owner;
    public Gee.List<Imap.SequenceNumber> positions;
    
    public ReplayAppend(GenericFolder owner, Gee.List<Imap.SequenceNumber> positions) {
        base ("Append");
        
        this.owner = owner;
        this.positions = positions;
    }
    
    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
        Gee.List<Imap.SequenceNumber> new_positions = new Gee.ArrayList<Imap.SequenceNumber>();
        foreach (Imap.SequenceNumber? position in positions) {
            Imap.SequenceNumber old_position = position;
            
            // adjust depending on relation to removed message
            position = position.shift_for_removed(removed);
            if (position != null)
                new_positions.add(position);
            
            debug("%s: ReplayAppend remote unsolicited remove: %s -> %s", owner.to_string(),
                old_position.to_string(), (position != null) ? position.to_string() : "(null)");
        }
        
        positions = new_positions;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() {
        if (positions.size > 0)
            yield owner.do_replay_appended_messages(positions);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "positions.size=%d".printf(positions.size);
    }
}

