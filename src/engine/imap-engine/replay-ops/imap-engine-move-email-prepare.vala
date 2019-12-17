/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Stage one of a {@link RevokableMove}.
 *
 * This operation collects valid {@link ImapDB.EmailIdentifier}s for
 * messages to be removed, mark the messages as removed, and update
 * counts.
 */
private class Geary.ImapEngine.MoveEmailPrepare : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<ImapDB.EmailIdentifier>? prepared_for_move = null;

    private MinimalFolder engine;
    private Cancellable? cancellable;
    private Gee.List<ImapDB.EmailIdentifier> to_move = new Gee.ArrayList<ImapDB.EmailIdentifier>();

    public MoveEmailPrepare(MinimalFolder engine,
                            Gee.Collection<ImapDB.EmailIdentifier> to_move,
                            GLib.Cancellable? cancellable) {
        base.only_local("MoveEmailPrepare", OnError.RETRY);

        this.engine = engine;
        this.to_move.add_all(to_move);
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (prepared_for_move != null)
            prepared_for_move.remove_all(ids);
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_move.size <= 0)
            return ReplayOperation.Status.COMPLETED;

        int count = this.engine.properties.email_total;
        // as this value is only used for reporting, offer best-possible service
        if (count < 0)
            count = to_move.size;

        prepared_for_move = yield engine.local_folder.mark_removed_async(to_move, true, cancellable);
        if (prepared_for_move == null || prepared_for_move.size == 0)
            return ReplayOperation.Status.COMPLETED;

        engine.replay_notify_email_removed(prepared_for_move);

        engine.replay_notify_email_count_changed(
            Numeric.int_floor(count - prepared_for_move.size, 0),
            Folder.CountChangeReason.REMOVED);

        return ReplayOperation.Status.COMPLETED;
    }

    public override string describe_state() {
        return "%d email IDs".printf(prepared_for_move != null ? prepared_for_move.size : 0);
    }
}
