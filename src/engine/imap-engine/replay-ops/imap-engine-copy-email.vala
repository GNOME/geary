/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CopyEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.HashSet<ImapDB.EmailIdentifier> to_copy = new Gee.HashSet<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;

    public CopyEmail(GenericFolder engine, Gee.List<ImapDB.EmailIdentifier> to_copy, 
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
        ImapDB.EmailIdentifier? imapdb_id = id as ImapDB.EmailIdentifier;
        if (imapdb_id == null)
            return true;
        
        // only interested in messages going away (i.e. can't be copied) ...
        // note that this method operates exactly the same way whether the EmailIdentifer is in
        // the to_copy list or not.
        if (op == ReplayOperation.WritebehindOperation.REMOVE)
            to_copy.remove(imapdb_id);
        
        return true;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        Gee.Set<Imap.UID>? uids = yield engine.local_folder.get_uids_async(to_copy,
            ImapDB.Folder.ListFlags.NONE, cancellable);
        
        if (uids != null && uids.size > 0) {
            yield engine.remote_folder.copy_email_async(
                new Imap.MessageSet.uid_sparse(uids.to_array()), destination, cancellable);
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

