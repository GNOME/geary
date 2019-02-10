/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016,2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying conversations as a list of emails.
 *
 * The view displays the current selected {@link
 * Geary.App.Conversation} from the conversation list. To do so, it
 * listens to signals from both the list and the current conversation
 * monitor, updating the email list as needed.
 *
 * Unlike ConversationListStore (which sorts by date received),
 * ConversationListBox sorts by the {@link Geary.Email.date} field
 * (the Date: header), as that's the date displayed to the user.
 */
public class ConversationListBox : Gtk.ListBox, Geary.BaseInterface {

    /** Fields that must be available for listing conversation email. */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        // Sorting the conversation
        Geary.Email.Field.DATE |
        // Determine unread/starred, etc
        Geary.Email.Field.FLAGS |
        // Determine if the message is from the sender or not
        Geary.Email.Field.ORIGINATORS
    );

    // Offset from the top of the list box which emails views will
    // scrolled to, so the user can see there are additional messages
    // above it. XXX This is currently approx 0.5 times the height of
    // a collapsed ConversationEmail, it should probably calculated
    // somehow so that differences user's font size are taken into
    // account.
    private const int EMAIL_TOP_OFFSET = 32;

    // Amount of time to wait after the user took some action that may
    // be interpreted as marking the email as read before actually
    // checking
    private const int MARK_READ_TIMEOUT_MSEC = 250;

    // Amount of pixels that need to be shown of an email's body to
    // mark it as read
    private const int MARK_READ_PADDING = 50;


    /** Manages find/search term matching in a conversation. */
    public class SearchManager : Geary.BaseObject {


        // The list that owns this manager
        private weak ConversationListBox list;

        // Conversation being managed
        private Geary.App.Conversation conversation;

        // Cached search terms to apply to new messages
        private Gee.Set<string>? terms = null;

        // Total number of search matches found
        private uint matches_found = 0;

        // Cancellable used when highlighting search matches
        private GLib.Cancellable highlight_cancellable = new GLib.Cancellable();


        /** Fired when the number of matching emails has changed. */
        public signal void matches_updated(uint matches);


        internal SearchManager(ConversationListBox list,
                               Geary.App.Conversation conversation) {
            this.list = list;
            this.conversation = conversation;
        }


        /**
         * Loads search term matches for this list's emails.
         */
        public async void highlight_matching_email(Geary.SearchQuery query)
            throws GLib.Error {
            cancel();

            // Keep a copy of the current cancellable so it can't get
            // changed out from underneath the execution of this method
            GLib.Cancellable cancellable = this.highlight_cancellable;

            Geary.Account account = this.conversation.base_folder.account;
            Gee.Collection<Geary.EmailIdentifier>? matching =
            yield account.local_search_async(
                query,
                this.conversation.get_count(),
                0,
                null,
                this.conversation.get_email_ids(),
                cancellable
            );

            if (matching != null) {
                Gee.Set<string>? terms =
                    yield account.get_search_matches_async(
                        query, matching, cancellable
                    );

                if (cancellable.is_cancelled()) {
                    throw new GLib.IOError.CANCELLED(
                        "Search term highlighting cancelled"
                    );
                }

                if (terms != null && !terms.is_empty) {
                    this.terms = terms;

                    // Scroll to the first matching row first
                    EmailRow? first = null;
                    foreach (Geary.EmailIdentifier id in matching) {
                        EmailRow? row = this.list.get_email_row_by_id(id);
                        if (row != null &&
                            (first == null || row.get_index() < first.get_index())) {
                            first = row;
                        }
                    }
                    if (first != null) {
                        this.list.scroll_to(first);
                    }

                    // Now expand them all
                    foreach (Geary.EmailIdentifier id in matching) {
                        EmailRow? row = this.list.get_email_row_by_id(id);
                        if (row != null) {
                            apply_terms(row, terms, cancellable);
                            row.expand.begin();
                        }
                    }
                }
            }
        }

        /**
         * Highlights matching terms in the given email row, if any.
         */
        internal void highlight_row_if_matching(EmailRow row) {
            if (this.terms != null) {
                apply_terms(row, this.terms, this.highlight_cancellable);
            }
        }

        /**
         * Removes search term highlighting from all messages.
         */
        public void unmark_terms() {
            cancel();

            this.list.foreach((child) => {
                    EmailRow? row = child as EmailRow;
                    if (row != null) {
                        if (row.is_search_match) {
                            row.is_search_match = false;
                            foreach (ConversationMessage msg_view in row.view) {
                                msg_view.unmark_search_terms();
                            }
                        }
                    }
                });
        }

        public void cancel() {
            this.highlight_cancellable.cancel();
            this.highlight_cancellable = new Cancellable();
            this.terms = null;
            this.matches_found = 0;
            notify_matches_updated();
        }

        private void apply_terms(EmailRow row,
                                 Gee.Set<string>? terms,
                                 GLib.Cancellable cancellable) {
            if (row.view.message_body_state == COMPLETED) {
                this.apply_terms_impl.begin(
                    row, terms, cancellable, apply_terms_impl_finished
                );
            } else {
                row.view.notify["message-body-state"].connect(() => {
                        this.apply_terms_impl.begin(
                            row, terms, cancellable, apply_terms_impl_finished
                        );
                    });
            }
        }

        // This should only be called from apply_terms above
        private async uint apply_terms_impl(EmailRow row,
                                            Gee.Set<string>? terms,
                                            GLib.Cancellable cancellable)
            throws GLib.IOError.CANCELLED {
            uint count = 0;
            foreach (ConversationMessage view in row.view) {
                if (cancellable.is_cancelled()) {
                    throw new GLib.IOError.CANCELLED(
                        "Applying search terms cancelled"
                    );
                }
                count += yield view.highlight_search_terms(terms, cancellable);
            }

            row.is_search_match = (count > 0);
            return count;
        }

        private void apply_terms_impl_finished(GLib.Object? obj,
                                               GLib.AsyncResult res) {
            try {
                this.matches_found += this.apply_terms_impl.end(res);
                notify_matches_updated();
            } catch (GLib.IOError.CANCELLED err) {
                // All good
            }
        }

        private inline void notify_matches_updated() {
            matches_updated(this.matches_found);
        }

    }


    // Base class for list rows it the list box
    internal abstract class ConversationRow : Gtk.ListBoxRow, Geary.BaseInterface {


        protected const string EXPANDED_CLASS = "geary-expanded";


        // The email being displayed by this row, if any
        public Geary.Email? email { get; private set; default = null; }

        // Is the row showing the email's message body or just headers?
        public bool is_expanded {
            get {
                return this._is_expanded;
            }
            protected set {
                this._is_expanded = value;
            }
        }
        private bool _is_expanded = false;


        // We can only scroll to a specific row once it has been
        // allocated space. This signal allows the viewer to hook up
        // to appropriate times to try to do that scroll.
        public signal void should_scroll();


        protected ConversationRow(Geary.Email? email) {
            base_ref();
            this.email = email;
            show();
        }

        ~ConversationRow() {
            base_unref();
        }

        // Request the row be expanded, if supported.
        public virtual new async void expand()
            throws GLib.Error {
            // Not supported by default
        }

        // Request the row be collapsed, if supported.
        public virtual void collapse() {
            // Not supported by default
        }

        // Enables firing the should_scroll signal when this row is
        // allocated a size
        public void enable_should_scroll() {
            this.size_allocate.connect(on_size_allocate);
        }

        protected inline void set_style_context_class(string class_name, bool value) {
            if (value) {
                get_style_context().add_class(class_name);
            } else {
                get_style_context().remove_class(class_name);
            }
        }

        protected void on_size_allocate() {
            // Disable should_scroll so we don't keep on scrolling
            // later, like when the window has been resized.
            this.size_allocate.disconnect(on_size_allocate);
            should_scroll();
        }

    }


    // Displays a single ConversationEmail in the list box
    internal class EmailRow : ConversationRow {


        private const string MATCH_CLASS = "geary-matched";


        // Has the row been temporarily expanded to show search matches?
        public bool is_pinned { get; private set; default = false; }

        // Does the row contain an email matching the current search?
        public bool is_search_match {
            get { return get_style_context().has_class(MATCH_CLASS); }
            set {
                set_style_context_class(MATCH_CLASS, value);
                this.is_pinned = value;
                update_row_expansion();
            }
        }


        // The email view for this row, if any
        public ConversationEmail view { get; private set; }


        public EmailRow(ConversationEmail view) {
            base(view.email);
            this.view = view;
            add(view);
        }

        public override async void expand()
            throws GLib.Error {
            this.is_expanded = true;
            update_row_expansion();
            if (this.view.message_body_state == NOT_STARTED) {
                yield this.view.load_body();
            }
        }

        public override void collapse() {
            this.is_expanded = false;
            this.is_pinned = false;
            update_row_expansion();
        }

        private inline void update_row_expansion() {
            if (this.is_expanded || this.is_pinned) {
                get_style_context().add_class(EXPANDED_CLASS);
                this.view.expand_email();
            } else {
                get_style_context().remove_class(EXPANDED_CLASS);
                this.view.collapse_email();
            }
        }

    }


    // Displays a loading widget in the list box
    internal class LoadingRow : ConversationRow {


        protected const string LOADING_CLASS = "geary-loading";


        public LoadingRow() {
            base(null);
            get_style_context().add_class(LOADING_CLASS);

            Gtk.Spinner spinner = new Gtk.Spinner();
            spinner.height_request = 16;
            spinner.width_request = 16;
            spinner.show();
            spinner.start();
            add(spinner);
        }

    }


    // Displays a single embedded composer in the list box
    internal class ComposerRow : ConversationRow {

        // The embedded composer for this row
        public ComposerEmbed view { get; private set; }


        public ComposerRow(ComposerEmbed view) {
            base(view.referred);
            this.view = view;
            this.is_expanded = true;
            get_style_context().add_class(EXPANDED_CLASS);
            add(this.view);
        }

    }


    static construct {
        // Set up custom keybindings
        unowned Gtk.BindingSet bindings = Gtk.BindingSet.by_class(
            (ObjectClass) typeof(ConversationListBox).class_ref()
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.space, 0, "focus-next", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.KP_Space, 0, "focus-next", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.space, Gdk.ModifierType.SHIFT_MASK, "focus-prev", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.KP_Space, Gdk.ModifierType.SHIFT_MASK, "focus-prev", 0
        );

        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Up, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.STEP_UP
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Down, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.STEP_DOWN
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Page_Up, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.PAGE_UP
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Page_Down, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.PAGE_DOWN
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Home, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.START
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.End, 0, "scroll", 1,
            typeof(Gtk.ScrollType), Gtk.ScrollType.END
        );
    }

    private static int on_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        Geary.Email? email1 = ((ConversationRow) row1).email;
        Geary.Email? email2 = ((ConversationRow) row2).email;

        if (email1 == null) {
            return 1;
        }
        if (email2 == null) {
            return -1;
        }
        return Geary.Email.compare_sent_date_ascending(email1, email2);
    }


    /** Conversation being displayed. */
    public Geary.App.Conversation conversation { get; private set; }

    /** Search manager for highlighting search terms in this list. */
    public SearchManager search { get; private set; }

    // Used to load messages in conversation.
    private Geary.App.EmailStore email_store;

    // Avatars for this conversation
    private Application.AvatarStore avatar_store;

    // App config
    private Configuration config;

    // Cancellable for this conversation's data loading.
    private Cancellable cancellable = new Cancellable();

    // Email view with selected text, if any
    private ConversationEmail? body_selected_view = null;

    // Maps displayed emails to their corresponding rows.
    private Gee.Map<Geary.EmailIdentifier,EmailRow> email_rows =
        new Gee.HashMap<Geary.EmailIdentifier,EmailRow>();

    // The id of the draft referred to by the current composer.
    private Geary.EmailIdentifier? draft_id = null;

    private Geary.TimeoutManager mark_read_timer;


    /** Keyboard action to scroll the conversation. */
    [Signal (action=true)]
    public virtual signal void scroll(Gtk.ScrollType type) {
        Gtk.Adjustment adj = get_adjustment();
        double value = adj.get_value();
        switch (type) {
        case Gtk.ScrollType.STEP_UP:
            value -= adj.get_step_increment();
            break;
        case Gtk.ScrollType.STEP_DOWN:
            value += adj.get_step_increment();
            break;
        case Gtk.ScrollType.PAGE_UP:
            value -= adj.get_page_increment();
            break;
        case Gtk.ScrollType.PAGE_DOWN:
            value += adj.get_page_increment();
            break;
        case Gtk.ScrollType.START:
            value = 0.0;
            break;
        case Gtk.ScrollType.END:
            value = adj.get_upper();
            break;
        }
        adj.set_value(value);
        this.mark_read_timer.start();
    }

    /** Keyboard action to shift focus to the next message, if any. */
    [Signal (action=true)]
    public virtual signal void focus_next() {
        this.move_cursor(Gtk.MovementStep.DISPLAY_LINES, 1);
        this.mark_read_timer.start();
    }

    /** Keyboard action to shift focus to the prev message, if any. */
    [Signal (action=true)]
    public virtual signal void focus_prev() {
        this.move_cursor(Gtk.MovementStep.DISPLAY_LINES, -1);
        this.mark_read_timer.start();
    }

    /** Fired when an email view is added to the conversation list. */
    public signal void email_added(ConversationEmail email);

    /** Fired when an email view is removed from the conversation list. */
    public signal void email_removed(ConversationEmail email);

    /** Fired when the user updates the flags for a set of emails. */
    public signal void mark_emails(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);


    /**
     * Constructs a new conversation list box instance.
     */
    public ConversationListBox(Geary.App.Conversation conversation,
                               Geary.App.EmailStore email_store,
                               Application.AvatarStore avatar_store,
                               Configuration config,
                               Gtk.Adjustment adjustment) {
        base_ref();
        this.conversation = conversation;
        this.email_store = email_store;
        this.avatar_store = avatar_store;
        this.config = config;

        this.search = new SearchManager(this, conversation);

        this.mark_read_timer = new Geary.TimeoutManager.milliseconds(
            MARK_READ_TIMEOUT_MSEC, this.check_mark_read
        );

        this.selection_mode = NONE;

        get_style_context().add_class("background");
        get_style_context().add_class("conversation-listbox");

        set_adjustment(adjustment);
        set_sort_func(ConversationListBox.on_sort);

        this.row_activated.connect(on_row_activated);

        this.conversation.appended.connect(on_conversation_appended);
        this.conversation.trimmed.connect(on_conversation_trimmed);
        this.conversation.email_flags_changed.connect(on_update_flags);
    }

    ~ConversationListBox() {
        base_unref();
    }

    public override void destroy() {
        this.search.cancel();
        this.cancellable.cancel();
        this.email_rows.clear();
        this.mark_read_timer.reset();
        base.destroy();
    }

    public async void load_conversation(Geary.SearchQuery? query)
        throws GLib.Error {
        set_sort_func(null);

        Gee.Collection<Geary.Email>? all_email = this.conversation.get_emails(
            Geary.App.Conversation.Ordering.SENT_DATE_ASCENDING
        );

        // Work out what the first interesting email is, and load it
        // before all of the email before and after that so we can
        // load them in an optimal order.
        Gee.LinkedList<Geary.Email> uninteresting =
            new Gee.LinkedList<Geary.Email>();
        Geary.Email? first_interesting = null;
        Gee.LinkedList<Geary.Email> post_interesting =
            new Gee.LinkedList<Geary.Email>();
        foreach (Geary.Email email in all_email) {
            if (first_interesting == null) {
                if (email.is_unread().is_certain() ||
                    email.is_flagged().is_certain()) {
                    first_interesting = email;
                } else {
                    // Inserted reversed so most recent uninteresting
                    // rows are added first.
                    uninteresting.insert(0, email);
                }
            } else {
                post_interesting.add(email);
            }
        }

        if (first_interesting == null) {
            // No interesting messages found so use the last one.
            first_interesting = uninteresting.remove_at(0);
        }
        EmailRow interesting_row = add_email(first_interesting);

        // If we have at least one uninteresting and one
        // post-interesting to load afterwards, show a spinner above
        // the interesting row to act as a placeholder.
        if (!uninteresting.is_empty && !post_interesting.is_empty) {
            insert(new LoadingRow(), 0);
        }

        // Load the interesting row completely up front, and load the
        // remaining in the background so we can return fast.
        yield interesting_row.expand();
        this.finish_loading.begin(
            query, uninteresting, post_interesting
        );

        this.mark_read_timer.start();
    }

    /** Cancels loading the current conversation, if still in progress */
    public void cancel_conversation_load() {
        this.cancellable.cancel();
    }

    /**
     * Returns the email view to be replied to, if any.
     *
     * If an email view has a visible body and selected text, that
     * view will be returned. Else the last message by sort order will
     * be returned, if any.
     */
    public ConversationEmail? get_reply_target() {
        ConversationEmail? view = get_selection_view();
        if (view == null) {
            EmailRow? last = null;
            this.foreach((child) => {
                    EmailRow? row = child as EmailRow;
                    if (row != null) {
                        last = row;
                    }
                });

            if (last != null) {
                view = last.view;
            }
        }
        return view;
    }

    /**
     * Returns the email view with a visible user selection, if any.
     *
     * If an email view has selected body text.
     */
    public ConversationEmail? get_selection_view() {
        ConversationEmail? view = this.body_selected_view;
        if (view != null) {
            if (view.is_collapsed) {
                // A collapsed email can't be visible
                view = null;
            } else {
                // XXX check the selected text is actually on screen
            }
        }
        return view;
    }

    /**
     * Adds an an embedded composer to the view.
     */
    public void add_embedded_composer(ComposerEmbed embed, bool is_draft) {
        if (is_draft) {
            this.draft_id = embed.referred.id;
            EmailRow? draft = this.email_rows.get(embed.referred.id);
            if (draft != null) {
                remove_email(draft.email);
            }
        }

        ComposerRow row = new ComposerRow(embed);
        row.enable_should_scroll();
        // Use row param rather than row var from closure to avoid a
        // circular ref.
        row.should_scroll.connect((row) => { scroll_to(row); });
        add(row);

        embed.composer.draft_id_changed.connect((id) => { this.draft_id = id; });
        embed.vanished.connect(() => {
                this.draft_id = null;
                remove(row);
                if (is_draft &&
                    row.email != null &&
                    !this.cancellable.is_cancelled()) {
                    load_full_email.begin(row.email.id);
                }
            });
    }

    /**
     * Marks all email with a visible body read.
     */
    public void mark_visible_read() {
        this.mark_read_timer.start();
    }

    /**
     * Displays an email as being read, regardless of its actual flags.
     */
    public void mark_manual_read(Geary.EmailIdentifier id) {
        EmailRow? row = this.email_rows.get(id);
        if (row != null) {
            row.view.is_manually_read = true;
        }
    }

    /**
     * Displays an email as being unread, regardless of its actual flags.
     */
    public void mark_manual_unread(Geary.EmailIdentifier id) {
        EmailRow? row = this.email_rows.get(id);
        if (row != null) {
            row.view.is_manually_read = false;
        }
    }

    /**
     * Increases the magnification level used for displaying messages.
     */
    public void zoom_in() {
        message_view_iterator().foreach((msg_view) => {
                msg_view.web_view.zoom_in();
                return true;
            });
    }

    /**
     * Decreases the magnification level used for displaying messages.
     */
    public void zoom_out() {
        message_view_iterator().foreach((msg_view) => {
                msg_view.web_view.zoom_out();
                return true;
            });
    }

    /**
     * Resets magnification level used for displaying messages to the default.
     */
    public void zoom_reset() {
        message_view_iterator().foreach((msg_view) => {
                msg_view.web_view.zoom_reset();
                return true;
            });
    }

    /** Returns the email row for the given id, if any. */
    internal EmailRow? get_email_row_by_id(Geary.EmailIdentifier id) {
        return this.email_rows.get(id);
    }

    private async void finish_loading(Geary.SearchQuery? query,
                                      Gee.LinkedList<Geary.Email> to_insert,
                                      Gee.LinkedList<Geary.Email> to_append)
        throws GLib.Error {
        // Add emails to append first because if the first interesting
        // message was short, these will show up in the UI under it,
        // filling the empty space.
        foreach (Geary.Email email in to_append) {
            EmailRow row = add_email(email);
            if (is_interesting(email)) {
                yield row.expand();
            }
            yield throttle_loading();
        }

        // Since first rows may have extra margin, remove that from
        // the height of rows when adjusting scrolling.
        Gtk.ListBoxRow initial_row = get_row_at_index(0);
        int loading_height = 0;
        if (initial_row is LoadingRow) {
            loading_height = GtkUtil.get_border_box_height(initial_row);
            remove(initial_row);
        }

        // None of these will be interesting, so just add them all,
        // but keep the scrollbar adjusted so that the first
        // interesting message remains visible.
        Gtk.Adjustment listbox_adj = get_adjustment();
        foreach (Geary.Email email in to_insert) {
            EmailRow row = add_email(email, false);
            // Since uninteresting rows are inserted above the
            // first expanded, adjust the scrollbar as they are
            // inserted so as to keep the list scrolled to the
            // same place.
            row.enable_should_scroll();
            row.should_scroll.connect(() => {
                    listbox_adj.value += GtkUtil.get_border_box_height(row);
                });

            // Only adjust for the loading row going away once
            loading_height = 0;

            yield throttle_loading();
        }

        set_sort_func(on_sort);

        if (query != null) {
            // XXX this sucks for large conversations because it can take
            // a long time for the load to complete and hence for
            // matches to show up.
            yield this.search.highlight_matching_email(query);
        }
    }

    private inline async void throttle_loading() throws GLib.IOError {
        // Give GTK a moment to process newly added rows, so when
        // updating the adjustment below the values are
        // valid. Priority must be low otherwise other async tasks
        // (like cancelling loading if another conversation is
        // selected) won't get a look in until this is done.
        GLib.Idle.add(
            this.throttle_loading.callback, GLib.Priority.LOW
        );
        yield;

        // Check for cancellation after resuming in case the load was
        // cancelled in the mean time.
        if (this.cancellable.is_cancelled()) {
            throw new GLib.IOError.CANCELLED(
                "Conversation load cancelled"
            );
        }
    }

    // Loads full version of an email, adds it to the listbox
    private async void load_full_email(Geary.EmailIdentifier id)
        throws GLib.Error {
        // Even though it would save a around-trip, don't load the
        // full email here so that ConverationEmail can handle it if
        // the full email isn't actually available in the same way as
        // any other.
        Geary.Email full_email = yield this.email_store.fetch_email_async(
            id,
            REQUIRED_FIELDS | ConversationEmail.REQUIRED_FOR_CONSTRUCT,
            Geary.Folder.ListFlags.NONE,
            this.cancellable
        );

        if (!this.cancellable.is_cancelled()) {
            EmailRow row = add_email(full_email);
            row.view.load_avatar.begin(this.avatar_store);
            this.search.highlight_row_if_matching(row);
            yield row.expand();
        }
    }

    // Constructs a row and view for an email, adds it to the listbox
    private EmailRow add_email(Geary.Email email, bool append_row = true) {
        bool is_sent = false;
        Geary.Account account = this.conversation.base_folder.account;
        if (email.from != null) {
            foreach (Geary.RFC822.MailboxAddress from in email.from) {
                if (account.information.has_sender_mailbox(from)) {
                    is_sent = true;
                    break;
                }
            }
        }

        ConversationEmail view = new ConversationEmail(
            email,
            this.email_store,
            this.avatar_store,
            this.config,
            is_sent,
            is_draft(email),
            this.cancellable
        );
        view.mark_email.connect(on_mark_email);
        view.mark_email_from_here.connect(on_mark_email_from_here);
        view.body_selection_changed.connect((email, has_selection) => {
                this.body_selected_view = has_selection ? email : null;
            });
        view.notify["message-body-state"].connect(
            on_message_body_state_notify
        );

        ConversationMessage conversation_message = view.primary_message;
        conversation_message.body_container.button_release_event.connect_after((event) => {
                // Consume all non-consumed clicks so the row is not
                // inadvertently activated after clicking on the
                // email body.
                return true;
            });

        EmailRow row = new EmailRow(view);
        this.email_rows.set(email.id, row);

        if (append_row) {
            add(row);
        } else {
            insert(row, 0);
        }
        email_added(view);

        return row;
    }

    // Removes the email's row from the listbox, if any
    private void remove_email(Geary.Email email) {
        EmailRow? row = null;
        if (this.email_rows.unset(email.id, out row)) {
            remove(row);
            email_removed(row.view);
        }
    }

    private void scroll_to(ConversationRow row) {
        Gtk.Allocation? alloc = null;
        row.get_allocation(out alloc);
        int y = 0;
        if (alloc.y > EMAIL_TOP_OFFSET) {
            y = alloc.y - EMAIL_TOP_OFFSET;
        }

        // Use set_value rather than clamp_value since we want to
        // scroll to the top of the window.
        get_adjustment().set_value(y);
    }

    /**
     * Finds any currently visible messages, marks them as being read.
     */
    private void check_mark_read() {
        Gee.List<Geary.EmailIdentifier> email_ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        Gtk.Adjustment adj = get_adjustment();
        int top_bound = (int) adj.value;
        int bottom_bound = top_bound + (int) adj.page_size;

        this.foreach((child) => {
            // Don't bother with not-yet-loaded emails since the
            // size of the body will be off, affecting the visibility
            // of emails further down the conversation.
            EmailRow? row = child as EmailRow;
            ConversationEmail? view = (row != null) ? row.view : null;
            Geary.Email? email = (view != null) ? view.email : null;
            if (row != null &&
                row.is_expanded &&
                view.message_body_state == COMPLETED &&
                !view.is_manually_read &&
                email.is_unread().is_certain()) {
                ConversationMessage conversation_message = view.primary_message;
                 int body_top = 0;
                 int body_left = 0;
                 ConversationWebView web_view = conversation_message.web_view;
                 web_view.translate_coordinates(
                     this,
                     0, 0,
                     out body_left, out body_top
                 );

                 int body_height = web_view.get_allocated_height();
                 int body_bottom = body_top + body_height;

                 // Only mark the email as read if it's actually visible
                 if (body_height > 0 &&
                     body_bottom > top_bound &&
                     body_top + MARK_READ_PADDING < bottom_bound) {
                     email_ids.add(view.email.id);

                     // Since it can take some time for the new flags
                     // to round-trip back to our signal handlers,
                     // mark as manually read here
                     view.is_manually_read = true;
                 }
             }
        });

        if (email_ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            mark_emails(email_ids, null, flags);
        }
    }

    /**
     * Returns an new Iterable over all email views in the viewer
     */
    private Gee.Iterator<ConversationEmail> email_view_iterator() {
        return this.email_rows.values.map<ConversationEmail>((row) => {
                return ((EmailRow) row).view;
            });
    }

    /**
     * Returns a new Iterable over all message views in the viewer
     */
    private Gee.Iterator<ConversationMessage> message_view_iterator() {
        return Gee.Iterator.concat<ConversationMessage>(
            email_view_iterator().map<Gee.Iterator<ConversationMessage>>(
                (email_view) => { return email_view.iterator(); }
            )
        );
    }

    /** Determines if an email should be expanded by default. */
    private inline bool is_interesting(Geary.Email email) {
        return (
            email.is_unread().is_certain() ||
            email.is_flagged().is_certain() ||
            is_draft(email)
        );
    }

    /** Determines if an email should be considered to be a draft. */
    private inline bool is_draft(Geary.Email email) {
        // XXX should be able to edit draft emails from any
        // conversation. This test should be more like "is in drafts
        // folder"
        Geary.SpecialFolderType type =
            this.conversation.base_folder.special_folder_type;
        bool is_in_folder = this.conversation.is_in_base_folder(email.id);

        return (
            is_in_folder && type == Geary.SpecialFolderType.DRAFTS // ||
            //email.flags.is_draft()
        );
    }

    private void on_conversation_appended(Geary.App.Conversation conversation,
                                          Geary.Email email) {
        on_conversation_appended_async.begin(conversation, email);
    }

    private async void on_conversation_appended_async(
        Geary.App.Conversation conversation, Geary.Email part_email) {
        // Don't add rows that are already present, or that are
        // currently being edited.
        if (!this.email_rows.has_key(part_email.id) &&
            part_email.id != this.draft_id) {
            load_full_email.begin(part_email.id, (obj, ret) => {
                    try {
                        load_full_email.end(ret);
                    } catch (Error err) {
                        debug(
                            "Unable to append email to conversation: %s",
                            err.message
                        );
                    }
                });
        }
    }

    private void on_conversation_trimmed(Geary.Email email) {
        remove_email(email);
    }

    private void on_update_flags(Geary.Email email) {
        if (!this.email_rows.has_key(email.id)) {
            return;
        }

        EmailRow row = this.email_rows.get(email.id);
        row.view.update_flags(email);
    }

    private void on_mark_email(ConversationEmail view,
                               Geary.NamedFlag? to_add,
                               Geary.NamedFlag? to_remove) {
        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        ids.add(view.email.id);
        mark_emails(ids, flag_to_flags(to_add), flag_to_flags(to_remove));
    }

    private void on_mark_email_from_here(ConversationEmail view,
                                         Geary.NamedFlag? to_add,
                                         Geary.NamedFlag? to_remove) {
        Geary.Email email = view.email;
        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        ids.add(email.id);
        this.foreach((row) => {
                if (row.get_visible()) {
                    Geary.Email other = ((EmailRow) row).view.email;
                    if (Geary.Email.compare_sent_date_ascending(
                            email, other) < 0) {
                        ids.add(other.id);
                    }
                }
            });
        mark_emails(ids, flag_to_flags(to_add), flag_to_flags(to_remove));
    }

    private void on_message_body_state_notify(GLib.Object obj,
                                              GLib.ParamSpec param) {
        ConversationEmail? view = obj as ConversationEmail;
        if (view != null && view.message_body_state == COMPLETED) {
            this.mark_read_timer.start();
        }
    }

    private Geary.EmailFlags? flag_to_flags(Geary.NamedFlag? flag) {
        Geary.EmailFlags flags = null;
        if (flag != null) {
            flags = new Geary.EmailFlags();
            flags.add(flag);
        }
        return flags;
    }

    private void on_row_activated(Gtk.ListBoxRow widget) {
        EmailRow? row = widget as EmailRow;
        if (row != null) {
            // Allow non-last rows to be expanded/collapsed, but also let
            // the last row to be expanded since appended sent emails will
            // be appended last. Finally, don't let rows with active
            // composers be collapsed.
            if (row.is_expanded) {
                if (get_row_at_index(row.get_index() + 1) != null) {
                    row.collapse();
                }
            } else {
                row.expand.begin();
            }
        }
    }

}
