/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CopyEmail : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<Imap.UID> destination_uids = new Gee.HashSet<Imap.UID>();

    private MinimalFolder engine;
    private Gee.HashSet<ImapDB.EmailIdentifier> to_copy = new Gee.HashSet<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;

    public CopyEmail(MinimalFolder engine, Gee.List<ImapDB.EmailIdentifier> to_copy,
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("CopyEmail", OnError.RETRY);

        this.engine = engine;

        this.to_copy.add_all(to_copy);
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        to_copy.remove_all(ids);
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_copy.size == 0)
            return ReplayOperation.Status.COMPLETED;

        // The local DB will be updated when the remote folder is opened and we see a new message
        // existing there.
        return ReplayOperation.Status.CONTINUE;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        if (to_copy.size > 0) {
            Gee.Set<Imap.UID>? uids = yield engine.local_folder.get_uids_async(
                to_copy, ImapDB.Folder.ListFlags.NONE, cancellable
            );

            if (uids != null && uids.size > 0) {
                Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(uids);
                foreach (Imap.MessageSet msg_set in msg_sets) {
                    Gee.Map<Imap.UID, Imap.UID>? src_dst_uids =
                        yield remote.copy_email_async(
                            msg_set, destination, cancellable
                        );
                    if (src_dst_uids != null)
                        destination_uids.add_all(src_dst_uids.values);
                }
            }
        }
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_copy.size, destination.to_string());
    }

}
