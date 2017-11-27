/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {
    private const int FETCH_DATE_RECEIVED_CHUNK_COUNT = 25;
    private const int SYNC_DELAY_SEC = 10;
    private const int RETRY_SYNC_DELAY_SEC = 60;

    private weak GenericAccount account { get; private set; }
    private weak Imap.Account remote { get; private set; }

    private Nonblocking.Queue<MinimalFolder> bg_queue =
        new Nonblocking.Queue<MinimalFolder>.priority(bg_queue_comparator);
    private Gee.HashSet<MinimalFolder> made_available =
        new Gee.HashSet<MinimalFolder>();
    private Gee.HashSet<FolderPath> unavailable_paths =
        new Gee.HashSet<FolderPath>();
    private MinimalFolder? current_folder = null;
    private Cancellable? bg_cancellable = null;
    private DateTime max_epoch = new DateTime(new TimeZone.local(), 2000, 1, 1, 0, 0, 0.0);


    public AccountSynchronizer(GenericAccount account, Imap.Account remote) {
        this.account = account;
        this.remote = remote;

        // don't allow duplicates because it's possible for a Folder to change several times
        // before finally opened and synchronized, which we only want to do once
        this.bg_queue.allow_duplicates = false;
        this.bg_queue.requeue_duplicate = false;

        this.account.information.notify["prefetch-period-days"].connect(on_account_prefetch_changed);
        this.account.folders_available_unavailable.connect(on_folders_available_unavailable);
        this.account.folders_contents_altered.connect(on_folders_contents_altered);
        this.remote.ready.connect(on_account_ready);
    }

    public void stop() {
        Cancellable? cancellable = this.bg_cancellable;
        if (cancellable != null) {
            debug("%s: Stopping...", this.account.to_string());
            cancellable.cancel();

            this.bg_queue.clear();
            this.made_available.clear();
            this.unavailable_paths.clear();
            this.current_folder = null;
        }
    }

    private void on_account_prefetch_changed() {
        try {
            // treat as an availability check (i.e. as if the account had just opened) because
            // just because this value has changed doesn't mean the contents in the folders
            // have changed
            if (this.account.is_open()) {
                delayed_send_all(account.list_folders(), true, SYNC_DELAY_SEC);
            }
        } catch (Error err) {
            debug("Unable to schedule re-sync for %s due to prefetch time changing: %s",
                account.to_string(), err.message);
        }
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Folder>? available,
                                                  Gee.Collection<Folder>? unavailable) {
        if (available != null) {
            foreach (Folder folder in available)
                unavailable_paths.remove(folder.path);
            
            delayed_send_all(available, true, SYNC_DELAY_SEC);
        }
        
        if (unavailable != null) {
            foreach (Folder folder in unavailable)
                unavailable_paths.add(folder.path);
            
            revoke_all(unavailable);
        }
    }
    
    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        delayed_send_all(altered, false, SYNC_DELAY_SEC);
    }

    private void delayed_send_all(Gee.Collection<Folder> folders, bool reason_available, int sec) {
        Timeout.add_seconds(sec, () => {
            // remove any unavailable folders
            Gee.ArrayList<Folder> trimmed_folders = new Gee.ArrayList<Folder>();
            foreach (Folder folder in folders) {
                if (!unavailable_paths.contains(folder.path))
                    trimmed_folders.add(folder);
            }
            
            send_all(trimmed_folders, reason_available);
            
            return false;
        });
    }
    
    private void send_all(Gee.Collection<Folder> folders, bool reason_available) {
        foreach (Folder folder in folders) {
            MinimalFolder? imap_folder = folder as MinimalFolder;
            
            // only deal with ImapEngine.MinimalFolder
            if (imap_folder == null)
                continue;
            
            // if considering folder not because it's available (i.e. because its contents changed),
            // and the folder is open, don't process it; MinimalFolder will take care of changes as
            // they occur, in order to remain synchronized
            if (!reason_available &&
                imap_folder.get_open_state() != Folder.OpenState.CLOSED) {
                continue;
            }

            // don't requeue the currently processing folder
            if (imap_folder != current_folder)
                bg_queue.send(imap_folder);
            
            // If adding because now available, make sure it's flagged as such, since there's an
            // additional check for available folders ... if not, remove from the map so it's
            // not treated as such, in case both of these come in back-to-back
            if (reason_available && imap_folder != current_folder)
                made_available.add(imap_folder);
            else
                made_available.remove(imap_folder);
        }
    }
    
    private void revoke_all(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            MinimalFolder? generic_folder = folder as MinimalFolder;
            if (generic_folder != null) {
                bg_queue.revoke(generic_folder);
                made_available.remove(generic_folder);
            }
        }
    }
    
    // This is used to ensure that certain special folders get prioritized over others, so folders
    // important to the user (i.e. Inbox) go first while less-used folders (Spam) are fetched last
    private static int bg_queue_comparator(MinimalFolder a, MinimalFolder b) {
        if (a == b)
            return 0;
        
        int cmp = score_folder(a) - score_folder(b);
        if (cmp != 0)
            return cmp;
        
        // sort by path to stabilize the sort
        return a.path.compare_to(b.path);
    }
    
    // Lower the score, the higher the importance.
    //
    // Some explanation is due here.  It may seem odd to place TRASH, SENT, and DRAFTS so high, but
    // there's a method to the madness.  In particular, because Geary can produce a lot of drafts
    // during composition, it's important to synchronize with Trash so discarded drafts don't wind
    // up included in conversations until, eventually, the Trash is synchronized.  (Recall that
    // Spam and Trash are blacklisted in conversations and searching.)  Since Drafts is open while
    // writing them, it's not vital to keep it absolutely high, but Trash is usually not open,
    // so it should be.
    //
    // All Mail is important, but synchronizing with it can be hard on the system because of the
    // sheer amount of messages, and so it's placed lower to put it off until the more active
    // folders are finished.
    private static int score_folder(Folder a) {
        switch (a.special_folder_type) {
            case SpecialFolderType.INBOX:
                return -70;
            
            case SpecialFolderType.TRASH:
                return -60;
            
            case SpecialFolderType.SENT:
                return -50;
            
            case SpecialFolderType.DRAFTS:
                return -40;
            
            case SpecialFolderType.FLAGGED:
                return -30;
            
            case SpecialFolderType.IMPORTANT:
                return -20;
            
            case SpecialFolderType.ALL_MAIL:
            case SpecialFolderType.ARCHIVE:
                return -10;
            
            case SpecialFolderType.SPAM:
                return 10;
            
            default:
                return 0;
        }
    }
    
    private async void process_queue_async() {
        if (this.bg_cancellable != null) {
            return;
        }
        Cancellable cancellable = this.bg_cancellable = new Cancellable();

        debug("%s: Starting background sync", this.account.to_string());

        while (!cancellable.is_cancelled()) {
            MinimalFolder folder;
            try {
                folder = yield bg_queue.receive(bg_cancellable);
            } catch (Error err) {
                if (!(err is IOError.CANCELLED))
                    debug("Failed to receive next folder for background sync: %s", err.message);
                break;
            }

            // generate the current epoch for synchronization (could cache this value, obviously, but
            // doesn't seem like this biggest win in this class)
            DateTime epoch;
            if (account.information.prefetch_period_days >= 0) {
                epoch = new DateTime.now_local();
                epoch = epoch.add_days(0 - account.information.prefetch_period_days);
            } else {
                epoch = max_epoch;
            }

            bool availability_check = false;
            try {
                // mark as current folder to prevent requeues while processing
                this.current_folder = folder;
                availability_check = this.made_available.remove(folder);
                yield process_folder_async(folder, availability_check, epoch, cancellable);
            } catch (Error err) {
                // retry the folder later
                delayed_send_all(
                    iterate<Folder>(folder).to_array_list(),
                    availability_check,
                    RETRY_SYNC_DELAY_SEC
                );
                if (!(err is IOError.CANCELLED)) {
                    debug("%s: Error synchronising %s: %s",
                          this.account.to_string(), folder.to_string(), err.message);
                }
                break;
            } finally {
                this.current_folder = null;
            }
        }

        this.bg_cancellable = null;
    }

    // Returns false if IOError.CANCELLED received
    private async void process_folder_async(MinimalFolder folder,
                                            bool availability_check,
                                            DateTime epoch,
                                            Cancellable cancellable)
        throws Error {
        Logging.debug(
            Logging.Flag.PERIODIC,
            "Background sync'ing %s to %s",
            folder.to_string(),
            epoch.to_string()
        );

        // If we aren't checking the folder because it became
        // available, then it has changed and we need to check it.
        // Otherwise compare the oldest mail in the local store and
        // see if it is before the epoch; if so, no need to
        // synchronize simply because this Folder is available; wait
        // for its contents to change instead.
        //
        // Note we can't compare the local and remote folder counts
        // here, since the folder may not have opened yet to determine
        // what the actual remote count is, which is particularly
        // problematic when an existing folder is seen for the first
        // time, e.g. when the account was just added.

        DateTime? oldest_local = null;
        Geary.EmailIdentifier? oldest_local_id = null;
        bool do_sync = true;

        if (!availability_check) {
            // Folder already available, so it must have changed
            Logging.debug(
                Logging.Flag.PERIODIC,
                "Folder %s changed, synchronizing...",
                folder.to_string()
            );
        } else {
            // get oldest local email and its time, as well as number
            // of messages in local store
            Gee.List<Geary.Email>? list =yield folder.local_folder.list_email_by_id_async(
                null,
                1,
                Email.Field.PROPERTIES,
                ImapDB.Folder.ListFlags.NONE | ImapDB.Folder.ListFlags.OLDEST_TO_NEWEST,
                cancellable
            );
            if (list != null && list.size > 0) {
                oldest_local = list[0].properties.date_received;
                oldest_local_id = list[0].id;
            }

            if (oldest_local == null) {
                // No oldest message found, so we haven't seen the folder
                // before or it has no messages. Either way we need to
                // open it to check, so sync it.
                Logging.debug(
                    Logging.Flag.PERIODIC,
                    "No oldest message found for %s, synchronizing...",
                    folder.to_string()
                );
            } else if (oldest_local.compare(epoch) < 0) {
                // Oldest local email before epoch, don't sync from network
                do_sync = false;
                Logging.debug(
                    Logging.Flag.PERIODIC,
                    "Oldest local message is older than the epoch for %s",
                    folder.to_string()
                );
            }
        }

        if (do_sync) {
            bool opened = false;
            try {
                yield folder.open_async(Folder.OpenFlags.FAST_OPEN, cancellable);
                opened = true;
                yield sync_folder_async(folder, epoch, oldest_local, oldest_local_id, cancellable);
            } finally {
                if (opened) {
                    try {
                        // don't pass Cancellable; really need this to complete in all cases
                        yield folder.close_async();
                    } catch (Error err) {
                        debug("%s: Error closing folder %s: %s",
                              this.account.to_string(), folder.to_string(), err.message);
                    }
                }
            }
        }
        Logging.debug(
            Logging.Flag.PERIODIC, "Background sync of %s completed",
            folder.to_string()
        );
    }

    private async void sync_folder_async(MinimalFolder folder,
                                         DateTime epoch,
                                         DateTime? oldest_local,
                                         Geary.EmailIdentifier? oldest_local_id,
                                         Cancellable cancellable)
        throws Error {

        // wait for the folder to be fully opened to be sure we have all the most current
        // information
        yield folder.wait_for_open_async(cancellable);
        
        // only perform vector expansion if oldest isn't old enough
        if (oldest_local == null || oldest_local.compare(epoch) > 0) {
            // go back three months at a time to the epoch, performing a little vector expansion at a
            // time rather than all at once (which will stall the replay queue)
            DateTime current_epoch = (oldest_local != null) ? oldest_local : new DateTime.now_local();
            do {
                // look for complete synchronization of UIDs (i.e. complete vector normalization)
                // no need to keep searching once this happens
                int local_count = yield folder.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                    cancellable);
                int remote_count = folder.properties.email_total;
                if (local_count >= remote_count) {
                    Logging.debug(
                        Logging.Flag.PERIODIC,
                        "Final vector normalization for %s: %d/%d emails",
                        folder.to_string(),
                        local_count,
                        remote_count
                    );
                    break;
                }
                
                current_epoch = current_epoch.add_months(-3);
                
                // if past max_epoch, then just pull in everything and be done with it
                if (current_epoch.compare(max_epoch) < 0) {
                    Logging.debug(
                        Logging.Flag.PERIODIC,
                        "Synchronization reached max epoch of %s, fetching all mail from %s (already got %d of %d emails)",
                        max_epoch.to_string(),
                        folder.to_string(),
                        local_count,
                        remote_count
                    );

                    // Per the contract for list_email_by_id_async, we
                    // need to specify int.MAX count and ensure that
                    // ListFlags.OLDEST_TO_NEWEST is *not* specified
                    // to get all messages listed.
                    //
                    // XXX This is expensive, but should only usually
                    // happen once per folder - at the end of a full
                    // sync.
                    yield folder.list_email_by_id_async(
                        null,
                        int.MAX,
                        Geary.Email.Field.NONE,
                        Geary.Folder.ListFlags.NONE,
                        cancellable
                    );
                } else {
                    // don't go past proscribed epoch
                    if (current_epoch.compare(epoch) < 0)
                        current_epoch = epoch;

                    Logging.debug(
                        Logging.Flag.PERIODIC,
                        "Synchronizing %s to %s (already got %d of %d emails)",
                        folder.to_string(),
                        current_epoch.to_string(),
                        local_count,
                        remote_count
                    );
                    Geary.EmailIdentifier? earliest_span_id = yield folder.find_earliest_email_async(current_epoch,
                        oldest_local_id, cancellable);
                    if (earliest_span_id == null && current_epoch.compare(epoch) <= 0) {
                        Logging.debug(
                            Logging.Flag.PERIODIC,
                            "Unable to locate epoch messages on remote folder %s%s, fetching one past oldest...",
                            folder.to_string(),
                            (oldest_local_id != null) ? " earlier than oldest local" : ""
                        );

                        // if there's nothing between the oldest local and the epoch, that means the
                        // mail just prior to our local oldest is oldest than the epoch; rather than
                        // continually thrashing looking for something that's just out of reach, add it
                        // to the folder and be done with it ... note that this even works if oldest_local_id
                        // is null, as that means the local folder is empty and so we should at least
                        // pull the first one to get a marker of age
                        yield folder.list_email_by_id_async(oldest_local_id, 1, Geary.Email.Field.NONE,
                            Geary.Folder.ListFlags.NONE, cancellable);
                    } else if (earliest_span_id != null) {
                        // use earliest email from that span for the next round
                        oldest_local_id = earliest_span_id;
                    }
                }
                
                yield Scheduler.sleep_ms_async(200);
            } while (current_epoch.compare(epoch) > 0);
        } else {
            Logging.debug(
                Logging.Flag.PERIODIC,
                "No expansion necessary for %s, oldest local (%s) is before epoch (%s)",
                folder.to_string(),
                oldest_local.to_string(),
                epoch.to_string()
            );
        }

        // always give email prefetcher time to finish its work
        Logging.debug(
            Logging.Flag.PERIODIC,
            "Waiting for email prefetcher to complete %s...",
            folder.to_string()
        );
        try {
            yield folder.email_prefetcher.active_sem.wait_async(cancellable);
        } catch (Error err) {
            Logging.debug(
                Logging.Flag.PERIODIC,
                "Error waiting for email prefetcher to complete %s: %s",
                folder.to_string(),
                err.message
            );
        }

        Logging.debug(
            Logging.Flag.PERIODIC,
            "Done background sync'ing %s",
            folder.to_string()
        );
    }

    private void on_account_ready() {
        this.process_queue_async.begin();
    }

}
