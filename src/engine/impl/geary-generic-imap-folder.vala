/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapFolder : Geary.EngineFolder {
    public const int DEFAULT_FLAG_WATCH_SEC = 3 * 60;
    
    private uint flag_watch_id = 0;
    private Cancellable flag_watch_cancellable = new Cancellable();
    private bool in_flag_watch = false;
    
    public GenericImapFolder(RemoteAccount remote, LocalAccount local, LocalFolder local_folder) {
        base (remote, local, local_folder);
    }
    
    ~GenericImapFolder() {
        disable_flag_watch();
        flag_watch_cancellable.cancel();
    }
    
    // Check if the remote folder's ordering has changed since last opened
    protected override async bool prepare_opened_folder(Geary.Folder local_folder,
        Geary.Folder remote_folder, Cancellable? cancellable) throws Error {
        debug("prepare_opened_folder %s", to_string());
        
        Geary.Imap.FolderProperties? local_properties =
            (Geary.Imap.FolderProperties?) local_folder.get_properties();
        Geary.Imap.FolderProperties? remote_properties =
            (Geary.Imap.FolderProperties?) remote_folder.get_properties();
        
        // both sets of properties must be available
        if (local_properties == null) {
            debug("Unable to verify UID validity for %s: missing local properties", get_path().to_string());
            
            return false;
        }
        
        if (remote_properties == null) {
            debug("Unable to verify UID validity for %s: missing remote properties", get_path().to_string());
            
            return false;
        }
        
        // and both must have their next UID's (it's possible they don't if it's a non-selectable
        // folder)
        if (local_properties.uid_next == null || local_properties.uid_validity == null) {
            debug("Unable to verify UID next for %s: missing local UID next (%s) and/or validity (%s)",
                get_path().to_string(), (local_properties.uid_next == null).to_string(),
                (local_properties.uid_validity == null).to_string());
            
            return false;
        }
        
        if (remote_properties.uid_next == null || remote_properties.uid_validity == null) {
            debug("Unable to verify UID next for %s: missing remote UID next (%s) and/or validity (%s)",
                get_path().to_string(), (remote_properties.uid_next == null).to_string(),
                (remote_properties.uid_validity == null).to_string());
            
            return false;
        }
        
        if (local_properties.uid_validity.value != remote_properties.uid_validity.value) {
            // TODO: Don't deal with UID validity changes yet
            error("UID validity changed: %lld -> %lld", local_properties.uid_validity.value,
                remote_properties.uid_validity.value);
        }
        
        Geary.Imap.Folder imap_remote_folder = (Geary.Imap.Folder) remote_folder;
        Geary.Sqlite.Folder imap_local_folder = (Geary.Sqlite.Folder) local_folder;
        
        // from here on the only operations being performed on the folder are creating or updating
        // existing emails or removing them, both operations being performed using EmailIdentifiers
        // rather than positional addressing ... this means the order of operation is not important
        // and can be batched up rather than performed serially
        NonblockingBatch batch = new NonblockingBatch();
        
        // if same, no problem-o, move on
        if (local_properties.uid_next.value != remote_properties.uid_next.value) {
            debug("UID next changed for %s: %lld -> %lld", to_string(), local_properties.uid_next.value,
                remote_properties.uid_next.value);
            
            // fetch everything from the last seen UID (+1) to the current next UID that's not
            // already in the local store (since the uidnext field isn't reported by NOOP or IDLE,
            // it's possible these were fetched the last time the folder was selected)
            int64 uid_start_value = local_properties.uid_next.value;
            for (;;) {
                Geary.EmailIdentifier start_id = new Imap.EmailIdentifier(new Imap.UID(uid_start_value));
                Geary.Email.Field available_fields;
                if (!yield imap_local_folder.is_email_present_async(start_id, out available_fields,
                    cancellable)) {
                    break;
                }
                
                debug("already have UID %lld in %s local store", uid_start_value, to_string());
                
                if (++uid_start_value >= remote_properties.uid_next.value)
                    break;
            }
            
            // store all the new emails' UIDs and properties (primarily flags) in the local store,
            // to normalize the database against the remote folder
            if (uid_start_value < remote_properties.uid_next.value) {
                Geary.Imap.EmailIdentifier uid_start = new Geary.Imap.EmailIdentifier(
                    new Geary.Imap.UID(uid_start_value));
                
                Gee.List<Geary.Email>? newest = yield imap_remote_folder.list_email_by_id_async(
                    uid_start, int.MAX, Geary.Email.Field.PROPERTIES, Geary.Folder.ListFlags.NONE,
                    cancellable);
                
                if (newest != null && newest.size > 0) {
                    foreach (Geary.Email email in newest)
                        batch.add(new CreateEmailOperation(local_folder, email));
                }
            }
        }
        
        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        Geary.Imap.UID? earliest_uid = yield imap_local_folder.get_earliest_uid_async(cancellable);
        
        // if no earliest UID, that means no messages in local store, so nothing to update
        if (earliest_uid == null || !earliest_uid.is_valid()) {
            debug("No earliest UID in %s, nothing to update", to_string());
            
            return true;
        }
        
        int64 full_uid_count = local_properties.uid_next.value - 1 - earliest_uid.value;
        
        // If no UID's, nothing to update
        if (full_uid_count <= 0 || (full_uid_count > int.MAX)) {
            debug("No valid UID range in local folder %s (count=%lld), nothing to update", to_string(),
                full_uid_count);
            
            return true;
        }
        
        Geary.Imap.EmailIdentifier earliest_id = new Geary.Imap.EmailIdentifier(earliest_uid);
        int full_id_count = (int) full_uid_count;
        
        // Get the local emails in the range
        Gee.List<Geary.Email>? old_local = yield imap_local_folder.list_email_by_id_async(
            earliest_id, full_id_count, Geary.Email.Field.PROPERTIES, Geary.Folder.ListFlags.NONE,
            cancellable);
        int local_length = (old_local != null) ? old_local.size : 0;
        
        // as before, if empty folder, nothing to update
        if (local_length == 0) {
            debug("Folder %s empty, nothing to update", to_string());
            
            return true;
        }
        
        // Get the remote emails in the range to either add any not known, remove deleted messages,
        // and update the flags of the remainder
        Gee.List<Geary.Email>? old_remote = yield imap_remote_folder.list_email_by_id_async(
            earliest_id, full_id_count, Geary.Email.Field.PROPERTIES, Geary.Folder.ListFlags.NONE,
            cancellable);
        int remote_length = (old_remote != null) ? old_remote.size : 0;
        
        int remote_ctr = 0;
        int local_ctr = 0;
        Gee.ArrayList<Geary.EmailIdentifier> removed_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        for (;;) {
            if (local_ctr >= local_length || remote_ctr >= remote_length)
                break;
            
            Geary.Imap.UID remote_uid = 
                ((Geary.Imap.EmailIdentifier) old_remote[remote_ctr].id).uid;
            Geary.Imap.UID local_uid =
                ((Geary.Imap.EmailIdentifier) old_local[local_ctr].id).uid;
            
            if (remote_uid.value == local_uid.value) {
                // same, update flags (if changed) and move on
                Geary.Imap.EmailProperties local_email_properties =
                    (Geary.Imap.EmailProperties) old_local[local_ctr].properties;
                Geary.Imap.EmailProperties remote_email_properties =
                    (Geary.Imap.EmailProperties) old_remote[remote_ctr].properties;
                
                if (!local_email_properties.equals(remote_email_properties))
                    batch.add(new CreateEmailOperation(local_folder, old_remote[remote_ctr]));
                
                remote_ctr++;
                local_ctr++;
            } else if (remote_uid.value < local_uid.value) {
                // one we'd not seen before is present, add and move to next remote
                batch.add(new CreateEmailOperation(local_folder, old_remote[remote_ctr]));
                
                remote_ctr++;
            } else {
                assert(remote_uid.value > local_uid.value);
                
                // local's email on the server has been removed, remove locally
                batch.add(new RemoveEmailOperation(local_folder, old_local[local_ctr].id));
                removed_ids.add(old_local[local_ctr].id);
                
                local_ctr++;
            }
        }
        
        // add newly-discovered emails to local store ... only report these as appended; earlier
        // CreateEmailOperations were updates of emails existing previously or additions of emails
        // that were on the server earlier but not stored locally (i.e. this value represents emails
        // added to the top of the stack)
        int appended = 0;
        for (; remote_ctr < remote_length; remote_ctr++) {
            batch.add(new CreateEmailOperation(local_folder, old_remote[remote_ctr]));
            appended++;
        }
        
        // remove anything left over ... use local count rather than remote as we're still in a stage
        // where only the local messages are available
        for (; local_ctr < local_length; local_ctr++)
            batch.add(new RemoveEmailOperation(local_folder, old_local[local_ctr].id));
        
        // execute them all at once
        yield batch.execute_all_async(cancellable);
        
        // throw the first exception, if one occurred
        batch.throw_first_exception();
        
        // notify emails that have been removed (see note above about why not all Creates are
        // signalled)
        foreach (Geary.EmailIdentifier removed_id in removed_ids)
            notify_message_removed(removed_id);
        
        // notify additions
        if (appended > 0)
            notify_messages_appended(appended);
        
        debug("completed prepare_opened_folder %s", to_string());
        
        return true;
    }
    
    protected override void notify_opened(Geary.Folder.OpenState state, int count) {
        base.notify_opened(state, count);
        
        if (state == Geary.Folder.OpenState.BOTH) {
            flag_watch_cancellable = new Cancellable();
            enable_flag_watch();
        }
    }
    
    protected override void notify_closed(Geary.Folder.CloseReason reason) {
        disable_flag_watch();
        flag_watch_cancellable.cancel();
        
        base.notify_closed(reason);
    }
    
    /**
     * Turns on the "flag watch."  This periodtically checks if the flags on any messages have changed.
     * 
     * If seconds is negative or zero, keepalives will be disabled.  (This is not recommended.)
     */
    private void enable_flag_watch(int seconds = DEFAULT_FLAG_WATCH_SEC) {
        if (seconds <= 0) {
            disable_flag_watch();
            
            return;
        }
        
        if (flag_watch_id != 0)
            Source.remove(flag_watch_id);
        
        flag_watch_id = Timeout.add_seconds(seconds, on_flag_watch);
    }
    
    private bool disable_flag_watch() {
        if (flag_watch_id == 0)
            return false;
        
        Source.remove(flag_watch_id);
        flag_watch_id = 0;
        
        return true;
    }
    
    private bool on_flag_watch() {
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
        Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> local_map = 
            new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>(Geary.Hashable.hash_func,
            Geary.Equalable.equal_func);
        Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags> changed_map = 
            new Gee.HashMap<Geary.EmailIdentifier, Geary.EmailFlags>(Geary.Hashable.hash_func,
            Geary.Equalable.equal_func);
        
        // Fetch all email properties in local folder.
        Gee.List<Geary.Email>? list_local = yield local_folder.list_email_async(-1, int.MAX, 
            Email.Field.PROPERTIES, ListFlags.FAST, flag_watch_cancellable);
        
        if (list_local == null)
            return;
        
        // Build local map and find lowest ID.
        Geary.EmailIdentifier? low = null;
        foreach (Geary.Email e in list_local) {
            local_map.set(e.id, e.properties.email_flags);
            
            if (low == null || e.id.compare(low) < 0)
                low = e.id;
        }
        
        // Fetch corresponding e-mail from folder.
        Gee.List<Geary.Email>? list_remote = yield list_email_by_id_async(low, int.MAX,
            Email.Field.PROPERTIES, ListFlags.FORCE_UPDATE, flag_watch_cancellable);
        
        // Build map of emails that have changed.
        foreach (Geary.Email e in list_remote) {
            if (!local_map.has_key(e.id))
                continue;
            
            if (!local_map.get(e.id).equals(e.properties.email_flags))
                changed_map.set(e.id, e.properties.email_flags);
        }
        
        if (!flag_watch_cancellable.is_cancelled() && changed_map.size > 0)
            notify_email_flags_changed(changed_map);
    }
}
