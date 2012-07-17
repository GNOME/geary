/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.ImapEngine.FetchEmail : Geary.ImapEngine.SendReplayOperation {
    public Email? email = null;
    
    private GenericFolder engine;
    private EmailIdentifier id;
    private Email.Field required_fields;
    private Email.Field remaining_fields;
    private Folder.ListFlags flags;
    private Cancellable? cancellable;
    
    public FetchEmail(GenericFolder engine, EmailIdentifier id, Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        base ("FetchEmail");
        
        this.engine = engine;
        this.id = id;
        this.required_fields = required_fields;
        remaining_fields = required_fields;
        this.flags = flags;
        this.cancellable = cancellable;
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
        
        // If local only and not found fully in local store, throw NOT_FOUND; there is no fallback
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
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield engine.throw_if_remote_not_ready_async(cancellable);
        
        // fetch only the remaining fields from the remote folder (if only pulling partial information,
        // will merge at end of this method)
        Gee.List<Geary.Email>? list = yield engine.remote_folder.list_email_async(
            new Imap.MessageSet.email_id(id), remaining_fields, cancellable);
        
        if (list == null || list.size != 1)
            throw new EngineError.NOT_FOUND("Unable to fetch %s in %s", id.to_string(), engine.to_string());
        
        // save to local store
        email = list[0];
        assert(email != null);
        if (yield engine.local_folder.create_or_merge_email_async(email, cancellable))
            engine.notify_email_locally_appended(new Geary.Singleton<Geary.EmailIdentifier>(email.id));
        
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

