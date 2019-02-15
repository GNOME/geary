/* Copyright 2016 Software Freedom Conservancy Inc.
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
private class Geary.ImapEngine.EmailPrefetcher : Geary.BaseObject {
    public const int PREFETCH_DELAY_SEC = 1;
    
    private const Geary.Email.Field PREFETCH_FIELDS = Geary.Email.Field.ALL;
    private const int PREFETCH_CHUNK_BYTES = 32 * 1024;
    
    public Nonblocking.CountingSemaphore active_sem { get; private set;
        default = new Nonblocking.CountingSemaphore(null); }

    private weak ImapEngine.MinimalFolder folder;
    private Nonblocking.Mutex mutex = new Nonblocking.Mutex();
    private Gee.TreeSet<Geary.Email> prefetch_emails = new Gee.TreeSet<Geary.Email>(
        Email.compare_recv_date_descending);
    private TimeoutManager prefetch_timer;
    private Cancellable? cancellable = null;


    public EmailPrefetcher(ImapEngine.MinimalFolder folder, int start_delay_sec = PREFETCH_DELAY_SEC) {
        this.folder = folder;

        if (start_delay_sec <= 0) {
            start_delay_sec = PREFETCH_DELAY_SEC;
        }

        this.prefetch_timer = new TimeoutManager.seconds(
            start_delay_sec, () => { do_prefetch_async.begin(); }
        );
    }

    public void open() {
        this.cancellable = new Cancellable();

        this.folder.email_locally_appended.connect(on_local_expansion);
        this.folder.email_locally_inserted.connect(on_local_expansion);

        // acquire here since .begin() only schedules for later
        this.active_sem.acquire();
        this.do_prepare_all_local_async.begin();
    }

    public void close() {
        if (this.prefetch_timer.is_running) {
            this.prefetch_timer.reset();
            // since an acquire was done when scheduled, need to
            // notify when cancelled
            this.active_sem.blind_notify();
        }

        this.folder.email_locally_appended.disconnect(on_local_expansion);
        this.folder.email_locally_inserted.disconnect(on_local_expansion);
        this.cancellable = null;
    }

    private void on_local_expansion(Gee.Collection<Geary.EmailIdentifier> ids) {
        // it's possible to be notified of an append prior to remote open; don't prefetch until
        // that occurs
        if (folder.get_open_state() != Geary.Folder.OpenState.REMOTE)
            return;

        // acquire here since .begin() only schedules for later
        active_sem.acquire();
        do_prepare_new_async.begin(ids);
    }

    // emails should include PROPERTIES
    private void schedule_prefetch(Gee.Collection<Geary.Email>? emails) {
        if (emails != null && emails.size > 0) {
            this.prefetch_emails.add_all(emails);

            // only increment active state if not rescheduling
            if (!this.prefetch_timer.is_running) {
                this.active_sem.acquire();
            }

            this.prefetch_timer.start();
        }
    }

    private async void do_prepare_all_local_async() {
        Gee.List<Geary.Email>? list = null;
        try {
            list = yield this.folder.local_folder.list_email_by_id_async(
                null, int.MAX,
                Geary.Email.Field.PROPERTIES,
                ImapDB.Folder.ListFlags.ONLY_INCOMPLETE,
                this.cancellable
            );
        } catch (GLib.IOError.CANCELLED err) {
            // all good
        } catch (GLib.Error err) {
            warning("%s: Error listing email on open: %s",
                    folder.to_string(), err.message);
        }

        debug("%s: Scheduling %d messages on open for prefetching",
              this.folder.to_string(), list != null ? list.size : 0);
        schedule_prefetch(list);
        this.active_sem.blind_notify();
    }

    private async void do_prepare_new_async(Gee.Collection<Geary.EmailIdentifier> ids) {
        Gee.List<Geary.Email>? list = null;
        try {
            list = yield this.folder.local_folder.list_email_by_sparse_id_async(
                (Gee.Collection<ImapDB.EmailIdentifier>) ids,
                Geary.Email.Field.PROPERTIES,
                ImapDB.Folder.ListFlags.ONLY_INCOMPLETE,
                this.cancellable
            );
        } catch (GLib.IOError.CANCELLED err) {
            // all good
        } catch (GLib.Error err) {
            warning("%s: Error listing email on open: %s",
                    folder.to_string(), err.message);
        }

        debug("%s: Scheduling %d new emails for prefetching",
              this.folder.to_string(), list != null ? list.size : 0);
        schedule_prefetch(list);
        this.active_sem.blind_notify();
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
        prefetch_emails = new Gee.TreeSet<Geary.Email>(Email.compare_recv_date_descending);
        
        if (emails.size == 0)
            return;
        
        debug("do_prefetch_batch_async %s start_total=%d", folder.to_string(), emails.size);

        // Big TODO: The engine needs to be able to synthesize
        // ENVELOPE (and any of the fields constituting it) from
        // HEADER if available.  When it can do that won't need to
        // prefetch ENVELOPE; prefetching HEADER will be enough.

        // Another big TODO: The engine needs to be able to chunk BODY
        // requests so a large email doesn't monopolize the pipe and
        // prevent other requests from going through

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

