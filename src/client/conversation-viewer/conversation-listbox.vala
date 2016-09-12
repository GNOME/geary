/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
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
public class ConversationListBox : Gtk.ListBox {

    /** Fields that must be available for display as a conversation. */
    private const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.FLAGS
        | Geary.Email.Field.PREVIEW
        | Geary.ComposedEmail.REQUIRED_REPLY_FIELDS;

    // Offset from the top of the list box which emails views will
    // scrolled to, so the user can see there are additional messages
    // above it. XXX This is currently approx 1.5 times the height of
    // a collapsed ConversationEmail, it should probably calculated
    // somehow so that differences user's font size are taken into
    // account.
    private const int EMAIL_TOP_OFFSET = 92;


    // Custom class used to display ConversationEmail views in the
    // conversation listbox.
    private class EmailRow : Gtk.ListBoxRow {

        private const string EXPANDED_CLASS = "geary-expanded";
        private const string LAST_CLASS = "geary-last";
        private const string MATCH_CLASS = "geary-match";


        // Is the row showing the email's message body or just headers?
        public bool is_expanded { get; private set; default = false; }

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

        // Designate this row as the last visible row in the
        // conversation listbox, or not. See Bug 764710 and
        // ::update_last_row() below.
        internal bool is_last {
            set { set_style_context_class(LAST_CLASS, value); }
        }


        // We can only scroll to a specific row once it has been
        // allocated space. This signal allows the viewer to hook up
        // to appropriate times to try to do that scroll.
        public signal void should_scroll();


        public ConversationEmail view {
            get { return (ConversationEmail) get_child(); }
        }

        public EmailRow(ConversationEmail view) {
            add(view);
        }

        public new void expand() {
            this.is_expanded = true;
            update_row_expansion();
        }

        public void collapse() {
            this.is_expanded = false;
            this.is_pinned = false;
            update_row_expansion();
        }

        public void enable_should_scroll() {
            this.size_allocate.connect(on_size_allocate);
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

        private inline void set_style_context_class(string class_name, bool value) {
            if (value) {
                get_style_context().add_class(class_name);
            } else {
                get_style_context().remove_class(class_name);
            }
        }

        private void on_size_allocate() {
            // We need to wait the web view to load first, so that the
            // message has a non-trivial height, and then wait for it
            // to be reallocated, so that it picks up the web_view's
            // height.
            if (view.primary_message.web_view.is_height_valid) {
                // Disable should_scroll after the message body has
                // been loaded so we don't keep on scrolling later,
                // like when the window has been resized.
                this.size_allocate.disconnect(on_size_allocate);
            }

            should_scroll();
        }

    }


    private static int on_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        ConversationEmail? msg1 = row1.get_child() as ConversationEmail;
        ConversationEmail? msg2 = row2.get_child() as ConversationEmail;
        return Geary.Email.compare_sent_date_ascending(msg1.email, msg2.email);
    }


    /** Conversation being displayed. */
    public Geary.App.Conversation conversation { get; private set; }

    // Folder from which the conversation was loaded
    internal Geary.Folder location { get; private set; }

    // Used to load messages in conversation.
    private Geary.App.EmailStore email_store;

    // Contacts for the account this conversation exists in
    private Geary.ContactStore contact_store;

    // Contacts for the account this conversation exists in
    private Geary.AccountInformation account_info;

    // Was this conversation loaded from the drafts folder?
    private bool is_draft_folder;

    // Cancellable for this conversation's data loading.
    private Cancellable cancellable = new Cancellable();

    // Email view with selected text, if any
    private ConversationEmail? body_selected_view = null;

    // Maps displayed emails to their corresponding EmailRow.
    private Gee.HashMap<Geary.EmailIdentifier, EmailRow> id_to_row = new
        Gee.HashMap<Geary.EmailIdentifier, EmailRow>();

    // Last visible row in the list, if any
    private EmailRow? last_email_row = null;

    // Cached search terms to apply to new messages
    private Gee.Set<string>? ordered_search_terms = null;


    /** Fired when an email view is added to the conversation list. */
    public signal void email_added(ConversationEmail email);

    /** Fired when an email view is removed from the conversation list. */
    public signal void email_removed(ConversationEmail email);

    /** Fired when the user updates the flags for a set of emails. */
    public signal void mark_emails(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    /** Fired when an email that matches the current search terms is found. */
    public signal void search_matches_found();


    /**
     * Constructs a new conversation list box instance.
     */
    public ConversationListBox(Geary.App.Conversation conversation,
                               Geary.Folder location,
                               Geary.App.EmailStore? email_store,
                               Geary.ContactStore contact_store,
                               Geary.AccountInformation account_info,
                               bool is_draft_folder,
                               Gtk.Adjustment adjustment) {
        this.conversation = conversation;
        this.location = location;
        this.email_store = email_store;
        this.contact_store = contact_store;
        this.account_info = account_info;
        this.is_draft_folder = is_draft_folder;

        get_style_context().add_class("background");
        get_style_context().add_class("conversation-listbox");

        set_adjustment(adjustment);
        set_selection_mode(Gtk.SelectionMode.NONE);
        set_sort_func(ConversationListBox.on_sort);

        this.key_press_event.connect(on_key_press);
        this.realize.connect(() => {
                adjustment.value_changed.connect(check_mark_read);
            });
        this.row_activated.connect(on_row_activated);
        this.size_allocate.connect(() => { check_mark_read(); });

        this.conversation.appended.connect(on_conversation_appended);
        this.conversation.trimmed.connect(on_conversation_trimmed);
        this.conversation.email_flags_changed.connect(on_update_flags);
    }

    public override void destroy() {
        this.cancellable.cancel();
        this.id_to_row.clear();
        base.destroy();
    }

    public async void load_conversation()
        throws Error {
        EmailRow? first_expanded_row = null;

        // Fetch full emails from the conversation
        Gee.Collection<Geary.Email> full_emails =
            yield list_full_emails_async(
                this.conversation.get_emails(
                    Geary.App.Conversation.Ordering.SENT_DATE_ASCENDING
                )
            );

        // Add them all
        foreach (Geary.Email full_email in full_emails) {
            if (this.cancellable.is_cancelled()) {
                return;
            }
            if (!this.id_to_row.contains(full_email.id)) {
                EmailRow row = add_email(full_email);
                if (first_expanded_row == null && row.is_expanded) {
                    first_expanded_row = row;
                    yield first_expanded_row.view.start_loading(
                        this.cancellable
                    );
                }
            }
        }

        if (this.last_email_row != null && !this.cancellable.is_cancelled()) {
            // The last row should always be expanded, so expand it
            // and start loading if needed.
            this.last_email_row.expand();
            if (this.last_email_row != first_expanded_row) {
                yield this.last_email_row.view.start_loading(this.cancellable);
            }

            // If no other row was expanded by default, use the last
            // row.
            if (first_expanded_row == null) {
                first_expanded_row = this.last_email_row;
            }

            // Ensure we scroll to the first expanded roll when it
            // finishes loading
            first_expanded_row.should_scroll.connect(scroll_to);
            first_expanded_row.enable_should_scroll();

            // Start everything else loading
            this.foreach((child) => {
                    if (!this.cancellable.is_cancelled()) {
                        EmailRow row = (EmailRow) child;
                        if (row != first_expanded_row) {
                            row.view.start_loading.begin(this.cancellable);
                        }
                    }
                });
        
            debug("Conversation loading complete");
        }
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
        if (view == null && this.last_email_row != null) {
            view = this.last_email_row.view;
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
    public void add_embedded_composer(ComposerEmbed embed) {
        EmailRow? row = this.id_to_row.get(embed.referred.id);
        if (row != null) {
            row.view.attach_composer(embed);
            embed.loaded.connect((box) => {
                    embed.grab_focus();
                });
            embed.vanished.connect((box) => {
                    row.view.remove_composer(embed);
                });
        } else {
            error("Could not find referred email for embedded composer: %s",
                  embed.referred.id.to_string());
        }
    }

    /**
     * Finds any currently visible messages, marks them as being read.
     */
    public void check_mark_read() {
        Gee.ArrayList<Geary.EmailIdentifier> email_ids =
            new Gee.ArrayList<Geary.EmailIdentifier>();

        Gtk.Adjustment adj = get_adjustment();
        int top_bound = (int) adj.value;
        int bottom_bound = top_bound + (int) adj.page_size;

        email_view_iterator().foreach((email_view) => {
            const int TEXT_PADDING = 50;
            ConversationMessage conversation_message = email_view.primary_message;
            // Don't bother with not-yet-loaded emails since the
            // size of the body will be off, affecting the visibility
            // of emails further down the conversation.
            if (email_view.email.is_unread().is_certain() &&
                conversation_message.web_view.is_height_valid &&
                !email_view.is_manually_read) {
                 int body_top = 0;
                 int body_left = 0;
                 ConversationWebView web_view = conversation_message.web_view;
                 web_view.translate_coordinates(
                     this,
                     0, 0,
                     out body_left, out body_top
                 );
                 int body_bottom =
                     body_top + web_view.get_allocated_height();

                 // Only mark the email as read if it's actually visible
                 if (body_bottom > top_bound &&
                     body_top + TEXT_PADDING < bottom_bound) {
                     email_ids.add(email_view.email.id);

                     // Since it can take some time for the new flags
                     // to round-trip back to our signal handlers,
                     // mark as manually read here
                     email_view.is_manually_read = true;
                 }
             }
            return true;
        });

        if (email_ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            mark_emails(email_ids, null, flags);
        }
    }

    /**
     * Displays an email as being read, regardless of its actual flags.
     */
    public void mark_manual_read(Geary.EmailIdentifier id) {
        EmailRow? row = this.id_to_row.get(id);
        if (row != null) {
            row.view.is_manually_read = true;
        }
    }

    /**
     * Displays an email as being unread, regardless of its actual flags.
     */
    public void mark_manual_unread(Geary.EmailIdentifier id) {
        EmailRow? row = this.id_to_row.get(id);
        if (row != null) {
            row.view.is_manually_read = false;
        }
    }

    /**
     * Hides a specific email in the conversation.
     */
    public void blacklist_by_id(Geary.EmailIdentifier? id) {
        EmailRow? row = this.id_to_row.get(id);
        if (row != null) {
            row.hide();
            update_last_row();
        }
    }

    /**
     * Re-displays a previously blacklisted email.
     */
    public void unblacklist_by_id(Geary.EmailIdentifier? id) {
        EmailRow? row = this.id_to_row.get(id);
        if (row != null) {
            row.show();
            update_last_row();
        }
    }

    /**
     * Loads search term matches for this list's emails.
     */
    public async void load_search_terms() {
        Geary.SearchFolder search = (Geary.SearchFolder) this.location;
        Geary.SearchQuery? query = search.search_query;
        if (query != null) {

            // List all IDs of emails we're viewing.
            Gee.Collection<Geary.EmailIdentifier> ids =
                new Gee.ArrayList<Geary.EmailIdentifier>();
            foreach (Gee.Map.Entry<Geary.EmailIdentifier, EmailRow> entry
                        in this.id_to_row.entries) {
                if (entry.value.get_visible()) {
                    ids.add(entry.key);
                }
            }

            Gee.Set<string>? search_matches = null;
            try {
                search_matches = yield search.get_search_matches_async(
                    ids, cancellable
                );
            } catch (Error e) {
                debug("Error highlighting search results: %s", e.message);
                // Continue on here since if nothing else we have the
                // fudging to fall back on immediately below.
            }

            if (search_matches == null)
                search_matches = new Gee.HashSet<string>();

            // This applies a fudge-factor set of matches when the database results
            // aren't entirely satisfactory, such as when you search for an email
            // address and the database tokenizes out the @ and ., etc.  It's not meant
            // to be comprehensive, just a little extra highlighting applied to make
            // the results look a little closer to what you typed.
            foreach (string word in query.raw.split(" ")) {
                if (word.has_suffix("\""))
                    word = word.substring(0, word.length - 1);
                if (word.has_prefix("\""))
                    word = word.substring(1);

                if (!Geary.String.is_empty_or_whitespace(word))
                    search_matches.add(word);
            }
            if (!this.cancellable.is_cancelled()) {
                highlight_search_terms(search_matches);
            }
        }
    }

    /**
     * Applies search term highlighting to all email views.
     *
     * Returns true if any were found, else returns false.
     */
    public void highlight_search_terms(Gee.Set<string> search_matches) {
        // Webkit's highlighting is ... weird.  In order to actually
        // see all the highlighting you're applying, it seems
        // necessary to start with the shortest string and work up.
        // If you don't, it seems that shorter strings will overwrite
        // longer ones, and you're left with incomplete highlighting.
        Gee.TreeSet<string> ordered_matches =
            new Gee.TreeSet<string>((a, b) => a.length - b.length);
        ordered_matches.add_all(search_matches);
        this.ordered_search_terms = ordered_matches;
        this.foreach((child) => {
                apply_search_terms((EmailRow) child);
            });
    }

    /**
     * Removes search term highlighting from all messages.
     */
    public void unmark_search_terms() {
        this.ordered_search_terms = null;
        this.foreach((child) => {
                EmailRow row = (EmailRow) child;
                if (row.is_search_match) {
                    row.is_search_match = false;
                    row.view.message_view_iterator().foreach((msg_view) => {
                            msg_view.unmark_search_terms();
                            return true;
                        });
                }
            });
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
                msg_view.web_view.zoom_level = 1.0f;
                return true;
            });
    }

    private EmailRow add_email(Geary.Email email) {
        // Should be able to edit draft emails from any
        // conversation. This test should be more like "is in drafts
        // folder"
        bool is_in_folder = this.conversation.is_in_current_folder(email.id);
        bool is_draft = (this.is_draft_folder && is_in_folder);

        bool is_sent = false;
        if (email.from != null) {
            foreach (Geary.RFC822.MailboxAddress from in email.from) {
                if (this.account_info.has_email_address(from)) {
                    is_sent = true;
                    break;
                }
            }
        }

        ConversationEmail view = new ConversationEmail(
            email,
            this.contact_store,
            is_sent,
            is_draft
        );
        view.mark_email.connect(on_mark_email);
        view.mark_email_from_here.connect(on_mark_email_from_here);
        view.body_selection_changed.connect((email, has_selection) => {
                this.body_selected_view = has_selection ? email : null;
            });

        ConversationMessage conversation_message = view.primary_message;
        conversation_message.body.button_release_event.connect_after((event) => {
                // Consume all non-consumed clicks so the row is not
                // inadvertently activated after clicking on the
                // email body.
                return true;
            });

        // Capture key events on the email's web views to allow
        // scrolling on Space, etc. need to do this after loading so
        // attached messages are present
        view.message_view_iterator().foreach((msg_view) => {
                msg_view.web_view.key_press_event.connect(on_key_press);
                return true;
            });

        EmailRow row = new EmailRow(view);
        row.show();
        this.id_to_row.set(email.id, row);

        add(row);
        update_last_row();
        email_added(view);

        // Expand interesting messages by default
        if (email.is_unread().is_certain() ||
            email.is_flagged().is_certain()) {
            row.expand();
        }

        // Apply any existing search terms to the new row
        if (this.ordered_search_terms != null) {
            apply_search_terms(row);
        }

        return row;
    }

    private void remove_email(Geary.Email email) {
        EmailRow? row = null;
        if (this.id_to_row.unset(email.id, out row)) {
            remove(row);
            email_removed(row.view);
        }
    }

    private void scroll_to(EmailRow row) {
        Gtk.Allocation? alloc = null;
        row.get_allocation(out alloc);
        int y = 0;
        if (alloc.y > EMAIL_TOP_OFFSET) {
            y = alloc.y - EMAIL_TOP_OFFSET;
        }

        // XXX This doesn't always quite work right, maybe since it's
        // hard getting a reliable height out of WebKitGTK, or maybe
        // because we stop calling this method when the email message
        // body has finished loading, but attachments and sub-messages
        // may still be loading. Or both?
        get_adjustment().set_value(y);
    }

    // Due to Bug 764710, we can only use the CSS :last-child selector
    // for GTK themes after 3.20.3, so for now manually maintain a
    // class on the last box so we can emulate it
    private void update_last_row() {
        EmailRow? last = null;
        this.foreach((child) => {
                if (child.get_visible()) {
                    last = (EmailRow) child;
                }
            });

        if (this.last_email_row != last) {
            if (this.last_email_row != null) {
                this.last_email_row.is_last = false;
            }

            this.last_email_row = last;
            this.last_email_row.is_last = true;
        }
    }

    // Given some emails, fetch the full versions with all required fields.
    private async Gee.Collection<Geary.Email> list_full_emails_async(
        Gee.Collection<Geary.Email> emails) throws Error {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Email email in emails)
            ids.add(email.id);

        Gee.Collection<Geary.Email>? full_emails =
            yield this.email_store.list_email_by_sparse_id_async(
                ids,
                REQUIRED_FIELDS,
                Geary.Folder.ListFlags.NONE,
                this.cancellable
            );

        if (full_emails == null) {
            full_emails = Gee.Collection.empty<Geary.Email>();
        }

        return full_emails;
    }
    
    private void apply_search_terms(EmailRow row) {
        if (row.view.message_bodies_loaded) {
            apply_search_terms_impl(row);
        } else {
            row.view.notify["message-bodies-loaded"].connect(() => {
                    apply_search_terms_impl(row);
                });
        }
    }

    private inline void apply_search_terms_impl(EmailRow row) {
        bool found = false;
        row.view.message_view_iterator().foreach((view) => {
                if (view.highlight_search_terms(this.ordered_search_terms) > 0) {
                    found = true;
                    return false;
                }
                return true;
            });
        row.is_search_match = found;
        if (found) {
            search_matches_found();
        }
    }

    /**
     * Returns an new Iterable over all email views in the viewer
     */
    private Gee.Iterator<ConversationEmail> email_view_iterator() {
        return this.id_to_row.values.map<ConversationEmail>((row) => {
                return (ConversationEmail) row.get_child();
            });
    }

    /**
     * Returns a new Iterable over all message views in the viewer
     */
    private Gee.Iterator<ConversationMessage> message_view_iterator() {
        return Gee.Iterator.concat<ConversationMessage>(
            email_view_iterator().map<Gee.Iterator<ConversationMessage>>(
                (email_view) => { return email_view.message_view_iterator(); }
            )
        );
    }

    private void on_conversation_appended(Geary.App.Conversation conversation, Geary.Email email) {
        on_conversation_appended_async.begin(conversation, email);
    }

    private async void on_conversation_appended_async(
        Geary.App.Conversation conversation, Geary.Email part_email) {
        try {
            if (!this.id_to_row.contains(part_email.id)) {
                Geary.Email full_email = yield this.email_store.fetch_email_async(
                    part_email.id,
                    REQUIRED_FIELDS,
                    Geary.Folder.ListFlags.NONE,
                    this.cancellable
                );

                if (!this.cancellable.is_cancelled()) {
                    EmailRow row = add_email(full_email);
                    yield row.view.start_loading(this.cancellable);
                }
            }
        } catch (Error err) {
            debug("Unable to append email to conversation: %s", err.message);
        }
    }

    private void on_conversation_trimmed(Geary.Email email) {
        remove_email(email);
    }

    private void on_update_flags(Geary.Email email) {
        if (!this.id_to_row.has_key(email.id)) {
            return;
        }

        EmailRow row = this.id_to_row.get(email.id);
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

    private Geary.EmailFlags? flag_to_flags(Geary.NamedFlag? flag) {
        Geary.EmailFlags flags = null;
        if (flag != null) {
            flags = new Geary.EmailFlags();
            flags.add(flag);
        }
        return flags;
    }

    private bool on_key_press(Gtk.Widget widget, Gdk.EventKey event) {
        // Override some key bindings to get something that works more
        // like a browser page.
        if (event.keyval == Gdk.Key.space) {
            Gtk.ScrollType dir = Gtk.ScrollType.PAGE_DOWN;
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) ==
                Gdk.ModifierType.SHIFT_MASK) {
                dir = Gtk.ScrollType.PAGE_UP;
            }
            this.move_cursor(Gtk.MovementStep.PAGES, 1);
            return true;
        }
        return false;
    }

    private void on_row_activated(Gtk.ListBoxRow widget) {
        EmailRow row = (EmailRow) widget;
        // Allow non-last rows to be expanded/collapsed, but also let
        // the last row to be expanded since appended sent emails will
        // be appended last. Finally, don't let rows with active
        // composers be collapsed.
        if (row.is_expanded) {
            if (this.last_email_row != row && row.view.composer == null) {
                row.collapse();
            }
        } else {
            row.expand();
        }
    }

}
