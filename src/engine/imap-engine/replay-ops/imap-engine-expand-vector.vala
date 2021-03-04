/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Extends the vector to include the given message set.
 *
 * The minimum required email fields for the given criteria will be
 * fetched from the remote and persisted in local storage, extending
 * the folder's local vector.
 */
private class Geary.ImapEngine.ExpandVector : ReplayOperation {


    private MinimalFolder engine;
    private Email.Field required_fields;
    private GLib.DateTime? target_date;
    private uint? target_count;
    private GLib.Cancellable? cancellable;


    public ExpandVector(MinimalFolder engine,
                        Email.Field required_fields,
                        GLib.DateTime? target_date,
                        uint? target_count,
                        GLib.Cancellable? cancellable = null) {
        base("ExpandVector", REMOTE_ONLY, OnError.RETRY);
        this.engine = engine;
        this.required_fields = required_fields;
        this.target_date = target_date;
        this.target_count = target_count;
        this.cancellable = cancellable;
    }

    public override async void replay_remote_async(Imap.FolderSession remote)
        throws GLib.Error {
        if (this.target_count != null) {
            yield expand_by_count(this.target_count, remote);
        }
        if (this.target_date != null) {
            yield expand_by_date(this.target_date, remote);
        }
    }

    public async void expand_by_count(uint target,
                                      Imap.FolderSession remote)
        throws GLib.Error {
        debug("Expanding vector by: %u new email", target);
        int64 low_pos = -1;
        int64 high_pos = -1;

        Imap.SequenceNumber? lowest_vector_pos = null;
        var lowest_vector_id = yield this.engine.local_folder.get_earliest_id_async(
            this.cancellable
        );
        if (lowest_vector_id != null) {
            var uid = lowest_vector_id.uid;
            // this does an IMAP FETCH, but EXPUNGE responses to that
            // are forbidden the returned UIDs are likely fine.
            Gee.Map<Imap.UID, Imap.SequenceNumber>? map =
                yield remote.uid_to_position_async(
                    new Imap.MessageSet.uid(uid), cancellable
                );
            lowest_vector_pos = map.get(uid);
        }

        if (lowest_vector_pos != null) {
            high_pos = lowest_vector_pos.value - 1;
        } else {
            high_pos = remote.folder.properties.email_total;
        }

        low_pos = high_pos - target;
        if (low_pos < Imap.SequenceNumber.MIN) {
            low_pos = Imap.SequenceNumber.MIN;
        }

        yield expand_on(
            new Imap.MessageSet.range_by_first_last(
                new Imap.SequenceNumber(low_pos),
                new Imap.SequenceNumber(high_pos)
            ),
            remote
        );
    }

    public async void expand_by_date(GLib.DateTime target,
                                     Imap.FolderSession remote)
    throws GLib.Error {
        debug(
            "Expanding vector to: %s",
            this.target_date != null
            ? this.target_date.format_iso8601()
            : "(null)"
        );

        Imap.SearchCriteria criteria = new Imap.SearchCriteria();
        criteria.is_(
            Imap.SearchCriterion.since_internaldate(
                new Imap.InternalDate.from_date_time(target)
            )
        );

        Imap.UID high_uid = new Imap.UID(Imap.UID.MAX);
        var lowest_vector_id = yield this.engine.local_folder.get_earliest_id_async(
            this.cancellable
        );
        if (lowest_vector_id != null && lowest_vector_id.uid != null) {
            high_uid = lowest_vector_id.uid.previous(true);
            criteria.and(
                Imap.SearchCriterion.message_set(
                    new Imap.MessageSet.uid_range(
                        new Imap.UID(Imap.UID.MIN), high_uid
                    )
                )
            );
        }

        Gee.SortedSet<Imap.UID>? uids = yield remote.search_async(
            criteria, cancellable
        );
        Imap.UID low_uid = (
            uids != null && !uids.is_empty
            ? uids.first()
            : new Imap.UID(Imap.UID.MIN)
        );

        yield expand_on(
            new Imap.MessageSet.uid_range(low_uid, high_uid), remote
        );
    }

    private async void expand_on(Imap.MessageSet msg_set,
                                 Imap.FolderSession remote) throws GLib.Error {
        debug("Adding %s to vector", msg_set.to_string());

        Gee.List<Geary.Email>? list = yield remote.list_email_async(
            msg_set,
            this.required_fields,
            cancellable
        );
        var created_ids = new Gee.HashSet<EmailIdentifier>();
        if (list != null) {
            Gee.Map<Email, bool>? created_or_merged =
                yield this.engine.local_folder.create_or_merge_email_async(
                    list, this.engine.harvester, cancellable
                );

            foreach (Email email in created_or_merged.keys) {
                if (created_or_merged.get(email)) {
                    created_ids.add(email.id);
                }
            }

            if (!created_ids.is_empty) {
                this.engine.email_inserted(created_ids);
            }
        }

        debug("Vector expansion added %d new email", created_ids.size);
    }

    public override string describe_state() {
        return "to date %s, to count: %s".printf(
            this.target_date != null ? this.target_date.format_iso8601() : "(null)",
            this.target_count != null ? this.target_count.to_string() : "(null)"
        );
    }

}
