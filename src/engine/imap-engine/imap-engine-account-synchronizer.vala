/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {
    private const int FETCH_DATE_RECEIVED_CHUNK_COUNT = 25;
    private const int SYNC_DELAY_SEC = 15;
    
    public GenericAccount account { get; private set; }
    
    private Nonblocking.Mailbox<GenericFolder> bg_queue = new Nonblocking.Mailbox<GenericFolder>(bg_queue_comparator);
    private Gee.HashSet<GenericFolder> made_available = new Gee.HashSet<GenericFolder>();
    private GenericFolder? current_folder = null;
    private Cancellable? bg_cancellable = null;
    private Nonblocking.Semaphore stopped = new Nonblocking.Semaphore();
    private Gee.HashSet<FolderPath> unavailable_paths = new Gee.HashSet<FolderPath>();
    
    public AccountSynchronizer(GenericAccount account) {
        this.account = account;
        
        // don't allow duplicates because it's possible for a Folder to change several times
        // before finally opened and synchronized, which we only want to do once
        bg_queue.allow_duplicates = false;
        bg_queue.requeue_duplicate = false;
        
        account.opened.connect(on_account_opened);
        account.closed.connect(on_account_closed);
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.folders_contents_altered.connect(on_folders_contents_altered);
    }
    
    ~AccountSynchronizer() {
        account.opened.disconnect(on_account_opened);
        account.closed.disconnect(on_account_closed);
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.folders_contents_altered.disconnect(on_folders_contents_altered);
    }
    
    public async void stop_async() {
        bg_cancellable.cancel();
        
        try {
            yield stopped.wait_async();
        } catch (Error err) {
            debug("Error waiting for AccountSynchronizer background task for %s to complete: %s",
                account.to_string(), err.message);
        }
    }
    
    private void on_account_opened() {
        if (stopped.is_passed())
            return;
        
        account.information.notify["prefetch-period-days"].connect(on_account_prefetch_changed);
        
        bg_queue.allow_duplicates = false;
        bg_queue.requeue_duplicate = false;
        bg_cancellable = new Cancellable();
        unavailable_paths.clear();
        
        // immediately start processing folders as they are announced as available
        process_queue_async.begin();
    }
    
    private void on_account_closed() {
        account.information.notify["prefetch-period-days"].disconnect(on_account_prefetch_changed);
        
        bg_cancellable.cancel();
        bg_queue.clear();
        unavailable_paths.clear();
    }
    
    private void on_account_prefetch_changed() {
        try {
            // treat as an availability check (i.e. as if the account had just opened) because
            // just because this value has changed doesn't mean the contents in the folders
            // have changed
            delayed_send_all(account.list_folders(), true);
        } catch (Error err) {
            debug("Unable to schedule re-sync for %s due to prefetch time changing: %s",
                account.to_string(), err.message);
        }
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Folder>? available,
        Gee.Collection<Folder>? unavailable) {
        if (stopped.is_passed())
            return;
        
        if (available != null) {
            foreach (Folder folder in available)
                unavailable_paths.remove(folder.path);
            
            delayed_send_all(available, true);
        }
        
        if (unavailable != null) {
            foreach (Folder folder in unavailable)
                unavailable_paths.add(folder.path);
            
            revoke_all(unavailable);
        }
    }
    
    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        delayed_send_all(altered, false);
    }
    
    private void delayed_send_all(Gee.Collection<Folder> folders, bool reason_available) {
        Timeout.add_seconds(SYNC_DELAY_SEC, () => {
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
            GenericFolder? generic_folder = folder as GenericFolder;
            
            // only deal with ImapEngine.GenericFolders
            if (generic_folder == null)
                continue;
            
            // don't requeue the currently processing folder
            if (generic_folder != current_folder)
                bg_queue.send(generic_folder);
            
            // If adding because now available, make sure it's flagged as such, since there's an
            // additional check for available folders ... if not, remove from the map so it's
            // not treated as such, in case both of these come in back-to-back
            if (reason_available && generic_folder != current_folder)
                made_available.add(generic_folder);
            else
                made_available.remove(generic_folder);
        }
    }
    
    private void revoke_all(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            GenericFolder? generic_folder = folder as GenericFolder;
            if (generic_folder != null) {
                bg_queue.revoke(generic_folder);
                made_available.remove(generic_folder);
            }
        }
    }
    
    // This is used to ensure that certain special folders get prioritized over others, so folders
    // important to the user (i.e. Inbox) and folders handy for pulling all mail (i.e. All Mail) go
    // first while less-used folders (Trash, Spam) are fetched last
    private static int bg_queue_comparator(GenericFolder a, GenericFolder b) {
        if (a == b)
            return 0;
        
        int cmp = score_folder(a) - score_folder(b);
        if (cmp != 0)
            return cmp;
        
        // sort by path to stabilize the sort
        return a.path.compare_to(b.path);
    }
    
    // Lower the score, the higher the importance.
    private static int score_folder(Folder a) {
        switch (a.special_folder_type) {
            case SpecialFolderType.INBOX:
                return -60;
            
            case SpecialFolderType.ALL_MAIL:
                return -50;
            
            case SpecialFolderType.SENT:
                return -40;
            
            case SpecialFolderType.FLAGGED:
                return -30;
            
            case SpecialFolderType.IMPORTANT:
                return -20;
            
            case SpecialFolderType.DRAFTS:
                return -10;
            
            case SpecialFolderType.SPAM:
                return 10;
            
            case SpecialFolderType.TRASH:
                return 20;
            
            default:
                return 0;
        }
    }
    
    private async void process_queue_async() {
        for (;;) {
            GenericFolder folder;
            try {
                folder = yield bg_queue.recv_async(bg_cancellable);
            } catch (Error err) {
                if (!(err is IOError.CANCELLED))
                    debug("Failed to receive next folder for background sync: %s", err.message);
                
                break;
            }
            
            // mark as current folder to prevent requeues while processing
            current_folder = folder;
            
            // generate the current epoch for synchronization (could cache this value, obviously, but
            // doesn't seem like this biggest win in this class)
            DateTime epoch;
            if (account.information.prefetch_period_days >= 0) {
                epoch = new DateTime.now_local();
                epoch = epoch.add_days(0 - account.information.prefetch_period_days);
            } else {
                epoch = new DateTime(new TimeZone.local(), 1, 1, 1, 0, 0, 0.0);
            }
            
            bool ok = yield process_folder_async(folder, made_available.remove(folder), epoch);
            
            // clear current folder in every event
            current_folder = null;
            
            if (!ok)
                break;
        }
        
        // clear queue of any remaining folders so references aren't held
        bg_queue.clear();
        
        // same with made_available table
        made_available.clear();
        
        // flag as stopped for any waiting tasks
        stopped.blind_notify();
    }
    
    // Returns false if IOError.CANCELLED received
    private async bool process_folder_async(GenericFolder folder, bool availability_check, DateTime epoch) {
        // get oldest local email and its time, as well as number of messages in local store
        DateTime? oldest_local = null;
        Geary.EmailIdentifier? oldest_local_id = null;
        int local_count = 0;
        try {
            Gee.List<Geary.Email>? list = yield folder.local_folder.list_email_by_id_async(null, 1,
                Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.NONE | ImapDB.Folder.ListFlags.OLDEST_TO_NEWEST,
                bg_cancellable);
            if (list != null && list.size > 0) {
                oldest_local = list[0].properties.date_received;
                oldest_local_id = list[0].id;
            }
            
            local_count = yield folder.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                bg_cancellable);
        } catch (Error err) {
            debug("Unable to fetch oldest local email for %s: %s", folder.to_string(), err.message);
        }
        
        if (availability_check) {
            // Compare the oldest mail in the local store and see if it is before the epoch; if so, no
            // need to synchronize simply because this Folder is available; wait for its contents to
            // change instead
            if (oldest_local != null) {
                if (oldest_local.compare(epoch) < 0) {
                    // Oldest local email before epoch, don't sync from network
                    return true;
                } else if (folder.properties.email_total == local_count) {
                    // Local earliest email is after epoch, but there's nothing before it
                    return true;
                } else {
                    debug("Oldest local email in %s not old enough (%s vs. %s), email_total=%d vs. local_count=%d, synchronizing...",
                        folder.to_string(), oldest_local.to_string(), epoch.to_string(),
                        folder.properties.email_total, local_count);
                }
            } else if (folder.properties.email_total == 0) {
                // no local messages, no remote messages -- this is as good as having everything up
                // to the epoch
                return true;
            } else {
                debug("No oldest message found for %s, synchronizing...", folder.to_string());
            }
        } else {
            debug("Folder %s changed, synchronizing...", folder.to_string());
        }
        
        try {
            yield folder.open_async(Folder.OpenFlags.FAST_OPEN, bg_cancellable);
            yield folder.wait_for_open_async(bg_cancellable);
        } catch (Error err) {
            // don't need to close folder; if either calls throws an error, the folder is not open
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Unable to open %s: %s", folder.to_string(), err.message);
            
            return true;
        }
        
        // turn off the flag watcher whilst synchronizing, as that can cause addt'l load on the
        // CPU
        folder.email_flag_watcher.enabled = false;
        
        try {
            yield sync_folder_async(folder, epoch, oldest_local, oldest_local_id);
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Error background syncing folder %s: %s", folder.to_string(), err.message);
            
            // fallthrough and close
        } finally {
            folder.email_flag_watcher.enabled = true;
        }
        
        try {
            // don't pass Cancellable; really need this to complete in all cases
            yield folder.close_async();
        } catch (Error err) {
            debug("Error closing %s: %s", folder.to_string(), err.message);
        }
        
        return true;
    }
    
    private async void sync_folder_async(GenericFolder folder, DateTime epoch, DateTime? oldest_local,
        Geary.EmailIdentifier? oldest_local_id) throws Error {
        debug("Background sync'ing %s", folder.to_string());
        
        // only perform vector expansion if oldest isn't old enough
        if (oldest_local == null || oldest_local.compare(epoch) > 0) {
            // go back one month at a time to the epoch, performing a little vector expansion at a
            // time rather than all at once (which will stall the replay queue)
            DateTime current_epoch = (oldest_local != null) ? oldest_local : new DateTime.now_local();
            do {
                current_epoch = current_epoch.add_months(-1);
                
                // don't go past epoch
                if (current_epoch.compare(epoch) < 0)
                    current_epoch = epoch;
                
                debug("Background sync'ing %s to %s", folder.to_string(), current_epoch.to_string());
                Geary.EmailIdentifier? epoch_id = yield folder.find_earliest_email_async(current_epoch,
                    oldest_local_id, bg_cancellable);
                if (epoch_id == null && current_epoch.compare(epoch) <= 0) {
                    debug("Unable to locate epoch messages on remote folder %s%s, fetching one past oldest...",
                        folder.to_string(),
                        (oldest_local_id != null) ? " earlier than oldest local" : "");
                    
                    // if there's nothing between the oldest local and the epoch, that means the
                    // mail just prior to our local oldest is oldest than the epoch; rather than
                    // continually thrashing looking for something that's just out of reach, add it
                    // to the folder and be done with it ... note that this even works if oldest_local_id
                    // is null, as that means the local folder is empty and so we should at least
                    // pull the first one to get a marker of age
                    yield folder.list_email_by_id_async(oldest_local_id, 1, Geary.Email.Field.NONE,
                        Geary.Folder.ListFlags.NONE, bg_cancellable);
                } else if (epoch_id != null) {
                    oldest_local_id = epoch_id;
                }
                
                // look for complete synchronization of UIDs (i.e. complete vector normalization)
                // no need to keep searching once this happens
                int local_count = yield folder.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                    bg_cancellable);
                if (local_count >= folder.properties.email_total) {
                    debug("Total vector normalization for %s: %d/%d emails", folder.to_string(), local_count,
                        folder.properties.email_total);
                    
                    break;
                }
            } while (current_epoch.compare(epoch) > 0);
        } else {
            debug("No expansion necessary for %s, oldest local (%s) is before epoch (%s)",
                folder.to_string(), oldest_local.to_string(), epoch.to_string());
        }
        
        // always give email prefetcher time to finish its work
        debug("Waiting for email prefetcher to complete %s...", folder.to_string());
        try {
            yield folder.email_prefetcher.active_sem.wait_async(bg_cancellable);
        } catch (Error err) {
            debug("Error waiting for email prefetcher to complete %s: %s", folder.to_string(),
                err.message);
        }
        
        debug("Done background sync'ing %s", folder.to_string());
    }
}

