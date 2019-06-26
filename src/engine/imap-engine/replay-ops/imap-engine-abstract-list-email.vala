/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A base class for building replay operations that list messages.
 */
private abstract class Geary.ImapEngine.AbstractListEmail : Geary.ImapEngine.SendReplayOperation {

    private static int total_fetches_avoided = 0;

    private class RemoteBatchOperation : Nonblocking.BatchOperation {
        // IN
        public Imap.FolderSession remote;
        public ImapDB.Folder local;
        public Imap.MessageSet msg_set;
        public Geary.Email.Field unfulfilled_fields;
        public Geary.Email.Field required_fields;
        public bool update_unread;

        // OUT
        public Gee.Set<Geary.EmailIdentifier> created_ids = new Gee.HashSet<Geary.EmailIdentifier>();

        private ContactHarvester harvester;


        public RemoteBatchOperation(Imap.FolderSession remote,
                                    ImapDB.Folder local,
                                    Imap.MessageSet msg_set,
                                    Geary.Email.Field unfulfilled_fields,
                                    Geary.Email.Field required_fields,
                                    bool update_unread,
                                    ContactHarvester harvester) {
            this.remote = remote;
            this.local = local;
            this.msg_set = msg_set;
            this.unfulfilled_fields = unfulfilled_fields;
            this.required_fields = required_fields;
            this.update_unread = update_unread;
            this.harvester = harvester;
        }

        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            // fetch from remote folder
            Gee.List<Geary.Email>? list = yield this.remote.list_email_async(
                msg_set, unfulfilled_fields, cancellable
            );
            if (list == null || list.size == 0)
                return null;

            // TODO: create_or_merge_email_async() should only write if something has changed
            Gee.Map<Email, bool> created_or_merged =
                yield this.local.create_or_merge_email_async(
                    list,
                    this.update_unread,
                    this.harvester,
                    cancellable
                );

            for (int ctr = 0; ctr < list.size; ctr++) {
                Geary.Email email = list[ctr];

                // if created, add to id pool
                if (created_or_merged.get(email))
                    created_ids.add(email.id);

                // if remote email doesn't fulfills all required fields, fetch full and return that
                // TODO: Need a sparse ID fetch in ImapDB.Folder to do this all at once
                if (!email.fields.fulfills(required_fields)) {
                    email = yield this.local.fetch_email_async(
                        (ImapDB.EmailIdentifier) email.id,
                        required_fields,
                        ImapDB.Folder.ListFlags.NONE,
                        cancellable
                    );
                    list[ctr] = email;
                }
            }

            return list;
        }
    }

    // The accumulated Email from the list operation.  Should only be accessed once the operation
    // has completed.
    public Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();

    protected MinimalFolder owner;
    protected Geary.Email.Field required_fields;
    protected Cancellable? cancellable;
    protected Folder.ListFlags flags;

    private Gee.HashMap<Imap.UID, Geary.Email.Field> unfulfilled = new Gee.HashMap<Imap.UID, Geary.Email.Field>();

    protected AbstractListEmail(string name, MinimalFolder owner, Geary.Email.Field required_fields,
        Folder.ListFlags flags, Cancellable? cancellable) {
        base(name, OnError.IGNORE_REMOTE);

        this.owner = owner;
        this.required_fields = required_fields;
        this.cancellable = cancellable;
        this.flags = flags;
    }

    protected void add_unfulfilled_fields(Imap.UID? uid, Geary.Email.Field unfulfilled_fields) {
        assert(uid != null);
        assert(uid.is_valid());

        if (!unfulfilled.has_key(uid))
            unfulfilled.set(uid, unfulfilled_fields);
        else
            unfulfilled.set(uid, unfulfilled.get(uid) | unfulfilled_fields);
    }

    protected void add_many_unfulfilled_fields(Gee.Collection<Imap.UID>? uids,
        Geary.Email.Field unfulfilled_fields) {
        if (uids != null) {
            foreach (Imap.UID uid in uids)
                add_unfulfilled_fields(uid, unfulfilled_fields);
        }
    }

    protected int get_unfulfilled_count() {
        return unfulfilled.size;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // remove email already picked up from local store ... for email reported via the
        // callback, too late
        Collection.remove_if<Geary.Email>(accumulator, (email) => {
            return ids.contains((ImapDB.EmailIdentifier) email.id);
        });

        // remove from unfulfilled list, as there's now nothing to fetch from the server
        // NOTE: Requires UID to work; this *should* always work, as the EmailIdentifier should
        // be originating from the database, not the Imap.Folder layer
        foreach (ImapDB.EmailIdentifier id in ids) {
            if (id.has_uid())
                unfulfilled.unset(id.uid);
        }
    }

    // Child class should execute its own calls *before* calling this base method
    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        // only deal with unfulfilled email, child class must deal with everything else
        if (unfulfilled.size == 0)
           return;

        // since list and search commands ahead of this one in the queue may have fulfilled some of
        // the emails thought to be unfulfilled when first checked locally, look for them now
        int fetches_avoided = yield remove_fulfilled_uids_async();
        if (fetches_avoided > 0) {
            total_fetches_avoided += fetches_avoided;

            debug("[%s] %d previously-fulfilled fetches avoided in list operation, %d total",
                owner.to_string(), fetches_avoided, total_fetches_avoided);

            // if all fulfilled, emails were added to accumulator in remove call, so done
            if (unfulfilled.size == 0)
                return;
        }

        // convert UID -> needed fields mapping to needed fields -> UIDs, as they can be grouped
        // and submitted at same time
        Gee.HashMultiMap<Geary.Email.Field, Imap.UID> reverse_unfulfilled = new Gee.HashMultiMap<
            Geary.Email.Field, Imap.UID>();
        foreach (Imap.UID uid in unfulfilled.keys)
            reverse_unfulfilled.set(unfulfilled.get(uid), uid);

        // schedule operations to remote for each set of email with unfulfilled fields and merge
        // in results, pulling out the entire email
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (Geary.Email.Field unfulfilled_fields in reverse_unfulfilled.get_keys()) {
            Gee.Collection<Imap.UID> unfulfilled_uids = reverse_unfulfilled.get(unfulfilled_fields);
            if (unfulfilled_uids.size == 0)
                continue;

            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(unfulfilled_uids);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                RemoteBatchOperation remote_op = new RemoteBatchOperation(
                    remote,
                    this.owner.local_folder,
                    msg_set,
                    unfulfilled_fields,
                    required_fields,
                    !this.flags.is_any_set(NO_UNREAD_UPDATE),
                    this.owner.harvester
                );
                batch.add(remote_op);
            }
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
        if (result_list.size > 0)
            accumulator.add_all(result_list);

        // signal
        if (created_ids.size > 0) {
            owner.replay_notify_email_inserted(created_ids);
            owner.replay_notify_email_locally_inserted(created_ids);
        }
    }

    /**
     * Expands the owning folder's vector.
     *
     * Lists on the remote messages needed to fulfill ImapDB's
     * requirements from `initial_uid` (inclusive) forward to the
     * start of the vector if the OLDEST_TO_NEWEST flag is set, else
     * from `initial_uid` (inclusive) back at most by `count` number
     * of messages. If `initial_uid` is null, the start or end of the
     * vector is used, respectively.
     *
     * The returned UIDs are those added to the vector, which can then
     * be examined and added to the messages to be fulfilled if
     * needed.
     */
    protected async Gee.Set<Imap.UID>? expand_vector_async(Imap.FolderSession remote,
                                                           Imap.UID? initial_uid,
                                                           int count)
        throws GLib.Error {
        debug("%s: expanding vector...", owner.to_string());
        int remote_count = remote.folder.properties.email_total;

        // include marked for removed in the count in case this is being called while a removal
        // is in process, in which case don't want to expand vector this moment because the
        // vector is in flux
        int local_count = yield owner.local_folder.get_email_count_async(
            ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE, cancellable);

        // watch out for attempts to expand vector when it's expanded as far as it will go
        if (local_count >= remote_count)
            return null;

        // Determine low and high position for expansion. The vector
        // start position is based on the assumption that the vector
        // end is the same as the remote end.
        int64 vector_start = (remote_count - local_count + 1);
        int64 low_pos = -1;
        int64 high_pos = -1;
        int64 initial_pos = -1;

        if (initial_uid != null) {
            Gee.Map<Imap.UID, Imap.SequenceNumber>? map =
            yield remote.uid_to_position_async(
                new Imap.MessageSet.uid(initial_uid), cancellable
            );
            Imap.SequenceNumber? pos = map.get(initial_uid);
            if (pos != null) {
                initial_pos = pos.value;
            }
        }

        // Determine low and high position for expansion
        if (flags.is_oldest_to_newest()) {
            low_pos = Imap.SequenceNumber.MIN;
            if (initial_pos > Imap.SequenceNumber.MIN) {
                low_pos = initial_pos;
            }
            high_pos = vector_start - 1;
        } else {
            // Newest to oldest.
            if (initial_pos <= Imap.SequenceNumber.MIN) {
                high_pos = remote_count;
                low_pos = Numeric.int64_floor(
                    high_pos - count + 1, Imap.SequenceNumber.MIN
                );
            } else {
                high_pos = Numeric.int64_floor(
                    initial_pos, vector_start - 1
                );
                low_pos = Numeric.int64_floor(
                    initial_pos - (count - 1), Imap.SequenceNumber.MIN
                );
            }
        }

        if (low_pos > high_pos) {
            debug("%s: Aborting vector expansion, low_pos=%s > high_pos=%s",
                  owner.to_string(), low_pos.to_string(), high_pos.to_string());
            return null;
        }

        Imap.MessageSet msg_set = new Imap.MessageSet.range_by_first_last(
            new Imap.SequenceNumber(low_pos),
            new Imap.SequenceNumber(high_pos)
        );
        int64 actual_count = (high_pos - low_pos) + 1;

        debug("%s: Performing vector expansion using %s for initial_uid=%s count=%d actual_count=%s local_count=%d remote_count=%d oldest_to_newest=%s",
            owner.to_string(), msg_set.to_string(),
            (initial_uid != null) ? initial_uid.to_string() : "(null)", count, actual_count.to_string(),
            local_count, remote_count, flags.is_oldest_to_newest().to_string());

        Gee.List<Geary.Email>? list = yield remote.list_email_async(msg_set,
            Geary.Email.Field.NONE, cancellable);

        Gee.Set<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        if (list != null) {
            // add all the new email to the unfulfilled list, which ensures (when replay_remote_async
            // is called) that the fields are downloaded and added to the database
            foreach (Geary.Email email in list)
                uids.add(((ImapDB.EmailIdentifier) email.id).uid);

            // remove any already stored locally
            Gee.Collection<ImapDB.EmailIdentifier>? ids =
                yield owner.local_folder.get_ids_async(uids, ImapDB.Folder.ListFlags.INCLUDE_MARKED_FOR_REMOVE,
                    cancellable);
            if (ids != null && ids.size > 0) {
                foreach (ImapDB.EmailIdentifier id in ids) {
                    assert(id.has_uid());
                    uids.remove(id.uid);
                }
            }

            // for the remainder (not in local store), fetch the required fields
            add_many_unfulfilled_fields(uids, ImapDB.Folder.REQUIRED_FIELDS);
        }

        debug("%s: Vector expansion completed (%d new email)", owner.to_string(),
            (uids != null) ? uids.size : 0);

        return uids != null && uids.size > 0 ? uids : null;
    }

    private async int remove_fulfilled_uids_async() throws Error {
        // if the update is forced, don't rely on cached database, have to go to the horse's mouth
        if (flags.is_force_update())
            return 0;

        ImapDB.Folder.ListFlags list_flags = ImapDB.Folder.ListFlags.from_folder_flags(flags);

        Gee.Set<ImapDB.EmailIdentifier>? unfulfilled_ids = yield owner.local_folder.get_ids_async(
            unfulfilled.keys, list_flags, cancellable);
        if (unfulfilled_ids == null || unfulfilled_ids.size == 0)
            return 0;

        Gee.Map<ImapDB.EmailIdentifier, Email.Field>? local_fields =
            yield owner.local_folder.list_email_fields_by_id_async(unfulfilled_ids, list_flags,
                cancellable);
        if (local_fields == null || local_fields.size == 0)
            return 0;

        // For each identifier, if now fulfilled in the database, fetch it, add it to the accumulator,
        // and remove it from the unfulfilled map -- one network operation saved
        int fetch_avoided = 0;
        foreach (ImapDB.EmailIdentifier id in local_fields.keys) {
            if (!local_fields.get(id).fulfills(required_fields))
                continue;

            try {
                Email email = yield owner.local_folder.fetch_email_async(id, required_fields, list_flags,
                    cancellable);
                accumulator.add(email);
            } catch (Error err) {
                if (err is IOError.CANCELLED)
                    throw err;

                // some problem locally, do the network round-trip
                continue;
            }

            // got it, don't fetch from remote
            unfulfilled.unset(id.uid);
            fetch_avoided++;
        }

        return fetch_avoided;
    }

    public override string describe_state() {
        return "required_fields=%Xh local_only=%s force_update=%s".printf(required_fields,
            flags.is_local_only().to_string(), flags.is_force_update().to_string());
    }
}
