/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MarkEmail : Geary.ImapEngine.SendReplayOperation {
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_mark = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Gee.List<Imap.UID> to_mark_uids = new Gee.ArrayList<Imap.UID>();
    private Geary.EmailFlags? flags_to_add;
    private Geary.EmailFlags? flags_to_remove;
    private Gee.Map<ImapDB.EmailIdentifier, Geary.EmailFlags>? original_flags = null;
    private Cancellable? cancellable;

    internal int unread_change { get; private set; default=0; }

    public MarkEmail(MinimalFolder engine,
                     Gee.Collection<ImapDB.EmailIdentifier> to_mark,
                     EmailFlags? flags_to_add,
                     EmailFlags? flags_to_remove,
                     GLib.Cancellable? cancellable = null) {
        base("MarkEmail", OnError.RETRY);

        this.engine = engine;

        this.to_mark.add_all(to_mark);
        this.flags_to_add = flags_to_add;
        this.flags_to_remove = flags_to_remove;
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // don't bother updating on server or backing out locally
        if (original_flags != null)
            Collection.map_unset_all_keys<EmailIdentifier, Geary.EmailFlags>(original_flags, ids);
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_mark.size == 0)
            return ReplayOperation.Status.COMPLETED;

        // Save original flags, then set new ones.
        // TODO: Make this atomic (otherwise there stands a chance backout_local_async() will
        // reapply the wrong flags): should get the original flags and the new flags in the same
        // operation as the marking procedure, so original flags and reported flags are correct
        original_flags = yield engine.local_folder.get_email_flags_async(to_mark, cancellable);
        if (original_flags == null || original_flags.size == 0)
            return ReplayOperation.Status.COMPLETED;

         this.unread_change = yield engine.local_folder.mark_email_async(
            original_flags.keys,
            flags_to_add,
            flags_to_remove,
            cancellable
        );

        // We can't rely on email identifier for remote replay
        // An email identifier id can match multiple uids
        to_mark_uids = yield engine.local_folder.get_email_uids_async(to_mark, cancellable);

        // Notify using flags from DB.
        Gee.Map<EmailIdentifier, Geary.EmailFlags>? map = yield engine.local_folder.get_email_flags_async(
            original_flags.keys, cancellable);
        if (map != null && map.size > 0)
            engine.replay_notify_email_flags_changed(map);

        return ReplayOperation.Status.CONTINUE;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        // potentially empty due to writebehind operation
        if (to_mark_uids.size > 0) {
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(to_mark_uids);
            yield remote.mark_email_async(
                msg_sets, flags_to_add, flags_to_remove, cancellable
            );
        }
        this.unread_change = 0;
    }

    public override async void backout_local_async() throws Error {
        // Restore original flags (if fetched, which may not have occurred if an error happened
        // during transaction)
        if (original_flags != null)
            yield engine.local_folder.set_email_flags_async(original_flags, cancellable);
    }

    public override string describe_state() {
        return "to_mark=%d flags_to_add=%s flags_to_remove=%s".printf(to_mark.size,
            (flags_to_add != null) ? flags_to_add.to_string() : "(none)",
            (flags_to_remove != null) ? flags_to_remove.to_string() : "(none)");
    }
}

