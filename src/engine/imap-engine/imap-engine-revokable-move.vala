/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A @{link Geary.Revokable} for {@link MinimalFolder} move operations.
 *
 * This will delay executing the move until (a) the source Folder is closed or (b) a timeout passes.
 * Even then, it will fire its "committed" signal with a {@link RevokableCommittedMove} to allow
 * the user to undo the operation, albeit taking more time to connect, open the destination folder,
 * and move the mail back.
 */

private class Geary.ImapEngine.RevokableMove : Revokable {
    private const int COMMIT_TIMEOUT_SEC = 5;

    private GenericAccount account;
    private MinimalFolder source;
    private Geary.Folder destination;
    private Gee.Set<ImapDB.EmailIdentifier> move_ids;

    public RevokableMove(GenericAccount account, MinimalFolder source, Geary.Folder destination,
        Gee.Set<ImapDB.EmailIdentifier> move_ids) {
        base (COMMIT_TIMEOUT_SEC);

        this.account = account;
        this.source = source;
        this.destination = destination;
        this.move_ids = move_ids;

        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        source.email_removed.connect(on_source_email_removed);
        source.marked_email_removed.connect(on_source_email_removed);
        source.closing.connect(on_source_closing);
    }

    ~RevokableMove() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        source.email_removed.disconnect(on_source_email_removed);
        source.marked_email_removed.disconnect(on_source_email_removed);
        source.closing.disconnect(on_source_closing);

        // if still valid, schedule operation so its executed
        if (valid && source.get_open_state() != Folder.OpenState.CLOSED) {
            debug("Freeing revokable, scheduling move %d emails from %s to %s", move_ids.size,
                source.path.to_string(), destination.to_string());

            try {
                source.schedule_op(new MoveEmailCommit(source, move_ids, destination.path, null));
            } catch (Error err) {
                debug("Move from %s to %s failed: %s", source.path.to_string(), destination.to_string(),
                    err.message);
            }
        } else if (valid) {
            debug("Not scheduling freed move revokable for %s, open_state=%s",
                source.path.to_string(), source.get_open_state().to_string());
        }
    }

    protected override async void internal_revoke_async(Cancellable? cancellable) throws Error {
        try {
            MoveEmailRevoke op = new MoveEmailRevoke(
                source, move_ids, cancellable
            );
            yield source.exec_op_async(op, cancellable);

            // valid must still be true before firing
            notify_revoked();

            yield op.wait_for_ready_async(cancellable);
            this.account.update_folder(this.destination);
        } finally {
            set_invalid();
        }
    }

    protected override async void internal_commit_async(Cancellable? cancellable) throws Error {
        try {
            MoveEmailCommit op = new MoveEmailCommit(source, move_ids, destination.path, cancellable);
            yield source.exec_op_async(op, cancellable);

            // valid must still be true before firing
            notify_committed(new RevokableCommittedMove(account, source.path, destination.path, op.destination_uids));

            yield op.wait_for_ready_async(cancellable);
            this.account.update_folder(this.destination);
        } finally {
            set_invalid();
        }
    }

    private void on_folders_available_unavailable(Gee.Collection<Folder>? available,
                                                  Gee.Collection<Folder>? unavailable) {
        // look for either of the folders going away
        if (unavailable != null) {
            foreach (Folder folder in unavailable) {
                if (folder.path.equal_to(source.path) ||
                    folder.path.equal_to(destination.path)) {
                    set_invalid();
                    break;
                }
            }
        }
    }

    private void on_source_email_removed(Gee.Collection<EmailIdentifier> ids) {
        // one-way switch
        if (!valid)
            return;

        foreach (EmailIdentifier id in ids)
            move_ids.remove((ImapDB.EmailIdentifier) id);

        if (move_ids.size <= 0)
            set_invalid();
    }

    private void on_source_closing(Gee.List<ReplayOperation> final_ops) {
        if (!valid)
            return;

        MoveEmailCommit op = new MoveEmailCommit(
            source, move_ids, destination.path, null
        );
        final_ops.add(op);
        set_invalid();

        // Capture these for the closure below, since once it gets
        // invoked, this instance may no longer exist.
        GenericAccount account = this.account;
        Geary.Folder destination = this.destination;
        op.wait_for_ready_async.begin(null, (obj, res) => {
                try {
                    op.wait_for_ready_async.end(res);
                    account.update_folder(destination);
                } catch (Error err) {
                    // Oh well
                }
            });
    }
}
