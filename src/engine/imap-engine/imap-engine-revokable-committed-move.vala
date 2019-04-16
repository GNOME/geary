/* Copyright 2016 Software Freedom Conservancy Inc.
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
        Imap.FolderSession? session = null;
        try {
            // use a detached folder to quickly open, issue command, and leave, without full
            // normalization that MinimalFolder requires
            session = yield this.account.claim_folder_session(destination, cancellable);
            foreach (Imap.MessageSet msg_set in Imap.MessageSet.uid_sparse(destination_uids)) {
                // don't use Cancellable to try to make operations atomic
                yield session.copy_email_async(msg_set, source, null);
                yield session.remove_email_async(msg_set.to_list(), null);

                if (cancellable != null && cancellable.is_cancelled())
                    throw new IOError.CANCELLED("Revoke cancelled");
            }

            notify_revoked();

            Geary.Folder target = this.account.get_folder(this.destination);
            this.account.update_folder(target);
        } finally {
            if (session != null) {
                yield this.account.release_folder_session(session);
            }
            set_invalid();
        }
    }

    protected override async void internal_commit_async(Cancellable? cancellable) throws Error {
        // pretty simple: already committed, so done
        notify_committed(null);
        set_invalid();
    }
}

