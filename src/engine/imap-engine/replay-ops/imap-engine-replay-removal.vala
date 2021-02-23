/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayRemoval : Geary.ImapEngine.ReplayOperation {

    private MinimalFolder owner;
    private int remote_count;
    private Imap.SequenceNumber position;

    public signal void email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    public signal void marked_email_removed(Gee.Collection<Geary.EmailIdentifier> ids);
    public signal void email_count_changed(int count, Folder.CountChangeReason reason);


    public ReplayRemoval(MinimalFolder owner, int remote_count, Imap.SequenceNumber position) {
        // Although technically a local-only operation, must treat as
        // remote to ensure it's processed in-order with ReplayAppend
        // and ReplayUpdate operations. Remote error will cause folder
        // to reconnect and re-normalize, making this remove moot
        base ("Removal", Scope.REMOTE_ONLY, OnError.IGNORE_REMOTE);

        this.owner = owner;
        this.remote_count = remote_count;
        this.position = position;
    }

    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
        // although using positional addressing, don't update state; EXPUNGEs that happen after
        // other EXPUNGEs have no affect on those ahead of it
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // this operation deals only in positional addressing
    }

    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // this ReplayOperation doesn't do remote removes, it reacts to them
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        debug("%s: ReplayRemoval this.position=%s reported_remote_count=%d",
              this.owner.to_string(), this.position.value.to_string(), this.remote_count);

        if (this.position.is_valid()) {
            yield do_replay_removed_message();
        } else {
            debug("%s do_replay_removed_message: ignoring, invalid remote position or count",
                to_string());
        }
    }

    public override string describe_state() {
        return "position=%s".printf(position.to_string());
    }

    private async void do_replay_removed_message() {
        int local_count = -1;
        int64 local_position = -1;

        ImapDB.EmailIdentifier? owned_id = null;
        try {
            // need total count, including those marked for removal,
            // to accurately calculate position from server's point of
            // view, not client's. The extra 1 taken off is due to the
            // remote count already being decremented in MinimalFolder
            // when this op was queued.
            local_count = yield this.owner.local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
            local_position = this.position.value - (this.remote_count + 1 - local_count);

            // zero or negative means the message exists beyond the local vector's range, so
            // nothing to do there
            if (local_position > 0) {
                debug("%s do_replay_removed_message: local_count=%d local_position=%s", to_string(),
                    local_count, local_position.to_string());

                owned_id = yield this.owner.local_folder.get_id_at_async(local_position, null);
            } else {
                debug("%s do_replay_removed_message: message not stored locally (local_count=%d local_position=%s)",
                    to_string(), local_count, local_position.to_string());
            }
        } catch (Error err) {
            debug("%s do_replay_removed_message: unable to determine ID of removed message %s: %s",
                to_string(), this.position.to_string(), err.message);
        }

        bool marked = false;
        if (owned_id != null) {
            debug("%s do_replay_removed_message: detaching from local store Email ID %s", to_string(),
                owned_id.to_string());
            try {
                // Reflect change in the local store and notify subscribers
                yield this.owner.local_folder.detach_single_email_async(owned_id, null, out marked);
            } catch (Error err) {
                debug("%s do_replay_removed_message: unable to remove message #%s: %s", to_string(),
                    this.position.to_string(), err.message);
            }

            // Notify queued replay operations that the email has been removed (by EmailIdentifier)
            this.owner.replay_queue.notify_remote_removed_ids(
                Geary.iterate<ImapDB.EmailIdentifier>(owned_id).to_array_list());
        } else {
            debug("%s do_replay_removed_message: this.position=%lld unknown in local store "
                + "(this.remote_count=%d local_position=%lld local_count=%d)",
                to_string(), this.position.value, this.remote_count, local_position, local_count);
        }

        // for debugging
        int new_local_count = -1;
        try {
            new_local_count = yield this.owner.local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
        } catch (Error err) {
            debug("%s do_replay_removed_message: error fetching new local count: %s", to_string(),
                err.message);
        }

        // as with on_remote_appended(), only update in local store inside a queue operation, to
        // ensure serial commits
        try {
            yield this.owner.local_folder.update_remote_selected_message_count(this.remote_count, null);
        } catch (Error err) {
            debug("%s do_replay_removed_message: unable to save removed remote count: %s", to_string(),
                err.message);
        }

        // notify of change ... use "marked-email-removed" for marked email to allow internal code
        // to be notified when a removed email is "really" removed
        if (owned_id != null) {
            Gee.List<EmailIdentifier> removed = Geary.iterate<Geary.EmailIdentifier>(owned_id).to_array_list();
            if (!marked)
                email_removed(removed);
            else
                marked_email_removed(removed);
        }

        if (!marked) {
            this.owner.replay_notify_email_count_changed(
                this.remote_count, Folder.CountChangeReason.REMOVED
            );
        }

        debug("%s ReplayRemoval: completed, "
            + "(this.remote_count=%d local_count=%d starting local_count=%d this.position=%lld local_position=%lld marked=%s)",
              this.owner.to_string(),
              this.remote_count, new_local_count, local_count,
              this.position.value, local_position, marked.to_string());
    }

}
