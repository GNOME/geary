/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {
    private const int FETCH_DATE_RECEIVED_CHUNK_COUNT = 25;
    private const int SYNC_DELAY_SEC = 10;
    private const int RETRY_SYNC_DELAY_SEC = 60;
    
    private enum Reason {
        MADE_AVAILABLE,
        ALTERED
    }
    
    private class SyncMessage : BaseObject {
        public MinimalFolder folder;
        public Reason reason;
        
        public SyncMessage(MinimalFolder folder, Reason reason) {
            this.folder = folder;
            this.reason = reason;
        }
    }
    
    public GenericAccount account { get; private set; }
    
    private Nonblocking.Mailbox<SyncMessage> bg_queue = new Nonblocking.Mailbox<SyncMessage>(bg_queue_comparator);
    private MinimalFolder? current_folder = null;
    private Cancellable? bg_cancellable = null;
    private Nonblocking.Semaphore stopped = new Nonblocking.Semaphore();
    private Gee.HashSet<FolderPath> unavailable_paths = new Gee.HashSet<FolderPath>();
    private DateTime max_epoch = new DateTime(new TimeZone.local(), 2000, 1, 1, 0, 0, 0.0);
    
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
        account.email_sent.connect(on_email_sent);
    }
    
    ~AccountSynchronizer() {
        account.opened.disconnect(on_account_opened);
        account.closed.disconnect(on_account_closed);
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.folders_contents_altered.disconnect(on_folders_contents_altered);
        account.email_sent.disconnect(on_email_sent);
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
            // if prefetch value changes, reschedule all folders to account for new value
            delayed_send_all(account.list_folders(), Reason.MADE_AVAILABLE, SYNC_DELAY_SEC);
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
            
            delayed_send_all(available, Reason.MADE_AVAILABLE, SYNC_DELAY_SEC);
        }
        
        if (unavailable != null) {
            foreach (Folder folder in unavailable)
                unavailable_paths.add(folder.path);
            
            revoke_all(unavailable);
        }
    }
    
    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        delayed_send_all(altered, Reason.ALTERED, SYNC_DELAY_SEC);
    }
    
    private void on_email_sent() {
        try {
            Folder? sent_mail = account.get_special_folder(SpecialFolderType.SENT);
            if (sent_mail != null)
                send_all(iterate<Folder>(sent_mail).to_array_list(), Reason.ALTERED);
        } catch (Error err) {
            debug("Unable to retrieve Sent Mail from %s: %s", account.to_string(), err.message);
        }
    }
    
    private void delayed_send_all(Gee.Collection<Folder> folders, Reason reason, int sec) {
        Timeout.add_seconds(sec, () => {
            send_all(folders, reason);
            
            return false;
        });
    }
    
    private void send_all(Gee.Collection<Folder> folders, Reason reason) {
        foreach (Folder folder in folders) {
            MinimalFolder? imap_folder = folder as MinimalFolder;
            
            // only deal with ImapEngine.MinimalFolder
            if (imap_folder == null)
                continue;
            
            // don't bother with unselectable or local-only folders
            if (!folder.properties.is_openable.is_possible() || folder.properties.is_local_only)
                continue;
            
            // drop unavailable folders
            if (unavailable_paths.contains(folder.path))
                continue;
            
            // if considering folder not because it's available (i.e. because its contents changed),
            // and the folder is open, don't process it; MinimalFolder will take care of changes as
            // they occur, in order to remain synchronized
            if (reason != Reason.MADE_AVAILABLE && folder.get_open_state() != Folder.OpenState.CLOSED)
                continue;
            
            // don't requeue the currently processing folder
            if (imap_folder == current_folder)
                continue;
            
            // if altered, remove made_available sync message; if made_available, comparator will
            // drop if altered message already present; this prioritizes altered over made_available
            if (reason == Reason.ALTERED) {
                bg_queue.revoke_matching((msg) => {
                    return msg.folder == imap_folder && msg.reason == Reason.MADE_AVAILABLE;
                });
            }
            
            bg_queue.send(new SyncMessage(imap_folder, reason));
        }
    }
    
    private void revoke_all(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            MinimalFolder? imap_folder = folder as MinimalFolder;
            if (imap_folder == null)
                continue;
            
            bg_queue.revoke_matching((msg) => {
                return msg.folder == imap_folder;
            });
        }
    }
    
    // This is used to ensure that certain special folders get prioritized over others, so folders
    // important to the user (i.e. Inbox) go first while less-used folders (Spam) are fetched last
    private static int bg_queue_comparator(SyncMessage a, SyncMessage b) {
        if (a == b)
            return 0;
        
        // don't allow the same folder in the queue at the same time; it's up to the submitter to
        // remove existing folders based on reason
        if (a.folder == b.folder)
            return 0;
        
        int cmp = score_folder(a.folder) - score_folder(b.folder);
        if (cmp != 0)
            return cmp;
        
        // sort by path to stabilize the sort
        return a.folder.path.compare_to(b.folder.path);
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
        for (;;) {
            SyncMessage msg;
            try {
                msg = yield bg_queue.recv_async(bg_cancellable);
            } catch (Error err) {
                if (!(err is IOError.CANCELLED))
                    debug("Failed to receive next folder for background sync: %s", err.message);
                
                break;
            }
            
            // mark as current folder to prevent requeues while processing
            current_folder = msg.folder;
            
            // generate the current epoch for synchronization (could cache this value, obviously, but
            // doesn't seem like this biggest win in this class)
            DateTime epoch;
            if (account.information.prefetch_period_days >= 0) {
                epoch = new DateTime.now_local();
                epoch = epoch.add_days(0 - account.information.prefetch_period_days);
            } else {
                epoch = max_epoch;
            }
            
            bool not_cancelled = yield process_folder_async(msg.folder, msg.reason, epoch);
            
            // clear current folder in every event
            current_folder = null;
            
            if (!not_cancelled)
                break;
        }
        
        // clear queue of any remaining folders so references aren't held
        bg_queue.clear();
        
        // flag as stopped for any waiting tasks
        stopped.blind_notify();
    }
    
    // Returns false if IOError.CANCELLED received
    private async bool process_folder_async(MinimalFolder folder, Reason reason, DateTime epoch) {
        // get oldest local email; when folders are more-or-less synchronized, this reduces the
        // IMAP SEARCH results by only asking for messages since a certain date that exist in the
        // UID message set prior to this earliest one, reducing network traffic by not returning
        // UIDs for messages already in the local store
        DateTime? oldest_local_date = null;
        Geary.EmailIdentifier? oldest_local_id = null;
        int local_count = 0;
        try {
            Gee.List<Geary.Email>? list = yield folder.local_folder.list_email_by_id_async(null, 1,
                Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.OLDEST_TO_NEWEST, bg_cancellable);
            if (list != null && list.size > 0) {
                oldest_local_date = list[0].properties.date_received;
                oldest_local_id = list[0].id;
            }
            
            local_count = yield folder.local_folder.get_email_count_async(ImapDB.Folder.ListFlags.NONE,
                bg_cancellable);
        } catch (Error err) {
            debug("Unable to fetch oldest local email for %s: %s", folder.to_string(), err.message);
        }
        
        // altered folders will always been synchronized, but if only made available (i.e. the
        // Account just opened up or the folder was just discovered), do some checking to avoid
        // round-tripping to the server
        if (reason == Reason.MADE_AVAILABLE) {
            if (oldest_local_id != null) {
                if (oldest_local_date.compare(epoch) < 0) {
                    // Oldest local is before epoch
                    return true;
                } else if (folder.properties.email_total == local_count) {
                    // Completely synchronized with remote
                    return true;
                }
            } else if (folder.properties.email_total == 0) {
                // no local messages, no remote messages
                return true;
            }
        }
        
        try {
            yield folder.open_async(Folder.OpenFlags.NO_DELAY, bg_cancellable);
        } catch (Error err) {
            // don't need to close folder; if either calls throws an error, the folder is not open
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Unable to open %s: %s", folder.to_string(), err.message);
            
            // retry later
            delayed_send_all(iterate<Folder>(folder).to_array_list(), reason, RETRY_SYNC_DELAY_SEC);
            
            return true;
        }
        
        bool not_cancelled = true;
        try {
            yield sync_folder_async(folder, epoch, oldest_local_id);
        } catch (Error err) {
            if (err is IOError.CANCELLED) {
                not_cancelled = false;
            } else {
                debug("Error background syncing folder %s: %s", folder.to_string(), err.message);
                
                // retry later
                delayed_send_all(iterate<Folder>(folder).to_array_list(), reason, RETRY_SYNC_DELAY_SEC);
            }
            
            // fallthrough and close
        }
        
        try {
            // don't pass Cancellable; really need this to complete in all cases
            yield folder.close_async();
        } catch (Error err) {
            debug("Error closing %s: %s", folder.to_string(), err.message);
        }
        
        return not_cancelled;
    }
    
    private async void sync_folder_async(MinimalFolder folder, DateTime epoch,
        Geary.EmailIdentifier? oldest_local_id) throws Error {
        debug("Background sync'ing %s", folder.to_string());
        
        // wait for the folder to be fully opened to be sure we have all the most current
        // information
        yield folder.wait_for_open_async(bg_cancellable);
        
        // find the first email (from 1 to n) that is since the epoch date but before the oldest local
        // id; this will expand the vector in the database to accomodate it, pulling in the
        // ImapDB.Folder.REQUIRED_FIELDS for all email from the end of the vector (n) to it
        Geary.EmailIdentifier? earliest_id = yield folder.find_earliest_email_async(epoch,
            oldest_local_id, bg_cancellable);
        
        // found an email in the range that is older than epoch, list *one email earlier* than
        // it to act as a sentinal; that email will be before the epoch and prevent future
        // resynchronization when MADE_AVAILABLE triggers (which happens each startup) ...
        // if not found, use the oldest_local_id to pull one before it to act as the sentinel;
        // if both are null, use that, which will pull the most recent email for the folder and
        // that becomes the sentinal
        yield folder.list_email_by_id_async(earliest_id ?? oldest_local_id, 1, Email.Field.NONE,
            Folder.ListFlags.NONE, bg_cancellable);
        
        // always give email prefetcher time to finish its work; this synchronizes the folder's
        // contents with the (possibly expanded) vector
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

