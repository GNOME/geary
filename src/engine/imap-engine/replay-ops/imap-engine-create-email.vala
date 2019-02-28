/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CreateEmail : Geary.ImapEngine.SendReplayOperation {
    public Geary.EmailIdentifier? created_id { get; private set; default = null; }

    private MinimalFolder engine;
    private RFC822.Message? rfc822;
    private Geary.EmailFlags? flags;
    private DateTime? date_received;
    private Cancellable? cancellable;

    public CreateEmail(MinimalFolder engine, RFC822.Message rfc822, Geary.EmailFlags? flags,
        DateTime? date_received, Cancellable? cancellable) {
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
        if (cancellable.is_cancelled())
            throw new IOError.CANCELLED("CreateEmail op cancelled immediately");

        // use IMAP APPEND command on remote folders, which doesn't require opening a folder ...
        // if retrying after a successful create, rfc822 will be null
        if (rfc822 != null)
            created_id = yield remote.create_email_async(rfc822, flags, date_received);

        // because this command retries, the create completed, remove the RFC822 message to prevent
        // creating it twice
        rfc822 = null;

        // If the user cancelled the operation, we need to wipe the new message to keep this
        // operation atomic.
        if (cancellable.is_cancelled()) {
            if (created_id != null) {
                yield remote.remove_email_async(
                    new Imap.MessageSet.uid(((ImapDB.EmailIdentifier) created_id).uid).to_list(),
                    null
                );
            }

            throw new IOError.CANCELLED("CreateEmail op cancelled after create");
        }

        if (created_id != null) {
            // TODO: need to prevent gaps that may occur here
            Geary.Email created = new Geary.Email(created_id);
            Gee.Map<Geary.Email, bool> results =
                yield this.engine.local_folder.create_or_merge_email_async(
                    Geary.iterate<Geary.Email>(created).to_array_list(),
                    true,
                    this.cancellable
                );
            if (results.size > 0) {
                created_id = Collection.get_first<Geary.Email>(results.keys).id;
            } else {
                created_id = null;
            }
        }
    }

    public override string describe_state() {
        return "created_id: %s".printf(
            this.created_id != null ? this.created_id.to_string() :  "none"
        );
    }

}
