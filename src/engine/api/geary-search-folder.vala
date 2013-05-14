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
    public override Account account { get { return _account; } }
    
    private static FolderRoot? path = null;
    
    private weak Account _account;
    private SearchFolderProperties properties = new SearchFolderProperties(0, 0);
    private Gee.HashSet<Geary.FolderPath> exclude_folders = new Gee.HashSet<Geary.FolderPath>();
    private Geary.SpecialFolderType[] exclude_types = { Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH };
    
    /**
     * Fired when the search keywords have changed.
     */
    public signal void search_keywords_changed(string keywords);
    
    public SearchFolder(Account account) {
        _account = account;
        
        // TODO: The exclusion system needs to watch for changes, since the special folders are
        // not always ready by the time this c'tor executes.
        foreach(Geary.SpecialFolderType type in exclude_types)
            exclude_special_folder(type);
    }
    
    /**
     * Sets the keyword string for this search.
     */
    public void set_search_keywords(string keywords) {
        search_keywords_changed(keywords);
        account.local_search_async.begin(keywords, exclude_folders, null, null, on_local_search_complete);
    }
    
    private void on_local_search_complete(Object? source, AsyncResult result) {
        Gee.Collection<Geary.EmailIdentifier>? search_results = null;
        try {
            search_results = account.local_search_async.end(result);
        } catch (Error e) {
            debug("Error gathering search results: %s", e.message);
        }
        
        if (search_results != null)
            search_results.clear(); // TODO: something useful.
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
        return yield account.get_special_folder(Geary.SpecialFolderType.INBOX).list_email_async(low, count,
            required_fields, flags, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier initial_id,
        int count, Geary.Email.Field required_fields, Folder.ListFlags flags, Cancellable? cancellable = null)
        throws Error {
        return yield account.get_special_folder(Geary.SpecialFolderType.INBOX).list_email_by_id_async(initial_id,
            count, required_fields, flags, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        return yield account.get_special_folder(Geary.SpecialFolderType.INBOX).list_email_by_sparse_id_async(ids,
            required_fields, flags, cancellable);
    }
    
    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        return yield account.get_special_folder(Geary.SpecialFolderType.INBOX).list_local_email_fields_async(
            ids, cancellable);
    }
    
    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
        Geary.Email.Field required_fields, Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null) throws Error {
        return yield account.get_special_folder(Geary.SpecialFolderType.INBOX).fetch_email_async(id,
            required_fields, flags, cancellable);
    }
    
    private void exclude_special_folder(Geary.SpecialFolderType type) {
        Geary.Folder? folder = null;
        try {
            folder = account.get_special_folder(type);
        } catch (Error e) {
            debug("Could not get special folder: %s", e.message);
        }
        
        if (folder != null)
            exclude_folders.add(folder.get_path());
    }
}

