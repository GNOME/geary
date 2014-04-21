/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The EmailPrefetcher monitors the supplied folder for its "opened" and "closed" signals.  When
 * opened, the prefetcher will pull in email from the server in the background so its available
 * in the local store.
 *
 * The EmailPrefetcher does not maintain a reference to the folder.
 */
private class Geary.ImapEngine.EmailPrefetcher : Object {
    public const int PREFETCH_DELAY_SEC = 1;
    
    private const Geary.Email.Field PREFETCH_FIELDS = Geary.Email.Field.ALL;
    private const int PREFETCH_IDS_CHUNKS = 500;
    private const int PREFETCH_CHUNK_BYTES = 32 * 1024;
    
    public Nonblocking.CountingSemaphore active_sem { get; private set;
        default = new Nonblocking.CountingSemaphore(null); }
    
    private unowned ImapEngine.MinimalFolder folder;
    private int start_delay_sec;
    private Nonblocking.Mutex mutex = new Nonblocking.Mutex();
    private Gee.TreeSet<Geary.Email> prefetch_emails = new Gee.TreeSet<Geary.Email>(
        Email.compare_date_received_descending);
    private uint schedule_id = 0;
    private Cancellable cancellable = new Cancellable();
    
    public EmailPrefetcher(ImapEngine.MinimalFolder folder, int start_delay_sec = PREFETCH_DELAY_SEC) {
        assert(start_delay_sec > 0);
        
        this.folder = folder;
        this.start_delay_sec = start_delay_sec;
        
        folder.opened.connect(on_opened);
        folder.closed.connect(on_closed);
        folder.email_appended.connect(on_local_expansion);
        folder.email_inserted.connect(on_local_expansion);
    }
    
    ~EmailPrefetcher() {
        if (schedule_id != 0)
            message("Warning: Geary.EmailPrefetcher destroyed before folder closed");
        
        folder.opened.disconnect(on_opened);
        folder.closed.disconnect(on_closed);
        folder.email_appended.disconnect(on_local_expansion);
        folder.email_inserted.disconnect(on_local_expansion);
    }
    
    private void on_opened(Geary.Folder.OpenState open_state) {
        if (open_state != Geary.Folder.OpenState.BOTH)
            return;
        
        cancellable = new Cancellable();
        
        // acquire here since .begin() only schedules for later
        active_sem.acquire();
        do_prepare_all_local_async.begin();
    }
    
    private void on_closed(Geary.Folder.CloseReason close_reason) {
        // cancel for any reason ... this will be called multiple times, but the following operations
        // can be executed any number of times and still get the desired results
        cancellable.cancel();
        
        if (schedule_id != 0) {
            Source.remove(schedule_id);
            schedule_id = 0;
            
            // since an acquire was done when scheduled, need to notify when cancelled
            active_sem.blind_notify();
        }
    }
    
    private void on_local_expansion(Gee.Collection<Geary.EmailIdentifier> ids) {
        // it's possible to be notified of an append prior to remote open; don't prefetch until
        // that occurs
        if (folder.get_open_state() != Geary.Folder.OpenState.BOTH)
            return;
        
        // acquire here since .begin() only schedules for later
        active_sem.acquire();
        do_prepare_new_async.begin(ids);
    }
    
    // emails should include PROPERTIES
    private void schedule_prefetch(Gee.Collection<Geary.Email> emails) {
        debug("%s: scheduling %d emails for prefetching", folder.to_string(), emails.size);
        
        prefetch_emails.add_all(emails);
        
        // only increment active state if not rescheduling
        if (schedule_id != 0)
            Source.remove(schedule_id);
        else
            active_sem.acquire();
        
        schedule_id = Timeout.add_seconds(start_delay_sec, on_start_prefetch);
    }
    
    private bool on_start_prefetch() {
        do_prefetch_async.begin();
        
        schedule_id = 0;
        
        return false;
    }
    
    private async void do_prepare_all_local_async() {
        Geary.EmailIdentifier? lowest = null;
        for (;;) {
            Gee.List<Geary.Email>? list = null;
            try {
                list = yield folder.local_folder.list_email_by_id_async((ImapDB.EmailIdentifier) lowest,
                    PREFETCH_IDS_CHUNKS, Geary.Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.ONLY_INCOMPLETE,
                    cancellable);
            } catch (Error err) {
                debug("Error while list local emails for %s: %s", folder.to_string(), err.message);
            }
            
            if (list == null || list.size == 0)
                break;
            
            // find lowest for next iteration
            lowest = Geary.EmailIdentifier.sort_emails(list).first().id;
            
            schedule_prefetch(list);
        }
        
        active_sem.blind_notify();
    }
    
    private async void do_prepare_new_async(Gee.Collection<Geary.EmailIdentifier> ids) {
        Gee.List<Geary.Email>? list = null;
        try {
            list = yield folder.local_folder.list_email_by_sparse_id_async(
                (Gee.Collection<ImapDB.EmailIdentifier>) ids,
                Geary.Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.ONLY_INCOMPLETE, cancellable);
        } catch (Error err) {
            debug("Error while list local emails for %s: %s", folder.to_string(), err.message);
        }
        
        if (list != null && list.size > 0)
            schedule_prefetch(list);
        
        active_sem.blind_notify();
    }
    
    private async void do_prefetch_async() {
        int token = Nonblocking.Mutex.INVALID_TOKEN;
        try {
            token = yield mutex.claim_async(cancellable);
            yield do_prefetch_batch_async();
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Error while prefetching emails for %s: %s", folder.to_string(), err.message);
        }
        
        // this round is done
        active_sem.blind_notify();
        
        if (token != Nonblocking.Mutex.INVALID_TOKEN) {
            try {
                mutex.release(ref token);
            } catch (Error release_err) {
                debug("Unable to release email prefetcher mutex: %s", release_err.message);
            }
        }
    }
    
    private async void do_prefetch_batch_async() throws Error {
        // snarf up all requested Emails for this round
        Gee.TreeSet<Geary.Email> emails = prefetch_emails;
        prefetch_emails = new Gee.TreeSet<Geary.Email>(Email.compare_date_received_descending);
        
        if (emails.size == 0)
            return;
        
        debug("do_prefetch_batch_async %s start_total=%d", folder.to_string(), emails.size);
        
        // Big TODO: The engine needs to be able to synthesize ENVELOPE (and any of the fields
        // constituting it) and PREVIEW from HEADER and BODY if available.  When it can do that
        // won't need to prefetch ENVELOPE or PREVIEW; prefetching HEADER and BODY will be enough.
        
        // Another big TODO: The engine needs to be able to chunk BODY requests so a large email
        // doesn't monopolize the pipe and prevent other requests from going through
        
        Gee.HashSet<Geary.EmailIdentifier> ids = new Gee.HashSet<Geary.EmailIdentifier>();
        int64 chunk_bytes = 0;
        int count = 0;
        
        while (emails.size > 0) {
            // dequeue emails by date received, newest to oldest
            Geary.Email email = emails.first();
            
            // only add to this chunk if the email is smaller than one chunk or there's nothing
            // in this chunk so far ... this means an oversized email will be pulled all by itself
            // in the next round if there's stuff already ahead of it
            if (email.properties.total_bytes < PREFETCH_CHUNK_BYTES || ids.size == 0) {
                bool removed = emails.remove(email);
                assert(removed);
                
                ids.add(email.id);
                chunk_bytes += email.properties.total_bytes;
                count++;
                
                // if not enough stuff is in this chunk, keep going
                if (chunk_bytes < PREFETCH_CHUNK_BYTES)
                    continue;
            }
            
            bool keep_going = yield do_prefetch_email_async(ids, chunk_bytes);
            
            // clear out for next chunk ... this also prevents the final prefetch_async() from trying
            // to pull twice if !keep_going
            ids.clear();
            chunk_bytes = 0;
            
            if (!keep_going)
                break;
            
            yield Scheduler.sleep_ms_async(200);
        }
        
        // get any remaining
        if (ids.size > 0)
            yield do_prefetch_email_async(ids, chunk_bytes);
        
        debug("finished do_prefetch_batch_async %s end_total=%d", folder.to_string(), count);
    }
    
    // Return true to continue, false to stop prefetching (cancelled or not open)
    private async bool do_prefetch_email_async(Gee.Collection<Geary.EmailIdentifier> ids, int64 chunk_bytes) {
        debug("do_prefetch_email_async: %s prefetching %d emails (%sb)", folder.to_string(),
            ids.size, chunk_bytes.to_string());
        
        try {
            yield folder.list_email_by_sparse_id_async(ids, PREFETCH_FIELDS, Folder.ListFlags.NONE,
                cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED) && !(err is EngineError.OPEN_REQUIRED)) {
                debug("Error prefetching %d emails for %s: %s", ids.size, folder.to_string(),
                    err.message);
            } else {
                // only exit if cancelled or not open; fetch_email_async() can error out on lots of things,
                // including mail that's been deleted, and that shouldn't stop the prefetcher
                return false;
            }
        }
        
        return true;
    }
}

