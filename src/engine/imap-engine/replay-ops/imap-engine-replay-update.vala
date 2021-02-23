/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Updates an existing message locally after an unsolicited FETCH.
 */
private class Geary.ImapEngine.ReplayUpdate : Geary.ImapEngine.ReplayOperation {


    private MinimalFolder owner;
    private int remote_count;
    private Imap.SequenceNumber position;
    private Imap.FetchedData data;


    public ReplayUpdate(MinimalFolder owner,
                        int remote_count,
                        Imap.SequenceNumber position,
                        Imap.FetchedData data) {
        // Although technically a local-only operation, must treat as
        // remote to ensure it's processed in-order with ReplayAppend
        // and ReplayRemove operations
        base ("Update", Scope.REMOTE_ONLY, OnError.RETRY);

        this.owner = owner;
        this.remote_count = remote_count;
        this.position = position;
        this.data = data;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        Imap.MessageFlags? message_flags =
            this.data.data_map.get(Imap.FetchDataSpecifier.FLAGS) as Imap.MessageFlags;
        if (message_flags != null) {
            int local_count = -1;
            int64 local_position = -1;

            // need total count, including those marked for removal, to accurately calculate position
            // from server's point of view, not client's
            local_count = yield this.owner.local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, null);
            local_position = this.position.value - (this.remote_count - local_count);

            ImapDB.EmailIdentifier? id = null;
            if (local_position > 0) {
                id = yield this.owner.local_folder.get_id_at_async(
                      local_position, null
                );
            }

            if (id != null) {
                Gee.Map<Geary.ImapDB.EmailIdentifier, Geary.EmailFlags> changed_map =
                new Gee.HashMap<Geary.ImapDB.EmailIdentifier, Geary.EmailFlags>();
                changed_map.set(id, new Imap.EmailFlags(message_flags));

                yield this.owner.local_folder.set_email_flags_async(changed_map, null);

                // only notify if the email is not marked for deletion
                try {
                    yield this.owner.local_folder.fetch_email_async(
                        id, NONE, NONE, null
                    );
                    this.owner.replay_notify_email_flags_changed(changed_map);
                } catch (EngineError.NOT_FOUND err) {
                    //fine
                }
            } else {
                debug("%s replay_local_async id is null!", to_string());
            }
        } else {
            debug("%s Don't know what to do without any FLAGS: %s",
                  to_string(), this.data.to_string());
        }
    }

    public override string describe_state() {
        Imap.MessageData? fetch_flags =
            this.data.data_map.get(Imap.FetchDataSpecifier.FLAGS);
        return "position.value=%lld, flags=%s".printf(
            this.position.value,
            fetch_flags != null ? fetch_flags.to_string() : "null"
        );
    }
}
