/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.MoveEmail : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder engine;
    private Gee.List<Geary.EmailIdentifier> to_move;
    private Geary.FolderPath destination;
    private Cancellable? cancellable;
    private int original_count = 0;

    public MoveEmail(GenericFolder engine, Gee.List<Geary.EmailIdentifier> to_move, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("MoveEmail");

        this.engine = engine;

        this.to_move = to_move;
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(to_move, true, cancellable);
        engine.notify_email_removed(to_move);

        original_count = engine.remote_count;
        engine.notify_email_count_changed(original_count - to_move.size,
            Geary.Folder.CountChangeReason.REMOVED);

        return ReplayOperation.Status.CONTINUE;
    }

    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        yield engine.remote_folder.move_email_async(new Imap.MessageSet.email_id_collection(to_move),
            destination, cancellable);

        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(to_move, false, cancellable);

        engine.notify_email_appended(to_move);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.ADDED);
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_move.size, destination.to_string());
    }
}

