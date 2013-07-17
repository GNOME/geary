/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ListEmailBySparseID : Geary.ImapEngine.AbstractListEmail {
    private class LocalBatchOperation : Nonblocking.BatchOperation {
        public GenericFolder owner;
        public Geary.EmailIdentifier id;
        public Geary.Email.Field required_fields;
        
        public LocalBatchOperation(GenericFolder owner, Geary.EmailIdentifier id,
            Geary.Email.Field required_fields) {
            this.owner = owner;
            this.id = id;
            this.required_fields = required_fields;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            // TODO: Need a sparse ID fetch in ImapDB.Folder to scoop all these up at once
            try {
                return yield owner.local_folder.fetch_email_async(id, required_fields,
                    ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);
            } catch (Error err) {
                // only throw errors that are not NOT_FOUND and INCOMPLETE_MESSAGE, as these two
                // are recoverable
                if (!(err is Geary.EngineError.NOT_FOUND) && !(err is Geary.EngineError.INCOMPLETE_MESSAGE))
                    throw err;
            }
            
            return null;
        }
    }
    
    private Gee.HashSet<Geary.EmailIdentifier> ids = new Gee.HashSet<Geary.EmailIdentifier>();
    
    public ListEmailBySparseID(GenericFolder owner, Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback cb, Cancellable? cancellable) {
        base ("ListEmailBySparseID", owner, required_fields, flags, accumulator, cb, cancellable);
        
        this.ids.add_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (flags.is_force_update()) {
            foreach (EmailIdentifier id in ids)
                unfulfilled.set(required_fields, id);
            
            return ReplayOperation.Status.CONTINUE;
        }
        
        Nonblocking.Batch batch = new Nonblocking.Batch();
        
        // Fetch emails by ID from local store all at once
        foreach (Geary.EmailIdentifier id in ids)
            batch.add(new LocalBatchOperation(owner, id, required_fields));
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        // Build list of emails fully fetched from local store and table of remaining emails by
        // their lack of completeness
        Gee.List<Geary.Email> fulfilled = new Gee.ArrayList<Geary.Email>();
        foreach (int batch_id in batch.get_ids()) {
            LocalBatchOperation local_op = (LocalBatchOperation) batch.get_operation(batch_id);
            Geary.Email? email = (Geary.Email?) batch.get_result(batch_id);
            
            // if completely unknown, make sure duplicate detection fields are included; otherwise,
            // if known, then they were pulled down during folder normalization and during
            // vector expansion
            if (email == null)
                unfulfilled.set(required_fields | ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION, local_op.id);
            else if (!email.fields.fulfills(required_fields))
                unfulfilled.set(required_fields.clear(email.fields), local_op.id);
            else
                fulfilled.add(email);
        }
        
        if (fulfilled.size > 0) {
            if (accumulator != null)
                accumulator.add_all(fulfilled);
            
            if (cb != null)
                cb(fulfilled, null);
        }
        
        if (flags.is_local_only() || unfulfilled.size == 0) {
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, nothing to backout
    }
    
    public override string describe_state() {
        return "ids.size=%d required_fields=%Xh flags=%Xh".printf(ids.size, required_fields, flags);
    }
}

