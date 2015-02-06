/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A {@link Geary.Revokable} for moving email back to its source after committed with
 * {@link RevokableMove}.
 */

private class Geary.ImapEngine.RevokableCommittedMove : Revokable {
    private GenericAccount account;
    private FolderPath source;
    private FolderPath destination;
    private Gee.Set<Imap.UID> destination_uids;
    
    public RevokableCommittedMove(GenericAccount account, FolderPath source, FolderPath destination,
        Gee.Set<Imap.UID> destination_uids) {
        this.account = account;
        this.source = source;
        this.destination = destination;
        this.destination_uids = destination_uids;
    }
    
    protected override async void internal_revoke_async(Cancellable? cancellable) throws Error {
        Imap.Folder? detached_destination = null;
        try {
            // use a detached folder to quickly open, issue command, and leave, without full
            // normalization that MinimalFolder requires
            detached_destination = yield account.fetch_detached_folder_async(destination, cancellable);
            
            yield detached_destination.open_async(cancellable);
            
            foreach (Imap.MessageSet msg_set in Imap.MessageSet.uid_sparse(destination_uids)) {
                // don't use Cancellable to try to make operations atomic
                yield detached_destination.copy_email_async(msg_set, source, null);
                yield detached_destination.remove_email_async(msg_set.to_list(), null);
                
                if (cancellable != null && cancellable.is_cancelled())
                    throw new IOError.CANCELLED("Revoke cancelled");
            }
            
            notify_revoked();
        } finally {
            if (detached_destination != null) {
                try {
                    yield detached_destination.close_async(cancellable);
                } catch (Error err) {
                    // ignored
                }
            }
            
            valid = false;
        }
    }
    
    protected override async void internal_commit_async(Cancellable? cancellable) throws Error {
        // pretty simple: already committed, so done
        notify_committed(null);
        valid = false;
    }
}

