/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ListEmailByID : Geary.ImapEngine.AbstractListEmail {
    private Imap.EmailIdentifier? initial_id;
    private int count;
    private int local_list_count = 0;
    
    public ListEmailByID(GenericFolder owner, Geary.EmailIdentifier? initial_id, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Gee.List<Geary.Email>? accumulator,
        EmailCallback? cb, Cancellable? cancellable) {
        base ("ListEmailByID", owner, required_fields, flags, accumulator, cb, cancellable);
        
        this.initial_id = (Imap.EmailIdentifier?) initial_id;
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
                if (email.fields.fulfills(required_fields))
                    fulfilled.add(email);
                else
                    unfulfilled.set(required_fields.clear(email.fields), email.id);
            }
        }
        
        // report fulfilled items
        if (fulfilled.size > 0) {
            if (accumulator != null)
                accumulator.add_all(fulfilled);
            
            if (cb != null)
                cb(fulfilled, null);
        }
        
        // local-only operations stop here; also, since the local store is normalized from the top
        // of the vector on down, if enough items came back fulfilled, then done
        local_list_count = (list != null) ? list.size : 0;
        if (flags.is_local_only() || (unfulfilled.size == 0 && local_list_count >= count)) {
            if (cb != null)
                cb(null, null);
            
            return ReplayOperation.Status.COMPLETED;
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // To get this far, either the local store doesn't have all the contents of the items in
        // the request range, or it doesn't have any row for items in the range (i.e. the vector
        // is too short).
        if (local_list_count + unfulfilled.size < count) {
            Gee.List<Geary.Email>? expanded = yield expand_vector_async();
            if (expanded != null) {
                // take all the IDs from the expanded vector and call them unfulfilled; base class
                // does the rest.  Add duplicate detection fields so that can be determined
                // immediately
                foreach (Geary.Email email in expanded) {
                    unfulfilled.set(required_fields | ImapDB.Folder.REQUIRED_FOR_DUPLICATE_DETECTION,
                        email.id);
                }
            }
        }
        
        // Even after expansion it's possible for the local_list_count + unfulfilled to be less
        // than count if the folder has fewer messages or the user is requesting a span near
        // either end of the vector, so don't do that kind of sanity checking here
        
        return yield base.replay_remote_async();
    }
    
    private async Gee.List<Geary.Email>? expand_vector_async() throws Error {
        // watch out for situations where the entire folder is represented locally (i.e. no
        // expansion necessary)
        int remote_count = owner.get_remote_counts(null, null);
        if (remote_count < 0)
            return null;
        
        // include marked for removed in the count in case this is being called while a removal
        // is in process, in which case don't want to expand vector this moment because the
        // vector is in flux
        int local_count = yield owner.local_folder.get_email_count_async(
            ImapDB.Folder.ListFlags.NONE, cancellable);
        int local_count_with_marked = yield owner.local_folder.get_email_count_async(
            ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);
        
        if (local_count_with_marked >= remote_count) {
            // watch for sync discrepencies ... this is not something that can be fixed up here
            if (local_count_with_marked > remote_count) {
                message("%s: not expanding vector remote_count=%d local_count=%d", to_string(),
                    remote_count, local_count);
            }
            
            return null;
        }
        
        // determine low and high position for expansion ... default in most code paths for high
        // is the SequenceNumber just below the lowest known message, unless no local messages
        // are present
        Imap.SequenceNumber? low_pos = null;
        Imap.SequenceNumber? high_pos = null;
        if (local_count > 0)
            high_pos = new Imap.SequenceNumber(Numeric.int_floor(remote_count - local_count, 1));
        
        if (flags.is_oldest_to_newest()) {
            if (initial_id == null) {
                // if oldest to newest and initial-id is null, then start at the bottom
                low_pos = new Imap.SequenceNumber(1);
            } else {
                // since initial_id is not null and contract requires that the ID come from this
                // folder, it must be known locally; the span for oldest-to-newest is always locally
                // available because the partial vector always is from the newest messages on
                // the remote down toward the oldest; so no vector expansion is necessary in this
                // case
                //
                // However ... there is some internal code (search, specifically) that relies on
                // being able to pass in an EmailIdentifier with a UID unknown locally, and so that
                // needs to be taken accounted of
                Gee.Map<Imap.UID, Imap.SequenceNumber>? map = yield owner.remote_folder.uid_to_position_async(
                    new Imap.MessageSet.uid(initial_id.uid), cancellable);
                if (map == null || map.size == 0 || !map.has_key(initial_id.uid)) {
                    debug("%s: Unable to expand vector for initial_id=%s: unable to convert to position",
                        to_string(), initial_id.to_string());
                    
                    return null;
                }
                
                low_pos = map.get(initial_id.uid);
            }
        } else {
            // newest to oldest
            //
            // if initial_id is null or no local earliest UID, then vector expansion is simple:
            // merely count backwards from the top of the vector
            if (initial_id == null || local_count == 0) {
                low_pos = new Imap.SequenceNumber(Numeric.int_floor((remote_count - count) + 1, 1));
                // don't set high_pos, leave null to use symbolic "highest" in MessageSet
                high_pos = null;
            } else {
                // not so simple; need to determine the *remote* position of the earliest local
                // UID and count backward from that; if no UIDs present, then it's as if no initial_id
                // is specified.
                //
                // low position: count backwards; note that it's possible this will overshoot and
                // pull in more email than technically required, but without a round-trip to the
                // server to determine the position number of a particular UID, this makes sense
                assert(high_pos != null);
                low_pos = new Imap.SequenceNumber(
                    Numeric.int_floor((high_pos.value - count) + 1, 1));
            }
        }
        
        // low_pos must be defined by this point
        assert(low_pos != null);
        
        Imap.MessageSet msg_set;
        if (high_pos != null)
            msg_set = new Imap.MessageSet.range_by_first_last(low_pos, high_pos);
        else
            msg_set = new Imap.MessageSet.range_to_highest(low_pos);
        
        debug("%s: Performing vector expansion using %s for %s/%u", owner.to_string(), msg_set.to_string(),
            (initial_id != null) ? initial_id.to_string() : "(null)", count);
        
        Gee.List<Geary.Email>? list = yield owner.remote_folder.list_email_async(msg_set,
            Geary.Email.Field.NONE, cancellable);
        
        debug("%s: Vector expansion completed (%d new email)", owner.to_string(),
            (list != null) ? list.size : 0);
        
        return list;
    }
    
    public override async void backout_local_async() throws Error {
        // R/O, nothing to backout
    }
    
    public override string describe_state() {
        return "%s initial_id=%s count=%u incl=%s newest_to_oldest=%s".printf(base.describe_state(),
            (initial_id != null) ? initial_id.to_string() : "(null)", count,
            flags.is_including_id().to_string(), flags.is_newest_to_oldest().to_string());
    }
}

