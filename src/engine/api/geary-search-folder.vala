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
    
    public override Account account { get { return _account; } }
    
    private static FolderRoot? path = null;
    
    private weak Account _account;
    private SearchFolderProperties properties = new SearchFolderProperties(0, 0);
    private Gee.HashSet<Geary.FolderPath?> exclude_folders = new Gee.HashSet<Geary.FolderPath?>();
    private Geary.SpecialFolderType[] exclude_types = {
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
        // Orphan emails (without a folder) are also excluded; see ctor.
    };
    private Gee.TreeSet<Geary.Email> search_results;
    private Geary.Nonblocking.Mutex result_mutex = new Geary.Nonblocking.Mutex();
    
    /**
     * Fired when the search keywords have changed.
     */
    public signal void search_keywords_changed(string keywords);
    
    public SearchFolder(Account account) {
        _account = account;
        
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        
        clear_search_results();
        
        // We always want to exclude emails that don't live anywhere from
        // search results.
        exclude_orphan_emails();
    }
    
    ~SearchFolder() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);;
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        if (available != null) {
            foreach (Geary.Folder folder in available) {
                // Exclude it from searching if it's got the right special type.
                if (folder.get_special_folder_type() in exclude_types)
                    exclude_folder(folder);
            }
        }
    }
    
    /**
     * Sets the keyword string for this search.
     */
    public void set_search_keywords(string keywords, Cancellable? cancellable = null) {
        search_keywords_changed(keywords);
        set_search_keywords_async.begin(keywords, cancellable, on_set_search_keywords_complete);
    }
    
    private void on_set_search_keywords_complete(Object? source, AsyncResult result) {
        try {
            set_search_keywords_async.end(result);
        } catch(Error e) {
            debug("Search error: %s", e.message);
        }
    }
    
    private async void set_search_keywords_async(string keywords, Cancellable? cancellable = null) throws Error {
        int result_mutex_token = yield result_mutex.claim_async();
        Error? error = null;
        try {
            // TODO: don't limit this to MAX_RESULT_EMAILS.  Instead, we could
            // be smarter about only fetching the search results in
            // list_email_async() etc., but this leads to some more
            // complications when redoing the search.
            Gee.Collection<Geary.Email>? _new_results = yield account.local_search_async(
                keywords, Geary.Email.Field.PROPERTIES, false, MAX_RESULT_EMAILS, 0,
                exclude_folders, null, cancellable);
            
            if (_new_results == null) {
                // No results?  Remove all existing results and return early.  If there are no
                // existing results, there's nothing to do.
                if (search_results.size > 0) {
                    Gee.TreeSet<Geary.Email> local_results = search_results;
                    // Clear existing results.
                    clear_search_results();
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
        
        if (error != null)
            throw error;
    }
    
    public override Geary.FolderPath get_path() {
        if (path == null)
            path = new SearchFolderRoot();
        
        return path;
    }
    
    public override Geary.SpecialFolderType get_special_folder_type() {
        return Geary.SpecialFolderType.SEARCH;
    }
    
    public override Geary.FolderProperties get_properties() {
        return properties;
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
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
        // TODO: This method is not currently called, but is required by the interface.  Before completing
        // this feature, it should either be implemented either here or in AbstractLocalFolder. 
        error("Search folder does not implement list_email_by_id_async");
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
    
    private void exclude_folder(Geary.Folder folder) {
        exclude_folders.add(folder.get_path());
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

