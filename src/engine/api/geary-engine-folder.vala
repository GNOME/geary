/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.EngineFolder : Geary.AbstractFolder {
    private const int REMOTE_FETCH_CHUNK_COUNT = 10;
    
    private RemoteAccount remote;
    private LocalAccount local;
    private RemoteFolder? remote_folder = null;
    private LocalFolder local_folder;
    private bool opened = false;
    private Geary.Common.NonblockingSemaphore remote_semaphore =
        new Geary.Common.NonblockingSemaphore(true);
    
    public EngineFolder(RemoteAccount remote, LocalAccount local, LocalFolder local_folder) {
        this.remote = remote;
        this.local = local;
        this.local_folder = local_folder;
        
        local_folder.updated.connect(on_local_updated);
    }
    
    ~EngineFolder() {
        if (opened)
            warning("Folder %s destroyed without closing", to_string());
        
        local_folder.updated.disconnect(on_local_updated);
    }
    
    public override Geary.FolderPath get_path() {
        return local_folder.get_path();
    }
    
    public override Geary.FolderProperties? get_properties() {
        return null;
    }
    
    public override async void create_email_async(Geary.Email email, Cancellable? cancellable) throws Error {
        throw new EngineError.READONLY("Engine currently read-only");
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (opened)
            throw new EngineError.ALREADY_OPEN("Folder %s already open", to_string());
        
        yield local_folder.open_async(readonly, cancellable);
        
        // Rather than wait for the remote folder to open (which blocks completion of this method),
        // attempt to open in the background and treat this folder as "opened".  If the remote
        // doesn't open, this folder remains open but only able to work with the local cache.
        //
        // Note that any use of remote_folder in this class should first call
        // wait_for_remote_to_open(), which uses a NonblockingSemaphore to indicate that the remote
        // is open (or has failed to open).  This allows for early calls to list and fetch emails
        // can work out of the local cache until the remote is ready.
        open_remote_async.begin(readonly, cancellable, on_open_remote_completed);
        
        opened = true;
        
        notify_opened();
    }
    
    private async void open_remote_async(bool readonly, Cancellable? cancellable) throws Error {
        RemoteFolder folder = (RemoteFolder) yield remote.fetch_folder_async(local_folder.get_path(),
            cancellable);
        yield folder.open_async(readonly, cancellable);
        
        remote_folder = folder;
        remote_folder.updated.connect(on_remote_updated);
        
        remote_semaphore.notify();
    }
    
    private void on_open_remote_completed(Object? source, AsyncResult result) {
        try {
            open_remote_async.end(result);
        } catch (Error err) {
            debug("Unable to open remote folder %s: %s", to_string(), err.message);
            
            remote_folder = null;
            try {
                remote_semaphore.notify();
            } catch (Error err) {
                debug("Unable to notify remote folder ready: %s", err.message);
            }
        }
    }
    
    private async void wait_for_remote_to_open() throws Error {
        yield remote_semaphore.wait_async();
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        yield local_folder.close_async(cancellable);
        
        // if the remote folder is open, close it in the background so the caller isn't waiting for
        // this method to complete (much like open_async())
        if (remote_folder != null) {
            yield remote_semaphore.wait_async();
            remote_semaphore = new Geary.Common.NonblockingSemaphore(true);
            
            remote_folder.updated.disconnect(on_remote_updated);
            RemoteFolder? folder = remote_folder;
            remote_folder = null;
            
            folder.close_async.begin(cancellable);
            
            notify_closed(CloseReason.FOLDER_CLOSED);
        }
        
        opened = false;
    }
    
    public override async int get_email_count(Cancellable? cancellable = null) throws Error {
        // TODO
        return 0;
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        if (count == 0)
            return null;
        
        // block on do_list_email_async(), using an accumulator to gather the emails and return
        // them all at once to the caller
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_async(low, count, required_fields, accumulator, null, cancellable);
        
        return accumulator;
    }
    
    public override void lazy_list_email_async(int low, int count, Geary.Email.Field required_fields,
        EmailCallback cb, Cancellable? cancellable = null) {
        // schedule do_list_email_async(), using the callback to drive availability of email
        do_list_email_async.begin(low, count, required_fields, null, cb, cancellable);
    }
    
    private async void do_list_email_async(int low, int count, Geary.Email.Field required_fields,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable = null)
        throws Error {
        assert(low >= 1);
        assert(count >= 0);
        
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
        
        if (count == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        Gee.List<Geary.Email>? local_list = null;
        try {
            local_list = yield local_folder.list_email_async(low, count, required_fields,
                cancellable);
        } catch (Error local_err) {
            if (cb != null)
                cb (null, local_err);
            
            throw local_err;
        }
        
        int local_list_size = (local_list != null) ? local_list.size : 0;
        
        if (local_list_size > 0) {
            if (accumulator != null)
                accumulator.add_all(local_list);
            
            if (cb != null)
                cb(local_list, null);
        }
        
        if (local_list_size == count) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
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
        
        if (needed_by_position.length == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        Gee.List<Geary.Email>? remote_list = null;
        try {
            // if cb != null, it will be called by remote_list_email(), so don't call again with
            // returned list
            remote_list = yield remote_list_email(needed_by_position, required_fields, cb, cancellable);
        } catch (Error remote_err) {
            if (cb != null)
                cb(null, remote_err);
            
            throw remote_err;
        }
        
        if (accumulator != null && remote_list != null && remote_list.size > 0)
            accumulator.add_all(remote_list);
        
        // signal finished
        if (cb != null)
            cb(null, null);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        if (by_position.length == 0)
            return null;
        
        Gee.List<Geary.Email> accumulator = new Gee.ArrayList<Geary.Email>();
        yield do_list_email_sparse_async(by_position, required_fields, accumulator, null,
            cancellable);
        
        return accumulator;
    }
    
    public override void lazy_list_email_sparse_async(int[] by_position, Geary.Email.Field required_fields,
        EmailCallback cb, Cancellable? cancellable = null) {
        // schedule listing in the background, using the callback to drive availability of email
        do_list_email_sparse_async.begin(by_position, required_fields, null, cb, cancellable);
    }
    
    private async void do_list_email_sparse_async(int[] by_position, Geary.Email.Field required_fields,
        Gee.List<Geary.Email>? accumulator, EmailCallback? cb, Cancellable? cancellable = null)
        throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
        
        if (by_position.length == 0) {
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        Gee.List<Geary.Email>? local_list = null;
        try {
            local_list = yield local_folder.list_email_sparse_async(by_position, required_fields,
                cancellable);
        } catch (Error local_err) {
            if (cb != null)
                cb(null, local_err);
            
            throw local_err;
        }
        
        int local_list_size = (local_list != null) ? local_list.size : 0;
        
        if (local_list_size == by_position.length) {
            if (accumulator != null)
                accumulator.add_all(local_list);
            
            // report and signal finished
            if (cb != null) {
                cb(local_list, null);
                cb(null, null);
            }
            
            return;
        }
        
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
        
        if (needed_by_position.length == 0) {
            if (local_list != null && local_list.size > 0) {
                if (accumulator != null)
                    accumulator.add_all(local_list);
                
                if (cb != null)
                    cb(local_list, null);
            }
            
            // signal finished
            if (cb != null)
                cb(null, null);
            
            return;
        }
        
        Gee.List<Geary.Email>? remote_list = null;
        try {
            // if cb != null, it will be called by remote_list_email(), so don't call again with
            // returned list
            remote_list = yield remote_list_email(needed_by_position, required_fields, cb, cancellable);
        } catch (Error remote_err) {
            if (cb != null)
                cb(null, remote_err);
            
            throw remote_err;
        }
        
        if (accumulator != null && remote_list != null && remote_list.size > 0)
            accumulator.add_all(remote_list);
        
        // signal finished
        if (cb != null)
            cb(null, null);
    }
    
    private async Gee.List<Geary.Email>? remote_list_email(int[] needed_by_position,
        Geary.Email.Field required_fields, EmailCallback? cb, Cancellable? cancellable) throws Error {
        // possible to call remote multiple times, wait for it to open once and go
        yield wait_for_remote_to_open();
        
        debug("Background fetching %d emails for %s", needed_by_position.length, to_string());
        
        Gee.List<Geary.Email> full = new Gee.ArrayList<Geary.Email>();
        
        int index = 0;
        while (index <= needed_by_position.length) {
            // if a callback is specified, pull the messages down in chunks, so they can be reported
            // incrementally
            unowned int[] list;
            if (cb != null) {
                int list_count = int.min(REMOTE_FETCH_CHUNK_COUNT, needed_by_position.length - index);
                list = needed_by_position[index:index + list_count];
            } else {
                list = needed_by_position;
            }
            
            Gee.List<Geary.Email>? remote_list = yield remote_folder.list_email_sparse_async(
                list, required_fields, cancellable);
            
            if (remote_list == null || remote_list.size == 0)
                break;
            
            // if any were fetched, store locally
            // TODO: Bulk writing
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
            
            if (cb != null)
                cb(remote_list, null);
            
            full.add_all(remote_list);
            
            index += list.length;
        }
        
        return full;
    }
    
    public override async Geary.Email fetch_email_async(int num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("Folder %s not opened", to_string());
        
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
        yield wait_for_remote_to_open();
        Geary.Email email = yield remote_folder.fetch_email_async(num, fields, cancellable);
        
        // save to local store
        yield local_folder.update_email_async(email, false, cancellable);
        
        return email;
    }
    
    private void on_local_updated() {
    }
    
    private void on_remote_updated() {
    }
}

