/*
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Fetches and updates extant email from the remote.
 *
 * The given fields will be fetched for the given email identifiers
 * from the remote, populating {@link fetched_email} when
 * complete. All fetched data is updated in local storage and the
 * fetched email have updated identifiers.
 */
private class Geary.ImapEngine.FetchEmail : SendReplayOperation {


    public Gee.Set<Email> fetched_email {
        get; private set; default = Email.new_identifier_based_set();
    }

    private MinimalFolder engine;
    private Gee.Set<ImapDB.EmailIdentifier> ids =
        new Gee.HashSet<ImapDB.EmailIdentifier>();
    private Email.Field required_fields;
    private GLib.Cancellable? cancellable;


    public FetchEmail(MinimalFolder engine,
                      Gee.Collection<ImapDB.EmailIdentifier> ids,
                      Email.Field required_fields,
                      GLib.Cancellable? cancellable = null) {
        base.only_remote("FetchEmail", OnError.RETRY);
        this.engine = engine;
        this.ids.add_all(ids);
        this.required_fields = required_fields;
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(
        Gee.Collection<ImapDB.EmailIdentifier> ids
    ) {
        this.ids.remove_all(ids);
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        var local = this.engine.local_folder;
        Gee.Set<Imap.UID>? uids = yield local.get_uids_async(
            this.ids, NONE, this.cancellable
        );

        if (uids != null && !uids.is_empty) {
            foreach (Imap.MessageSet msg_set in
                     Imap.MessageSet.uid_sparse(uids)) {
                var fetched = yield remote.list_email_async(
                    msg_set,
                    this.required_fields,
                    this.cancellable
                );
                var updated = yield local.create_or_merge_email_async(
                    fetched,
                    true,
                    this.engine.harvester,
                    cancellable
                );
                this.fetched_email.add_all(updated.keys);
            }
        }
    }

    public override string describe_state() {
        return (
            this.ids.size == 1
            ? Collection.first(this.ids).to_string()
            : "%d email ids".printf(this.ids.size)
        );
    }

}
