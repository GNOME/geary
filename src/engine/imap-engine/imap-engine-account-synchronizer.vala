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
            // 1. Are remote backed
            // 2. Can actually be opened (i.e. are selectable)
            //
            // This implies the folder must be a MinimalFolder and
            // we do require that for syncing at the moment anyway,
            // but keep the tests in for that one glorious day where
            // we can just use a generic folder.
            var imap_folder = folder as MinimalFolder;
            if (imap_folder != null &&
                imap_folder.remote_properties.is_openable.is_possible()) {

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


    internal FolderSync(GenericAccount account,
                        MinimalFolder folder,
                        GLib.DateTime sync_max_epoch) {
        base(account, folder);
        this.sync_max_epoch = sync_max_epoch;
    }

    public override async void execute(GLib.Cancellable cancellable)
        throws GLib.Error {
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

        try {
            yield sync_folder(actual_max_epoch, cancellable);
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            this.account.report_problem(
                new ServiceProblemReport(
                    this.account.information,
                    this.account.information.incoming,
                    err
                )
            );
        }
    }

    protected abstract async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error;

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
        base(account, folder, sync_max_epoch);
    }

    protected override async void sync_folder(GLib.DateTime max_epoch,
                                              GLib.Cancellable cancellable)
        throws GLib.Error {
        var remote = (RemoteFolder) this.folder as RemoteFolder;
        yield remote.synchronise(cancellable);
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
        var imap_folder = (MinimalFolder) this.folder;
        var local_folder = imap_folder.local_folder;

        // Detach older emails outside the prefetch window
        if (this.account.information.prefetch_period_days >= 0) {
            Gee.Collection<Geary.EmailIdentifier>? detached_ids =
                yield local_folder.detach_emails_before_timestamp(max_epoch,
                                                                  cancellable);
            if (detached_ids != null) {
                // Only notify for the folder here, GC should handle
                // notifying when deleted account-wide
                this.folder.email_removed(detached_ids);

                // Ensure a foreground GC is queued so any email now
                // folderless will be reaped
                var imap_account = (GenericAccount) this.account;
                imap_account.queue_operation(
                    new ForegroundGarbageCollection(imap_account)
                );
            }
        }

        Gee.List<Email> vector = yield this.folder.list_email_range_by_id(
            null, 1, PROPERTIES, OLDEST_TO_NEWEST, cancellable
        );
        var current_oldest = Collection.first(vector);

        GLib.DateTime? oldest_date = (current_oldest != null)
            ? current_oldest.properties.date_received : null;
        if (oldest_date == null) {
            oldest_date = new DateTime.now_local();
        }

        GLib.DateTime next_epoch = oldest_date;
        debug("XXX next: %s, oldest %s, cmp: %d",
              next_epoch.format_iso8601(),
              max_epoch.format_iso8601(),
              next_epoch.compare(max_epoch));
        while (true) {
            int local_count = yield local_folder.get_email_count_async(
                INCLUDE_MARKED_FOR_REMOVE, cancellable
            );

            next_epoch = next_epoch.add_months(-3);
            if (next_epoch.compare(max_epoch) < 0) {
                next_epoch = max_epoch;
            }

            if (local_count < imap_folder.remote_properties.email_total &&
                next_epoch.compare(max_epoch) > 0) {
                debug("Fetching to: %s", next_epoch.to_string());
                yield imap_folder.expand_vector(next_epoch, null, cancellable);
            } else {
                break;
            }

            // Wait for basic syncing (i.e. the prefetcher) to
            // complete as well.
            yield base.sync_folder(max_epoch, cancellable);
        }
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
        base(account, folder, sync_max_epoch);
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
                // Only notify for the folder here, GC should handle
                // notifying when deleted account-wide
                this.folder.email_removed(detached_ids);
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
