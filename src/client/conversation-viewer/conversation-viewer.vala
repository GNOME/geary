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
 * ConversationViewer sorts by the {@link Geary.Email.date} field (the
 * Date: header), as that's the date displayed to the user.
 *
 * In addition to the email list, docked composers, a progress spinner
 * and user messages are also displayed, depending on its current
 * state.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-viewer.ui")]
public class ConversationViewer : Gtk.Stack {

    /** Fields that must be available for display as a conversation. */
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.FLAGS
        | Geary.Email.Field.PREVIEW;

    private const int SELECT_CONVERSATION_TIMEOUT_MSEC = 100;

    // Offset from the top of the list box which emails views will
    // scrolled to, so the user can see there are additional messages
    // above it. XXX This is currently approx 1.5 times the height of
    // a collapsed ConversationEmail, it should probably calculated
    // somehow so that differences user's font size are taken into
    // account.
    private const int EMAIL_TOP_OFFSET = 92;

    private enum ViewState {
        // Main view state
        CONVERSATION,
        COMPOSE;
    }

    private enum SearchState {
        // Search/find states.
        NONE,         // Not in search
        FIND,         // Find toolbar
        SEARCH_FOLDER, // Search folder
        
        COUNT;
    }
    
    private enum SearchEvent {
        // User-initated events.
        RESET,
        OPEN_FIND_BAR,
        CLOSE_FIND_BAR,
        ENTER_SEARCH_FOLDER,
        
        COUNT;
    }

    // Custom class used to display ConversationEmail views in the
    // conversation listbox.
    private class EmailRow : Gtk.ListBoxRow {

        private const string EXPANDED_CLASS = "geary-expanded";
        private const string LAST_CLASS = "geary-last";

        // Is the row showing the email's message body?
        public bool is_expanded {
            get { return get_style_context().has_class(EXPANDED_CLASS); }
        }

        // Designate this row as the last visible row in the
        // conversation listbox, or not. See Bug 764710 and
        // on_conversation_listbox_email_row_added
        public bool is_last {
            get { return get_style_context().has_class(LAST_CLASS); }
            set {
                if (value) {
                    get_style_context().add_class(LAST_CLASS);
                } else {
                    get_style_context().remove_class(LAST_CLASS);
                }
            }
        }

        // We can only scroll to a specific row once it has been
        // allocated space in the conversation listbox. This signal
        // allows the viewer to hook up to appropriate times to try to
        // do that scroll.
        public signal void should_scroll();

        public ConversationEmail view {
            get { return (ConversationEmail) get_child(); }
        }

        public EmailRow(ConversationEmail view) {
            add(view);
        }

        public new void expand(bool include_transitions=true) {
            get_style_context().add_class(EXPANDED_CLASS);
            this.view.expand_email(include_transitions);
        }

        public void collapse() {
            get_style_context().remove_class(EXPANDED_CLASS);
            this.view.collapse_email();
        }

        public void enable_should_scroll() {
            this.size_allocate.connect(on_size_allocate);
        }

        private void on_size_allocate() {
            // Disable should_scroll after the message body has been
            // loaded so we don't keep on scrolling later, like when
            // the window has been resized.
            ConversationWebView web_view = view.primary_message.web_view;
            if (web_view.is_height_valid &&
                web_view.load_status == WebKit.LoadStatus.FINISHED) {
                this.size_allocate.disconnect(on_size_allocate);
            }
            
            should_scroll();
        }

    }


    /** Fired when an email view is added to the conversation list. */
    public signal void email_row_added(ConversationEmail email);

    /** Fired when an email view is removed from the conversation list. */
    public signal void email_row_removed(ConversationEmail email);

    /** Fired when the user updates the flags for a set of emails. */
    public signal void mark_emails(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    /** Fired when the email list has been cleared. */
    public signal void cleared();

    /** Current conversation being displayed, or null if none. */
    public Geary.App.Conversation? current_conversation = null;

    // Stack pages
    [GtkChild]
    private Gtk.Image splash_page;
    [GtkChild]
    private Gtk.Spinner loading_page;
    [GtkChild]
    private Gtk.ScrolledWindow conversation_page;
    [GtkChild]
    private Gtk.Box user_message_page;
    [GtkChild]
    private Gtk.Box composer_page;

    // Conversation emails list
    [GtkChild]
    private Gtk.ListBox conversation_listbox;
    private EmailRow? last_email_row = null;

    // Email view with selected text, if any
    private ConversationEmail? body_selected_view = null;

    // Label for displaying messages in the main pane.
    [GtkChild]
    private Gtk.Label user_message_label;

    // Sorted set of emails being displayed
    private Gee.TreeSet<Geary.Email> emails { get; private set; default =
        new Gee.TreeSet<Geary.Email>(Geary.Email.compare_sent_date_ascending); }

    // Maps displayed emails to their corresponding EmailRow.
    private Gee.HashMap<Geary.EmailIdentifier, EmailRow> email_to_row = new
        Gee.HashMap<Geary.EmailIdentifier, EmailRow>();

    // State machine setup for search/find modes.
    private Geary.State.MachineDescriptor search_machine_desc = new Geary.State.MachineDescriptor(
        "ConversationViewer search", SearchState.NONE, SearchState.COUNT, SearchEvent.COUNT, null, null); 
   
    private ViewState state = ViewState.CONVERSATION;
    private weak Geary.Folder? current_folder = null;
    private weak Geary.SearchFolder? search_folder = null;
    private Geary.App.EmailStore? email_store = null;
    private ConversationFindBar conversation_find_bar;
    private Cancellable cancellable_fetch = new Cancellable();
    private Geary.State.Machine fsm;
    private uint select_conversation_timeout_id = 0;
    private bool loading_conversations = false;

    /**
     * Constructs a new conversation view instance.
     */
    public ConversationViewer() {
        // Setup the conversation list box
        conversation_listbox.add.connect(() => {
                update_last_row();
            });
        conversation_listbox.realize.connect(() => {
                conversation_page.get_vadjustment()
                    .value_changed.connect(check_mark_read);
            });
        conversation_listbox.row_activated.connect(
            on_conversation_listbox_row_activated
            );
        conversation_listbox.set_sort_func(
            on_conversation_listbox_sort
            );
        conversation_listbox.size_allocate.connect(() => {
                check_mark_read();
            });

        // Setup state machine for search/find states.
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(SearchState.NONE, SearchEvent.RESET, on_reset),
            new Geary.State.Mapping(SearchState.NONE, SearchEvent.OPEN_FIND_BAR, on_open_find_bar),
            new Geary.State.Mapping(SearchState.NONE, SearchEvent.CLOSE_FIND_BAR, on_close_find_bar),
            new Geary.State.Mapping(SearchState.NONE, SearchEvent.ENTER_SEARCH_FOLDER, on_enter_search_folder),
            
            new Geary.State.Mapping(SearchState.FIND, SearchEvent.RESET, on_reset),
            new Geary.State.Mapping(SearchState.FIND, SearchEvent.OPEN_FIND_BAR, Geary.State.nop),
            new Geary.State.Mapping(SearchState.FIND, SearchEvent.CLOSE_FIND_BAR, on_close_find_bar),
            new Geary.State.Mapping(SearchState.FIND, SearchEvent.ENTER_SEARCH_FOLDER, Geary.State.nop),
            
            new Geary.State.Mapping(SearchState.SEARCH_FOLDER, SearchEvent.RESET, on_reset),
            new Geary.State.Mapping(SearchState.SEARCH_FOLDER, SearchEvent.OPEN_FIND_BAR, on_open_find_bar),
            new Geary.State.Mapping(SearchState.SEARCH_FOLDER, SearchEvent.CLOSE_FIND_BAR, on_close_find_bar),
            new Geary.State.Mapping(SearchState.SEARCH_FOLDER, SearchEvent.ENTER_SEARCH_FOLDER, Geary.State.nop),
        };
        
        fsm = new Geary.State.Machine(search_machine_desc, mappings, null);
        fsm.set_logging(false);
        
        GearyApplication.instance.controller.conversations_selected.connect(on_conversations_selected);
        GearyApplication.instance.controller.folder_selected.connect(on_folder_selected);
        GearyApplication.instance.controller.conversation_count_changed.connect(on_conversation_count_changed);
        
        //conversation_find_bar = new ConversationFindBar(web_view);
        //conversation_find_bar.no_show_all = true;
        //conversation_find_bar.close.connect(() => { fsm.issue(SearchEvent.CLOSE_FIND_BAR); });
        //pack_start(conversation_find_bar, false);

        do_conversation();
    }

    /**
     * Returns the email view to be replied to, if any.
     *
     * If an email view has selected body text that view will be
     * returned. Else the last message by sort order will be returned,
     * if any.
     */
    public ConversationEmail? get_reply_email_view() {
        ConversationEmail? view = this.body_selected_view;
        if (view == null) {
            if (this.last_email_row != null) {
                view = this.last_email_row.view;
            }
        }
        return view;
    }

    /**
     * Displays an email as being read, regardless of its actual flags.
     */
    public void mark_manual_read(Geary.EmailIdentifier id) {
        ConversationEmail? row = conversation_email_for_id(id);
        if (row != null) {
            row.mark_manual_read();
        }
    }

    /**
     * Hides a specific email in the conversation.
     */
    public void blacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null) {
            return;
        }
        email_to_row.get(id).hide();
        update_last_row();
    }

    /**
     * Re-displays a previously blacklisted email.
     */
    public void unblacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null) {
            return;
        }
        email_to_row.get(id).show();
        update_last_row();
    }

    /**
     * Puts the view into conversation mode, showing the email list.
     */
    public void do_conversation() {
        state = ViewState.CONVERSATION;
        set_visible_child(loading_page);
    }

    /**
     * Puts the view into composer mode, showing a full-height composer.
     */
    public void do_compose(ComposerWidget composer) {
        state = ViewState.COMPOSE;
        ComposerBox box = new ComposerBox(composer);

        // XXX move the ConversationListView management code into
        // GearyController or somewhere more appropriate
        ConversationListView conversation_list_view = ((MainWindow) GearyApplication.instance.controller.main_window).conversation_list_view;
        Gee.Set<Geary.App.Conversation>? prev_selection = conversation_list_view.get_selected_conversations();
        conversation_list_view.get_selection().unselect_all();
        box.vanished.connect((box) => {
                do_conversation();
                if (prev_selection.is_empty) {
                    conversation_list_view.conversations_selected(prev_selection);
                } else {
                    conversation_list_view.select_conversations(prev_selection);
                }
            });
        composer_page.pack_start(box);
        set_visible_child(composer_page);
    }

    /**
     * Puts the view into conversation mode, but with an embedded composer.
     */
    public void do_embedded_composer(ComposerWidget composer, Geary.Email referred) {
        state = ViewState.CONVERSATION;

        ComposerEmbed embed = new ComposerEmbed(
            referred, composer, conversation_page
        );
        embed.get_style_context().add_class("geary-composer-embed");

        ConversationEmail? email_view = conversation_email_for_id(referred.id);
        if (email_view != null) {
            email_view.attach_composer(embed);
            embed.loaded.connect((box) => {
                    embed.grab_focus();
                });
            embed.vanished.connect((box) => {
                    email_view.remove_composer(embed);
                });
        } else {
            error("Could not find referred email for embedded composer: %s",
                  referred.id.to_string());
        }
    }

    /**
     * Shows the in-conversation search UI.
     */
    public void show_find_bar() {
        fsm.issue(SearchEvent.OPEN_FIND_BAR);
        conversation_find_bar.focus_entry();
    }

    /**
     * Displays the next/previous match for an in-conversation search.
     */
    public void find(bool forward) {
        if (!conversation_find_bar.visible)
            show_find_bar();

        conversation_find_bar.find(forward);
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

    /**
     * Sets the currently visible page of the stack.
     */
    private new void set_visible_child(Gtk.Widget widget) {
        debug("Showing child: %s\n", widget.get_name());
        base.set_visible_child(widget);
    }

    /**
     * Returns an new Iterable over all email views in the viewer
     */
    private Gee.Iterator<ConversationEmail> email_view_iterator() {
        return this.email_to_row.values.map<ConversationEmail>((row) => {
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

    /**
     * Finds any currently visible messages, marks them as being read.
     */
    private void check_mark_read() {
        Gee.ArrayList<Geary.EmailIdentifier> email_ids =
            new Gee.ArrayList<Geary.EmailIdentifier>();

        Gtk.Adjustment adj = conversation_page.vadjustment;
        int top_bound = (int) adj.value;
        int bottom_bound = top_bound + (int) adj.page_size;

        email_view_iterator().foreach((email_view) => {
            const int TEXT_PADDING = 50;
            ConversationMessage conversation_message = email_view.primary_message;
            // Don't bother with not-yet-loaded emails since the
            // size of the body will be off, affecting the visibility
            // of emails further down the conversation.
            if (email_view.email.email_flags.is_unread() &&
                conversation_message.is_loading_complete &&
                !email_view.is_manual_read()) {
                 int body_top = 0;
                 int body_left = 0;
                 conversation_message.web_view.translate_coordinates(
                     conversation_listbox,
                     0, 0,
                     out body_left, out body_top
                 );
                 int body_bottom = body_top +
                     conversation_message.web_view_allocation.height;

                 // Only mark the email as read if it's actually visible
                 if (body_bottom > top_bound &&
                     body_top + TEXT_PADDING < bottom_bound) {
                     email_ids.add(email_view.email.id);

                     // Since it can take some time for the new flags
                     // to round-trip back to ConversationViewer's
                     // signal handlers, mark as manually read here
                     email_view.mark_manual_read();
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

    // Removes all displayed e-mails from the view.
    private void clear() {
        // Cancel any pending avatar loads here, rather than in
        // ConversationMessage using a Cancellable callback since we
        // don't have per-message control of it when using
        // Soup.Session.queue_message.
        GearyApplication.instance.controller.avatar_session.flush_queue();
        foreach (Gtk.Widget child in conversation_listbox.get_children()) {
            conversation_listbox.remove(child);
        }
        email_to_row.clear();
        emails.clear();
        current_conversation = null;
        body_selected_view = null;
        cleared();
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
        this.conversation_page.get_vadjustment().clamp_page(
            y, y + alloc.height
        );
    }

    // Due to Bug 764710, we can only use the CSS :last-child selector
    // for GTK themes after 3.20.3, so for now manually maintain a
    // class on the last box in the convo listbox so we can emulate
    // it.
    private void update_last_row() {
        EmailRow? last = null;
        this.conversation_listbox.foreach((child) => {
                if (child.is_visible()) {
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

    private void on_folder_selected(Geary.Folder? folder) {
        cancel_load();
        loading_conversations = true;
        current_folder = folder;

        if (folder == null) {
            email_store = null;
            clear();
        } else {
            email_store = new Geary.App.EmailStore(current_folder.account);
        }

        fsm.issue(SearchEvent.RESET);
        if (current_folder is Geary.SearchFolder) {
            fsm.issue(SearchEvent.ENTER_SEARCH_FOLDER);
            //web_view.allow_collapsing(false);
        } else {
            //web_view.allow_collapsing(true);
        }
    }
    
    private void on_conversation_count_changed(int count) {
        if (state == ViewState.CONVERSATION) {
            if (count == 0) {
                user_message_label.set_text((current_folder is Geary.SearchFolder)
                                            ? _("No search results found.")
                                            : _("No conversations in folder."));
                set_visible_child(user_message_page);
            }
        }
    }
    
    private void on_conversations_selected(Gee.Set<Geary.App.Conversation> conversations,
        Geary.Folder current_folder) {
        cancel_load();

        if (current_conversation != null) {
            current_conversation.appended.disconnect(on_conversation_appended);
            current_conversation.trimmed.disconnect(on_conversation_trimmed);
            current_conversation.email_flags_changed.disconnect(on_update_flags);
            current_conversation = null;
        }

        if (state == ViewState.CONVERSATION) {
            // Disable message buttons until conversation loads.
            GearyApplication.instance.controller.enable_message_buttons(false);

            switch (conversations.size) {
            case 0:
                if (!loading_conversations) {
                    set_visible_child(splash_page);
                }
                break;

            case 1:
                // Timer will take care of showing the loading page
                break;

            default:
                user_message_label.set_text(
                    _("%u conversations selected").printf(conversations.size)
                );
                set_visible_child(user_message_page);
                GearyApplication.instance.controller.enable_multiple_message_buttons();
                break;
            }
        }

        if (conversations.size == 1) {
            loading_conversations = true;
            clear();
            
            if (select_conversation_timeout_id != 0)
                Source.remove(select_conversation_timeout_id);
            
            // If the load is taking too long, display a spinner.
            select_conversation_timeout_id =
            Timeout.add(SELECT_CONVERSATION_TIMEOUT_MSEC, () => {
                    if (select_conversation_timeout_id != 0) {
                        debug("Loading timed out\n");
                        set_visible_child(loading_page);
                    }
                    return false;
                });
            
            current_conversation = Geary.Collection.get_first(conversations);

            select_conversation_async.begin(current_conversation, current_folder,
                                            on_select_conversation_completed);
            
            current_conversation.appended.connect(on_conversation_appended);
            current_conversation.trimmed.connect(on_conversation_trimmed);
            current_conversation.email_flags_changed.connect(on_update_flags);
            
            GearyApplication.instance.controller.enable_message_buttons(true);
        }
    }
    
    private async void select_conversation_async(Geary.App.Conversation conversation,
        Geary.Folder current_folder) throws Error {
        // Load this once, so if it's cancelled, we cancel the WHOLE load.
        Cancellable cancellable = cancellable_fetch;

        // Fetch full emails.
        Gee.Collection<Geary.Email>? emails_to_add
            = yield list_full_emails_async(conversation.get_emails(
            Geary.App.Conversation.Ordering.SENT_DATE_ASCENDING), cancellable);

        if (cancellable.is_cancelled()) {
            return;
        }

        if (emails_to_add != null) {
            foreach (Geary.Email email in emails_to_add)
                add_email(email, conversation.is_in_current_folder(email.id));
        }

        // Work out what the first expanded row is. We can't do this
        // in the foreach above since that is not adding messages in
        // order.
        EmailRow? first_expanded_row = null;
        this.conversation_listbox.foreach((child) => {
                if (first_expanded_row == null) {
                    EmailRow row = (EmailRow) child;
                    if (row.is_expanded) {
                        first_expanded_row = row;
                    }
                }
            });

        if (this.last_email_row != null) {
            // The last email should always be expanded so the user
            // isn't presented with a list of collapsed headers when a
            // conversation has no unread messages.
            this.last_email_row.expand(false);

            if (first_expanded_row == null) {
                first_expanded_row = this.last_email_row;
            }

            // The first expanded row (i.e. first unread or simply the
            // last message) is scrolled to the top of the visible
            // area. We need to wait the web view to load first, so
            // that the message has a non-trivial height, and then
            // wait for it to be reallocated, so that it picks up the
            // web_view's height.
            first_expanded_row.should_scroll.connect((row) => {
                    scroll_to(row);
                });
            first_expanded_row.enable_should_scroll();
        }

        if (state == ViewState.CONVERSATION) {
            set_visible_child(conversation_page);
        }

        this.loading_conversations = false;
        debug("Conversation loading complete");

        // Only do search highlighting after all loading is complete
        // since it's async, and hence things like the conversation
        // changing could happen in the mean time
        if (current_folder is Geary.SearchFolder) {
            yield highlight_search_terms();
        } else {
            compress_emails();
        }

    }

    private void on_select_conversation_completed(Object? source, AsyncResult result) {
        select_conversation_timeout_id = 0;
        try {
            select_conversation_async.end(result);
            check_mark_read();
        } catch (Error err) {
            debug("Unable to select conversation: %s", err.message);
        }
    }

    private int on_conversation_listbox_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        ConversationEmail? msg1 = row1.get_child() as ConversationEmail;
        ConversationEmail? msg2 = row2.get_child() as ConversationEmail;
        return Geary.Email.compare_sent_date_ascending(msg1.email, msg2.email);
    }

    private void on_conversation_listbox_row_activated(Gtk.ListBoxRow widget) {
        EmailRow row = (EmailRow) widget;
        if (!row.is_last) {
            if (row.is_expanded) {
                row.collapse();
            } else {
                row.expand();
            }
        }
    }

    private async void highlight_search_terms() {
        Geary.SearchQuery? query = (this.search_folder != null)
            ? search_folder.search_query
            : null;
        if (query == null)
            return;

        // List all IDs of emails we're viewing.
        Gee.Collection<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Email email in emails)
            ids.add(email.id);

        // Using the fetch cancellable here is appropriate since each
        // time the search results change, the old fetch will be
        // cancelled and we should also cancel the highlighting. Store
        // it here for use later in the method.
        Cancellable cancellable = this.cancellable_fetch;

        Gee.Set<string>? search_matches = null;
        try {
            search_matches = yield search_folder.get_search_matches_async(
                ids, cancellable);
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

        // Webkit's highlighting is ... weird.  In order to actually
        // see all the highlighting you're applying, it seems
        // necessary to start with the shortest string and work up.
        // If you don't, it seems that shorter strings will overwrite
        // longer ones, and you're left with incomplete highlighting.
        Gee.ArrayList<string> ordered_matches = new Gee.ArrayList<string>();
        ordered_matches.add_all(search_matches);
        ordered_matches.sort((a, b) => a.length - b.length);

        if (!cancellable.is_cancelled()) {
            message_view_iterator().foreach((msg_view) => {
                    msg_view.highlight_search_terms(search_matches);
                    return true;
                });
        }
    }

    // Given some emails, fetch the full versions with all required fields.
    private async Gee.Collection<Geary.Email>? list_full_emails_async(
        Gee.Collection<Geary.Email> emails, Cancellable? cancellable) throws Error {
        Geary.Email.Field required_fields = ConversationViewer.REQUIRED_FIELDS |
            Geary.ComposedEmail.REQUIRED_REPLY_FIELDS;
        
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Email email in emails)
            ids.add(email.id);
        
        return yield email_store.list_email_by_sparse_id_async(ids, required_fields,
            Geary.Folder.ListFlags.NONE, cancellable);
    }
    
    // Given an email, fetch the full version with all required fields.
    private async Geary.Email fetch_full_email_async(Geary.Email email,
        Cancellable? cancellable) throws Error {
        Geary.Email.Field required_fields = ConversationViewer.REQUIRED_FIELDS |
            Geary.ComposedEmail.REQUIRED_REPLY_FIELDS;
        
        return yield email_store.fetch_email_async(email.id, required_fields,
            Geary.Folder.ListFlags.NONE, cancellable);
    }
    
    // Cancels the current email load, if in progress.
    private void cancel_load() {
        Cancellable old_cancellable = cancellable_fetch;
        cancellable_fetch = new Cancellable();
        
        old_cancellable.cancel();
    }

    private void on_conversation_appended(Geary.App.Conversation conversation, Geary.Email email) {
        on_conversation_appended_async.begin(conversation, email, on_conversation_appended_complete);
    }
    
    private async void on_conversation_appended_async(Geary.App.Conversation conversation,
        Geary.Email email) throws Error {
        add_email(yield fetch_full_email_async(email, cancellable_fetch),
            conversation.is_in_current_folder(email.id));
    }
    
    private void on_conversation_appended_complete(Object? source, AsyncResult result) {
        try {
            on_conversation_appended_async.end(result);
        } catch (Error err) {
            debug("Unable to append email to conversation: %s", err.message);
        }
    }
    
    private void on_conversation_trimmed(Geary.Email email) {
        remove_email(email);
    }
    
    private void add_email(Geary.Email email, bool is_in_folder) {
        if (emails.contains(email)) {
            return;
        }
        emails.add(email);

        // XXX Should be able to edit draft emails from any
        // conversation. This test should be more like "is in drafts
        // folder"
        bool is_draft = (
            current_folder.special_folder_type == Geary.SpecialFolderType.DRAFTS &&
            is_in_folder
        );

        ConversationEmail conversation_email = new ConversationEmail(
            email,
            current_folder.account.get_contact_store(),
            is_draft
        );
        conversation_email.mark_email.connect(on_mark_email);
        conversation_email.mark_email_from_here.connect(on_mark_email_from_here);
        conversation_email.body_selection_changed.connect((email, has_selection) => {
                this.body_selected_view = has_selection ? email : null;
            });

        ConversationMessage conversation_message = conversation_email.primary_message;
        conversation_message.body_box.button_release_event.connect_after((event) => {
                // Consume all non-consumed clicks so the row is not
                // inadvertently activated after clicking on the
                // email body.
                return true;
            });

        // Capture key events on the email's web views to allow
        // scrolling on Space, etc.
        conversation_message.web_view.key_press_event.connect(on_conversation_key_press);
        foreach (ConversationMessage attached in conversation_email.attached_messages) {
            attached.web_view.key_press_event.connect(on_conversation_key_press);
        }

        EmailRow row = new EmailRow(conversation_email);
        row.show();
        email_to_row.set(email.id, row);

        conversation_listbox.add(row);

        if (email.is_unread() == Geary.Trillian.TRUE) {
            row.expand(false);
        }

        conversation_email.start_loading.begin(cancellable_fetch);
        email_row_added(conversation_email);

        // Update the search results
        //if (conversation_find_bar.visible)
        //    conversation_find_bar.commence_search();

        return;
    }

    private void remove_email(Geary.Email email) {
        Gtk.ListBoxRow row = email_to_row.get(email.id);
        email_row_removed((ConversationEmail) row.get_child());
        conversation_listbox.remove(row);
        email_to_row.get(email.id);
        emails.remove(email);
    }

    private void compress_emails() {
        conversation_listbox.get_style_context().add_class("geary_compressed");
    }

    //private void decompress_emails() {
    //  conversation_listbox.get_style_context().remove_class("geary_compressed");
    //}

    private void on_update_flags(Geary.Email email) {
        // Nothing to do if we aren't displaying this email.
        if (!email_to_row.has_key(email.id)) {
            return;
        }

        // Get the convo email and update its state.
        Gtk.ListBoxRow row = email_to_row.get(email.id);
        ((ConversationEmail) row.get_child()).update_flags(email);
    }

    // State reset.
    private uint on_reset(uint state, uint event, void *user, Object? object) {
        //web_view.allow_collapsing(true);

        message_view_iterator().foreach((msg_view) => {
                msg_view.unmark_search_terms();
                return true;
            });

        if (search_folder != null) {
            search_folder = null;
        }

        //if (conversation_find_bar.visible)
        //    fsm.do_post_transition(() => { conversation_find_bar.hide(); }, user, object);

        return SearchState.NONE;
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
        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        ids.add(view.email.id);
        foreach (Geary.Email other in this.emails) {
            if (Geary.Email.compare_sent_date_ascending(view.email, other) < 0) {
                ids.add(other.id);
            }
        }
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

    // Find bar opened.
    private uint on_open_find_bar(uint state, uint event, void *user, Object? object) {
        if (!conversation_find_bar.visible)
            conversation_find_bar.show();
        
        conversation_find_bar.focus_entry();
        //web_view.allow_collapsing(false);
        
        return SearchState.FIND;
    }
    
    // Find bar closed.
    private uint on_close_find_bar(uint state, uint event, void *user, Object? object) {
        if (current_folder is Geary.SearchFolder) {
            highlight_search_terms.begin();
            
            return SearchState.SEARCH_FOLDER;
        } else {
            //web_view.allow_collapsing(true);
            
            return SearchState.NONE;
        } 
    }

    // Search folder entered.
    private uint on_enter_search_folder(uint state, uint event, void *user, Object? object) {
        search_folder = current_folder as Geary.SearchFolder;
        assert(search_folder != null);
        return SearchState.SEARCH_FOLDER;
    }

    [GtkCallback]
    private bool on_conversation_key_press(Gtk.Widget widget, Gdk.EventKey event) {
        // Override some key bindings to get something that works more
        // like a browser page.
        if (event.keyval == Gdk.Key.space) {
            Gtk.ScrollType dir = Gtk.ScrollType.PAGE_DOWN;
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) ==
                Gdk.ModifierType.SHIFT_MASK) {
                dir = Gtk.ScrollType.PAGE_UP;
            }
            conversation_page.scroll_child(dir, false);
            return true;
        }
        return false;
    }

    private ConversationEmail? conversation_email_for_id(Geary.EmailIdentifier id) {
        return email_to_row.get(id).view;
    }

}
