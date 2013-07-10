/* Copyright 2012-2013 Yorba Foundation
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
    private const int PREFETCH_CHUNK_BYTES = 128 * 1024;
    
    private unowned Geary.Folder folder;
    private int start_delay_sec;
    private Nonblocking.Mutex mutex = new Nonblocking.Mutex();
    private Gee.TreeSet<Geary.Email> prefetch_emails = new Collection.FixedTreeSet<Geary.Email>(
        Email.compare_date_received_descending);
    private uint schedule_id = 0;
    private Cancellable cancellable = new Cancellable();
    
    public signal void halting();
    
    public EmailPrefetcher(Geary.Folder folder, int start_delay_sec = PREFETCH_DELAY_SEC) {
        assert(start_delay_sec > 0);
        
        this.folder = folder;
        this.start_delay_sec = start_delay_sec;
        
        folder.opened.connect(on_opened);
        folder.closed.connect(on_closed);
        folder.email_locally_appended.connect(on_locally_appended);
    }
    
    ~EmailPrefetcher() {
        if (schedule_id != 0)
            message("Warning: Geary.EmailPrefetcher destroyed before folder closed");
        
        folder.opened.disconnect(on_opened);
        folder.closed.disconnect(on_closed);
        folder.email_locally_appended.disconnect(on_locally_appended);
    }
    
    public bool has_work() {
        return prefetch_emails.size > 0;
    }
    
    private void on_opened(Geary.Folder.OpenState open_state) {
        if (open_state != Geary.Folder.OpenState.BOTH)
            return;
        
        cancellable = new Cancellable();
        do_prepare_all_local_async.begin();
    }
    
    private void on_closed(Geary.Folder.CloseReason close_reason) {
        // cancel for any reason ... this will be called multiple times, but the following operations
        // can be executed any number of times and still get the desired results
        cancellable.cancel();
        
        if (schedule_id != 0) {
            Source.remove(schedule_id);
            schedule_id = 0;
        }
    }
    
    private void on_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        do_prepare_new_async.begin(ids);
    }
    
    // emails should include PROPERTIES
    private void schedule_prefetch(Gee.Collection<Geary.Email> emails) {
        prefetch_emails.add_all(emails);
        
        if (schedule_id != 0)
            Source.remove(schedule_id);
        
        schedule_id = Timeout.add_seconds(start_delay_sec, on_start_prefetch);
    }
    
    private bool on_start_prefetch() {
        do_prefetch_async.begin();
        
        schedule_id = 0;
        
        return false;
    }
    
    private async void do_prepare_all_local_async() {
        int low = -1;
        bool finished = false;
        do {
            finished = (low == 1);
            
            Gee.List<Geary.Email>? list = null;
            try {
                list = yield folder.list_email_async(low, PREFETCH_IDS_CHUNKS, Geary.Email.Field.PROPERTIES,
                    Geary.Folder.ListFlags.LOCAL_ONLY, cancellable);
            } catch (Error err) {
                debug("Error while list local emails for %s: %s", folder.to_string(), err.message);
            }
            
            if (list == null || list.size == 0)
                break;
            
            schedule_prefetch(list);
            
            low = Numeric.int_floor(low - PREFETCH_IDS_CHUNKS, 1);
        } while (!finished);
    }
    
    private async void do_prepare_new_async(Gee.Collection<Geary.EmailIdentifier> ids) {
        Gee.List<Geary.Email>? list = null;
        try {
            list = yield folder.list_email_by_sparse_id_async(ids, Geary.Email.Field.PROPERTIES,
                Geary.Folder.ListFlags.LOCAL_ONLY, cancellable);
        } catch (Error err) {
            debug("Error while list local emails for %s: %s", folder.to_string(), err.message);
        }
        
        if (list != null && list.size > 0)
            schedule_prefetch(list);
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
        
        // only signal "halting" if it looks like nothing more is waiting for another round
        if (prefetch_emails.size == 0)
            halting();
        
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
        prefetch_emails = new Collection.FixedTreeSet<Geary.Email>(Email.compare_date_received_descending);
        
        if (emails.size == 0)
            return;
        
        debug("do_prefetch_batch_async %s start_total=%d", folder.to_string(), emails.size);
        
        // Remove anything that is fully prefetched
        Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? fields = null;
        try {
            fields = yield folder.list_local_email_fields_async(Email.emails_to_map(emails).keys,
                cancellable);
        } catch (Error err) {
            debug("do_prefetch_batch_async: Unable to list local fields for %s prefetch: %s",
                folder.to_string(), err.message);
            
            return;
        }
        
        Collection.filtered_remove<Geary.Email>(emails, (email) => {
            // if not present, don't prefetch
            if (fields == null || !fields.has_key(email.id))
                return false;
            
            // only prefetch if missing fields
            return !fields.get(email.id).fulfills(PREFETCH_FIELDS);
        });
        
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
        }
        
        // get any remaining
        if (ids.size > 0)
            yield do_prefetch_email_async(ids, chunk_bytes);
        
        debug("finished do_prefetch_batch_async %s end_total=%d", folder.to_string(), count);
    }
    
    // Return true to continue, false to stop prefetching (cancelled)
    private async bool do_prefetch_email_async(Gee.Collection<Geary.EmailIdentifier> ids, int64 chunk_bytes) {
        debug("do_prefetch_email_async: %s prefetching %d emails (%sb)", folder.to_string(),
            ids.size, chunk_bytes.to_string());
        
        try {
            yield folder.list_email_by_sparse_id_async(ids, PREFETCH_FIELDS, Folder.ListFlags.NONE,
                cancellable);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                debug("Error prefetching %d emails for %s: %s", ids.size, folder.to_string(),
                    err.message);
            } else {
                // only exit if cancelled; fetch_email_async() can error out on lots of things,
                // including mail that's been deleted, and that shouldn't stop the prefetcher
                return false;
            }
        }
        
        return true;
    }
}

