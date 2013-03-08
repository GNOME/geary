/* Copyright 2012 Yorba Foundation
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
public class Geary.ImapEngine.EmailPrefetcher : Object {
    public const int PREFETCH_DELAY_SEC = 1;
    
    private const Geary.Email.Field PREFETCH_FIELDS = Geary.Email.Field.ALL;
    
    private unowned Geary.Folder folder;
    private int start_delay_sec;
    private NonblockingMutex mutex = new NonblockingMutex();
    private Gee.HashSet<Geary.EmailIdentifier> prefetch_ids = new Gee.HashSet<Geary.EmailIdentifier>(
        Hashable.hash_func, Equalable.equal_func);
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
        return prefetch_ids.size > 0;
    }
    
    private void on_opened(Geary.Folder.OpenState open_state) {
        if (open_state != Geary.Folder.OpenState.BOTH)
            return;
        
        cancellable = new Cancellable();
        schedule_prefetch_all_local();
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
        schedule_prefetch(ids);
    }
    
    private void schedule_prefetch_all_local() {
        // Async method will schedule prefetch once ids are known
        do_prefetch_all_local.begin();
    }
    
    private void schedule_prefetch(Gee.Collection<Geary.EmailIdentifier> ids) {
        prefetch_ids.add_all(ids);
        
        if (schedule_id != 0)
            Source.remove(schedule_id);
        
        schedule_id = Timeout.add_seconds(start_delay_sec, on_start_prefetch);
    }
    
    private bool on_start_prefetch() {
        do_prefetch.begin();
        
        schedule_id = 0;
        
        return false;
    }
    
    private async void do_prefetch_all_local() {
        Gee.List<Geary.Email>? list = null;
        try {
            // by listing NONE, retrieving only the EmailIdentifier for the range (which here is all)
            list = yield folder.list_email_async(1, -1, Geary.Email.Field.NONE,
                Geary.Folder.ListFlags.LOCAL_ONLY, cancellable);
        } catch (Error err) {
            debug("Error while prefetching all emails for %s: %s", folder.to_string(), err.message);
        }
        
        if (list == null || list.size == 0)
            return;
        
        Gee.HashSet<Geary.EmailIdentifier> ids = new Gee.HashSet<Geary.EmailIdentifier>(
            Hashable.hash_func, Equalable.equal_func);
        foreach (Geary.Email email in list)
            ids.add(email.id);
        
        if (ids.size > 0)
            schedule_prefetch(ids);
    }
    
    private async void do_prefetch() {
        int token = NonblockingMutex.INVALID_TOKEN;
        try {
            token = yield mutex.claim_async(cancellable);
            yield do_prefetch_batch();
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Error while prefetching emails for %s: %s", folder.to_string(), err.message);
        }
        
        // only signal "halting" if it looks like nothing more is waiting for another round
        if (prefetch_ids.size == 0)
            halting();
        
        if (token != NonblockingMutex.INVALID_TOKEN) {
            try {
                mutex.release(ref token);
            } catch (Error release_err) {
                debug("Unable to release email prefetcher mutex: %s", release_err.message);
            }
        }
    }
    
    private async void do_prefetch_batch() throws Error {
        // snarf up all requested EmailIdentifiers for this round
        Gee.HashSet<Geary.EmailIdentifier> ids = prefetch_ids;
        prefetch_ids = new Gee.HashSet<Geary.EmailIdentifier>(Hashable.hash_func, Equalable.equal_func);
        
        if (ids.size == 0)
            return;
        
        // Get the stored fields of all the local email
        Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? local_fields =
            yield folder.list_local_email_fields_async(ids, cancellable);
        
        if (local_fields == null || local_fields.size == 0) {
            debug("No local fields in %s", folder.to_string());
            
            return;
        }
        
        debug("do_prefetch_batch %s %d", folder.to_string(), ids.size);
        
        // Sort email by date
        Gee.TreeSet<Geary.Email> sorted_email = new Collection.FixedTreeSet<Geary.Email>(
            Email.compare_date_received_descending);
        foreach (Geary.EmailIdentifier id in local_fields.keys) {
            sorted_email.add(yield folder.fetch_email_async(id, Geary.Email.Field.PROPERTIES,
                Geary.Folder.ListFlags.LOCAL_ONLY, cancellable));
        }
        
        // Big TODO: The engine needs to be able to synthesize ENVELOPE (and any of the fields
        // constituting it) and PREVIEW from HEADER and BODY if available.  When it can do that
        // won't need to prefetch ENVELOPE or PREVIEW; prefetching HEADER and BODY will be enough.
        
        // Another big TODO: The engine needs to be able to chunk BODY requests so a large email
        // doesn't monopolize the pipe and prevent other requests from going through
        
        int skipped = 0;
        foreach (Geary.Email email in sorted_email) {
            if (local_fields.get(email.id).fulfills(PREFETCH_FIELDS)) {
                skipped++;
                
                continue;
            }
            
            if (cancellable.is_cancelled())
                break;
            
            try {
                yield folder.fetch_email_async(email.id, PREFETCH_FIELDS, Folder.ListFlags.NONE,
                    cancellable);
            } catch (Error err) {
                if (!(err is IOError.CANCELLED)) {
                    debug("Error prefetching %s for %s: %s", folder.to_string(), email.id.to_string(),
                        err.message);
                } else {
                    // only exit if cancelled; fetch_email_async() can error out on lots of things,
                    // including mail that's been deleted, and that shouldn't stop the prefetcher
                    break;
                }
            }
        }
        
        debug("finished do_prefetch_batch %s %d skipped=%d", folder.to_string(), ids.size, skipped);
    }
}

