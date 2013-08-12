/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.AbstractListEmail : Geary.ImapEngine.SendReplayOperation {
    private class RemoteBatchOperation : Nonblocking.BatchOperation {
        // IN
        public GenericFolder owner;
        public Imap.MessageSet msg_set;
        public Geary.Email.Field unfulfilled_fields;
        public Geary.Email.Field required_fields;
        
        // OUT
        public Gee.Set<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();
        
        public RemoteBatchOperation(GenericFolder owner, Imap.MessageSet msg_set,
            Geary.Email.Field unfulfilled_fields, Geary.Email.Field required_fields) {
            this.owner = owner;
            this.msg_set = msg_set;
            this.unfulfilled_fields = unfulfilled_fields;
            this.required_fields = required_fields;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            // fetch from remote folder
            Gee.List<Geary.Email>? list = yield owner.remote_folder.list_email_async(msg_set,
                unfulfilled_fields, cancellable);
            if (list == null || list.size == 0)
                return null;
            
            // TODO: create_or_merge_email_async() should only write if something has changed
            Gee.Map<Geary.Email, bool> created_or_merged = yield owner.local_folder.create_or_merge_email_async(
                list, cancellable);
            for (int ctr = 0; ctr < list.size; ctr++) {
                Geary.Email email = list[ctr];
                
                // if created, add to id pool
                if (created_or_merged.get(email))
                    created_ids.add(email.id);
                
                // if remote email doesn't fulfills all required fields, fetch full and return that
                // TODO: Need a sparse ID fetch in ImapDB.Folder to do this all at once
                if (!email.fields.fulfills(required_fields)) {
                    email = yield owner.local_folder.fetch_email_async(email.id, required_fields,
                        ImapDB.Folder.ListFlags.NONE, cancellable);
                    list[ctr] = email;
                }
            }
            
            return list;
        }
    }
    
    protected GenericFolder owner;
    protected Geary.Email.Field required_fields;
    protected Gee.List<Geary.Email>? accumulator = null;
    protected weak EmailCallback? cb;
    protected Cancellable? cancellable;
    protected Folder.ListFlags flags;
    protected Gee.HashMultiMap<Geary.Email.Field, Geary.EmailIdentifier> unfulfilled = new Gee.HashMultiMap<
        Geary.Email.Field, Geary.EmailIdentifier>();
    
    public AbstractListEmail(string name, GenericFolder owner, Geary.Email.Field required_fields,
        Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator, EmailCallback? cb,
        Cancellable? cancellable) {
        base(name);
        
        this.owner = owner;
        this.required_fields = required_fields;
        this.accumulator = accumulator;
        this.cb = cb;
        this.cancellable = cancellable;
        this.flags = flags;
    }
    
    public override bool query_local_writebehind_operation(ReplayOperation.WritebehindOperation op,
        EmailIdentifier id, Imap.EmailFlags? flags) {
        // don't need to check if id is present here, all paths deal with this possibility
        // correctly
        
        switch (op) {
            case ReplayOperation.WritebehindOperation.REMOVE:
                // remove email already picked up from local store ... for email reported via the
                // callback, too late
                if (accumulator != null) {
                    Gee.HashSet<Geary.Email> wb_removed = new Gee.HashSet<Geary.Email>();
                    foreach (Geary.Email email in accumulator) {
                        if (email.id.equal_to(id))
                            wb_removed.add(email);
                    }
                    
                    accumulator.remove_all(wb_removed);
                }
                
                // remove from unfulfilled list, as there's nothing to fetch from the server
                // this funky little loop ensures that all mentions of the EmailIdentifier in
                // the unfulfilled MultiMap are removed, but must restart loop because removing
                // within a foreach invalidates the Iterator
                bool removed = false;
                do {
                    removed = false;
                    foreach (Geary.Email.Field field in unfulfilled.get_keys()) {
                        removed = unfulfilled.remove(field, id);
                        if (removed)
                            break;
                    }
                } while (removed);
                
                return true;
            
            default:
                // ignored
                return true;
        }
    }
    
    // Child class should execute its own calls *before* calling this base method
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // only deal with unfulfilled email, child class must deal with everything else
        if (unfulfilled.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // schedule operations to remote for each set of email with unfulfilled fields and merge
        // in results, pulling out the entire email
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (Geary.Email.Field unfulfilled_fields in unfulfilled.get_keys()) {
            Gee.Collection<EmailIdentifier> email_ids = unfulfilled.get(unfulfilled_fields);
            if (email_ids.size == 0)
                continue;
            
            Imap.MessageSet msg_set = new Imap.MessageSet.email_id_collection(email_ids);
            RemoteBatchOperation remote_op = new RemoteBatchOperation(owner, msg_set, unfulfilled_fields,
                required_fields);
            batch.add(remote_op);
        }
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        Gee.ArrayList<Geary.Email> result_list = new Gee.ArrayList<Geary.Email>();
        Gee.HashSet<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (int batch_id in batch.get_ids()) {
            Gee.List<Geary.Email>? list = (Gee.List<Geary.Email>?) batch.get_result(batch_id);
            if (list != null && list.size > 0) {
                result_list.add_all(list);
                
                RemoteBatchOperation op = (RemoteBatchOperation) batch.get_operation(batch_id);
                created_ids.add_all(op.created_ids);
            }
        }
        
        // report merged emails
        if (result_list.size > 0) {
            if (accumulator != null)
                accumulator.add_all(result_list);
            
            if (cb != null)
                cb(result_list, null);
        }
        
        // done
        if (cb != null)
            cb(null, null);
        
        // signal
        if (created_ids.size > 0)
            owner.notify_local_expansion(created_ids);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, no backout
    }
    
    public override string describe_state() {
        return "required_fields=%Xh local_only=%s force_update=%s".printf(required_fields,
            flags.is_local_only().to_string(), flags.is_force_update().to_string());
    }
}

