/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.EngineFolder : Object, Geary.Folder {
    private RemoteAccount remote;
    private LocalAccount local;
    private RemoteFolder remote_folder;
    private LocalFolder local_folder;
    
    public EngineFolder(RemoteAccount remote, LocalAccount local, LocalFolder local_folder) {
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        
        local_folder.updated.connect(on_local_updated);
    }
    
    ~EngineFolder() {
        local_folder.updated.disconnect(on_local_updated);
    }
    
    public string get_name() {
        return local_folder.get_name();
    }
    
    public Geary.FolderProperties? get_properties() {
        return null;
    }
    
    public async void create_email_async(Geary.Email email, Cancellable? cancellable) throws Error {
        throw new EngineError.READONLY("Engine currently read-only");
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        yield local_folder.open_async(readonly, cancellable);
        
        if (remote_folder == null) {
            remote_folder = (RemoteFolder) yield remote.fetch_folder_async(null, local_folder.get_name(),
                cancellable);
            remote_folder.updated.connect(on_remote_updated);
        }
        
        yield remote_folder.open_async(readonly, cancellable);
        
        notify_opened();
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        yield local_folder.close_async(cancellable);
        
        if (remote_folder != null) {
            remote_folder.updated.disconnect(on_remote_updated);
            yield remote_folder.close_async(cancellable);
            remote_folder = null;
            
            notify_closed(CloseReason.FOLDER_CLOSED);
        }
    }
    
    public async int get_email_count(Cancellable? cancellable = null) throws Error {
        // TODO
        return 0;
    }
    
    public async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        assert(low >= 1);
        assert(count >= 0);
        
        if (count == 0)
            return null;
        
        Gee.List<Geary.Email>? local_list = yield local_folder.list_email_async(low, count,
            required_fields, cancellable);
        int local_list_size = (local_list != null) ? local_list.size : 0;
        debug("local list found %d", local_list_size);
        
        if (remote_folder == null || local_list_size == count)
            return local_list;
        
        // go through the positions from (low) to (low + count) and see if they're not already
        // present in local_list; whatever isn't present needs to be fetched
        int[] needed_by_position = new int[0];
        int position = low;
        for (int index = 0; (index < count) && (position <= (low + count - 1)); position++) {
            while ((index < local_list_size) && (local_list[index].location.position < position))
                index++;
            
            if (index >= local_list_size || local_list[index].location.position != position)
                needed_by_position += position;
        }
        
        if (needed_by_position.length == 0)
            return local_list;
        
        Gee.List<Geary.Email>? remote_list = yield remote_list_email(needed_by_position,
            required_fields, cancellable);
        
        return combine_lists(local_list, remote_list);
    }
    
    public async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        if (by_position.length == 0)
            return null;
        
        Gee.List<Geary.Email>? local_list = yield local_folder.list_email_sparse_async(by_position,
            required_fields, cancellable);
        int local_list_size = (local_list != null) ? local_list.size : 0;
        
        if (remote_folder == null || local_list_size == by_position.length)
            return local_list;
        
        // go through the list looking for anything not already in the sparse by_position list
        // to fetch from the server; since by_position is not guaranteed to be sorted, the local
        // list needs to be searched each iteration.
        //
        // TODO: Optimize this, especially if large lists/sparse sets are supplied
        int[] needed_by_position = new int[0];
        foreach (int position in by_position) {
            bool found = false;
            if (local_list != null) {
                foreach (Geary.Email email in local_list) {
                    if (email.location.position == position) {
                        found = true;
                        
                        break;
                    }
                }
            }
            
            if (!found)
                needed_by_position += position;
        }
        
        if (needed_by_position.length == 0)
            return local_list;
        
        Gee.List<Geary.Email>? remote_list = yield remote_list_email(needed_by_position,
            required_fields, cancellable);
        
        return combine_lists(local_list, remote_list);
    }
    
    private async Gee.List<Geary.Email>? remote_list_email(int[] needed_by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable) throws Error {
        debug("Background fetching %d emails for %s", needed_by_position.length, get_name());
        
        Gee.List<Geary.Email>? remote_list = yield remote_folder.list_email_sparse_async(
            needed_by_position, required_fields, cancellable);
        
        if (remote_list != null && remote_list.size == 0)
            remote_list = null;
        
        // if any were fetched, store locally
        // TODO: Bulk writing
        if (remote_list != null) {
            foreach (Geary.Email email in remote_list) {
                bool exists_in_system = false;
                if (email.message_id != null) {
                    int count;
                    exists_in_system = yield local.has_message_id_async(email.message_id, out count,
                        cancellable);
                }
                
                bool exists_in_folder = yield local_folder.is_email_associated_async(email,
                    cancellable);
                
                // NOTE: Although this looks redundant, this is a complex decision case and laying
                // it out like this helps explain the logic.  Also, this code relies on the fact
                // that update_email_async() is a powerful call which might be broken down in the
                // future (requiring a duplicate email be manually associated with the folder,
                // for example), and so would like to keep this around to facilitate that.
                if (!exists_in_system && !exists_in_folder) {
                    // This case indicates the email is new to the local store OR has no
                    // Message-ID and so a new copy must be stored.
                    yield local_folder.create_email_async(email, cancellable);
                } else if (exists_in_system && !exists_in_folder) {
                    // This case indicates the email has been (partially) stored previously but
                    // was not associated with this folder; update it (which implies association)
                    yield local_folder.update_email_async(email, false, cancellable);
                } else if (!exists_in_system && exists_in_folder) {
                    // This case indicates the message doesn't have a Message-ID and can only be
                    // identified by a folder-specific ID, so it can be updated in the folder
                    // (This may result in multiple copies of the message stored locally.)
                    yield local_folder.update_email_async(email, true, cancellable);
                } else if (exists_in_system && exists_in_folder) {
                    // This indicates the message is in the local store and was previously
                    // associated with this folder, so merely update the local store
                    yield local_folder.update_email_async(email, false, cancellable);
                }
            }
        }
        
        return remote_list;
    }
    
    public async Geary.Email fetch_email_async(int num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (remote_folder == null)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", get_name());
        
        try {
            return yield local_folder.fetch_email_async(num, fields, cancellable);
        } catch (Error err) {
            // TODO: Better parsing of error; currently merely falling through and trying network
            // for copy
            debug("Unable to fetch email from local store: %s", err.message);
        }
        
        // To reach here indicates either the local version does not have all the requested fields
        // or it's simply not present.  If it's not present, want to ensure that the Message-ID
        // is requested, as that's a good way to manage duplicate messages in the system
        Geary.Email.Field available_fields;
        bool is_present = yield local_folder.is_email_present_at(num, out available_fields, cancellable);
        if (!is_present)
            fields = fields.set(Geary.Email.Field.REFERENCES);
        
        // fetch from network
        Geary.Email email = yield remote_folder.fetch_email_async(num, fields, cancellable);
        
        // save to local store
        yield local_folder.update_email_async(email, false, cancellable);
        
        return email;
    }
    
    private void on_local_updated() {
    }
    
    private void on_remote_updated() {
    }
    
    private Gee.List<Geary.Email>? combine_lists(Gee.List<Geary.Email>? a, Gee.List<Geary.Email>? b) {
        if (a == null)
            return b;
        
        if (b == null)
            return a;
        
        Gee.List<Geary.Email> combined = new Gee.ArrayList<Geary.Email>();
        combined.add_all(a);
        combined.add_all(b);
        
        return combined;
    }
}

