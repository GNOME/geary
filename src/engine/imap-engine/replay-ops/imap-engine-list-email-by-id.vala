/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ListEmailByID : Geary.ImapEngine.AbstractListEmail {
    private ImapDB.EmailIdentifier? initial_id;
    private int count;
    private int fulfilled_count = 0;
    private Imap.UID? initial_uid = null;
    
    public ListEmailByID(GenericFolder owner, ImapDB.EmailIdentifier? initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) {
        base ("ListEmailByID", owner, required_fields, flags, accumulator, cb, cancellable);
        
        this.initial_id = initial_id;
        this.count = count;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (flags.is_force_update())
            return ReplayOperation.Status.CONTINUE;
        
        // get everything from local store, even partial matches, that fit range
        ImapDB.Folder.ListFlags list_flags = ImapDB.Folder.ListFlags.from_folder_flags(flags);
        list_flags |= ImapDB.Folder.ListFlags.PARTIAL_OK;
        Gee.List<Geary.Email>? list = yield owner.local_folder.list_email_by_id_async(initial_id,
            count, required_fields, list_flags, cancellable);
        
        // walk list, breaking out unfulfilled items from fulfilled items
        Gee.ArrayList<Geary.Email> fulfilled = new Gee.ArrayList<Geary.Email>();
        if (list != null) {
            foreach (Geary.Email email in list) {
                Imap.UID uid = ((ImapDB.EmailIdentifier) email.id).uid;
                
                // if INCLUDING_ID, then find the initial UID for the initial_id (if specified)
                if (flags.is_including_id()) {
                    if (initial_id != null && email.id.equal_to(initial_id))
                        initial_uid = uid;
                } else {
                    // !INCLUDING_ID, so find the earliest UID (for oldest-to-newest) or latest
                    // UID (newest-to-oldest)
                    if (flags.is_oldest_to_newest()) {
                        if (initial_uid == null || uid.compare_to(initial_uid) < 0)
                            initial_uid = uid;
                    } else {
                        // newest-to-oldest
                        if (initial_uid == null || uid.compare_to(initial_uid) > 0)
                            initial_uid = uid;
                    }
                }
                
                if (email.fields.fulfills(required_fields)) {
                    fulfilled.add(email);
                } else {
                    unfulfilled.set(required_fields.clear(email.fields),
                        (ImapDB.EmailIdentifier) email.id);
                }
            }
        }
        
        // If INCLUDING_ID specified, verify that the initial_id was found; if not, then want to
        // get it from the remote (this will force a vector expansion, if required)
        if (flags.is_including_id()) {
            if (initial_id != null && initial_uid == null) {
                unfulfilled.set(required_fields | ImapDB.Folder.REQUIRED_FIELDS,
                    initial_id);
            }
        } else {
            // the initial uid should have been found if at least one Email was returned from the
            // local list
            if (list != null && list.size > 0)
                assert(initial_uid != null);
        }
        
        // report fulfilled items
        fulfilled_count = fulfilled.size;
        if (fulfilled_count > 0) {
            if (accumulator != null)
                accumulator.add_all(fulfilled);
            
            if (cb != null)
                cb(fulfilled, null);
        }
        
        // determine if everything was listed
        bool finished = false;
        if (flags.is_local_only()) {
            // local-only operations stop here
            finished = true;
        } else if (count != int.MAX) {
            // fetching 'count' fulfilled items and no unfulfilled items means listing is done
            // this is true for both oldest-to-newest, newest-to-oldest, whether or not they have
            // an initial_id
            finished = (unfulfilled.size == 0 && fulfilled_count >= count);
        } else {
            // count == int.MAX
            // This sentinel means "get everything from this point", so this has different meanings
            // depending on direction
            if (flags.is_newest_to_oldest()) {
                // only finished if the folder is entirely normalized
                Trillian is_fully_expanded = yield is_fully_expanded_async();
                finished = (is_fully_expanded == Trillian.TRUE);
            } else {
                // for oldest-to-newest, finished if no unfulfilled items
                finished = (unfulfilled.size == 0);
            }
        }
        
        // local-only operations stop here; also, since the local store is normalized from the top
        // of the vector on down, if enough items came back fulfilled, then done
        if (finished) {
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        bool expansion_required = false;
        Trillian is_fully_expanded = yield is_fully_expanded_async();
        if (is_fully_expanded == Trillian.FALSE) {
            if (flags.is_oldest_to_newest()) {
                if (initial_id != null) {
                    // expand vector if not initial_id not discovered
                    expansion_required = (initial_uid == null);
                } else {
                    // initial_id == null, expansion required if not fully already
                    expansion_required = true;
                }
            } else {
                // newest-to-oldest
                if (count == int.MAX) {
                    // if infinite count, expansion required if not already
                    expansion_required = true;
                } else if (initial_id != null) {
                    // finite count, expansion required if initial not found *or* not enough
                    // items were pulled in
                    expansion_required = (initial_uid == null) || (fulfilled_count + unfulfilled.size < count);
                } else {
                    // initial_id == null
                    // finite count, expansion required if not enough found
                    expansion_required = (fulfilled_count + unfulfilled.size < count);
                }
            }
        }
        
        // If the vector is too short, expand it now
        if (expansion_required)
            yield expand_vector_async(initial_uid, count);
        
        // Even after expansion it's possible for the local_list_count + unfulfilled to be less
        // than count if the folder has fewer messages or the user is requesting a span near
        // either end of the vector, so don't do that kind of sanity checking here
        
        return yield base.replay_remote_async();
    }
    
    public override string describe_state() {
        return "%s initial_id=%s count=%u incl=%s newest_to_oldest=%s".printf(base.describe_state(),
            (initial_id != null) ? initial_id.to_string() : "(null)", count,
            flags.is_including_id().to_string(), flags.is_newest_to_oldest().to_string());
    }
}

