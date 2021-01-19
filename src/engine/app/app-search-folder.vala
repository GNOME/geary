/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A folder for executing and listing an account-wide email search.
 *
 * This uses the search methods on {@link Account} to implement the
 * search, then collects search results and presents them via the
 * folder interface.
 */
public class Geary.App.SearchFolder :
    AbstractLocalFolder, FolderSupport.Remove {


    /** Number of messages to include in the initial search. */
    public const int MAX_RESULT_EMAILS = 1000;

    /** The canonical name of the search folder. */
    public const string MAGIC_BASENAME = "$GearyAccountSearchFolder$";

    private const Folder.SpecialUse[] EXCLUDE_TYPES = {
        DRAFTS,
        JUNK,
        TRASH,
        // Orphan emails (without a folder) are also excluded; see ctor.
    };


    private class FolderPropertiesImpl : FolderProperties {


        public FolderPropertiesImpl(int total, int unread) {
            base(total, unread, Trillian.FALSE, Trillian.FALSE, Trillian.TRUE, true, true, false);
        }

        public void set_total(int total) {
            this.email_total = total;
        }

    }


    // Represents an entry in the folder. Does not implement
    // Gee.Comparable since that would require extending GLib.Object
    // and hence make them very heavyweight.
    private class EmailEntry {


        public static int compare_to(EmailEntry a, EmailEntry b) {
            int cmp = 0;
            if (a != b && a.id != b.id && !a.id.equal_to(b.id)) {
                cmp = a.received.compare(b.received);
                if (cmp == 0) {
                    cmp = a.id.stable_sort_comparator(b.id);
                }
            }
            return cmp;
        }


        public EmailIdentifier id;
        public GLib.DateTime received;


        public EmailEntry(EmailIdentifier id, GLib.DateTime received) {
            this.id = id;
            this.received = received;
        }

    }


    /** {@inheritDoc} */
    public override Account account {
        get { return _account; }
    }
    private weak Account _account;

    /** {@inheritDoc} */
    public override FolderProperties properties {
        get { return _properties; }
    }
    private FolderPropertiesImpl _properties;

    /** {@inheritDoc} */
    public override FolderPath path {
        get { return _path; }
    }
    private FolderPath? _path = null;

    /**
     * {@inheritDoc}
     *
     * Always returns {@link Folder.SpecialUse.SEARCH}.
     */
    public override Folder.SpecialUse used_as {
        get { return SEARCH; }
    }

    /** The query being evaluated by this folder, if any. */
    public SearchQuery? query { get; protected set; default = null; }

    // Folders that should be excluded from search
    private Gee.HashSet<FolderPath?> exclude_folders =
        new Gee.HashSet<FolderPath?>();

    // The email present in the folder, sorted
    private Gee.SortedSet<EmailEntry> entries;

    // Map of engine ids to search ids
    private Gee.Map<EmailIdentifier,EmailEntry> ids;

    private Nonblocking.Mutex result_mutex = new Nonblocking.Mutex();

    private GLib.Cancellable executing = new GLib.Cancellable();


    public SearchFolder(Account account, FolderRoot root) {
        this._account = account;
        this._properties = new FolderPropertiesImpl(0, 0);
        this._path = root.get_child(MAGIC_BASENAME, Trillian.TRUE);

        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.folders_use_changed.connect(on_folders_use_changed);
        account.email_locally_complete.connect(on_email_locally_complete);
        account.email_removed.connect(on_account_email_removed);
        account.email_locally_removed.connect(on_account_email_removed);

        this.entries = new_entry_set();
        this.ids = new_id_map();

        // Always exclude emails that don't live anywhere from search
        // results.
        exclude_orphan_emails();
    }

    ~SearchFolder() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.folders_use_changed.disconnect(on_folders_use_changed);
        account.email_locally_complete.disconnect(on_email_locally_complete);
        account.email_removed.disconnect(on_account_email_removed);
        account.email_locally_removed.disconnect(on_account_email_removed);
    }

    /**
     * Sets the current search query for the folder.
     *
     * Calling this method will start the search folder asynchronously
     * in the background. If the given query is not equal to the
     * existing query, the folder's contents will be updated to
     * reflect the changed query.
     */
    public void update_query(SearchQuery query) {
        if (this.query == null || !this.query.equal_to(query)) {
            this.executing.cancel();
            this.executing = new GLib.Cancellable();

            this.query = query;
            this.update.begin();
        }
    }

    /**
     * Cancels and clears the search query and results.
     *
     * The {@link query} property will be set to null.
     */
    public void clear_query() {
        this.executing.cancel();
        this.executing = new GLib.Cancellable();

        this.query = null;
        var old_ids = this.ids;

        this.entries = new_entry_set();
        this.ids = new_id_map();

        notify_email_removed(old_ids.keys);
        notify_email_count_changed(0, REMOVED);
    }

    /**
     * Returns a set of case-folded words matched by the current query.
     *
     * The set contains words from the given collection of email that
     * match any of the non-negated text operators in {@link query}.
     */
    public async Gee.Set<string>? get_search_matches_async(
        Gee.Collection<EmailIdentifier> targets,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        Gee.Set<string>? results = null;
        if (this.query != null) {
            results = yield account.get_search_matches_async(
                this.query, check_ids(targets), cancellable
            );
        }
        return results;
    }

    /** {@inheritDoc} */
    public override async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        debug("Waiting for checking contains");
        int result_mutex_token = yield this.result_mutex.claim_async(cancellable);
        var existing_ids = this.ids;
        result_mutex.release(ref result_mutex_token);

        debug("Checking contains");
        return Geary.traverse(
            ids
        ).filter(
            (id) => existing_ids.has_key(id)
        ).to_hash_set();
    }

    public override async Gee.List<Email>? list_email_by_id_async(
        EmailIdentifier? initial_id,
        int count,
        Email.Field required_fields,
        Folder.ListFlags flags,
        Cancellable? cancellable = null
    ) throws GLib.Error {
        debug("Waiting to list email");
        int result_mutex_token = yield this.result_mutex.claim_async(cancellable);
        var existing_entries = this.entries;
        var existing_ids = this.ids;
        result_mutex.release(ref result_mutex_token);

        debug("Listing email");
        var engine_ids = new Gee.LinkedList<EmailIdentifier>();

        if (Folder.ListFlags.OLDEST_TO_NEWEST in flags) {
            EmailEntry? oldest = null;
            if (!existing_entries.is_empty) {
                if (initial_id == null) {
                    oldest = existing_entries.last();
                } else {
                    oldest = existing_ids.get(initial_id);

                    if (oldest == null) {
                        throw new EngineError.NOT_FOUND(
                            "Initial id not found: %s", initial_id.to_string()
                        );
                    }

                    if (!(Folder.ListFlags.INCLUDING_ID in flags)) {
                        oldest = existing_entries.higher(oldest);
                    }
                }
            }
            if (oldest != null) {
                var iter = (
                    existing_entries.iterator_at(oldest) as
                    Gee.BidirIterator<EmailEntry>
                );
                engine_ids.add(oldest.id);
                while (engine_ids.size < count && iter.previous()) {
                    engine_ids.add(iter.get().id);
                }
            }
        } else {
            // Newest to oldest
            EmailEntry? newest = null;
            if (!existing_entries.is_empty) {
                if (initial_id == null) {
                    newest = existing_entries.first();
                } else {
                    newest = existing_ids.get(initial_id);

                    if (newest == null) {
                        throw new EngineError.NOT_FOUND(
                            "Initial id not found: %s", initial_id.to_string()
                        );
                    }

                    if (!(Folder.ListFlags.INCLUDING_ID in flags)) {
                        newest = existing_entries.lower(newest);
                    }
                }
            }
            if (newest != null) {
                var iter = (
                    existing_entries.iterator_at(newest) as
                    Gee.BidirIterator<EmailEntry>
                );
                engine_ids.add(newest.id);
                while (engine_ids.size < count && iter.next()) {
                    engine_ids.add(iter.get().id);
                }
            }
        }

        Gee.List<Email>? results = null;
        GLib.Error? list_error = null;
        if (!engine_ids.is_empty) {
            try {
                results = yield this.account.list_local_email_async(
                    engine_ids,
                    required_fields,
                    cancellable
                );
            } catch (GLib.Error error) {
                list_error = error;
            }
        }

        if (list_error != null) {
            throw list_error;
        }

        return results;
    }

    public override async Gee.List<Email>? list_email_by_sparse_id_async(
        Gee.Collection<EmailIdentifier> list,
        Email.Field required_fields,
        Folder.ListFlags flags,
        Cancellable? cancellable = null
    ) throws GLib.Error {
        return yield this.account.list_local_email_async(
            check_ids(list), required_fields, cancellable
        );
    }

    public override async Email fetch_email_async(EmailIdentifier fetch,
                                                  Email.Field required_fields,
                                                  Folder.ListFlags flags,
                                                  GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        require_id(fetch);
        return yield this.account.local_fetch_email_async(
            fetch, required_fields, cancellable
        );
    }

    public virtual async void remove_email_async(
        Gee.Collection<EmailIdentifier> remove,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        Gee.MultiMap<EmailIdentifier,FolderPath>? ids_to_folders =
            yield account.get_containing_folders_async(
                check_ids(remove), cancellable
            );
        if (ids_to_folders != null) {
            Gee.MultiMap<FolderPath,EmailIdentifier> folders_to_ids =
                Collection.reverse_multi_map<EmailIdentifier,FolderPath>(
                    ids_to_folders
                );

            foreach (FolderPath path in folders_to_ids.get_keys()) {
                Folder folder = account.get_folder(path);
                FolderSupport.Remove? removable = folder as FolderSupport.Remove;
                if (removable != null) {
                    Gee.Collection<EmailIdentifier> ids = folders_to_ids.get(path);

                    debug("Search folder removing %d emails from %s", ids.size, folder.to_string());

                    bool open = false;
                    try {
                        yield folder.open_async(NONE, cancellable);
                        open = true;
                        yield removable.remove_email_async(ids, cancellable);
                    } finally {
                        if (open) {
                            try {
                                yield folder.close_async();
                            } catch (Error e) {
                                debug("Error closing folder %s: %s", folder.to_string(), e.message);
                            }
                        }
                    }
                }
            }
        }
    }

    public override void set_used_as_custom(bool enabled)
        throws EngineError.UNSUPPORTED {
        throw new EngineError.UNSUPPORTED("Folder special use cannot be changed");
    }

    private void require_id(EmailIdentifier id)
        throws EngineError.NOT_FOUND {
        if (!this.ids.has_key(id)) {
            throw new EngineError.NOT_FOUND(
                "Id not found: %s", id.to_string()
            );
        }
    }

    private Gee.List<EmailIdentifier> check_ids(
        Gee.Collection<EmailIdentifier> to_check
    ) {
        var available = new Gee.LinkedList<EmailIdentifier>();
        var ids = this.ids;
        var iter = to_check.iterator();
        while (iter.next()) {
            var id = iter.get();
            if (ids.has_key(id)) {
                available.add(id);
            }
        }
        return available;
    }

    private async void append(Folder folder,
                              Gee.Collection<EmailIdentifier> ids) {
        // Grab the cancellable before the lock so that if the current
        // search is cancelled while waiting, this doesn't go and try
        // to update the new results.
        var cancellable = this.executing;

        debug("Waiting to append to search results");
        try {
            int result_mutex_token = yield this.result_mutex.claim_async(
                cancellable
            );
            try {
                if (!this.exclude_folders.contains(folder.path)) {
                    yield do_search_async(ids, null, cancellable);
                }
            } catch (GLib.Error error) {
                this.account.report_problem(
                    new AccountProblemReport(this.account.information, error)
                );
            }

            this.result_mutex.release(ref result_mutex_token);
        } catch (GLib.IOError.CANCELLED mutex_err) {
            // all good
        } catch (GLib.Error mutex_err) {
            warning("Error acquiring lock: %s", mutex_err.message);
        }
    }

    private async void update() {
        // Grab the cancellable before the lock so that if the current
        // search is cancelled while waiting, this doesn't go and try
        // to update the new results.
        var cancellable = this.executing;

        debug("Waiting to update search results");
        try {
            int result_mutex_token = yield this.result_mutex.claim_async(
                cancellable
            );
            try {
                yield do_search_async(null, null, cancellable);
            } catch (GLib.Error error) {
                this.account.report_problem(
                    new AccountProblemReport(this.account.information, error)
                );
            }

            this.result_mutex.release(ref result_mutex_token);
        } catch (GLib.IOError.CANCELLED mutex_err) {
            // all good
        } catch (GLib.Error mutex_err) {
            warning("Error acquiring lock: %s", mutex_err.message);
        }
    }

    private async void remove(Folder folder,
                              Gee.Collection<EmailIdentifier> ids) {

        // Grab the cancellable before the lock so that if the current
        // search is cancelled while waiting, this doesn't go and try
        // to update the new results.
        var cancellable = this.executing;

        debug("Waiting to remove from search results");
        try {
            int result_mutex_token = yield this.result_mutex.claim_async(
                cancellable
            );

            // Ensure this happens inside the lock so it is working with
            // up-to-date data
            var id_map = this.ids;
            var relevant_ids = (
                traverse(ids)
                .filter(id => id_map.has_key(id))
                .to_linked_list()
            );
            if (relevant_ids.size > 0) {
                try {
                    yield do_search_async(null, relevant_ids, cancellable);
                } catch (GLib.Error error) {
                    this.account.report_problem(
                        new AccountProblemReport(this.account.information, error)
                    );
                }
            }

            this.result_mutex.release(ref result_mutex_token);
        } catch (GLib.IOError.CANCELLED mutex_err) {
            // all good
        } catch (GLib.Error mutex_err) {
            warning("Error acquiring lock: %s", mutex_err.message);
        }
    }

    // NOTE: you must call this ONLY after locking result_mutex_token.
    // If both *_ids parameters are null, the results of this search are
    // considered to be the full new set.  If non-null, the results are
    // considered to be a delta and are added or subtracted from the full set.
    // add_ids are new ids to search for, remove_ids are ids in our result set
    // and will be removed.
    private async void do_search_async(Gee.Collection<EmailIdentifier>? add_ids,
                                       Gee.Collection<EmailIdentifier>? remove_ids,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("Processing search results");
        var entries = new_entry_set();
        var ids = new_id_map();
        var added = new Gee.LinkedList<EmailIdentifier>();
        var removed = new Gee.LinkedList<EmailIdentifier>();

        entries.add_all(this.entries);
        ids.set_all(this.ids);

        if (remove_ids == null) {
            // Adding email to the search, either searching all local
            // email if to_add is null, or adding only a matching
            // subset of the given in to_add
            //
            // TODO: don't limit this to MAX_RESULT_EMAILS.  Instead,
            // we could be smarter about only fetching the search
            // results in list_email_async() etc., but this leads to
            // some more complications when redoing the search.
            Gee.Collection<EmailIdentifier>? id_results =
                yield this.account.local_search_async(
                    this.query,
                    MAX_RESULT_EMAILS,
                    0,
                    this.exclude_folders,
                    add_ids, // If null, will search all local email
                    cancellable
                );

            if (id_results != null) {
                // Fetch email to get the received date for
                // correct ordering in the search folder
                Gee.Collection<Email> email_results =
                    yield this.account.list_local_email_async(
                        id_results,
                        PROPERTIES,
                        cancellable
                    );

                if (add_ids == null) {
                    // Not appending new email, so remove any not
                    // found in the results. Add to a set first to
                    // avoid O(N^2) lookup complexity.
                    var hashed_results = new Gee.HashSet<EmailIdentifier>();
                    hashed_results.add_all(id_results);

                    var existing = ids.map_iterator();
                    while (existing.next()) {
                        if (!hashed_results.contains(existing.get_key())) {
                            var entry = existing.get_value();
                            existing.unset();
                            entries.remove(entry);
                            removed.add(entry.id);
                        }
                    }
                }

                foreach (var email in email_results) {
                    if (!ids.has_key(email.id)) {
                        var entry = new EmailEntry(
                            email.id, email.properties.date_received
                        );
                        entries.add(entry);
                        ids.set(email.id, entry);
                        added.add(email.id);
                    }
                }
            }
        } else {
            // Removing email, can just remove them directly
            foreach (var id in remove_ids) {
                EmailEntry entry;
                if (ids.unset(id, out entry)) {
                    entries.remove(entry);
                    removed.add(id);
                }
            }
        }

        if (!cancellable.is_cancelled()) {
            this.entries = entries;
            this.ids = ids;

            this._properties.set_total(entries.size);

            // Note that we probably shouldn't be firing these signals from inside
            // our mutex lock.  Keep an eye on it, and if there's ever a case where
            // it might cause problems, it shouldn't be too hard to move the
            // firings outside.

            Folder.CountChangeReason reason = CountChangeReason.NONE;
            if (removed.size > 0) {
                notify_email_removed(removed);
                reason |= Folder.CountChangeReason.REMOVED;
            }
            if (added.size > 0) {
                // TODO: we'd like to be able to use APPENDED here
                // when applicable, but because of the potential to
                // append a thousand results at once and the
                // ConversationMonitor's inability to handle that
                // gracefully (#7464), we always use INSERTED for now.
                notify_email_inserted(added);
                reason |= Folder.CountChangeReason.INSERTED;
            }
            if (reason != CountChangeReason.NONE) {
                notify_email_count_changed(this.entries.size, reason);
            }
            debug("Processing done, entries/ids: %d/%d", entries.size, ids.size);
        } else {
            debug("Processing cancelled, dropping entries/ids: %d/%d", entries.size, ids.size);
        }
    }

    private inline Gee.SortedSet<EmailEntry> new_entry_set() {
        return new Gee.TreeSet<EmailEntry>(EmailEntry.compare_to);
    }

    private inline Gee.Map<EmailIdentifier,EmailEntry> new_id_map() {
        return new Gee.HashMap<EmailIdentifier,EmailEntry>();
    }

    private void include_folder(Folder folder) {
        this.exclude_folders.remove(folder.path);
    }

    private void exclude_folder(Folder folder) {
        this.exclude_folders.add(folder.path);
    }

    private void exclude_orphan_emails() {
        this.exclude_folders.add(null);
    }

    private void on_folders_available_unavailable(
        Gee.Collection<Folder>? available,
        Gee.Collection<Folder>? unavailable
    ) {
        if (available != null) {
            // Exclude it from searching if it's got the right special type.
            foreach(var folder in traverse<Folder>(available)
                .filter(f => f.used_as in EXCLUDE_TYPES))
                exclude_folder(folder);
        }
    }

    private void on_folders_use_changed(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.used_as in EXCLUDE_TYPES) {
                exclude_folder(folder);
            } else {
                include_folder(folder);
            }
        }
    }

    private void on_email_locally_complete(Folder folder,
                                           Gee.Collection<EmailIdentifier> ids) {
        if (this.query != null) {
            this.append.begin(folder, ids);
        }
    }

    private void on_account_email_removed(Folder folder,
                                          Gee.Collection<EmailIdentifier> ids) {
        if (this.query != null) {
            this.remove.begin(folder, ids);
        }
    }

}
