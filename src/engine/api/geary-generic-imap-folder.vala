/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.GenericImapFolder : Geary.EngineFolder {
    public GenericImapFolder(RemoteAccount remote, LocalAccount local, LocalFolder local_folder) {
        base (remote, local, local_folder);
    }
    
    // Check if the remote folder's ordering has changed since last opened
    protected override async bool prepare_opened_folder(Geary.Folder local_folder,
        Geary.Folder remote_folder, Cancellable? cancellable) throws Error {
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
            debug("UID validity changed: %lld -> %lld", local_properties.uid_validity.value,
                remote_properties.uid_validity.value);
            breakpoint();
        }
        
        Geary.Imap.Folder imap_remote_folder = (Geary.Imap.Folder) remote_folder;
        Geary.Sqlite.Folder imap_local_folder = (Geary.Sqlite.Folder) local_folder;
        
        // if same, no problem-o
        if (local_properties.uid_next.value != remote_properties.uid_next.value) {
            debug("UID next changed: %lld -> %lld", local_properties.uid_next.value,
                remote_properties.uid_next.value);
            
            // fetch everything from the last seen UID (+1) to the current next UID
            // TODO: Could break this fetch up in chunks if it helps
            Gee.List<Geary.Email>? newest = yield imap_remote_folder.list_email_uid_async(
                local_properties.uid_next, null, Geary.Email.Field.PROPERTIES, cancellable);
            
            if (newest != null && newest.size > 0) {
                debug("saving %d newest emails", newest.size);
                foreach (Geary.Email email in newest) {
                    try {
                        yield local_folder.create_email_async(email, cancellable);
                    } catch (Error newest_err) {
                        debug("Unable to save new email in %s: %s", to_string(), newest_err.message);
                    }
                }
            }
        }
        
        // fetch email from earliest email to last to (a) remove any deletions and (b) update
        // any flags that may have changed
        Geary.Imap.UID last_uid = new Geary.Imap.UID(local_properties.uid_next.value - 1);
        Geary.Imap.UID? earliest_uid = yield imap_local_folder.get_earliest_uid_async(cancellable);
        
        // if no earliest UID, that means no messages in local store, so nothing to update
        if (earliest_uid == null || !earliest_uid.is_valid()) {
            debug("No earliest UID in %s, nothing to update", to_string());
            
            return true;
        }
        
        Gee.List<Geary.Email>? old_local = yield imap_local_folder.list_email_uid_async(earliest_uid,
            last_uid, Geary.Email.Field.PROPERTIES, cancellable);
        int local_length = (old_local != null) ? old_local.size : 0;
        
        // as before, if empty folder, nothing to update
        if (local_length == 0) {
            debug("Folder %s empty, nothing to update", to_string());
            
            return true;
        }
        
        Gee.List<Geary.Email>? old_remote = yield imap_remote_folder.list_email_uid_async(earliest_uid,
            last_uid, Geary.Email.Field.PROPERTIES, cancellable);
        int remote_length = (old_remote != null) ? old_remote.size : 0;
        
        int remote_ctr = 0;
        int local_ctr = 0;
        for (;;) {
            if (local_ctr >= local_length || remote_ctr >= remote_length)
                break;
            
            Geary.Imap.UID remote_uid = 
                ((Geary.Imap.EmailIdentifier) old_remote[remote_ctr].id).uid;
            Geary.Imap.UID local_uid =
                ((Geary.Imap.EmailIdentifier) old_local[local_ctr].id).uid;
            
            if (remote_uid.value == local_uid.value) {
                // same, update flags and move on
                try {
                    yield imap_local_folder.update_email_async(old_remote[remote_ctr], true,
                        cancellable);
                } catch (Error update_err) {
                    debug("Unable to update old email in %s: %s", to_string(), update_err.message);
                }
                
                remote_ctr++;
                local_ctr++;
            } else if (remote_uid.value < local_uid.value) {
                // one we'd not seen before is present, add and move to next remote
                try {
                    yield local_folder.create_email_async(old_remote[remote_ctr], cancellable);
                } catch (Error add_err) {
                    debug("Unable to add new email to %s: %s", to_string(), add_err.message);
                }
                
                remote_ctr++;
            } else {
                assert(remote_uid.value > local_uid.value);
                
                // local's email on the server has been removed, remove locally
                try {
                    yield local_folder.remove_email_async(old_local[local_ctr], cancellable);
                } catch (Error remove_err) {
                    debug("Unable to remove discarded email from %s: %s", to_string(),
                        remove_err.message);
                }
                
                local_ctr++;
            }
        }
        
        // add newly-discovered emails to local store
        for (; remote_ctr < remote_length; remote_ctr++) {
            try {
                yield local_folder.create_email_async(old_remote[remote_ctr], cancellable);
            } catch (Error append_err) {
                debug("Unable to append new email to %s: %s", to_string(), append_err.message);
            }
        }
        
        // remove anything left over
        for (; local_ctr < local_length; local_ctr++) {
            try {
                yield local_folder.remove_email_async(old_local[local_ctr], cancellable);
            } catch (Error discard_err) {
                debug("Unable to discard email from %s: %s", to_string(), discard_err.message);
            }
        }
        
        return true;
    }
}
