/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.CopyEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_copy = new Gee.ArrayList<Geary.EmailIdentifier>(
        Equalable.equal_func);
    private Geary.FolderPath destination;
    private Cancellable? cancellable;

    public CopyEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_copy, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("CopyEmail");
        
        this.engine = engine;
        
        this.to_copy.add_all(to_copy);
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_copy.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // The local DB will be updated when the remote folder is opened and we see a new message
        // existing there.
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
        EmailIdentifier id, Imap.EmailFlags? flags) {
        // only interested in messages going away (i.e. can't be copied) ...
        // note that this method operates exactly the same way whether the EmailIdentifer is in
        // the to_copy list or not.
        if (op == ReplayOperation.WritebehindOperation.REMOVE)
            to_copy.remove(id);
        
        return true;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // perform_immediate_local_operation() may have removed all messages to copy
        if (to_copy.size > 0) {
            yield engine.remote_folder.copy_email_async(new Imap.MessageSet.email_id_collection(to_copy),
                destination, cancellable);
        }
        
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        // Nothing to undo.
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_copy.size, destination.to_string());
    }
}

