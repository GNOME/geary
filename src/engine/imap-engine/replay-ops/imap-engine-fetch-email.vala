/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.FetchEmail : Geary.ImapEngine.SendReplayOperation {
    public Email? email = null;
    
    private GenericFolder engine;
    private ImapDB.EmailIdentifier id;
    private Email.Field required_fields;
    private Email.Field remaining_fields;
    private Folder.ListFlags flags;
    private Cancellable? cancellable;
    private Imap.UID? uid = null;
    private bool remote_removed = false;
    
    public FetchEmail(GenericFolder engine, ImapDB.EmailIdentifier id, Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        base ("FetchEmail");
        
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
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        // If forcing an update, skip local operation and go direct to replay_remote()
        if (flags.is_all_set(Folder.ListFlags.FORCE_UPDATE))
            return ReplayOperation.Status.CONTINUE;
        
        try {
            email = yield engine.local_folder.fetch_email_async(id, required_fields,
                ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);
        } catch (Error err) {
            // If NOT_FOUND or INCOMPLETE_MESSAGE, then fall through, otherwise return to sender
            if (!(err is Geary.EngineError.NOT_FOUND) && !(err is Geary.EngineError.INCOMPLETE_MESSAGE))
                throw err;
        }
        
        // If returned in full, done
        if (email != null && email.fields.fulfills(required_fields))
            return ReplayOperation.Status.COMPLETED;
        
        // If local only and not found fully in local store, throw NOT_FOUND
        if (flags.is_all_set(Folder.ListFlags.LOCAL_ONLY)) {
            throw new EngineError.NOT_FOUND("Email %s with fields %Xh not found in %s", id.to_string(),
                required_fields, to_string());
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
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (remote_removed) {
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s (removed from remote)",
                id.to_string(), engine.to_string());
        }
        
        // fetch only the remaining fields from the remote folder (if only pulling partial information,
        // will merge at end of this method)
        Gee.List<Geary.Email>? list = yield engine.remote_folder.list_email_async(
            new Imap.MessageSet.uid(uid), remaining_fields, cancellable);
        if (list == null || list.size != 1)
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s", id.to_string(), engine.to_string());
        
        // save to local store
        email = list[0];
        assert(email != null);
        
        Gee.Map<Geary.Email, bool> created_or_merged =
            yield engine.local_folder.create_or_merge_email_async(
                Geary.iterate<Geary.Email>(email).to_array_list(), cancellable);
        
        // true means created
        if (created_or_merged.get(email)) {
            Gee.Collection<Geary.EmailIdentifier> ids
                = Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list();
            engine.notify_email_inserted(ids);
            engine.notify_email_locally_inserted(ids);
        }
        
        // if remote_email doesn't fulfill all required, pull from local database, which should now
        // be able to do all of that
        if (!email.fields.fulfills(required_fields)) {
            email = yield engine.local_folder.fetch_email_async(id, required_fields,
                ImapDB.Folder.ListFlags.NONE, cancellable);
            assert(email != null);
        }
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // read-only
    }
    
    public override string describe_state() {
        return "id=%s required_fields=%Xh remaining_fields=%Xh flags=%Xh".printf(id.to_string(),
            required_fields, remaining_fields, flags);
    }
}

