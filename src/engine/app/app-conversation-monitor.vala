/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018, 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Loads conversation in a folder and monitors changes to them.
 *
 * The standard IMAP model does not provide a means of easily
 * aggregating messages in a single conversation across mailboxes,
 * hence this class provides applications with a means of loading
 * complete conversations, one for each email message found in a
 * specified base folder. This is an expensive operation since it may
 * require opening several other folders to find all messages in the
 * conversation, and so the monitor is lazy and will only load enough
 * conversations to fill a minimal window size. Additional
 * conversations can be loaded afterwards as needed.
 *
 * When monitoring starts via a call to {@link
 * start_monitoring}, the folder will perform an initial
 * //scan// of messages in the base folder and load conversation load
 * based on that. Increasing {@link min_window_count} will cause
 * additional scan operations to be executed as needed to fill the new
 * window size.
 *
 * If the folder is backed by a remote mailbox, scans will be
 * local-only if the remote is not open so as to not block. However
 * this means any messages (and their conversations) that are not
 * sufficiently complete to satisfy both the monitor's and the owner's
 * email field requirements will not be found. If or when the folder
 * does open a remote connection, the folder will be re-scanned to
 * ensure any missing messages are picked up.
 *
 * The monitor will also keep track of messages being appended or
 * removed account-wide, so that known conversations can be updated as
 * needed.
 */
public class Geary.App.ConversationMonitor : BaseObject, Logging.Source {

    /**
     * The fields Conversations require to thread emails together.
     *
     * These fields will be retrieved regardless of the Field
     * parameter passed to the constructor.
     */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        Geary.Email.Field.REFERENCES |
        Geary.Email.Field.FLAGS |
        Geary.Email.Field.DATE
    );

    /** The GLib logging domain used by this class. */
    public const string LOGGING_DOMAIN = Logging.DOMAIN + ".Conv";


    private struct ProcessJobContext {

        public Gee.Map<Geary.EmailIdentifier,Geary.Email> emails;


        public ProcessJobContext() {
            this.emails = new Gee.HashMap<Geary.EmailIdentifier,Geary.Email>();
        }

    }


    /**
     * A read-only view of loaded conversations.
     *
     * Note that since background tasks may asynchronously update the
     * set at ant time, any asynchronous tasks carried out while
     * holding an returned by this method may allow the iterator to
     * become invalid.
     */
    public Gee.Set<Conversation> read_only_view {
        owned get { return this.conversations.read_only_view; }
    }

    /**
     * Number of conversations currently loaded by the monitor.
     */
    public int size { get { return this.conversations.size; } }

    /** Folder from which the conversation is originating. */
    public Folder base_folder { get; private set; }

    /** Determines if this monitor is monitoring the base folder. */
    public bool is_monitoring { get; private set; default = false; }

    /** Determines if more conversations should be loaded. */
    public bool should_load_more {
        get {
            return (this.conversations.size < this.min_window_count);
        }
    }

    /** Determines if more conversations can be loaded. */
    public bool can_load_more {
        get {
            return (
                this.base_folder.properties.email_total >
                this.folder_window_size
            ) && !this.fill_complete;
        }
    }

    /** Minimum number of emails large conversations should contain. */
    public int min_window_count {
        get { return _min_window_count; }
        set {
            _min_window_count = value;
            check_window_count();
        }
    }
    private int _min_window_count = 0;

    /** Indicates progress conversations are being loaded. */
    public ProgressMonitor progress_monitor {
        get; private set; default = new SimpleProgressMonitor(ProgressType.ACTIVITY);
    }

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent {
        get { return this.base_folder; }
    }

    /** The set of all conversations loaded by the monitor. */
    internal ConversationSet conversations { get; private set; }

    /** The number of messages currently loaded from the base folder. */
    internal uint folder_window_size {
        get {
            return (this.window.is_empty) ? 0 : this.window.size;
        }
    }

    /** The oldest message from the base folder in the loaded window. */
    internal EmailIdentifier? window_lowest {
        owned get {
            return (this.window.is_empty) ? null : this.window.first();
        }
    }

    /** Determines if the fill operation can load more messages. */
    internal bool fill_complete { get; set; default = false; }

    // Determines if the base folder was actually opened or not
    private bool base_was_opened = false;

    private Geary.Email.Field required_fields;
    private ConversationOperationQueue queue;
    private GLib.Cancellable operation_cancellable = new GLib.Cancellable();

    // Set of known, in-folder emails, explicitly loaded for the
    // monitor's window. This exists purely to support the window_size
    // and window_lowest properties above, but we need to maintain a
    // sorted set of all known messages since if the last known email
    // is removed, we won't know what the next lowest is. Only email
    // listed by one of the load_by_*_id methods are added here. Other
    // in-folder messages pulled in for a conversation aren't added,
    // since they may not be within the load window.
    private Gee.SortedSet<EmailIdentifier> window =
        new Gee.TreeSet<EmailIdentifier>((a,b) => {
            return a.natural_sort_comparator(b);
        });


    /**
     * Fired when a message load has started.
     *
     * Note that more than one load can be initiated, due to
     * Conversations being completely asynchronous. Both this, and
     * {@link scan_completed} will be fired for each individual load
     * request; that is, there is no internal counter to ensure only a
     * single completed signal is fired to indicate multiple loads
     * have finished.
     */
    public virtual signal void scan_started() {
        debug("scan_started");
    }

    /**
     * Fired when all extant message loads have completed.
     *
     * @see scan_started
     */
    public virtual signal void scan_completed() {
        debug("scan_completed");
    }

    /**
     * Fired when an error was encountered while loading messages.
     */
    public virtual signal void scan_error(Error err) {
        debug("scan_error: %s", err.message);
    }

    /**
     * Fired when one or more new conversations have been detected.
     *
     * This may be due to either a user-initiated load request or due
     * to background monitoring.
     */
    public virtual signal void conversations_added(Gee.Collection<Conversation> conversations) {
        debug("conversations_added: %d", conversations.size);
    }

    /**
     * Fired when all email in a conversation has been removed.
     *
     * It's possible this will be called without a signal alerting
     * that it's emails have been removed, i.e. a
     * "conversations-removed" signal may fire with no accompanying
     * "conversation-trimmed".
     *
     * This may be due to either a user-initiated load request or due
     * to background monitoring.
     */
    public virtual signal void conversations_removed(Gee.Collection<Conversation> conversations) {
        debug("conversations_removed: %d", conversations.size);
    }

    /**
     * Fired when one or more email have been added to a conversation.
     *
     * This may be due to either a user-initiated load request or due
     * to background monitoring.
     */
    public virtual signal void conversation_appended(Conversation conversation,
                                                     Gee.Collection<Email> email) {
        debug("conversation_appended");
    }

    /**
     * Fired when one or more email have been removed from a conversation.
     *
     * If the trimmed email is the last usable email in the
     * Conversation, this signal will be followed by
     * "conversation-removed".  However, it's possible for
     * "conversation-removed" to fire without "conversation-trimmed"
     * preceding it, in the case of all emails being removed from a
     * conversation at once.
     *
     * This may be due to either a user-initiated load request or due
     * to background monitoring.
     */
    public virtual signal void conversation_trimmed(Conversation conversation,
                                                    Gee.Collection<Email> email) {
        debug("conversation_trimmed");
    }

    /**
     * Fired when a conversation's email's flags have changed.
     *
     * The local copy of the email is first updated and then this
     * signal is fired.
     *
     * Note that if the flags of an email not captured by the
     * Conversations object change, no signal is fired.  To know of
     * all changes to all flags, subscribe to the base folder's
     * "email-flags-changed" signal.
     */
    public virtual signal void email_flags_changed(Conversation conversation,
                                                   Email email) {
        debug("email_flag_changed");
    }

    /**
     * Creates a conversation monitor for the given folder.
     *
     * @param base_folder a Folder to monitor for conversations
     * @param required_fields See {@link Geary.Folder}
     * @param min_window_count Minimum number of conversations that will be loaded
     */
    public ConversationMonitor(Folder base_folder,
                               Email.Field required_fields,
                               int min_window_count) {
        this.base_folder = base_folder;
        this.required_fields = required_fields | REQUIRED_FIELDS;
        this._min_window_count = min_window_count;
        this.conversations = new ConversationSet(base_folder);
        this.operation_cancellable = new Cancellable();
        this.queue = new ConversationOperationQueue(this.progress_monitor);
    }

    /**
     * Opens the base folder scans and starts monitoring conversations.
     *
     * This method will open the base folder, start a scan to load
     * conversations from it, and starts monitoring the folder and
     * account for messages being added or removed.
     *
     * The //cancellable// parameter will be used when opening the
     * folder, but not subsequently when scanning for new messages. To
     * cancel any such operations, simply close the monitor via {@link
     * stop_monitoring}.
     *
     * @param open_flags See {@link Geary.Folder}
     * @param cancellable Passed to the folder open operation
     */
    public async bool start_monitoring(Folder.OpenFlags open_flags,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (this.is_monitoring)
            return false;

        // Set early yield to guard against reentrancy
        this.is_monitoring = true;
        this.base_was_opened = false;

        this.base_folder.email_appended.connect(on_folder_email_appended);
        this.base_folder.email_inserted.connect(on_folder_email_inserted);
        this.base_folder.email_locally_complete.connect(on_folder_email_complete);
        this.base_folder.email_removed.connect(on_folder_email_removed);
        this.base_folder.email_locally_removed.connect(on_folder_email_removed);
        this.base_folder.opened.connect(on_folder_opened);
        this.base_folder.account.email_appended.connect(on_account_email_appended);
        this.base_folder.account.email_inserted.connect(on_account_email_inserted);
        this.base_folder.account.email_locally_complete.connect(on_account_email_complete);
        this.base_folder.account.email_removed.connect(on_account_email_removed);
        this.base_folder.account.email_flags_changed.connect(on_account_email_flags_changed);

        this.queue.operation_error.connect(on_operation_error);
        this.queue.add(new FillWindowOperation(this));

        // Take the union of the two cancellables so that of the
        // monitor is closed while it is opening, the folder open is
        // also cancelled
        GLib.Cancellable opening = new GLib.Cancellable();
        if (cancellable != null) {
            cancellable.cancelled.connect(() => opening.cancel());
        }
        this.operation_cancellable.cancelled.connect(() => opening.cancel());

        try {
            yield this.base_folder.open_async(open_flags, opening);
            this.base_was_opened = true;
        } catch (GLib.Error err) {
            // This check is needed since ::stop_monitoring may have
            // been called while this call is waiting for the folder
            // to finish opening. If so, we're already disconnected
            // and don't need to do it again.
            if (this.is_monitoring) {
                try {
                    yield stop_monitoring_internal(null);
                } catch (GLib.Error stop_error) {
                    warning(
                        "Error cleaning up after folder open error: %s", err.message
                    );
                }
            }

            this.is_monitoring = false;
            throw err;
        }

        // Now the folder is open, start the queue running. The here
        // is needed for the same reason as the one immediately above.
        if (this.is_monitoring) {
            this.queue.run_process_async.begin();
        }

        return true;
    }

    /**
     * Stops monitoring for new messages and closes the base folder.
     *
     * Returns a result code that is semantically identical to the
     * result of {@link Geary.Folder.close_async}.
     *
     * The //cancellable// parameter will be used when waiting for
     * internal monitor operations to complete, but will not prevent
     * attempts to close the base folder.
     */
    public async bool stop_monitoring(GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool is_closing = false;
        if (this.is_monitoring) {
            // Set now to prevent reentrancy during yield or signal
            this.is_monitoring = false;
            is_closing = yield stop_monitoring_internal(cancellable);
        }
        return is_closing;
    }

    /** Ensures the given email are loaded in the monitor. */
    public async void load_email(Gee.Collection<Geary.EmailIdentifier> to_load,
                                 GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (!this.is_monitoring) {
            throw new EngineError.OPEN_REQUIRED("Monitor is not open");
        }

        var remaining = traverse(to_load).filter(
            id => this.conversations.get_by_email_identifier(id) == null
        ).to_array_list();

        if (!remaining.is_empty) {
            remaining.sort((a, b) => a.natural_sort_comparator(b));
            var op = new LoadOperation(
                this, remaining[0], this.operation_cancellable
            );
            this.queue.add(op);
            yield op.wait_until_complete(cancellable);
        }
    }

    /**
     * Returns the conversation containing the given email, if any.
     */
    public Conversation? get_by_email_identifier(Geary.EmailIdentifier email_id) {
        return this.conversations.get_by_email_identifier(email_id);
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "size=%d, min_window_count=%u, can_load_more=%s, should_load_more=%s",
            this.size,
            this.min_window_count,
            this.can_load_more.to_string(),
            this.should_load_more.to_string()
        );
    }

    /** Ensures enough conversations are present, otherwise loads more. */
    internal void check_window_count() {
        if (this.is_monitoring &&
            this.can_load_more &&
            this.should_load_more) {
            this.queue.add(new FillWindowOperation(this));
        }
    }

    /**
     * Returns the list of folders that disqualify emails from conversations.
     */
    internal Gee.Collection<Geary.FolderPath> get_search_folder_blacklist() {
        Folder.SpecialUse[] blacklisted_folder_types = {
            JUNK,
            TRASH,
            DRAFTS,
        };

        var blacklist = new Gee.ArrayList<Geary.FolderPath?>();
        foreach (var type in blacklisted_folder_types) {
            Geary.Folder? blacklist_folder = this.base_folder.account.get_special_folder(type);
            if (blacklist_folder != null) {
                blacklist.add(blacklist_folder.path);
            }
        }

        // Add "no folders" so we omit results that have been deleted permanently from the server.
        blacklist.add(null);

        return blacklist;
    }

    /**
     * Returns the list of flags that disqualify emails from conversations.
     */
    internal Geary.EmailFlags get_search_flag_blacklist() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.DRAFT);
        return flags;
    }

    /** Loads messages from the base folder into the window. */
    internal async int load_by_id_async(EmailIdentifier? initial_id,
                                        int count,
                                        Folder.ListFlags flags = Folder.ListFlags.NONE)
        throws Error {
        notify_scan_started();

        int load_count = 0;
        GLib.Error? scan_error = null;
        try {
            Gee.Collection<Geary.Email>? messages =
                yield this.base_folder.list_email_by_id_async(
                    initial_id, count, required_fields, flags,
                    this.operation_cancellable
                );

            if (messages != null && !messages.is_empty) {
                load_count = messages.size;

                foreach (Email email in messages) {
                    this.window.add(email.id);
                }

                yield process_email_async(messages, ProcessJobContext());
            }
        } catch (GLib.Error err) {
            scan_error = err;
        }

        notify_scan_completed();

        if (scan_error != null) {
            throw scan_error;
        }

        return load_count;
    }

    /** Loads messages from the base folder into the window. */
    internal async void load_by_sparse_id(Gee.Collection<EmailIdentifier> ids,
                                          Folder.ListFlags flags = Folder.ListFlags.NONE)
        throws Error {
        notify_scan_started();

        GLib.Error? scan_error = null;
        try {
            Gee.Collection<Geary.Email>? messages =
                yield this.base_folder.list_email_by_sparse_id_async(
                    ids, required_fields, flags, this.operation_cancellable
                );

            if (messages != null && !messages.is_empty) {
                foreach (Email email in messages) {
                    this.window.add(email.id);
                }

                yield process_email_async(messages, ProcessJobContext());
            }
        } catch (GLib.Error err) {
            scan_error = err;
        }

        notify_scan_completed();

        if (scan_error != null) {
            throw scan_error;
        }
    }

    /**
     * Loads messages from outside the monitor's base folder.
     *
     * Since this requires opening and closing the other folder, it is
     * handled separately.
     */
    internal async void external_load_by_sparse_id(Folder folder,
                                                   Gee.Collection<EmailIdentifier> ids,
                                                   Folder.ListFlags flags)
        throws Error {
        bool opened = false;

        Gee.List<Geary.Email>? emails = null;
        try {
            yield folder.open_async(
                Geary.Folder.OpenFlags.NONE, this.operation_cancellable
            );
            opened = true;

            // First just get the bare minimum we need to determine if we even
            // care about the messages.
            emails = yield folder.list_email_by_sparse_id_async(
                ids, Geary.Email.Field.REFERENCES, flags, this.operation_cancellable
            );
            if (emails != null) {
                Gee.HashSet<Geary.EmailIdentifier> relevant_ids =
                    new Gee.HashSet<Geary.EmailIdentifier>();
                foreach (Geary.Email email in emails) {
                    Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
                    if (ancestors != null &&
                        Geary.traverse<RFC822.MessageID>(ancestors).any(id => conversations.has_message_id(id)))
                        relevant_ids.add(email.id);
                }

                // List the relevant messages again with the full set of fields, to
                // make sure when we load them from the database we have all the
                // data we need.
                if (!relevant_ids.is_empty) {
                    emails = yield folder.list_email_by_sparse_id_async(
                        relevant_ids, required_fields, flags, this.operation_cancellable
                    );
                } else {
                    emails = null;
                }
            }

            yield folder.close_async(null);
            opened = false;
        } catch (Error err) {
            if (opened) {
                // Always try to close the opened folder
                try {
                    yield folder.close_async(null);
                } catch (Error close_err) {
                    warning("Error closing folder %s: %s",
                            folder.to_string(), close_err.message);
                }
            }
            throw err;
        }

        if (emails != null && !emails.is_empty) {
            debug("Fetched %d relevant emails locally", emails.size);
            yield process_email_async(emails, ProcessJobContext());
        }
    }

   /** Notifies of removed conversations and removes emails from the window. */
   internal void removed(Gee.Collection<Conversation> removed,
                         Gee.MultiMap<Conversation, Email> trimmed,
                         Gee.Collection<EmailIdentifier>? base_folder_removed) {
        foreach (Conversation conversation in trimmed.get_keys()) {
            notify_conversation_trimmed(conversation, trimmed.get(conversation));
        }

        if (removed.size > 0) {
            notify_conversations_removed(removed);
        }

        if (base_folder_removed != null) {
            this.window.remove_all(base_folder_removed);
        }
    }

    protected virtual void notify_scan_started() {
        scan_started();
    }

    protected virtual void notify_scan_error(Error err) {
        scan_error(err);
    }

    protected virtual void notify_scan_completed() {
        scan_completed();
    }

    protected virtual void notify_conversations_added(Gee.Collection<Conversation> conversations) {
        conversations_added(conversations);
    }

    protected virtual void notify_conversations_removed(Gee.Collection<Conversation> conversations) {
        conversations_removed(conversations);
    }

    protected virtual void notify_conversation_appended(Conversation conversation,
        Gee.Collection<Geary.Email> emails) {
        conversation_appended(conversation, emails);
    }

    protected virtual void notify_conversation_trimmed(Conversation conversation,
        Gee.Collection<Geary.Email> emails) {
        conversation_trimmed(conversation, emails);
    }

    protected virtual void notify_email_flags_changed(Conversation conversation, Geary.Email email) {
        conversation.email_flags_changed(email);
        email_flags_changed(conversation, email);
    }

    private async bool stop_monitoring_internal(GLib.Cancellable? cancellable)
        throws Error {
        this.base_folder.email_appended.disconnect(on_folder_email_appended);
        this.base_folder.email_inserted.disconnect(on_folder_email_inserted);
        this.base_folder.email_locally_complete.disconnect(on_folder_email_complete);
        this.base_folder.email_removed.disconnect(on_folder_email_removed);
        this.base_folder.email_locally_removed.disconnect(on_folder_email_removed);
        this.base_folder.opened.disconnect(on_folder_opened);
        this.base_folder.account.email_appended.disconnect(on_account_email_appended);
        this.base_folder.account.email_inserted.disconnect(on_account_email_inserted);
        this.base_folder.account.email_locally_complete.disconnect(on_account_email_complete);
        this.base_folder.account.email_removed.disconnect(on_account_email_removed);
        this.base_folder.account.email_flags_changed.disconnect(on_account_email_flags_changed);

        // Cancel outstanding ops so they don't block the queue closing
        this.operation_cancellable.cancel();

        // Keep track of errors stopping the queue but continue, since
        // the cleanup below needs to occur.
        Error? close_err = null;
        try {
            yield this.queue.stop_processing_async(cancellable);
        } catch (Error err) {
            close_err = err;
        }

        bool closing = false;
        if (this.base_was_opened) {
            try {
                closing = yield this.base_folder.close_async(null);
            } catch (GLib.Error err) {
                if (close_err == null) {
                    close_err = err;
                } else {
                    warning(
                        "Unable to close monitored folder %s: %s",
                        this.base_folder.to_string(), err.message
                    );
                }
            }
        }

        if (close_err != null)
            throw close_err;

        return closing;
    }

    private async void process_email_async(Gee.Collection<Geary.Email>? emails,
                                           ProcessJobContext job)
        throws Error {
        if (emails == null || emails.size == 0) {
            yield process_email_complete_async(job);
            return;
        }

        debug("process_email: %d emails", emails.size);

        Gee.HashSet<RFC822.MessageID> new_message_ids = new Gee.HashSet<RFC822.MessageID>();
        foreach (Geary.Email email in emails) {
            if (!job.emails.has_key(email.id)) {
                job.emails.set(email.id, email);

                // Expand conversations whose messages have ancestors, and aren't marked
                // for deletion.
                Geary.EmailFlags? flags = email.email_flags;
                bool marked_for_deletion = (flags != null) ? flags.is_deleted() : false;

                Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
                if (ancestors != null && !marked_for_deletion) {
                    Geary.traverse<RFC822.MessageID>(ancestors)
                        .filter(id => !new_message_ids.contains(id))
                        .add_all_to(new_message_ids);
                }
            }
        }

        // Expand the conversation to include any Message-IDs we know we need
        // and may have on disk, but aren't in the folder.
        yield expand_conversations_async(new_message_ids, job);

        debug("process_email completed: %d emails", emails.size);
    }

    private async void process_email_complete_async(ProcessJobContext job) {
        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation, Geary.Email>? appended = null;
        Gee.Collection<Conversation>? removed_due_to_merge = null;
        try {
            // Get known paths for all emails
            Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? email_paths =
                yield this.base_folder.account.get_containing_folders_async(
                    job.emails.keys,
                    this.operation_cancellable
                );

            // Add them to the conversation set
            if (email_paths != null) {
                this.conversations.add_all_emails(
                    job.emails.values, email_paths,
                    out added, out appended, out removed_due_to_merge
                );
            }
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            warning("Unable to add emails to conversation: %s", err.message);
            // Fall-through anyway
        }

        if (removed_due_to_merge != null && removed_due_to_merge.size > 0) {
            notify_conversations_removed(removed_due_to_merge);
        }

        if (added != null && added.size > 0)
            notify_conversations_added(added);

        if (appended != null) {
            foreach (Conversation conversation in appended.get_keys())
                notify_conversation_appended(conversation, appended.get(conversation));
        }
    }

    private async void expand_conversations_async(Gee.Set<RFC822.MessageID> needed_message_ids,
                                                   ProcessJobContext job)
        throws Error {
        if (needed_message_ids.size == 0) {
            yield process_email_complete_async(job);
            return;
        }

        debug("expand_conversations: %d email ids", needed_message_ids.size);

        Gee.Collection<Geary.FolderPath> folder_blacklist = get_search_folder_blacklist();
        Geary.EmailFlags flag_blacklist = get_search_flag_blacklist();

        // execute all the local search operations at once
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (RFC822.MessageID message_id in needed_message_ids) {
            batch.add(new LocalSearchOperation(this.base_folder.account, message_id, required_fields,
                folder_blacklist, flag_blacklist));
        }

        yield batch.execute_all_async();

        // collect their results into a single collection of addt'l emails
        Gee.HashMap<Geary.EmailIdentifier, Geary.Email> needed_messages = new Gee.HashMap<
            Geary.EmailIdentifier, Geary.Email>();
        foreach (int id in batch.get_ids()) {
            LocalSearchOperation op = (LocalSearchOperation) batch.get_operation(id);
            if (op.emails != null) {
                Geary.traverse<Geary.Email>(op.emails.get_keys())
                    .filter(e => !needed_messages.has_key(e.id))
                    .add_all_to_map<Geary.EmailIdentifier>(needed_messages, e => e.id);
            }
        }

        // process them as through they're been loaded from the folder; this, in turn, may
        // require more local searching of email
        yield process_email_async(needed_messages.values, job);

        debug("expand_conversations completed: %d email ids (%d found)",
              needed_message_ids.size, needed_messages.size);
    }

    private void on_folder_opened(Geary.Folder.OpenState state, int count) {
        if (state == Geary.Folder.OpenState.REMOTE)
            this.queue.add(new ReseedOperation(this));
    }

    private void on_folder_email_appended(Gee.Collection<EmailIdentifier> appended) {
        this.queue.add(new AppendOperation(this, appended));
    }

    private void on_folder_email_complete(Gee.Collection<EmailIdentifier> completed) {
        // InsertOperation will add the emails only if they are after
        // the earliest, which is what we want here.
        this.queue.add(new InsertOperation(this, completed));
    }

    private void on_folder_email_inserted(Gee.Collection<EmailIdentifier> inserted) {
        this.queue.add(new InsertOperation(this, inserted));
    }

    private void on_folder_email_removed(Gee.Collection<EmailIdentifier> removed) {
        this.queue.add(new RemoveOperation(this, this.base_folder, removed));
    }

    private void on_account_email_appended(Folder folder,
                                           Gee.Collection<EmailIdentifier> added) {
        if (folder != this.base_folder) {
            this.queue.add(new ExternalAppendOperation(this, folder, added));
        }
    }

    private void on_account_email_complete(Folder folder,
                                           Gee.Collection<EmailIdentifier> inserted) {
        // ExternalAppendOperation will check to determine if the
        // email is relevant for some existing conversation before
        // adding it, which is what we want here.
        if (folder != this.base_folder) {
            this.queue.add(new ExternalAppendOperation(this, folder, inserted));
        }
    }

    private void on_account_email_inserted(Folder folder,
                                           Gee.Collection<EmailIdentifier> inserted) {
        // ExternalAppendOperation will check to determine if the
        // email is relevant for some existing conversation before
        // adding it, which is what we want here.
        if (folder != this.base_folder) {
            this.queue.add(new ExternalAppendOperation(this, folder, inserted));
        }
    }

    private void on_account_email_removed(Folder folder,
                                          Gee.Collection<EmailIdentifier> removed) {
        if (folder != this.base_folder) {
            this.queue.add(new RemoveOperation(this, folder, removed));
        }
    }

    private void on_account_email_flags_changed(Geary.Folder folder,
                                                Gee.Map<EmailIdentifier,EmailFlags> map) {
        Gee.HashSet<EmailIdentifier> inserted_ids = new Gee.HashSet<EmailIdentifier>();
        Gee.HashSet<EmailIdentifier> removed_ids = new Gee.HashSet<EmailIdentifier>();
        Gee.HashSet<Conversation> removed_conversations = new Gee.HashSet<Conversation>();
        foreach (EmailIdentifier id in map.keys) {
            Conversation? conversation = this.conversations.get_by_email_identifier(id);
            if (conversation == null) {
                if (folder == this.base_folder) {
                    // Check to see if the incoming message is sorted later than the last message in the
                    // window. If it is, don't resurrect it since it likely hasn't been loaded yet.
                    Geary.EmailIdentifier? lowest = this.window_lowest;
                    if (lowest != null) {
                        if (lowest.natural_sort_comparator(id) < 0) {
                            debug(
                                "Unflagging email %s for deletion resurrects conversation",
                                id.to_string()
                            );
                            inserted_ids.add(id);
                        } else {
                            debug(
                                "Not resurrecting undeleted email %s outside of window",
                                id.to_string()
                            );
                        }
                    }
                }

                continue;
            }

            Email? email = conversation.get_email_by_id(id);
            if (email == null)
                continue;

            email.set_flags(map.get(id));
            notify_email_flags_changed(conversation, email);

            // Remove conversation if get_emails yields an empty collection -- this probably means
            // the conversation was deleted.
            if (conversation.get_emails(Geary.App.Conversation.Ordering.NONE).size == 0) {
                debug(
                    "Flagging email %s for deletion evaporates conversation %s",
                    id.to_string(), conversation.to_string()
                );
                this.conversations.remove_conversation(conversation);
                removed_conversations.add(conversation);
                removed_ids.add(id);
            }
        }

        // Notify about inserted messages
        if (inserted_ids.size > 0) {
            this.queue.add(new InsertOperation(this, inserted_ids));
        }

        // Notify self about removed conversations
        // NOTE: We are only notifying the conversation monitor about the removed conversations instead of
        // enqueuing a RemoveOperation, because these messages haven't actually been removed. They're only
        // hidden at the conversation-level for being marked as deleted.
        removed(
            removed_conversations,
            new Gee.HashMultiMap<Conversation, Email>(),
            (folder == this.base_folder) ? removed_ids : null
        );
    }

    private void on_operation_error(ConversationOperation op, Error err) {
        if (!(err is GLib.IOError.CANCELLED)) {
            warning("Error executing %s: %s", op.get_type().name(), err.message);
        }
        notify_scan_error(err);
    }

}
