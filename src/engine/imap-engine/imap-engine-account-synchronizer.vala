/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {


    private weak GenericAccount account { get; private set; }

    private TimeoutManager prefetch_timer;
    private DateTime max_epoch = new DateTime(
        new TimeZone.local(), 2000, 1, 1, 0, 0, 0.0
    );


    public AccountSynchronizer(GenericAccount account) {
        this.account = account;
        this.prefetch_timer = new TimeoutManager.seconds(
            10, do_prefetch_changed
        );

        this.account.information.notify["prefetch-period-days"].connect(on_account_prefetch_changed);
        this.account.folders_available_unavailable.connect(on_folders_updated);
        this.account.folders_contents_altered.connect(on_folders_contents_altered);
    }

    private void send_all(Gee.Collection<Folder> folders, bool became_available) {
        foreach (Folder folder in folders) {
            MinimalFolder? imap_folder = folder as MinimalFolder;
            // only deal with ImapEngine.MinimalFolder
            if (imap_folder == null)
                continue;

            // if considering folder not because it's available (i.e. because its contents changed),
            // and the folder is open, don't process it; MinimalFolder will take care of changes as
            // they occur, in order to remain synchronized
            if (!became_available &&
                imap_folder.get_open_state() != Folder.OpenState.CLOSED) {
                continue;
            }

            AccountOperation op = became_available
                ? new CheckFolderSync(this.account, imap_folder, this.max_epoch)
                : new RefreshFolderSync(this.account, imap_folder);

            try {
                this.account.queue_operation(op);
            } catch (Error err) {
                debug("Failed to queue sync operation: %s", err.message);
            }
        }
    }

    private void do_prefetch_changed() {
        // treat as an availability check (i.e. as if the account had
        // just opened) because just because this value has changed
        // doesn't mean the contents in the folders have changed
        if (this.account.is_open()) {
            try {
                send_all(this.account.list_folders(), true);
            } catch (Error err) {
                debug("Failed to list account folders for sync: %s", err.message);
            }
        }
    }

    private void on_account_prefetch_changed() {
        this.prefetch_timer.start();
    }

    private void on_folders_updated(Gee.Collection<Folder>? available,
                                    Gee.Collection<Folder>? unavailable) {
        if (available != null) {
            send_all(available, true);
        }
    }

    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        send_all(altered, false);
    }

}

/**
 * Synchronises a folder after its contents have changed.
 *
 * This synchronisation process simply opens the remote folder, waits
 * for it to finish opening for normalisation and pre-fetching to
 * complete, then closes it again.
 */
private class Geary.ImapEngine.RefreshFolderSync : FolderOperation {


    internal RefreshFolderSync(GenericAccount account,
                               MinimalFolder folder) {
        base(account, folder);
    }

    public override async void execute(Cancellable cancellable)
        throws Error {
        bool opened = false;
        try {
            yield this.folder.open_async(Folder.OpenFlags.FAST_OPEN, cancellable);
            opened = true;
            yield this.folder.wait_for_remote_async(cancellable);
            yield sync_folder(cancellable);
        } finally {
            if (opened) {
                try {
                    // don't pass in the Cancellable; really need this
                    // to complete in all cases
                    yield this.folder.close_async();
                } catch (Error err) {
                    debug(
                        "%s: Error closing folder %s: %s",
                        this.account.to_string(),
                        this.folder.to_string(),
                        err.message
                    );
                }
            }
        }
    }

    protected virtual async void sync_folder(Cancellable cancellable)
        throws Error {
        yield wait_for_prefetcher(cancellable);
    }

    protected async void wait_for_prefetcher(Cancellable cancellable)
        throws Error {
        MinimalFolder minimal = (MinimalFolder) this.folder;
        try {
            yield minimal.email_prefetcher.active_sem.wait_async(cancellable);
        } catch (Error err) {
            Logging.debug(
                Logging.Flag.PERIODIC,
                "Error waiting for email prefetcher to complete %s: %s",
                folder.to_string(),
                err.message
            );
        }
    }

}

/**
 * Synchronises a folder after first checking if it needs to be sync'ed.
 *
 * This synchronisation process performs the same work as its base
 * class, but also ensures enough mail has been fetched to satisfy the
 * account's prefetch period, by checking the earliest mail in the
 * folder and if later than the maximum prefetch epoch, expands the
 * folder's vector until it does.
 */
private class Geary.ImapEngine.CheckFolderSync : RefreshFolderSync {


    private DateTime sync_max_epoch;


    internal CheckFolderSync(GenericAccount account,
                             MinimalFolder folder,
                             DateTime sync_max_epoch) {
        base(account, folder);
        this.sync_max_epoch = sync_max_epoch;
    }

    protected override async void sync_folder(Cancellable cancellable)
        throws Error {
        // Determine the earliest date we should be synchronising back to
        DateTime prefetch_max_epoch;
        if (this.account.information.prefetch_period_days >= 0) {
            prefetch_max_epoch = new DateTime.now_local();
            prefetch_max_epoch = prefetch_max_epoch.add_days(
                0 - account.information.prefetch_period_days
            );
        } else {
            prefetch_max_epoch = this.sync_max_epoch;
        }

        // get oldest local email and its time, as well as number
        // of messages in local store
        ImapDB.Folder local_folder = ((MinimalFolder) this.folder).local_folder;
        Gee.List<Geary.Email>? list = yield local_folder.list_email_by_id_async(
            null,
            1,
            Email.Field.PROPERTIES,
            ImapDB.Folder.ListFlags.NONE | ImapDB.Folder.ListFlags.OLDEST_TO_NEWEST,
            cancellable
        );

        Geary.Email? current_oldest = null;
        if (list != null && list.size > 0) {
            current_oldest = list[0];
        }

        DateTime? oldest_date = (current_oldest != null)
            ? current_oldest.properties.date_received : null;
        if (oldest_date == null) {
            oldest_date = new DateTime.now_local();
        }

        DateTime? next_epoch = oldest_date;
        while (next_epoch.compare(prefetch_max_epoch) > 0) {
            int local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.NONE, cancellable
            );

            next_epoch = next_epoch.add_months(-3);
            if (next_epoch.compare(prefetch_max_epoch) < 0) {
                next_epoch = prefetch_max_epoch;
            }

            debug("%s *** syncing to: %s", this.account.to_string(), next_epoch.to_string());

            if (local_count < this.folder.properties.email_total &&
                next_epoch.compare(prefetch_max_epoch) >= 0) {
                if (next_epoch.compare(this.sync_max_epoch) > 0) {
                    current_oldest = yield expand_vector(
                        next_epoch, current_oldest, cancellable
                    );
                    if (current_oldest == null &&
                        next_epoch.equal(prefetch_max_epoch)) {
                        yield expand_to_previous(
                            current_oldest, cancellable
                        );
                        // Exit next time around
                        next_epoch = prefetch_max_epoch.add_days(-1);
                    }
                } else {
                    yield expand_complete_vector(cancellable);
                    // Exit next time around
                    next_epoch = prefetch_max_epoch.add_days(-1);
                }
            } else {
                // Exit next time around
                next_epoch = prefetch_max_epoch.add_days(-1);
            }

            // let the prefetcher catch up
            yield wait_for_prefetcher(cancellable);
        }
    }

    private async Geary.Email? expand_vector(DateTime next_epoch,
                                             Geary.Email? current_oldest,
                                             Cancellable cancellable)
        throws Error {
        // Expand the vector up until the given epoch
        Logging.debug(
            Logging.Flag.PERIODIC,
            "Synchronizing %s:%s to %s",
            this.account.to_string(),
            this.folder.to_string(),
            next_epoch.to_string()
        );
        return yield ((MinimalFolder) this.folder).find_earliest_email_async(
            next_epoch,
            (current_oldest != null) ? current_oldest.id : null,
            cancellable
        );
    }

    private async void expand_to_previous(Geary.Email? current_oldest,
                                          Cancellable cancellable)
        throws Error {
        // there's nothing between the oldest local and the epoch,
        // which means the mail just prior to our local oldest is
        // oldest than the epoch; rather than continually thrashing
        // looking for something that's just out of reach, add it to
        // the folder and be done with it ... note that this even
        // works if id is null, as that means the local folder is
        // empty and so we should at least pull the first one to get a
        // marker of age
        Geary.EmailIdentifier? id =
            (current_oldest != null) ? current_oldest.id : null;
        Logging.debug(
            Logging.Flag.PERIODIC,
            "Unable to locate epoch messages on remote folder %s:%s%s, fetching one past oldest...",
            this.account.to_string(),
            this.folder.to_string(),
            (id != null) ? " earlier than oldest local" : ""
        );
        yield this.folder.list_email_by_id_async(
            id, 1,
            Geary.Email.Field.NONE,
            Geary.Folder.ListFlags.NONE, cancellable
        );
    }

    private async void expand_complete_vector(Cancellable cancellable)
        throws Error {
        // past max_epoch, so just pull in everything and be done with it
        Logging.debug(
            Logging.Flag.PERIODIC,
            "Synchronization reached max epoch of %s, fetching all mail from %s:%s",
            this.sync_max_epoch.to_string(),
            this.account.to_string(),
            this.folder.to_string()
        );

        // Per the contract for list_email_by_id_async, we need to
        // specify int.MAX count and ensure that
        // ListFlags.OLDEST_TO_NEWEST is *not* specified to get all
        // messages listed.
        //
        // XXX This is expensive, but should only usually happen once
        // per folder - at the end of a full sync.
        yield this.folder.list_email_by_id_async(
            null,
            int.MAX,
            Geary.Email.Field.NONE,
            Geary.Folder.ListFlags.NONE,
            cancellable
        );
    }

}
