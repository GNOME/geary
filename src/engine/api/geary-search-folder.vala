/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Special local {@link Folder} used to query and display search results of {@link Email} from
 * across the {@link Account}'s local storage.
 *
 * SearchFolder is merely specified to be a Folder, but implementations may add various
 * {@link FolderSupport} interfaces.  In particular {@link FolderSupport.Remove} should be supported,
 * but again, is not required.
 *
 * SearchFolder is expected to produce {@link EmailIdentifier}s which can be accepted by other
 * Folders within the Account (with the exception of the Outbox).  Those Folders may need to
 * translate those EmailIdentifiers to their own type for ordering reasons, but in general the
 * expectation is that the results of SearchFolder can then be applied to operations on Email in
 * other remote-backed folders.
 */

public abstract class Geary.SearchFolder : Geary.AbstractLocalFolder {
    private weak Account _account;
    public override Account account { get { return _account; } }
    
    private FolderProperties _properties;
    public override FolderProperties properties { get { return _properties; } }
    
    private FolderPath? _path = null;
    public override FolderPath path { get { return _path; } }
    
    public override SpecialFolderType special_folder_type {
        get {
            return Geary.SpecialFolderType.SEARCH;
        }
    }
    
    public Geary.SearchQuery? search_query { get; protected set; default = null; }
    
    /**
     * Fired when the search query has changed.  This signal is fired *after* the search
     * has completed.
     */
    public signal void search_query_changed(Geary.SearchQuery? query);
    
    protected SearchFolder(Account account, FolderProperties properties, FolderPath path) {
        _account = account;
        _properties = properties;
        _path = path;
    }
    
    protected virtual void notify_search_query_changed(SearchQuery? query) {
        search_query_changed(query);
    }
    
    /**
     * Sets the keyword string for this search.
     *
     * This is a nonblocking call that initiates a background search which can be stopped with the
     * supplied Cancellable.
     *
     * When the search is completed, {@link search_query_changed} will be fired.  It's possible for
     * the {@link search_query} property to change before completion.
     */
    public abstract void search(string query, SearchQuery.Strategy strategy, Cancellable? cancellable = null);
    
    /**
     * Clears the search query and results.
     *
     * {@link search_query_changed} will be fired and {@link search_query} will be set to null.
     */
    public abstract void clear();
    
    /**
     * Given a list of mail IDs, returns a set of casefolded words that match for the current
     * search query.
     */
    public abstract async Gee.Set<string>? get_search_matches_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error;
}

