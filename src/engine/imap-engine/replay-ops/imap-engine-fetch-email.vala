/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.FetchEmail : Geary.ImapEngine.SendReplayOperation {
    public Email? email = null;

    private MinimalFolder engine;
    private ImapDB.EmailIdentifier id;
    private Email.Field required_fields;
    private Email.Field remaining_fields;
    private Folder.ListFlags flags;
    private Cancellable? cancellable;
    private Imap.UID? uid = null;
    private bool remote_removed = false;

    public FetchEmail(MinimalFolder engine, ImapDB.EmailIdentifier id, Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        // Unlike the list operations, fetch needs to retry remote
        base ("FetchEmail", OnError.RETRY);

        this.engine = engine;
        this.id = id;
        this.required_fields = required_fields;
        this.flags = flags;
        this.cancellable = cancellable;

        // always fetch the required fields unless a modified list, in which case want to do exactly
        // what's required, no more and no less
        if (!flags.is_all_set(Folder.ListFlags.LOCAL_ONLY) && !flags.is_all_set(Folder.ListFlags.FORCE_UPDATE))
            this.required_fields |= ImapDB.Folder.REQUIRED_FIELDS;

        remaining_fields = required_fields;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        remote_removed = ids.contains(id);
    }

    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (flags.is_all_set(Folder.ListFlags.FORCE_UPDATE)) {
            // Forcing an update, get the local UID then go direct to
            // replay_remote()
            this.uid = yield engine.local_folder.get_uid_async(
                this.id, NONE, this.cancellable
            );
            return Status.CONTINUE;
        }

        bool local_only = flags.is_all_set(Folder.ListFlags.LOCAL_ONLY);
        Geary.Email? email = null;
        try {
            email = yield engine.local_folder.fetch_email_async(
                id,
                required_fields,
                ImapDB.Folder.ListFlags.PARTIAL_OK,
                cancellable
            );
        } catch (Geary.EngineError.NOT_FOUND err) {
            if (local_only) {
                throw err;
            }
        }

        // If returned in full, done
        if (email != null && email.fields.fulfills(required_fields)) {
            this.email = email;
            this.remaining_fields = Email.Field.NONE;
            return ReplayOperation.Status.COMPLETED;
        } else if (local_only) {
            // Didn't have an email that fulfills the reqs, but the
            // caller didn't want to go to the remote, so let them
            // know
            throw new EngineError.INCOMPLETE_MESSAGE(
                "Email %s with fields %Xh locally incomplete %s",
                id.to_string(),
                required_fields,
                to_string()
            );
        }

        // only fetch what's missing
        if (email != null)
            remaining_fields = required_fields.clear(email.fields);
        else
            remaining_fields = required_fields;

        assert(remaining_fields != 0);

        if (email != null)
            uid = ((ImapDB.EmailIdentifier) email.id).uid;
        else
            uid = yield engine.local_folder.get_uid_async(id, ImapDB.Folder.ListFlags.NONE, cancellable);

        if (uid == null)
            throw new EngineError.NOT_FOUND("Unable to find %s in %s", id.to_string(), engine.to_string());

        return ReplayOperation.Status.CONTINUE;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        if (remote_removed) {
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s (removed from remote)",
                id.to_string(), engine.to_string());
        }

        // fetch only the remaining fields from the remote folder (if only pulling partial information,
        // will merge at end of this method)
        Gee.List<Geary.Email>? list = yield remote.list_email_async(
            new Imap.MessageSet.uid(uid), remaining_fields, cancellable);
        if (list == null || list.size != 1)
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s", id.to_string(), engine.to_string());

        Gee.Map<Geary.Email, bool> created_or_merged =
            yield this.engine.local_folder.create_or_merge_email_async(
                list, true, this.engine.harvester, this.cancellable
            );

        Geary.Email email = list[0];
        if (created_or_merged.get(email)) {
            Gee.Collection<Geary.EmailIdentifier> ids
                = Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list();
            engine.replay_notify_email_inserted(ids);
            engine.replay_notify_email_locally_inserted(ids);
        }

        // Finally, pull again from the local database, to get the
        // full set of required fields, and ensure attachments are
        // created, if needed.
        this.email = yield this.engine.local_folder.fetch_email_async(
            this.id, this.required_fields, NONE, this.cancellable
        );
    }

    public override string describe_state() {
        return "id=%s required_fields=%Xh remaining_fields=%Xh flags=%Xh has_email=%s".printf(
            this.id.to_string(),
            this.required_fields,
            this.remaining_fields,
            this.flags,
            (this.email == null).to_string()
        );
    }
}
