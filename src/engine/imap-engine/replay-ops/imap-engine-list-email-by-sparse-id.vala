/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ListEmailBySparseID : Geary.ImapEngine.AbstractListEmail {
    private Gee.HashSet<ImapDB.EmailIdentifier> ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
    
    public ListEmailBySparseID(GenericFolder owner, Gee.Collection<ImapDB.EmailIdentifier> ids,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback cb, Cancellable? cancellable) {
        base ("ListEmailBySparseID", owner, required_fields, flags, accumulator, cb, cancellable);
        
        this.ids.add_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (flags.is_force_update()) {
            foreach (ImapDB.EmailIdentifier id in ids)
                unfulfilled.set(required_fields, id);
            
            return ReplayOperation.Status.CONTINUE;
        }
        
        Gee.List<Geary.Email>? local_list = yield owner.local_folder.list_email_by_sparse_id_async(ids,
            required_fields, ImapDB.Folder.ListFlags.PARTIAL_OK, cancellable);
        
        // Build list of emails fully fetched from local store and table of remaining emails by
        // their lack of completeness
        Gee.List<Geary.Email> fulfilled = new Gee.ArrayList<Geary.Email>();
        if (local_list != null && local_list.size > 0) {
            Gee.Map<Geary.EmailIdentifier, Geary.Email>? map = Email.emails_to_map(local_list);
            assert(map != null);
            
            // walk list of *requested* IDs to ensure that unknown are considering unfulfilled
            foreach (Geary.EmailIdentifier id in ids) {
                Geary.Email? email = map.get(id);
            
                // if completely unknown, make sure duplicate detection fields are included; otherwise,
                // if known, then they were pulled down during folder normalization and during
                // vector expansion
                if (email == null)
                    unfulfilled.set(required_fields | ImapDB.Folder.REQUIRED_FIELDS, id);
                else if (!email.fields.fulfills(required_fields))
                    unfulfilled.set(required_fields.clear(email.fields), id);
                else
                    fulfilled.add(email);
            }
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

