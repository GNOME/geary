/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayAppend : Geary.ImapEngine.ReplayOperation {
    public MinimalFolder owner;
    public int remote_count;
    public Gee.List<Imap.SequenceNumber> positions;
    
    public ReplayAppend(MinimalFolder owner, int remote_count, Gee.List<Imap.SequenceNumber> positions) {
        base ("Append", Scope.REMOTE_ONLY);
        
        this.owner = owner;
        this.remote_count = remote_count;
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
        
        // DON'T update remote_count, it is intended to report the remote count at the time the
        // appended messages arrived
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override async ReplayOperation.Status replay_remote_async() {
        if (positions.size > 0)
            yield owner.do_replay_appended_messages(remote_count, positions);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "remote_count=%d positions.size=%d".printf(remote_count, positions.size);
    }
}

