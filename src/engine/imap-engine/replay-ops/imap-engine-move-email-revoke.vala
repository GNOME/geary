/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Revoked {@link RevokableMove}: Unmark emails as removed and update counts.
 */

private class Geary.ImapEngine.MoveEmailRevoke : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_revoke = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Cancellable? cancellable;

    public MoveEmailRevoke(MinimalFolder engine, Gee.Collection<ImapDB.EmailIdentifier> to_revoke,
        Cancellable? cancellable) {
        base.only_local("MoveEmailRevoke", OnError.RETRY);

        this.engine = engine;

        this.to_revoke.add_all(to_revoke);
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        to_revoke.remove_all(ids);
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_revoke.size == 0)
            return ReplayOperation.Status.COMPLETED;

        Gee.Set<ImapDB.EmailIdentifier>? revoked = yield engine.local_folder.mark_removed_async(
            to_revoke, false, cancellable);
        if (revoked != null && !revoked.is_empty) {
            yield this.engine.update_email_counts(this.cancellable);
            this.engine.email_inserted(revoked);
        }
        return COMPLETED;
    }

    public override string describe_state() {
        return "%d email IDs".printf(to_revoke.size);
    }
}
