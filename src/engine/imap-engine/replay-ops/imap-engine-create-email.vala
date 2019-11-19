/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CreateEmail : SendReplayOperation {

    public Geary.EmailIdentifier? created_id { get; private set; default = null; }

    private MinimalFolder engine;
    private RFC822.Message? rfc822;
    private Geary.EmailFlags? flags;
    private DateTime? date_received;
    private Cancellable? cancellable;


    public CreateEmail(MinimalFolder engine,
                       RFC822.Message rfc822,
                       EmailFlags? flags,
                       DateTime? date_received,
                       GLib.Cancellable? cancellable) {
        base.only_remote("CreateEmail", OnError.RETRY);

        this.engine = engine;

        this.rfc822 = rfc822;
        this.flags = flags;
        this.date_received = date_received;
        this.cancellable = cancellable;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        // Deal with cancellable manually since create_email_async cannot be cancelled.
        if (this.cancellable.is_cancelled()) {
            throw new IOError.CANCELLED("CreateEmail op cancelled immediately");
        }

        // use IMAP APPEND command on remote folders, which doesn't
        // require opening a folder ...  if retrying after a
        // successful create, rfc822 will be null
        if (this.rfc822 != null) {
            this.created_id = yield remote.create_email_async(
                this.rfc822, this.flags, this.date_received
            );
        }

        // because this command retries, the create completed, remove
        // the RFC822 message to prevent creating it twice
        this.rfc822 = null;

        // Bail out early if cancelled
        yield check_cancelled(remote);

        if (this.created_id != null) {
            // Since the server provided the UID of the new message,
            // it is possible to email locally then fill in the
            // missing parts from the remote.
            //
            // TODO: need to prevent gaps between UIDS that may occur
            // here if this is created before we know of an earlier
            // message that has arrived.
            Geary.Email created = new Geary.Email(this.created_id);
            Gee.Map<Geary.Email, bool> results =
                yield this.engine.local_folder.create_or_merge_email_async(
                    Geary.iterate<Geary.Email>(created).to_array_list(),
                    true,
                    this.engine.harvester,
                    this.cancellable
                );

            if (results.size > 0) {
                this.created_id = Collection.first(results.keys).id;
            } else {
                // Something went wrong creating/merging the message,
                // so pretend we don't know what its UID is so the
                // background sync goes off and gets it.
                this.created_id = null;
            }
        }
    }

    public override string describe_state() {
        return "created_id: %s".printf(
            this.created_id != null ? this.created_id.to_string() :  "none"
        );
    }

    private async void check_cancelled(Imap.FolderSession remote)
        throws GLib.Error {
        if (this.cancellable.is_cancelled()) {
            // Need to wipe the new message if possible to keep the
            // operation atomic.
            if (this.created_id != null) {
                yield remote.remove_email_async(
                    new Imap.MessageSet.uid(
                        ((ImapDB.EmailIdentifier) this.created_id).uid
                    ).to_list(),
                    // Don't observe the cancellable since it's
                    // already cancelled
                    null
                );
            }

            throw new IOError.CANCELLED("CreateEmail op cancelled after create");
        }
    }

}
