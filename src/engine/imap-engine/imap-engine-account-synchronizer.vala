/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2017-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer :
    Geary.BaseObject, Logging.Source {


    private enum Reason {

        REFRESH_CONTENTS,
        FULL_SYNC,
        TRUNCATE_TO_EPOCH;

    }


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
        this.account.folders_available_unavailable.connect(on_folders_discovered);
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent {
        get { return this.account; }
    }

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%s, %s",
            this.account.information.id,
            this.max_epoch.to_string()
        );
    }

    internal void folders_discovered(Gee.Collection<Folder> available) {
        if (this.account.imap.current_status == CONNECTED) {
            send_all(available, FULL_SYNC);
        }
    }

    internal void folders_contents_altered(Gee.Collection<Folder> altered) {
        if (this.account.imap.current_status == CONNECTED) {
            send_all(altered, REFRESH_CONTENTS);
        }
    }

    internal void cleanup_storage() {
        IdleGarbageCollection op = new IdleGarbageCollection(this.account);

        send_all(this.account.list_folders(), TRUNCATE_TO_EPOCH, op);

        // Add GC operation after message removal during background cleanup
        try {
            this.account.queue_operation(op);
        } catch (Error err) {
                warning("Failed to queue sync operation: %s", err.message);
        }
    }

    private void send_all(Gee.Collection<Folder> folders,
                          Reason reason,
                          IdleGarbageCollection? post_idle_detach_op = null) {

        foreach (Folder folder in folders) {
            // Only sync folders that:
            // 1. Can actually be opened (i.e. are selectable)
            // 2. Are remote backed
            //
            // All this implies the folder must be a MinimalFolder and
            // we do require that for syncing at the moment anyway,
            // but keep the tests in for that one glorious day where
            // we can just use a generic folder.
            MinimalFolder? imap_folder = folder as MinimalFolder;
            if (imap_folder != null &&
                folder.properties.is_openable.is_possible() &&
                !folder.properties.is_local_only &&
                !folder.properties.is_virtual) {

                AccountOperation? op = null;
                switch (reason) {
                case REFRESH_CONTENTS:
                    op = new RefreshFolderSync(
                        this.account,
                        imap_folder,
                        this.max_epoch
                    );
                    break;

                case FULL_SYNC:
                    op = new FullFolderSync(
                        this.account,
                        imap_folder,
                        this.max_epoch
                    );
                    break;

                case TRUNCATE_TO_EPOCH:
                    op = new TruncateToEpochFolderSync(
                        this.account,
                        imap_folder,
                        this.max_epoch,
                        post_idle_detach_op
                    );
                    break;
                }

                try {
                    this.account.queue_operation(op);
                } catch (GLib.Error err) {
                    warning("Failed to queue sync operation: %s", err.message);
                }
            }
        }
    }

    private void do_prefetch_changed() {
        if (this.account.is_open() &&
            this.account.imap.current_status == CONNECTED) {
            send_all(this.account.list_folders(), FULL_SYNC);
        }
    }

    private void on_account_prefetch_changed() {
        this.prefetch_timer.start();
    }

    private void on_folders_discovered(Gee.Collection<Folder>? available,
                                       Gee.Collection<Folder>? unavailable) {
        if (available != null) {
            folders_discovered(available);
        }
    }

}


/**
 * Base class for folder synchronisation account operations.
 */
private abstract class Geary.ImapEngine.FolderSync : FolderOperation {


    protected GLib.DateTime sync_max_epoch { get; private set; }

    private Folder.OpenFlags open_flags;
    private GLib.Cancellable? closed_cancellable = null;


    internal FolderSync(GenericAccount account,
                        MinimalFolder folder,
                        GLib.DateTime sync_max_epoch,
                        Folder.OpenFlags open_flags) {
        base(account, folder);
        this.sync_max_epoch = sync_max_epoch;
        this.open_flags = open_flags;
        this.folder.closed.connect(on_folder_close);
    }

    ~FolderSync() {
        weak Geary.Folder? folder = this.folder;
        if (folder != null) {
            this.folder.closed.disconnect(on_folder_close);
        }
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws GLib.Error {
        // Stash the cancellable so the op can cancel the sync if the
        // folder closes.
        this.closed_cancellable = cancellable;

        bool was_opened = false;
        MinimalFolder minimal = (MinimalFolder) this.folder;
        try {
            yield minimal.open_async(this.open_flags, cancellable);
            was_opened = true;

            debug("Synchronising");
            // Determine the earliest date we should be synchronising
            // back to
            DateTime actual_max_epoch;
            if (this.account.information.prefetch_period_days >= 0) {
                actual_max_epoch = new DateTime.now_local();
                actual_max_epoch = actual_max_epoch.add_days(
                    0 - account.information.prefetch_period_days
                );
            } else {
                actual_max_epoch = this.sync_max_epoch;
            }

            yield sync_folder(actual_max_epoch, cancellable);
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (EngineError.ALREADY_CLOSED err) {
            // Failed to open the folder, which could be because the
            // network went away, or because the remote folder went
            // away. Either way don't bother reporting it.
            debug(
                "Folder failed to open %s: %s",
                minimal.to_string(),
                err.message
            );
        } catch (GLib.Error err) {
            this.account.report_problem(
                new ServiceProblemReport(
                    this.account.information,
                    this.account.information.incoming,
                    err
                )
            );
        }

        // Clear this now so that the wait for close below doesn't get
        // cancelled as the folder closes.
        this.closed_cancellable = null;

        if (was_opened) {
            try {
                // don't pass in the Cancellable; really need this
                // to complete in all cases
                if (yield this.folder.close_async(null)) {
                    // The folder was actually closing, so wait
                    // for it here to completely close so that its
                    // session has a chance to exit IMAP Selected
                    // state when released, allowing the next sync
                    // op to reuse the same session. Here we
                    // definitely want to use the cancellable so
                    // the wait can be interrupted.
                    yield this.folder.wait_for_close_async(cancellable);
                }
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

    protected abstract async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error;

    private void on_folder_close() {
        if (this.closed_cancellable != null) {
            this.closed_cancellable.cancel();
        }
    }

}


/**
 * Refreshes a folder's contents after they have changed.
 *
 * This synchronisation process simply opens the remote folder, waits
 * for it to finish opening for normalisation and pre-fetching to
 * complete, then closes it again.
 */
private class Geary.ImapEngine.RefreshFolderSync : FolderSync {


    internal RefreshFolderSync(GenericAccount account,
                               MinimalFolder folder,
                               GLib.DateTime sync_max_epoch) {
        base(account, folder, sync_max_epoch, NO_DELAY);
    }

    protected override async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error {
        yield this.folder.synchronise_remote(cancellable);
    }

}

/**
 * Refreshes folder contents and ensures its vector extends to the epoch.
 *
 * This synchronisation process performs the same work as its base
 * class, but also ensures enough mail has been fetched to satisfy the
 * account's prefetch period, by checking the earliest mail in the
 * folder and if later than the maximum prefetch epoch, expands the
 * folder's vector until it does.
 *
 * It also truncates email that extends past the epoch, ensuring no
 * more email is stored than is desired.
 */
private class Geary.ImapEngine.FullFolderSync : RefreshFolderSync {



    internal FullFolderSync(GenericAccount account,
                            MinimalFolder folder,
                            DateTime sync_max_epoch) {
        base(account, folder, sync_max_epoch);
    }

    protected override async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error {
        ImapDB.Folder local_folder = ((MinimalFolder) this.folder).local_folder;

        // Detach older emails outside the prefetch window
        if (this.account.information.prefetch_period_days >= 0) {
            Gee.Collection<Geary.EmailIdentifier>? detached_ids =
                yield local_folder.detach_emails_before_timestamp(max_epoch,
                                                                  cancellable);
            if (detached_ids != null) {
                this.account.email_locally_removed(this.folder, detached_ids);
                this.folder.email_locally_removed(detached_ids);

                // Ensure a foreground GC is queued so any email now
                // folderless will be reaped
                var imap_account = (GenericAccount) this.account;
                imap_account.queue_operation(
                    new ForegroundGarbageCollection(imap_account)
                );
            }
        }

        // get oldest local email and its time, as well as number
        // of messages in local store
        Gee.List<Geary.Email>? list = yield local_folder.list_email_by_id_async(
            null,
            1,
            Email.Field.PROPERTIES,
            ImapDB.Folder.ListFlags.OLDEST_TO_NEWEST,
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
        while (next_epoch.compare(max_epoch) > 0) {
            int local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.NONE, cancellable
            );

            next_epoch = next_epoch.add_months(-3);
            if (next_epoch.compare(max_epoch) < 0) {
                next_epoch = max_epoch;
            }

            debug("Fetching to: %s", next_epoch.to_string());

            if (local_count < this.folder.properties.email_total &&
                next_epoch.compare(max_epoch) >= 0) {
                if (next_epoch.compare(this.sync_max_epoch) > 0) {
                    current_oldest = yield expand_vector(
                        next_epoch, current_oldest, cancellable
                    );
                    if (current_oldest == null &&
                        next_epoch.equal(max_epoch)) {
                        yield expand_to_previous(
                            current_oldest, cancellable
                        );
                        // Exit next time around
                        next_epoch = max_epoch.add_days(-1);
                    }
                } else {
                    yield expand_complete_vector(cancellable);
                    // Exit next time around
                    next_epoch = max_epoch.add_days(-1);
                }
            } else {
                // Exit next time around
                next_epoch = max_epoch.add_days(-1);
            }

            // Wait for basic syncing (i.e. the prefetcher) to
            // complete as well.
            yield base.sync_folder(max_epoch, cancellable);
        }
    }

    private async Geary.Email? expand_vector(DateTime next_epoch,
                                             Geary.Email? current_oldest,
                                             Cancellable cancellable)
        throws Error {
        debug("Expanding vector to %s", next_epoch.to_string());
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
        debug(
            "Unable to locate epoch messages on remote folder%s, fetching one past oldest...",
            (id != null) ? " earlier than oldest local" : ""
        );
        yield this.folder.list_email_by_id_async(
            id,
            1,
            Geary.Email.Field.NONE,
            Geary.Folder.ListFlags.NONE,
            cancellable
        );
    }

    private async void expand_complete_vector(Cancellable cancellable)
        throws Error {
        // past max_epoch, so just pull in everything and be done with it
        debug(
            "Reached max epoch of %s, fetching all mail",
            this.sync_max_epoch.to_string()
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


/**
 * Removes any email locally from folder that extends past the epoch.
 *
 * This synchronisation operation ensures that the folder's vector
 * does not extend pass the epoch, ensuring no more email is stored
 * than is desired.
 */
private class Geary.ImapEngine.TruncateToEpochFolderSync : FolderSync {


    private IdleGarbageCollection? post_idle_detach_op;


    internal TruncateToEpochFolderSync(GenericAccount account,
                                       MinimalFolder folder,
                                       DateTime sync_max_epoch,
                                       IdleGarbageCollection? post_idle_detach_op) {
        base(account, folder, sync_max_epoch, NONE);
        this.post_idle_detach_op = post_idle_detach_op;
    }

    protected override async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error {
        ImapDB.Folder local_folder = ((MinimalFolder) this.folder).local_folder;

        // Detach older emails outside the prefetch window
        if (this.account.information.prefetch_period_days >= 0) {
            Gee.Collection<Geary.EmailIdentifier>? detached_ids =
                yield local_folder.detach_emails_before_timestamp(max_epoch,
                                                                  cancellable);
            if (detached_ids != null) {
                this.account.email_locally_removed(this.folder, detached_ids);
                this.folder.email_locally_removed(detached_ids);
                this.post_idle_detach_op.messages_detached();
            }
        }
    }

}


/**
 * Kicks off garbage collection after old messages have been removed.
 *
 * Queues a basic GC run which will run if old messages were detached
 * after a folder became available. Not used for backgrounded account
 * storage operations, which are handled instead by the
 * {@link IdleGarbageCollection}.
 */
private class Geary.ImapEngine.ForegroundGarbageCollection: AccountOperation {

    internal ForegroundGarbageCollection(GenericAccount account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws Error {
        if (cancellable.is_cancelled())
            return;

        // Run basic GC
        GenericAccount generic_account = (GenericAccount) account;
        yield generic_account.local.db.run_gc(NONE, null, cancellable);
    }

    public override bool equal_to(AccountOperation op) {
        return (op != null
                && (this == op || this.get_type() == op.get_type())
                && this.account == op.account);
    }

}

/**
 * Performs garbage collection after old messages have been removed during
 * backgrounded idle cleanup.
 *
 * Queues a GC run after a cleanup of messages has occurred while the
 * app is idle in the background. Vacuuming will be permitted and if
 * messages have been removed a reap will be forced.
 */
private class Geary.ImapEngine.IdleGarbageCollection: AccountOperation {

    // Vacuum is allowed as we're running in the background
    private Geary.ImapDB.Database.GarbageCollectionOptions options = ALLOW_VACUUM;

    internal IdleGarbageCollection(GenericAccount account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws Error {
        if (cancellable.is_cancelled())
            return;

        GenericAccount generic_account = (GenericAccount) this.account;
        generic_account.local.db.run_gc.begin(
            this.options,
            new Gee.ArrayList<ClientService>.wrap(
                {generic_account.imap, generic_account.smtp}
            ),
            cancellable
        );
    }

    public void messages_detached() {
        // Reap is forced if messages were detached
        this.options |= FORCE_REAP;
    }

}
