/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayAppend : Geary.ImapEngine.ReplayOperation {

    private MinimalFolder owner;
    private int remote_count;
    private Gee.List<Imap.SequenceNumber> positions;
    private Cancellable? cancellable;

    public signal void email_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    public signal void email_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids);
    public signal void email_count_changed(int count, Folder.CountChangeReason reason);


    public ReplayAppend(MinimalFolder owner,
                        int remote_count,
                        Gee.List<Imap.SequenceNumber> positions,
                        Cancellable? cancellable) {
        // Since this is a report op, both ReplayRemove and
        // ReplayUpdate must also be run as remote ops so their
        // effects are interleaved correctly. IGNORE remote errors
        // because the reconnect will re-normalize the folder, making
        // this append moot
        base ("Append", Scope.REMOTE_ONLY, OnError.IGNORE_REMOTE);

        this.owner = owner;
        this.remote_count = remote_count;
        this.positions = positions;
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
        Gee.List<Imap.SequenceNumber> new_positions = new Gee.ArrayList<Imap.SequenceNumber>();
        foreach (Imap.SequenceNumber? position in positions) {
            Imap.SequenceNumber old_position = position;

            // adjust depending on relation to removed message
            position = position.shift_for_removed(removed);
            if (position != null)
                new_positions.add(position);

            debug("%s: ReplayAppend remote unsolicited remove: %s -> %s", owner.to_string(),
                old_position.to_string(), (position != null) ? position.to_string() : "(null)");
        }

        positions = new_positions;

        // DON'T update remote_count, it is intended to report the remote count at the time the
        // appended messages arrived
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        if (this.positions.size > 0) {
            yield do_replay_appended_messages(remote);
        }
    }

    public override string describe_state() {
        return "remote_count=%d positions.size=%d".printf(remote_count, positions.size);
    }

    // Need to prefetch at least an EmailIdentifier (and duplicate detection fields) to create a
    // normalized placeholder in the local database of the message, so all positions are
    // properly relative to the end of the message list; once this is done, notify user of new
    // messages.  If duplicates, create_email_async() will fall through to an updated merge,
    // which is exactly what we want.
    private async void do_replay_appended_messages(Imap.FolderSession remote)
        throws Error {
        StringBuilder positions_builder = new StringBuilder("( ");
        foreach (Imap.SequenceNumber remote_position in this.positions)
            positions_builder.append_printf("%s ", remote_position.to_string());
        positions_builder.append(")");

        debug("%s do_replay_appended_message: this.remote_count=%d this.positions=%s",
            to_string(), this.remote_count, positions_builder.str);

        Gee.HashSet<Geary.EmailIdentifier> created = new Gee.HashSet<Geary.EmailIdentifier>();
        Gee.HashSet<Geary.EmailIdentifier> appended = new Gee.HashSet<Geary.EmailIdentifier>();
        Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.sparse(this.positions);
        foreach (Imap.MessageSet msg_set in msg_sets) {
            Gee.List<Geary.Email>? list = yield remote.list_email_async(
                msg_set, ImapDB.Folder.REQUIRED_FIELDS, this.cancellable
            );
            if (list != null && list.size > 0) {
                debug("%s do_replay_appended_message: %d new messages in %s", to_string(),
                      list.size, msg_set.to_string());

                // need to report both if it was created (not known before) and appended (which
                // could mean created or simply a known email associated with this folder)
                Gee.Map<Geary.Email, bool> created_or_merged =
                    yield this.owner.local_folder.create_or_merge_email_async(
                        list, true, this.owner.harvester, this.cancellable
                    );
                foreach (Geary.Email email in created_or_merged.keys) {
                    // true means created
                    if (created_or_merged.get(email)) {
                        debug("%s do_replay_appended_message: appended email ID %s added",
                              to_string(), email.id.to_string());

                        created.add(email.id);
                    } else {
                        debug("%s do_replay_appended_message: appended email ID %s associated",
                              to_string(), email.id.to_string());
                    }

                    appended.add(email.id);
                }
            } else {
                debug("%s do_replay_appended_message: no new messages in %s", to_string(),
                      msg_set.to_string());
            }
        }

        // store the reported count, *not* the current count (which is updated outside the of
        // the queue) to ensure that updates happen serially and reflect committed local changes
        yield this.owner.local_folder.update_remote_selected_message_count(
            this.remote_count, this.cancellable
        );

        if (appended.size > 0)
            email_appended(appended);

        if (created.size > 0)
            email_locally_appended(created);

        email_count_changed(this.remote_count, Folder.CountChangeReason.APPENDED);

        debug("%s do_replay_appended_message: completed, this.remote_count=%d",
              to_string(), this.remote_count);
    }

}
