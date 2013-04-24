/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Because IMAP doesn't offer a standard mechanism for notifications of email flags changing,
 * have to poll for changes, annoyingly.  This class performs this task by monitoring the supplied
 * folder for its "opened" and "closed" signals and periodically polling for changes.
 *
 * Note that EmailFlagWatcher doesn't maintain a reference to the Geary.Folder it's watching.
 */
private class Geary.ImapEngine.EmailFlagWatcher : BaseObject {
    public const int DEFAULT_FLAG_WATCH_SEC = 3 * 60;
    
    private const int PULL_CHUNK_COUNT = 100;
    private const int MAX_EMAIL_WATCHED = 1000;
    
    public bool enabled { get; set; default = true; }
    
    private unowned Geary.Folder folder;
    private int seconds;
    private uint watch_id = 0;
    private bool in_flag_watch = false;
    private Cancellable cancellable = new Cancellable();
    
    public signal void email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> changed);
    
    public EmailFlagWatcher(Geary.Folder folder, int seconds = DEFAULT_FLAG_WATCH_SEC) {
        assert(seconds > 0);
        
        this.folder = folder;
        this.seconds = seconds;
        
        folder.opened.connect(on_opened);
        folder.closed.connect(on_closed);
    }
    
    ~FlagWatcher() {
        if (watch_id != 0)
            message("Warning: Geary.FlagWatcher destroyed before folder closed");
        
        folder.opened.disconnect(on_opened);
        folder.closed.disconnect(on_closed);
    }
    
    private void on_opened(Geary.Folder.OpenState open_state) {
        if (open_state != Geary.Folder.OpenState.BOTH)
            return;
        
        cancellable = new Cancellable();
        if (watch_id == 0)
            watch_id = Timeout.add_seconds(seconds, on_flag_watch);
    }
    
    private void on_closed(Geary.Folder.CloseReason close_reason) {
        if (close_reason != Geary.Folder.CloseReason.FOLDER_CLOSED)
            return;
        
        cancellable.cancel();
        
        if (watch_id != 0)
            Source.remove(watch_id);
        
        watch_id = 0;
    }
    
    private bool on_flag_watch() {
        if (enabled)
            flag_watch_async.begin();
        
        return true;
    }
    
    private async void flag_watch_async() {
        if (in_flag_watch)
            return;
        
        in_flag_watch = true;
        try {
            yield do_flag_watch_async();
        } catch (Error err) {
            message("Flag watch error: %s", err.message);
        }
        in_flag_watch = false;
    }
    
    private async void do_flag_watch_async() throws Error {
        Logging.debug(Logging.Flag.PERIODIC, "do_flag_watch_async begin %s", folder.to_string());
        
        int low = -1;
        bool finished = false;
        int total = 0;
        for (;;) {
            if (finished)
                break;
            
            // Fetch a chunk of email flags in local folder.
            Gee.List<Geary.Email>? list_local = yield folder.list_email_async(low, PULL_CHUNK_COUNT,
                Email.Field.FLAGS, Geary.Folder.ListFlags.LOCAL_ONLY, cancellable);
            if (list_local == null || list_local.size == 0)
                break;
            
            total += list_local.size;
            
            // if this request's low was 1 or processed the top 2000, then this is the last iteration
            finished = (low == 1 || total >= MAX_EMAIL_WATCHED);
            
            // Get all email identifiers in the local folder; also, update the low and count arguments
            Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> local_map = new Gee.HashMap<
                Geary.EmailIdentifier, Geary.EmailFlags>(Geary.Hashable.hash_func, Geary.Equalable.equal_func);
            foreach (Geary.Email e in list_local) {
                if (low == -1)
                    low = e.position;
                else if (low > e.position)
                    low = e.position;
                
                local_map.set(e.id, e.email_flags);
            }
            
            // now roll back PULL_CHUNK_COUNT earlier
            low = Numeric.int_floor(low - PULL_CHUNK_COUNT, 1);
            
            // Fetch e-mail from folder using force update, which will cause the cache to be bypassed
            // and the latest to be gotten from the server (updating the cache in the process)
            Gee.List<Geary.Email>? list_remote = yield folder.list_email_by_sparse_id_async(local_map.keys,
                Email.Field.FLAGS, Geary.Folder.ListFlags.FORCE_UPDATE, cancellable);
            if (list_remote == null || list_remote.size == 0)
                continue;
            
            // Build map of emails that have changed.
            Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> changed_map = 
                new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>(Geary.Hashable.hash_func,
                Geary.Equalable.equal_func);
            foreach (Geary.Email e in list_remote) {
                if (!local_map.has_key(e.id))
                    continue;
                
                if (!local_map.get(e.id).equals(e.email_flags))
                    changed_map.set(e.id, e.email_flags);
            }
            
            if (!cancellable.is_cancelled() && changed_map.size > 0)
                email_flags_changed(changed_map);
        }
        
        Logging.debug(Logging.Flag.PERIODIC, "do_flag_watch_async: completed %s", folder.to_string());
    }
}

