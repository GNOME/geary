/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.SearchFolderRoot : Geary.FolderRoot {
    public const string MAGIC_BASENAME = "$GearySearchFolder$";
    
    public SearchFolderRoot() {
        base(MAGIC_BASENAME, null, false);
    }
}

public class Geary.SearchFolderProperties : Geary.FolderProperties {
    public SearchFolderProperties(int total, int unread) {
        base(total, unread, Trillian.FALSE, Trillian.FALSE, Trillian.TRUE);
    }
    
    public void set_total(int total) {
        this.email_total = total;
    }
}

/**
 * Special folder type used to query and display search results.
 */

public class Geary.SearchFolder : Geary.AbstractLocalFolder {
    // Max number of emails that can ever be in the folder.
    public static const int MAX_RESULT_EMAILS = 1000;
    
    private weak Account _account;
    public override Account account { get { return _account; } }
    
    private SearchFolderProperties _properties = new SearchFolderProperties(0, 0);
    public override FolderProperties properties { get { return _properties; } }
    
    private FolderPath? _path = null;
    public override FolderPath path {
        get {
            return (_path != null) ? _path : _path = new SearchFolderRoot();
        }
    }
    
    public override SpecialFolderType special_folder_type {
        get {
            return Geary.SpecialFolderType.SEARCH;
        }
    }
    
    private Gee.HashSet<Geary.FolderPath?> exclude_folders = new Gee.HashSet<Geary.FolderPath?>();
    private Geary.SpecialFolderType[] exclude_types = {
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
        // Orphan emails (without a folder) are also excluded; see ctor.
    };
    private string? search_query = null;
    private Gee.TreeSet<Geary.Email> search_results;
    private Geary.Nonblocking.Mutex result_mutex = new Geary.Nonblocking.Mutex();
    
    /**
     * Fired when the search query has changed.  This signal is fired *after* the search
     * has completed.
     */
    public signal void search_query_changed(string? query);
    
    public SearchFolder(Account account) {
        _account = account;
        
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.email_locally_complete.connect(on_email_locally_complete);
        
        clear_search_results();
        
        // We always want to exclude emails that don't live anywhere from
        // search results.
        exclude_orphan_emails();
    }
    
    ~SearchFolder() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);;
        account.email_locally_complete.disconnect(on_email_locally_complete);
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        if (available != null) {
            foreach (Geary.Folder folder in available) {
                // Exclude it from searching if it's got the right special type.
                if (folder.special_folder_type in exclude_types)
                    exclude_folder(folder);
            }
        }
    }
    
    private async Gee.ArrayList<Geary.EmailIdentifier> folder_ids_to_search_async(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> folder_ids, Cancellable? cancellable) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> local_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.EmailIdentifier folder_id in folder_ids) {
            // TODO: parallelize.
            Geary.EmailIdentifier? local_id = yield account.folder_email_id_to_search_async(
                folder.path, folder_id, path, cancellable);
            if (local_id != null)
                local_ids.add(local_id);
        }
        return local_ids;
    }
    
    private async void append_new_email_async(string query, Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> local_ids = yield folder_ids_to_search_async(
            folder, ids, cancellable);
        
        int result_mutex_token = yield result_mutex.claim_async();
        Error? error = null;
        try {
            Gee.Collection<Geary.Email>? results = yield account.local_search_async(
                query, Geary.Email.Field.PROPERTIES, false, path, MAX_RESULT_EMAILS, 0,
                exclude_folders, local_ids, cancellable);
            
            if (results != null) {
                Gee.HashMap<Geary.EmailIdentifier, Geary.Email> to_add
                    = new Gee.HashMap<Geary.EmailIdentifier, Geary.Email>();
                foreach(Geary.Email email in results)
                    if (!search_results.contains(email))
                        to_add.set(email.id, email);
                
                if (to_add.size > 0) {
                    search_results.add_all(to_add.values);
                    
                    _properties.set_total(search_results.size);
                    
                    notify_email_appended(to_add.keys);
                    notify_email_count_changed(search_results.size, CountChangeReason.APPENDED);
                }
            }
        } catch(Error e) {
            error = e;
        }
        
        result_mutex.release(ref result_mutex_token);
        
        if (error != null)
            throw error;
    }
    
    private void on_append_new_email_complete(Object? source, AsyncResult result) {
        try {
            append_new_email_async.end(result);
        } catch(Error e) {
            debug("Error appending new email to search results: %s", e.message);
        }
    }
    
    private void on_email_locally_complete(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> ids) {
        if (search_query != null)
            append_new_email_async.begin(search_query, folder, ids, null, on_append_new_email_complete);
    }
    
    /**
     * Clears the search query and results.
     */
    public void clear() {
        Gee.TreeSet<Geary.Email> local_results = search_results;
        clear_search_results();
        notify_email_removed(email_collection_to_ids(local_results));
        notify_email_count_changed(0, Geary.Folder.CountChangeReason.REMOVED);
        
        if (search_query != null) {
            search_query = null;
            search_query_changed(null);
        }
    }
    
    /**
     * Sets the keyword string for this search.
     */
    public void set_search_query(string query, Cancellable? cancellable = null) {
        set_search_query_async.begin(query, cancellable, on_set_search_query_complete);
    }
    
    private void on_set_search_query_complete(Object? source, AsyncResult result) {
        try {
            set_search_query_async.end(result);
        } catch(Error e) {
            debug("Search error: %s", e.message);
        }
    }
    
    private async void set_search_query_async(string query, Cancellable? cancellable = null) throws Error {
        int result_mutex_token = yield result_mutex.claim_async();
        Error? error = null;
        try {
            // TODO: don't limit this to MAX_RESULT_EMAILS.  Instead, we could
            // be smarter about only fetching the search results in
            // list_email_async() etc., but this leads to some more
            // complications when redoing the search.
            Gee.Collection<Geary.Email>? _new_results = yield account.local_search_async(
                query, Geary.Email.Field.PROPERTIES, false, path, MAX_RESULT_EMAILS, 0,
                exclude_folders, null, cancellable);
            
            if (_new_results == null) {
                // No results?  Remove all existing results and return early.  If there are no
                // existing results, there's nothing to do.
                if (search_results.size > 0) {
                    Gee.TreeSet<Geary.Email> local_results = search_results;
                    // Clear existing results.
                    clear_search_results();
                    
                    // Note that we probably shouldn't be firing these signals
                    // from inside our mutex lock.  We do it here, below, and
                    // in append_new_email_async().  Keep an eye on it, and if
                    // there's ever a case where it might cause problems, it
                    // shouldn't be too hard to move the firings outside.
                    notify_email_removed(email_collection_to_ids(local_results));
                    notify_email_count_changed(0, Geary.Folder.CountChangeReason.REMOVED);
                }
            } else {
                // Move new search results into a hashset, using email ID for equality.
                Gee.HashSet<Geary.Email> new_results = new Gee.HashSet<Geary.Email>(email_id_hash, email_id_equal);
                new_results.add_all(_new_results);
                
                // Match the new results up with the existing results.
                Gee.HashSet<Geary.Email> to_add = new Gee.HashSet<Geary.Email>(email_id_hash, email_id_equal);
                Gee.HashSet<Geary.Email> to_remove = new Gee.HashSet<Geary.Email>(email_id_hash, email_id_equal);
                
                foreach(Geary.Email email in new_results)
                    if (!search_results.contains(email))
                        to_add.add(email);
                
                foreach(Geary.Email email in search_results)
                    if (!new_results.contains(email))
                        to_remove.add(email);
                
                search_results.remove_all(to_remove);
                search_results.add_all(to_add);
                
                _properties.set_total(search_results.size);
                
                Geary.Folder.CountChangeReason reason = CountChangeReason.NONE;
                
                if (to_add.size > 0) {
                    reason |= Geary.Folder.CountChangeReason.INSERTED;
                }
                
                if (to_remove.size > 0) {
                    notify_email_removed(email_collection_to_ids(to_remove));
                    reason |= Geary.Folder.CountChangeReason.REMOVED;
                }
                
                if (reason != CountChangeReason.NONE)
                    notify_email_count_changed(search_results.size, reason);
            }
        } catch(Error e) {
            error = e;
        }
        
        result_mutex.release(ref result_mutex_token);
        
        search_query = query;
        search_query_changed(query);
        
        if (error != null)
            throw error;
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        if (low >= 0)
            error("Search folder can't list email positionally");
        
        // TODO:
        // * This is a temporary implementation that can't handle positional addressing.
        // * Fetch emails as a batch, not one at a time.
        int result_mutex_token = yield result_mutex.claim_async();
        
        Gee.List<Geary.Email> results = new Gee.ArrayList<Geary.Email>();
        Error? error = null;
        try {
            int i = 0;
            foreach(Geary.Email email in search_results) {
                results.add(yield fetch_email_async(email.id, required_fields, flags, cancellable));
                
                i++;
                if (count > 0 && i >= count)
                    break;
            }
        } catch(Error e) {
            error = e;
        }
        
        result_mutex.release(ref result_mutex_token);
        
        if (error != null)
            throw error;
        
        return (results.size == 0 ? null : results);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        // TODO: as above, this is incomplete and inefficient.
        int result_mutex_token = yield result_mutex.claim_async();
        
        Geary.EmailIdentifier[] ids = new Geary.EmailIdentifier[search_results.size];
        int initial_index = -1;
        int i = 0;
        foreach (Geary.Email email in search_results) {
            if (email.id.equal_to(initial_id))
                initial_index = i;
            ids[i++] = email.id;
        }
        
        Gee.List<Geary.Email> results = new Gee.ArrayList<Geary.Email>();
        Error? error = null;
        if (initial_index >= 0) {
            try {
                // A negative count means we walk forwards in our array and
                // vice versa.
                int real_count = count.abs();
                int increment = (count < 0 ? 1 : -1);
                i = initial_index;
                if ((flags & Folder.ListFlags.EXCLUDING_ID) != 0)
                    i += increment;
                else
                    ++real_count;
                int end = i + real_count * increment;
                
                for (; i >= 0 && i < search_results.size && i != end; i += increment)
                    results.add(yield fetch_email_async(ids[i], required_fields, flags, cancellable));
            } catch (Error e) {
                error = e;
            }
        }
        
        result_mutex.release(ref result_mutex_token);
        
        if (error != null)
            throw error;
        
        return (results.size == 0 ? null : results);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        // TODO: Fetch emails in a batch.
        Gee.List<Geary.Email> result = new Gee.ArrayList<Geary.Email>();
        foreach(Geary.EmailIdentifier id in ids)
            result.add(yield fetch_email_async(id, required_fields, flags, cancellable));
        
        return (result.size == 0 ? null : result);
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        // TODO: This method is not currently called, but is required by the interface.  Before completing
        // this feature, it should either be implemented either here or in AbstractLocalFolder. 
        error("Search folder does not implement list_local_email_fields_async");
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        return yield account.local_fetch_email_async(id, required_fields, cancellable);
    }
    
    /**
     * Given a list of mail IDs, returns a list of words that match for the current
     * search query.
     */
    public async Gee.Collection<string>? get_search_matches_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        if (search_query == null)
            return null;
        return yield account.get_search_matches_async(ids, cancellable);
    }
    
    private void exclude_folder(Geary.Folder folder) {
        exclude_folders.add(folder.path);
    }
    
    private void exclude_orphan_emails() {
        exclude_folders.add(null);
    }
    
    private uint email_id_hash(Geary.Email a) {
        return a.id.hash();
    }
    
    private bool email_id_equal(Geary.Email a, Geary.Email b) {
        return a.id.equal_to(b.id);
    }
    
    // Destroys existing results.
    private void clear_search_results() {
        search_results = new Gee.TreeSet<Geary.Email>(Geary.Email.compare_date_received_descending);
    }
    
    // Converts a collection of emails to a set of email ids.
    private Gee.Set<Geary.EmailIdentifier> email_collection_to_ids(Gee.Collection<Geary.Email> collection) {
        Gee.HashSet<Geary.EmailIdentifier> ids = new Gee.HashSet<Geary.EmailIdentifier>();
        foreach(Geary.Email email in collection)
            ids.add(email.id);
        
        return ids;
    }
}

