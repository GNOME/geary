/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A local folder to execute and collect results of search queries.
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
 *
 * @see SearchQuery
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


    /** The query being evaluated by this folder, if any. */
    public Geary.SearchQuery? query { get; protected set; default = null; }

    /** Emitted when the current query has been fully evaluated. */
    public signal void query_evaluation_complete();


    protected SearchFolder(Account account, FolderProperties properties, FolderPath path) {
        _account = account;
        _properties = properties;
        _path = path;
    }

    /**
     * Sets the query to be evaluated for this folder.
     *
     * Executes an asynchronous search, which can be stopped via the
     * supplied cancellable. When the search is complete, {@link
     * query_evaluation_complete} will be emitted. if an error occurs,
     * the signal will not be invoked. It is possible for the {@link
     * query} property to change before completion.
     */
    public abstract async void search(SearchQuery query,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Clears the search query and results.
     *
     * The {@link query_evaluation_complete} signal will be emitted
     * and {@link query} will be set to null.
     */
    public abstract void clear();

    /**
     * Returns a set of case-folded words matched by the current query.
     *
     * The set contains words from the given collection of email that
     * match any of the non-negated text operators in {@link query}.
     */
    public abstract async Gee.Set<string>? get_search_matches_async(
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

}
