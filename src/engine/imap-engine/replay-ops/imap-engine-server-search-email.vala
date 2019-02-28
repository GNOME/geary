/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Performs an IMAP SEARCH command on the server, performing vector expansion to include all
 * discovered emails if required.
 *
 * Note that this does ''no'' searching of local email.
 */
private class Geary.ImapEngine.ServerSearchEmail : Geary.ImapEngine.AbstractListEmail {
    private Imap.SearchCriteria criteria;

    public ServerSearchEmail(MinimalFolder owner, Imap.SearchCriteria criteria, Geary.Email.Field required_fields,
        Cancellable? cancellable) {
        // OLDEST_TO_NEWEST used for vector expansion, if necessary
        base ("ServerSearchEmail", owner, required_fields, Geary.Folder.ListFlags.OLDEST_TO_NEWEST,
            cancellable);

        // unlike list, need to retry this as there's no local component to return
        on_remote_error = OnError.RETRY;

        this.criteria = criteria;
    }

    // XXX Shouldn't need to override this, but AbstractListEmail
    // won't let us declare it as remote-only
    public override async ReplayOperation.Status replay_local_async()
        throws GLib.Error {
        return ReplayOperation.Status.CONTINUE;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        Gee.SortedSet<Imap.UID>? uids = yield remote.search_async(
            criteria, this.cancellable
        );
        if (uids == null || uids.size == 0)
            return;

        // if the earliest UID is not in the local store, then need to expand vector to it
        Geary.EmailIdentifier? first_id = yield owner.local_folder.get_id_async(uids.first(),
            ImapDB.Folder.ListFlags.NONE, cancellable);
        if (first_id == null)
            yield expand_vector_async(remote, uids.first(), 1);

        // Convert UIDs into EmailIdentifiers for lookup
        Gee.HashSet<ImapDB.EmailIdentifier> local_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        foreach (Imap.UID uid in uids) {
            // if null, presumably was picked up in the vector expansion (but hasn't been assigned
            // to the database yet)
            //
            // TODO: We need a sparse version of this to scoop them up all at once
            ImapDB.EmailIdentifier? id = yield owner.local_folder.get_id_async(uid,
                ImapDB.Folder.ListFlags.NONE, cancellable);
            if (id != null)
                local_ids.add(id);
        }

        Gee.List<Geary.Email>? local_list = yield owner.local_folder.list_email_by_sparse_id_async(
            local_ids, required_fields, ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);

        // Build list of local email
        Gee.Map<ImapDB.EmailIdentifier, Geary.Email> map = new Gee.HashMap<ImapDB.EmailIdentifier, Geary.Email>();
        if (local_list != null) {
            foreach (Geary.Email email in local_list)
                map.set((ImapDB.EmailIdentifier) email.id, email);
        }

        // Convert into fulfilled and unfulfilled email for the base class to complete
        foreach (ImapDB.EmailIdentifier id in map.keys) {
            Geary.Email? email = map.get(id);
            if (email == null)
                add_unfulfilled_fields(id.uid, required_fields | ImapDB.Folder.REQUIRED_FIELDS);
            else if (!email.fields.fulfills(required_fields))
                add_unfulfilled_fields(id.uid, required_fields.clear(email.fields));
            else
                accumulator.add(email);
        }

        // with unfufilled set and fulfilled added to accumulator, let
        // base class do the rest of the work
        yield base.replay_remote_async(remote);
    }

    public override string describe_state() {
        return "criteria=%s".printf(criteria.to_string());
    }
}

