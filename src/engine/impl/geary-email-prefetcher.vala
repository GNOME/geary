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
public class Geary.EmailPrefetcher : Object {
    public const int PREFETCH_DELAY_SEC = 5;
    
    private unowned Geary.Folder folder;
    private int start_delay_sec;
    private NonblockingMutex mutex = new NonblockingMutex();
    private Gee.HashSet<Geary.EmailIdentifier> prefetch_ids = new Gee.HashSet<Geary.EmailIdentifier>(
        Hashable.hash_func, Equalable.equal_func);
    private uint schedule_id = 0;
    private Cancellable cancellable = new Cancellable();
    
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
    
    private void on_opened(Geary.Folder.OpenState open_state) {
        if (open_state != Geary.Folder.OpenState.BOTH)
            return;
        
        cancellable = new Cancellable();
        schedule_prefetch_all();
    }
    
    private void on_closed(Geary.Folder.CloseReason close_reason) {
        if (close_reason != Geary.Folder.CloseReason.FOLDER_CLOSED)
            return;
        
        cancellable.cancel();
    }
    
    private void on_locally_appended(Gee.Collection<Geary.EmailIdentifier> ids) {
        schedule_prefetch(ids);
    }
    
    private void schedule_prefetch_all() {
        // Async method will schedule prefetch once ids are known
        do_prefetch_all.begin();
    }
    
    private void schedule_prefetch(Gee.Collection<Geary.EmailIdentifier> ids) {
        prefetch_ids.add_all(ids);
        
        if (schedule_id != 0)
            Source.remove(schedule_id);
        
        schedule_id = Timeout.add_seconds(start_delay_sec, on_start_prefetch, Priority.LOW);
    }
    
    private bool on_start_prefetch() {
        do_prefetch.begin();
        
        schedule_id = 0;
        
        return false;
    }
    
    private async void do_prefetch_all() {
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
            debug("Error while prefetching emails for %s: %s", folder.to_string(), err.message);
        }
        
        if (token != NonblockingMutex.INVALID_TOKEN) {
            try {
                mutex.release(ref token);
            } catch (Error release_err) {
                debug("Unable to release email prefetcher mutex: %s", release_err.message);
            }
        }
    }
    
    private async void do_prefetch_batch() throws Error {
        debug("do_prefetch_batch %s %d", folder.to_string(), prefetch_ids.size);
        
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
        
        // Sort email by size
        Gee.TreeSet<Geary.Email> sorted_email = new Gee.TreeSet<Geary.Email>(email_size_ascending_comparator);
        foreach (Geary.EmailIdentifier id in local_fields.keys) {
            sorted_email.add(yield folder.fetch_email_async(id, Geary.Email.Field.PROPERTIES,
                Geary.Folder.ListFlags.LOCAL_ONLY, cancellable));
        }
        
        // Big TODO: The engine needs to be able to synthesize ENVELOPE (and any of the fields
        // constituting it) and PREVIEW from HEADER and BODY if available.  When it can do that
        // won't need to prefetch ENVELOPE or PREVIEW; prefetching HEADER and BODY will be enough.
        
        foreach (Geary.Email email in sorted_email) {
            Geary.EmailIdentifier id = email.id;
            Geary.Email.Field field = local_fields.get(id);
            
            if (!field.is_all_set(Geary.Email.Field.ENVELOPE))
                yield prefetch_field_async(id, Geary.Email.Field.ENVELOPE, "envelope");
            
            if (!field.is_all_set(Geary.Email.Field.HEADER))
                yield prefetch_field_async(id, Geary.Email.Field.HEADER, "headers");
            
            if (!field.is_all_set(Geary.Email.Field.BODY))
                yield prefetch_field_async(id, Geary.Email.Field.BODY, "body");
            
            if (!field.is_all_set(Geary.Email.Field.PREVIEW))
                yield prefetch_field_async(id, Geary.Email.Field.PREVIEW, "preview");
        }
        
        debug("finished do_prefetch_batch %s %d", folder.to_string(), ids.size);
    }
    
    private async void prefetch_field_async(Geary.EmailIdentifier id, Geary.Email.Field field, string name) {
        try {
            yield folder.fetch_email_async(id, field, Geary.Folder.ListFlags.NONE, cancellable);
        } catch (Error error) {
            debug("Error prefetching %s for %s: %s", name, id.to_string(), error.message);
        }
    }
    
    private static int email_size_ascending_comparator(void *a, void *b) {
        long asize = 0;
        Geary.Imap.EmailProperties? aprop = (Geary.Imap.EmailProperties) ((Geary.Email *) a)->properties;
        if (aprop != null && aprop.rfc822_size != null)
            asize = aprop.rfc822_size.value;
        
        long bsize = 0;
        Geary.Imap.EmailProperties? bprop = (Geary.Imap.EmailProperties) ((Geary.Email *) b)->properties;
        if (bprop != null && bprop.rfc822_size != null)
            bsize = bprop.rfc822_size.value;
        
        if (asize < bsize)
            return -1;
        else if (asize > bsize)
            return 1;
        else
            return 0;
    }
}

