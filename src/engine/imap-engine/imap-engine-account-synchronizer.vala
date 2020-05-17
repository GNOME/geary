/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer :
    Geary.BaseObject, Logging.Source {


    private weak GenericAccount account { get; private set; }

    private TimeoutManager prefetch_timer;
    private DateTime max_epoch = new DateTime(
        new TimeZone.local(), 2000, 1, 1, 0, 0, 0.0
    );
    private bool background_idle_gc_scheduled = false;


    public AccountSynchronizer(GenericAccount account) {
        this.account = account;
        this.prefetch_timer = new TimeoutManager.seconds(
            10, do_prefetch_changed
        );

        this.account.information.notify["prefetch-period-days"].connect(on_account_prefetch_changed);
        this.account.old_messages_background_cleanup_request.connect(old_messages_background_cleanup);
        this.account.folders_available_unavailable.connect(on_folders_updated);
        this.account.folders_contents_altered.connect(on_folders_contents_altered);
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

    private void send_all(Gee.Collection<Folder> folders,
                                            bool became_available,
                                            bool for_storage_clean=false,
                                            GarbageCollectPostIdleMessageDetach? post_idle_detach_op=null) {

        bool add_post_idle_detach_op = false;
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

                AccountOperation op;
                if (became_available || for_storage_clean) {
                    CheckFolderSync check_op = new CheckFolderSync(
                        this.account,
                        imap_folder,
                        this.max_epoch,
                        for_storage_clean,
                        post_idle_detach_op
                    );
                    op = check_op;
                    if (post_idle_detach_op != null) {
                        add_post_idle_detach_op = true;
                    }
                } else {
                    op = new RefreshFolderSync(this.account, imap_folder);
                }

                try {
                    this.account.queue_operation(op);
                } catch (Error err) {
                    warning("Failed to queue sync operation: %s", err.message);
                }
            }
        }

        // Add GC operation after message removal during background cleanup
        if (add_post_idle_detach_op) {
            try {
                this.account.queue_operation(post_idle_detach_op);
            } catch (Error err) {
                warning("Failed to queue sync operation: %s", err.message);
            }
        }
    }

    private void do_prefetch_changed() {
        // treat as an availability check (i.e. as if the account had
        // just opened) because just because this value has changed
        // doesn't mean the contents in the folders have changed
        if (this.account.is_open()) {
            send_all(this.account.list_folders(), true);
        }
    }

    private void old_messages_background_cleanup(GLib.Cancellable? cancellable) {

        if (this.account.is_open() && !this.background_idle_gc_scheduled) {
            this.background_idle_gc_scheduled = true;
            GarbageCollectPostIdleMessageDetach op =
                new GarbageCollectPostIdleMessageDetach(account);
            op.completed.connect(() => {
                this.background_idle_gc_scheduled = false;
            });
            cancellable.cancelled.connect(() => {
                this.background_idle_gc_scheduled = false;
            });
            send_all(this.account.list_folders(), false, true, op);
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


    GLib.Cancellable? closed_cancellable = null;


    internal RefreshFolderSync(GenericAccount account,
                               MinimalFolder folder) {
        base(account, folder);
        this.folder.closed.connect(on_folder_close);
    }

    ~RefreshFolderSync() {
        Geary.Folder? folder = this.folder;
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
            yield minimal.open_async(Folder.OpenFlags.NO_DELAY, cancellable);
            was_opened = true;
            debug("Synchronising");
            yield sync_folder(cancellable);
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

    protected virtual async void sync_folder(GLib.Cancellable cancellable)
        throws GLib.Error {
        yield this.folder.synchronise_remote(cancellable);
    }

    private void on_folder_close() {
        if (this.closed_cancellable != null) {
            this.closed_cancellable.cancel();
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
    private bool for_storage_clean;
    private GarbageCollectPostIdleMessageDetach? post_idle_detach_op;


    internal CheckFolderSync(GenericAccount account,
                             MinimalFolder folder,
                             DateTime sync_max_epoch,
                             bool for_storage_clean,
                             GarbageCollectPostIdleMessageDetach? post_idle_detach_op) {
        base(account, folder);
        this.sync_max_epoch = sync_max_epoch;
        this.for_storage_clean = for_storage_clean;
        this.post_idle_detach_op = post_idle_detach_op;
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

        ImapDB.Folder local_folder = ((MinimalFolder) this.folder).local_folder;

        // Detach older emails outside the prefetch window
        if (this.account.information.prefetch_period_days >= 0) {
            Gee.Collection<Geary.EmailIdentifier>? detached_ids =
                yield local_folder.detach_emails_before_timestamp(prefetch_max_epoch,
                                                                  cancellable);
            if (detached_ids != null) {
                this.folder.email_locally_removed(detached_ids);
                if (post_idle_detach_op != null) {
                    post_idle_detach_op.messages_detached();
                }

                if (!for_storage_clean) {
                    GenericAccount imap_account = (GenericAccount) account;
                    GarbageCollectPostMessageDetach op =
                        new GarbageCollectPostMessageDetach(imap_account);
                    try {
                        imap_account.queue_operation(op);
                    } catch (Error err) {
                        warning("Failed to queue sync operation: %s", err.message);
                    }
                }
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
        while (next_epoch.compare(prefetch_max_epoch) > 0) {
            int local_count = yield local_folder.get_email_count_async(
                ImapDB.Folder.ListFlags.NONE, cancellable
            );

            next_epoch = next_epoch.add_months(-3);
            if (next_epoch.compare(prefetch_max_epoch) < 0) {
                next_epoch = prefetch_max_epoch;
            }

            debug("Fetching to: %s", next_epoch.to_string());

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

            // Wait for basic syncing (i.e. the prefetcher) to
            // complete as well.
            yield base.sync_folder(cancellable);
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
 * Kicks off garbage collection after old messages have been removed.
 *
 * Queues a basic GC run which will run if old messages were detached
 * after a folder became available. Not used for backgrounded account
 * storage operations, which are handled instead by the
 * {@link GarbageCollectPostIdleMessageDetach}.
 */
private class Geary.ImapEngine.GarbageCollectPostMessageDetach: AccountOperation {

    internal GarbageCollectPostMessageDetach(GenericAccount account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws Error {
        if (cancellable.is_cancelled())
            return;

        // Run basic GC
        GenericAccount generic_account = (GenericAccount) account;
        Geary.ClientService services_to_pause[] = {};
        yield generic_account.local.db.run_gc(NONE, services_to_pause, cancellable);
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
private class Geary.ImapEngine.GarbageCollectPostIdleMessageDetach: AccountOperation {

    // Vacuum is allowed as we're running in the background
    private Geary.ImapDB.Database.GarbageCollectionOptions options = ALLOW_VACUUM;

    internal GarbageCollectPostIdleMessageDetach(GenericAccount account) {
        base(account);
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws Error {
        if (cancellable.is_cancelled())
            return;

        GenericAccount generic_account = (GenericAccount) this.account;
        generic_account.local.db.run_gc.begin(this.options,
                                              {generic_account.imap, generic_account.smtp},
                                              cancellable);
    }

    public void messages_detached() {
        // Reap is forced if messages were detached
        this.options |= FORCE_REAP;
    }
}
