/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {
    private const int FETCH_DATE_RECEIVED_CHUNK_COUNT = 25;
    
    public GenericAccount account { get; private set; }
    
    private NonblockingMailbox<GenericFolder>? bg_queue = null;
    private Gee.HashSet<GenericFolder> made_available = new Gee.HashSet<GenericFolder>();
    private Cancellable? bg_cancellable = null;
    private NonblockingSemaphore stopped = new NonblockingSemaphore();
    private NonblockingSemaphore prefetcher_semaphore = new NonblockingSemaphore();
    
    public AccountSynchronizer(GenericAccount account) {
        this.account = account;
        
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
        
        bg_queue = new NonblockingMailbox<GenericFolder>(bg_queue_comparator);
        bg_queue.allow_duplicates = false;
        bg_queue.requeue_duplicate = false;
        bg_cancellable = new Cancellable();
        
        // immediately start processing folders as they are announced as available
        process_queue_async.begin();
    }
    
    private void on_account_closed() {
        bg_cancellable.cancel();
        bg_queue.clear();
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Folder>? available,
        Gee.Collection<Folder>? unavailable) {
        if (stopped.is_passed())
            return;
        
        if (available != null)
            send_all(available, true);
        
        if (unavailable != null)
            revoke_all(unavailable);
    }
    
    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        send_all(altered, false);
    }
    
    private void send_all(Gee.Collection<Folder> folders, bool reason_available) {
        foreach (Folder folder in folders) {
            GenericFolder? generic_folder = folder as GenericFolder;
            if (generic_folder != null)
                bg_queue.send(generic_folder);
            
            // If adding because now available, make sure it's flagged as such, since there's an
            // additional check for available folders ... if not, remove from the map so it's
            // not treated as such, in case both of these come in back-to-back
            if (reason_available)
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
        return a.get_path().compare(b.get_path());
    }
    
    // Lower the score, the higher the importance.
    private static int score_folder(Folder a) {
        switch (a.get_special_folder_type()) {
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
            
            // generate the current epoch for synchronization (could cache this value, obviously, but
            // doesn't seem like this biggest win in this class)
            DateTime epoch;
            if (account.information.prefetch_period_days >= 0) {
                epoch = new DateTime.now_local();
                epoch = epoch.add_days(0 - account.information.prefetch_period_days);
            } else {
                epoch = new DateTime(new TimeZone.local(), 1, 1, 1, 0, 0, 0.0);
            }
            
            if (!yield process_folder_async(folder, made_available.remove(folder), epoch))
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
        if (availability_check) {
            // Fetch the oldest mail in the local store and see if it is before the epoch; if so, no
            // need to synchronize simply because this Folder is available; wait for its contents to
            // change instead
            Gee.List<Geary.Email>? oldest_local = null;
            try {
                oldest_local = yield folder.local_folder.local_list_email_async(1, 1,
                    Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.NONE, bg_cancellable);
            } catch (Error err) {
                debug("Unable to fetch oldest local email for %s: %s", folder.to_string(), err.message);
            }
            
            if (oldest_local != null && oldest_local.size > 0) {
                if (oldest_local[0].properties.date_received.compare(epoch) < 0) {
                    debug("Oldest local email in %s before epoch, don't sync from network", folder.to_string());
                    
                    return true;
                } else {
                    debug("Oldest local email in %s not old enough (%s), synchronizing...", folder.to_string(),
                        oldest_local[0].properties.date_received.to_string());
                }
            } else if (folder.get_properties().email_total == 0) {
                // no local messages, no remote messages -- this is as good as having everything up
                // to the epoch
                debug("No messages in local or remote folder %s, don't sync from network",
                    folder.to_string());
                
                return true;
            } else {
                debug("No oldest message found for %s, synchronizing...", folder.to_string());
            }
        }
        
        try {
            yield folder.open_async(true, bg_cancellable);
            yield folder.wait_for_open_async(bg_cancellable);
        } catch (Error err) {
            // don't need to close folder; if either calls throws an error, the folder is not open
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Unable to open %s: %s", folder.to_string(), err.message);
            
            return true;
        }
        
        // set up monitoring the Folder's prefetcher so an exception doesn't leave dangling
        // signal subscriptions
        prefetcher_semaphore = new NonblockingSemaphore();
        folder.email_prefetcher.halting.connect(on_email_prefetcher_completed);
        folder.closed.connect(on_email_prefetcher_completed);
        
        try {
            yield sync_folder_async(folder, epoch);
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Error background syncing folder %s: %s", folder.to_string(), err.message);
            
            // fallthrough and close
        } finally {
            folder.email_prefetcher.halting.disconnect(on_email_prefetcher_completed);
            folder.closed.disconnect(on_email_prefetcher_completed);
        }
        
        try {
            // don't pass Cancellable; really need this to complete in all cases
            yield folder.close_async();
        } catch (Error err) {
            debug("Error closing %s: %s", folder.to_string(), err.message);
        }
        
        return true;
    }
    
    private async void sync_folder_async(GenericFolder folder, DateTime epoch) throws Error {
        debug("Background sync'ing %s", folder.to_string());
        
        // TODO: This could be done in a single IMAP SEARCH command, as INTERNALDATE may be searched
        // upon (returning all messages that fit the criteria).  For now, simply iterating backward
        // in the folder until the oldest is found, then pulling the email down in chunks
        int low = -1;
        int count = FETCH_DATE_RECEIVED_CHUNK_COUNT;
        for (;;) {
            Gee.List<Email>? list = yield folder.list_email_async(low, count, Geary.Email.Field.PROPERTIES,
                Folder.ListFlags.NONE, bg_cancellable);
            if (list == null || list.size == 0)
                break;
            
            // sort these by their received date so they're walked in order
            Gee.TreeSet<Email> sorted_list = new Collection.FixedTreeSet<Email>(Email.compare_date_received_descending);
            sorted_list.add_all(list);
            
            // look for any that are older than epoch and bail out if found
            bool found = false;
            int lowest = int.MAX;
            foreach (Email email in sorted_list) {
                if (email.properties.date_received.compare(epoch) < 0) {
                    debug("Found epoch for %s at %s (%s)", folder.to_string(), email.id.to_string(),
                        email.properties.date_received.to_string());
                    
                    found = true;
                    
                    break;
                }
                
                // find lowest position for next round of fetching
                if (email.position < lowest)
                    lowest = email.position;
            }
            
            if (found || low == 1)
                break;
            
            low = Numeric.int_floor(lowest - FETCH_DATE_RECEIVED_CHUNK_COUNT, 1);
            count = (lowest - low).clamp(1, FETCH_DATE_RECEIVED_CHUNK_COUNT);
        }
        
        if (folder.email_prefetcher.has_work()) {
            // expanding an already opened folder doesn't guarantee the prefetcher will start
            debug("Waiting for email prefetcher to complete %s...", folder.to_string());
            try {
                yield prefetcher_semaphore.wait_async(bg_cancellable);
            } catch (Error err) {
                debug("Error waiting for email prefetcher to complete %s: %s", folder.to_string(),
                    err.message);
            }
        }
        
        debug("Done background sync'ing %s", folder.to_string());
    }
    
    private void on_email_prefetcher_completed() {
        debug("on_email_prefetcher_completed");
        prefetcher_semaphore.blind_notify();
    }
}

