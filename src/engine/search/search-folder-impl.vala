/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A default implementation of a search folder.
 *
 * This implementation of {@link Geary.SearchFolder} uses the search
 * methods on {@link Account} to implement account-wide email search.
 */
internal class Geary.Search.FolderImpl :
    Geary.SearchFolder, Geary.FolderSupport.Remove {


    /** Max number of emails that can ever be in the folder. */
    public const int MAX_RESULT_EMAILS = 1000;

    /** The canonical name of the search folder. */
    public const string MAGIC_BASENAME = "$GearySearchFolder$";

    private const Geary.SpecialFolderType[] EXCLUDE_TYPES = {
        Geary.SpecialFolderType.SPAM,
        Geary.SpecialFolderType.TRASH,
        Geary.SpecialFolderType.DRAFTS,
        // Orphan emails (without a folder) are also excluded; see ct or.
    };


    private class FolderProperties : Geary.FolderProperties {


        public FolderProperties(int total, int unread) {
            base(total, unread, Trillian.FALSE, Trillian.FALSE, Trillian.TRUE, true, true, false);
        }

        public void set_total(int total) {
            this.email_total = total;
        }

    }


    // Folders that should be excluded from search
    private Gee.HashSet<Geary.FolderPath?> exclude_folders =
        new Gee.HashSet<Geary.FolderPath?>();

    // The email present in the folder, sorted
    private Gee.TreeSet<EmailIdentifier> contents;

    // Map of engine ids to search ids
    private Gee.Map<Geary.EmailIdentifier,EmailIdentifier> id_map;

    private Geary.Nonblocking.Mutex result_mutex = new Geary.Nonblocking.Mutex();


    public FolderImpl(Geary.Account account, FolderRoot root) {
        base(
            account,
            new FolderProperties(0, 0),
            root.get_child(MAGIC_BASENAME, Trillian.TRUE)
        );

        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.folders_special_type.connect(on_folders_special_type);
        account.email_locally_complete.connect(on_email_locally_complete);
        account.email_removed.connect(on_account_email_removed);

        clear_contents();

        // We always want to exclude emails that don't live anywhere
        // from search results.
        exclude_orphan_emails();
    }

    ~FolderImpl() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.folders_special_type.disconnect(on_folders_special_type);
        account.email_locally_complete.disconnect(on_email_locally_complete);
        account.email_removed.disconnect(on_account_email_removed);
    }

    /**
     * Sets the keyword string for this search.
     */
    public override async void search(Geary.SearchQuery query,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        int result_mutex_token = yield result_mutex.claim_async();

        this.query = query;
        GLib.Error? error = null;
        try {
            yield do_search_async(null, null, cancellable);
        } catch(Error e) {
            error = e;
        }

        result_mutex.release(ref result_mutex_token);

        if (error != null) {
            throw error;
        }

        this.query_evaluation_complete();
    }

    /**
     * Clears the search query and results.
     */
    public override void clear() {
        var old_contents = this.contents;
        clear_contents();
        notify_email_removed(old_contents);
        notify_email_count_changed(0, Geary.Folder.CountChangeReason.REMOVED);

        if (this.query != null) {
            this.query = null;
            this.query_evaluation_complete();
        }
    }

    /**
     * Given a list of mail IDs, returns a set of casefolded words that match for the current
     * search query.
     */
    public override async Gee.Set<string>? get_search_matches_async(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        Gee.Set<string>? results = null;
        if (this.query != null) {
            results = yield account.get_search_matches_async(
                this.query,
                EmailIdentifier.to_source_ids(ids),
                cancellable
            );
        }
        return results;
    }

    public override async Gee.List<Email>? list_email_by_id_async(
        Geary.EmailIdentifier? initial_id,
        int count,
        Email.Field required_fields,
        Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null
    ) throws GLib.Error {
        int result_mutex_token = yield result_mutex.claim_async();

        var engine_ids = new Gee.LinkedList<Geary.EmailIdentifier>();

        if (Geary.Folder.ListFlags.OLDEST_TO_NEWEST in flags) {
            EmailIdentifier? oldest = null;
            if (!this.contents.is_empty) {
                if (initial_id == null) {
                    oldest = this.contents.last();
                } else {
                    oldest = this.id_map.get(initial_id);

                    if (oldest == null) {
                        throw new EngineError.NOT_FOUND(
                            "Initial id not found %s", initial_id.to_string()
                        );
                    }

                    if (!(Geary.Folder.ListFlags.INCLUDING_ID in flags)) {
                        oldest = contents.higher(oldest);
                    }
                }
            }
            if (oldest != null) {
                var iter = (
                    this.contents.iterator_at(oldest) as
                    Gee.BidirIterator<EmailIdentifier>
                );
                engine_ids.add(oldest.source_id);
                while (engine_ids.size < count && iter.previous()) {
                    engine_ids.add(iter.get().source_id);
                }
            }
        } else {
            // Newest to oldest
            EmailIdentifier? newest = null;
            if (!this.contents.is_empty) {
                if (initial_id == null) {
                    newest = this.contents.first();
                } else {
                    newest = this.id_map.get(initial_id);

                    if (newest == null) {
                        throw new EngineError.NOT_FOUND(
                            "Initial id not found %s", initial_id.to_string()
                        );
                    }

                    if (!(Geary.Folder.ListFlags.INCLUDING_ID in flags)) {
                        newest = contents.lower(newest);
                    }
                }
            }
            if (newest != null) {
                var iter = (
                    this.contents.iterator_at(newest) as
                    Gee.BidirIterator<EmailIdentifier>
                );
                engine_ids.add(newest.source_id);
                while (engine_ids.size < count && iter.next()) {
                    engine_ids.add(iter.get().source_id);
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

        result_mutex.release(ref result_mutex_token);

        if (list_error != null) {
            throw list_error;
        }

        return results;
    }

    public override async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields,
        Geary.Folder.ListFlags flags,
        Cancellable? cancellable = null
    ) throws GLib.Error {
        return yield this.account.list_local_email_async(
            EmailIdentifier.to_source_ids(ids),
            required_fields,
            cancellable
        );
    }

    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>? list_local_email_fields_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        // TODO: This method is not currently called, but is required by the interface.  Before completing
        // this feature, it should either be implemented either here or in AbstractLocalFolder.
        error("Search folder does not implement list_local_email_fields_async");
    }

    public override async Geary.Email fetch_email_async(Geary.EmailIdentifier id,
                                                        Geary.Email.Field required_fields,
                                                        Geary.Folder.ListFlags flags,
                                                        Cancellable? cancellable = null)
        throws GLib.Error {
        return yield this.account.local_fetch_email_async(
            EmailIdentifier.to_source_id(id), required_fields, cancellable
        );
    }

    public virtual async void remove_email_async(
        Gee.Collection<Geary.EmailIdentifier> email_ids,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? ids_to_folders =
            yield account.get_containing_folders_async(
                EmailIdentifier.to_source_ids(email_ids),
                cancellable
            );
        if (ids_to_folders != null) {
            Gee.MultiMap<Geary.FolderPath, Geary.EmailIdentifier> folders_to_ids =
                Geary.Collection.reverse_multi_map<Geary.EmailIdentifier, Geary.FolderPath>(ids_to_folders);

            foreach (Geary.FolderPath path in folders_to_ids.get_keys()) {
                Geary.Folder folder = account.get_folder(path);
                Geary.FolderSupport.Remove? remove = folder as Geary.FolderSupport.Remove;
                if (remove != null) {
                    Gee.Collection<Geary.EmailIdentifier> ids = folders_to_ids.get(path);

                    debug("Search folder removing %d emails from %s", ids.size, folder.to_string());

                    bool open = false;
                    try {
                        yield folder.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
                        open = true;
                        yield remove.remove_email_async(ids, cancellable);
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

    // NOTE: you must call this ONLY after locking result_mutex_token.
    // If both *_ids parameters are null, the results of this search are
    // considered to be the full new set.  If non-null, the results are
    // considered to be a delta and are added or subtracted from the full set.
    // add_ids are new ids to search for, remove_ids are ids in our result set
    // and will be removed.
    private async void do_search_async(Gee.Collection<Geary.EmailIdentifier>? add_ids,
                                       Gee.Collection<Geary.EmailIdentifier>? remove_ids,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        var id_map = this.id_map;
        var contents = this.contents;
        var added = new Gee.LinkedList<EmailIdentifier>();
        var removed = new Gee.LinkedList<EmailIdentifier>();

        if (remove_ids == null) {
            // Adding email to the search, either searching all local
            // email if to_add is null, or adding only a matching
            // subset of the given in to_add
            //
            // TODO: don't limit this to MAX_RESULT_EMAILS.  Instead,
            // we could be smarter about only fetching the search
            // results in list_email_async() etc., but this leads to
            // some more complications when redoing the search.
            Gee.Collection<Geary.EmailIdentifier>? id_results =
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
                    var hashed_results = new Gee.HashSet<Geary.EmailIdentifier>();
                    hashed_results.add_all(id_results);

                    var existing = id_map.map_iterator();
                    while (existing.next()) {
                        if (!hashed_results.contains(existing.get_key())) {
                            var search_id = existing.get_value();
                            existing.unset();
                            contents.remove(search_id);
                            removed.add(search_id);
                        }
                    }
                }

                foreach (var email in email_results) {
                    if (!id_map.has_key(email.id)) {
                        var search_id = new EmailIdentifier(
                            email.id, email.properties.date_received
                        );
                        id_map.set(email.id, search_id);
                        contents.add(search_id);
                        added.add(search_id);
                    }
                }
            }
        } else {
            // Removing email, can just remove them directly
            foreach (var id in remove_ids) {
                EmailIdentifier search_id;
                if (id_map.unset(id, out search_id)) {
                    contents.remove(search_id);
                    removed.add(search_id);
                }
            }
        }

        ((FolderProperties) this.properties).set_total(this.contents.size);

        // Note that we probably shouldn't be firing these signals from inside
        // our mutex lock.  Keep an eye on it, and if there's ever a case where
        // it might cause problems, it shouldn't be too hard to move the
        // firings outside.

        Geary.Folder.CountChangeReason reason = CountChangeReason.NONE;
        if (added.size > 0) {
            // TODO: we'd like to be able to use APPENDED here when applicable,
            // but because of the potential to append a thousand results at
            // once and the ConversationMonitor's inability to handle that
            // gracefully (#7464), we always use INSERTED for now.
            notify_email_inserted(added);
            reason |= Geary.Folder.CountChangeReason.INSERTED;
        }
        if (removed.size > 0) {
            notify_email_removed(removed);
            reason |= Geary.Folder.CountChangeReason.REMOVED;
        }
        if (reason != CountChangeReason.NONE)
            notify_email_count_changed(this.contents.size, reason);
    }

    private async void do_append(Geary.Folder folder,
                                 Gee.Collection<Geary.EmailIdentifier> ids,
                                 GLib.Cancellable? cancellable)
        throws GLib.Error {
        int result_mutex_token = yield result_mutex.claim_async();

        GLib.Error? error = null;
        try {
            if (!this.exclude_folders.contains(folder.path)) {
                yield do_search_async(ids, null, cancellable);
            }
        } catch (GLib.Error e) {
            error = e;
        }

        result_mutex.release(ref result_mutex_token);

        if (error != null)
            throw error;
    }

    private async void do_remove(Geary.Folder folder,
                                 Gee.Collection<Geary.EmailIdentifier> ids,
                                 GLib.Cancellable? cancellable)
        throws GLib.Error {
        int result_mutex_token = yield result_mutex.claim_async();

        GLib.Error? error = null;
        try {
            var id_map = this.id_map;
            var relevant_ids = (
                traverse(ids)
                .filter(id => id_map.has_key(id))
                .to_linked_list()
            );

            if (relevant_ids.size > 0) {
                yield do_search_async(null, relevant_ids, cancellable);
            }
        } catch (GLib.Error e) {
            error = e;
        }

        result_mutex.release(ref result_mutex_token);

        if (error != null)
            throw error;
    }

    private void clear_contents() {
        this.contents = new Gee.TreeSet<EmailIdentifier>(
            EmailIdentifier.compare_descending
        );
        this.id_map = new Gee.HashMap<Geary.EmailIdentifier,EmailIdentifier>();
    }

    private void include_folder(Geary.Folder folder) {
        this.exclude_folders.remove(folder.path);
    }

    private void exclude_folder(Geary.Folder folder) {
        this.exclude_folders.add(folder.path);
    }

    private void exclude_orphan_emails() {
        this.exclude_folders.add(null);
    }

    private void on_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        if (available != null) {
            // Exclude it from searching if it's got the right special type.
            foreach(Geary.Folder folder in Geary.traverse<Geary.Folder>(available)
                .filter(f => f.special_folder_type in EXCLUDE_TYPES))
                exclude_folder(folder);
        }
    }

    private void on_folders_special_type(Gee.Collection<Geary.Folder> folders) {
        foreach (Geary.Folder folder in folders) {
            if (folder.special_folder_type in EXCLUDE_TYPES) {
                exclude_folder(folder);
            } else {
                include_folder(folder);
            }
        }
    }

    private void on_email_locally_complete(Geary.Folder folder,
                                           Gee.Collection<Geary.EmailIdentifier> ids) {
        if (this.query != null) {
            this.do_append.begin(
                folder, ids, null,
                (obj, res) => {
                    try {
                        this.do_append.end(res);
                    } catch (GLib.Error error) {
                        this.account.report_problem(
                            new Geary.AccountProblemReport(
                                this.account.information, error
                            )
                        );
                    }
                }
            );
        }
    }

    private void on_account_email_removed(Geary.Folder folder,
                                          Gee.Collection<Geary.EmailIdentifier> ids) {
        if (this.query != null) {
            this.do_remove.begin(
                folder, ids, null,
                (obj, res) => {
                    try {
                        this.do_remove.end(res);
                    } catch (GLib.Error error) {
                        this.account.report_problem(
                            new Geary.AccountProblemReport(
                                this.account.information, error
                            )
                        );
                    }
                }
            );
        }
    }

}
