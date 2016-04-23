/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A Stack for managing the conversation pane and a {@link Geary.App.Conversation}.
 *
 * Unlike ConversationListStore (which sorts by date received), ConversationViewer sorts by the
 * {@link Geary.Email.date} field (the Date: header), as that's the date displayed to the user.
 */

[GtkTemplate (ui = "/org/gnome/Geary/conversation-viewer.ui")]
public class ConversationViewer : Gtk.Stack {
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

    // Fired when an email is added to the view
    public signal void email_row_added(ConversationEmail email);

    // Fired when an email is removed from the view
    public signal void email_row_removed(ConversationEmail email);

    // Fired when the user marks messages.
    public signal void mark_emails(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    // Fired when the user opens an attachment.
    public signal void open_attachment(Geary.Attachment attachment);

    // Fired when the user wants to save one or more attachments.
    public signal void save_attachments(Gee.List<Geary.Attachment> attachment);
    
    // Fired when the user wants to save an image buffer to disk
    public signal void save_buffer_to_file(string? filename, Geary.Memory.Buffer buffer);
    
    // Fired when the viewer has been cleared.
    public signal void cleared();
    
    // Current conversation, or null if none.
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
    private Gtk.Widget? last_list_row;

    // Label for displaying messages in the main pane.
    [GtkChild]
    private Gtk.Label user_message_label;

    // Sorted set of emails being displayed
    private Gee.TreeSet<Geary.Email> emails { get; private set; default =
        new Gee.TreeSet<Geary.Email>(Geary.Email.compare_sent_date_ascending); }

    // Maps displayed emails to their corresponding ListBoxRow.
    private Gee.HashMap<Geary.EmailIdentifier, Gtk.ListBoxRow> email_to_row = new
        Gee.HashMap<Geary.EmailIdentifier, Gtk.ListBoxRow>();

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
    
    public ConversationViewer() {
        // Setup the conversation list box
        conversation_listbox.set_sort_func((row1, row2) => {
                // If not a ConversationEmail, will be an
                // embedded composer and should always be last.
                ConversationEmail? msg1 = row1.get_child() as ConversationEmail;
                if (msg1 == null) {
                    return 1;
                }
                ConversationEmail? msg2 = row2.get_child() as ConversationEmail;
                if (msg2 == null) {
                    return -1;
                }
                return Geary.Email.compare_sent_date_ascending(msg1.email, msg2.email);
            });
        conversation_listbox.row_activated.connect((box, row) => {
                // If not a ConversationEmail, will be an
                // embedded composer and should not be activated.
                ConversationEmail? msg = row.get_child() as ConversationEmail;
                if (email_to_row.size > 1 && msg != null) {
                    if (msg.is_message_body_visible) {
                        collapse_email(row);
                    } else {
                        expand_email(row);
                    }
                }
            });
        conversation_listbox.realize.connect(() => {
                conversation_page.get_vadjustment()
                    .value_changed.connect(check_mark_read);
            });
        conversation_listbox.size_allocate.connect(check_mark_read);
        conversation_listbox.add.connect((widget) => {
                // Due to Bug 764710, we can only use the CSS
                // :last-child selector for GTK themes after 3.20.3,
                // so for now manually maintain a class on the last
                // box in the convo listbox so we can emulate it.

                Gtk.Widget current_last_row =
                    conversation_listbox.get_children().last().data;;
                if (last_list_row != current_last_row) {
                    if (last_list_row != null) {
                        last_list_row.get_style_context().remove_class("geary_last");
                    }

                    last_list_row = current_last_row;
                    last_list_row.get_style_context().add_class("geary_last");
                }
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
    
    public Geary.Email? get_last_email() {
        return emails.is_empty ? null : emails.last();
    }
    
    public Geary.Email? get_selected_email(out string? quote) {
        // XXX check to see if there is a email with selected text,
        // if so return that
        quote = null;
        return emails.is_empty ? null : emails.last();
    }

    public void check_mark_read() {
        Gee.ArrayList<Geary.EmailIdentifier> email_ids =
            new Gee.ArrayList<Geary.EmailIdentifier>();

        Gtk.Adjustment adj = conversation_page.vadjustment;
        int top_bound = (int) adj.value;
        int bottom_bound = top_bound + (int) adj.page_size;

        const int TEXT_PADDING = 50;
        foreach (Geary.Email email in emails) {
            ConversationEmail conversation_email = conversation_email_for_id(email.id);
            ConversationMessage conversation_message =
                conversation_email.primary_message;
            // Don't bother with not-yet-loaded emails since the
            // size of the body will be off, affecting the visibility
            // of emails further down the conversation.
            if (email.email_flags.is_unread() &&
                conversation_message.is_loading_complete &&
                !conversation_email.is_manual_read()) {
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
                     email_ids.add(email.id);

                     // Since it can take some time for the new flags
                     // to round-trip back to ConversationViewer's
                     // signal handlers, mark as manually read here
                     conversation_email.mark_manual_read();
                 }
             }
        }

        if (email_ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            mark_emails(email_ids, null, flags);
        }
    }

    // Use this when an email has been marked read through manual (user) intervention
    public void mark_manual_read(Geary.EmailIdentifier id) {
        ConversationEmail? row = conversation_email_for_id(id);
        if (row != null) {
            row.mark_manual_read();
        }
    }

    public void blacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null) {
            return;
        }
        email_to_row.get(id).hide();
    }
    
    public void unblacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null) {
            return;
        }
        email_to_row.get(id).show();
    }

    public void do_conversation() {
        state = ViewState.CONVERSATION;
        set_visible_child(loading_page);
    }
    
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
    
    public void do_embedded_composer(ComposerWidget composer, Geary.Email referred) {
        state = ViewState.CONVERSATION;
        
        ComposerEmbed embed = new ComposerEmbed(
            referred, composer, conversation_page
        );
        embed.set_property("name", "composer_embed"); // Bug 764622

        Gtk.ListBoxRow row = new Gtk.ListBoxRow();
        row.get_style_context().add_class("geary_composer");
        row.show();
        row.add(embed);
        conversation_listbox.add(row);

        embed.loaded.connect((box) => {
                row.grab_focus();
            });
        embed.vanished.connect((box) => {
                conversation_listbox.remove(row);
            });

    }

    public new void set_visible_child(Gtk.Widget widget) {
        debug("Showing child: %s\n", widget.get_name());
        base.set_visible_child(widget);
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
        cleared();
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

        // Add emails.
        if (emails_to_add != null) {
            foreach (Geary.Email email in emails_to_add)
                add_email(email, conversation.is_in_current_folder(email.id));
        }

        if (current_folder is Geary.SearchFolder) {
            yield highlight_search_terms();
        } else {
            compress_emails();
        }

        // Ensure the last email is always shown
        Gtk.ListBoxRow last_row =
            conversation_listbox.get_row_at_index(emails.size - 1);
        expand_email(last_row, false);

        loading_conversations = false;
        if (state == ViewState.CONVERSATION) {
            debug("Emails loaded\n");
            set_visible_child(conversation_page);
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
    
    private void on_search_text_changed(Geary.SearchQuery? query) {
        if (query != null)
            highlight_search_terms.begin();
    }
    
    private async void highlight_search_terms() {
        Geary.SearchQuery? query = (this.search_folder != null)
            ? search_folder.search_query
            : null;
        if (query == null)
            return;

        // Remove existing highlights.
        //web_view.unmark_text_matches();

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
            foreach(string match in ordered_matches) {
                //web_view.mark_text_matches(match, false, 0);
            }

            //web_view.set_highlight_text_matches(true);
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
        conversation_email.mark_email_from.connect(on_mark_email_from);

        ConversationMessage conversation_message = conversation_email.primary_message;
        conversation_message.body_box.button_release_event.connect_after((event) => {
                // Consume all non-consumed clicks so the row is not
                // inadvertently activated after clicking on the
                // email body.
                return true;
            });

        Gtk.ListBoxRow row = new Gtk.ListBoxRow();
        row.show();
        row.add(conversation_email);
        email_to_row.set(email.id, row);

        conversation_listbox.add(row);

        if (email.is_unread() == Geary.Trillian.TRUE) {
            expand_email(row, false);
        }

        conversation_email.start_loading.begin(cancellable_fetch);
        email_row_added(conversation_email);

        // Update the search results
        //if (conversation_find_bar.visible)
        //    conversation_find_bar.commence_search();
    }

    private void remove_email(Geary.Email email) {
        Gtk.ListBoxRow row = email_to_row.get(email.id);
        email_row_removed((ConversationEmail) row.get_child());
        conversation_listbox.remove(row);
        email_to_row.get(email.id);
        emails.remove(email);
    }

    private void expand_email(Gtk.ListBoxRow row, bool include_transitions=true) {
        row.get_style_context().add_class("geary_expand");
        ((ConversationEmail) row.get_child()).expand_email(include_transitions);
    }

    private void collapse_email(Gtk.ListBoxRow row) {
        row.get_style_context().remove_class("geary_expand");
        ((ConversationEmail) row.get_child()).collapse_email();
    }

    private void compress_emails() {
        conversation_listbox.get_style_context().add_class("geary_compressed");
    }
    
    //private void decompress_emails() {
    //  conversation_listbox.get_style_context().remove_class("geary_compressed");
    //}
    
    public void show_find_bar() {
        fsm.issue(SearchEvent.OPEN_FIND_BAR);
        conversation_find_bar.focus_entry();
    }
    
    public void find(bool forward) {
        if (!conversation_find_bar.visible)
            show_find_bar();
        
        conversation_find_bar.find(forward);
    }
    
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
        //web_view.set_highlight_text_matches(false);
        //web_view.allow_collapsing(true);
        //web_view.unmark_text_matches();
        
        if (search_folder != null) {
            search_folder.search_query_changed.disconnect(on_search_text_changed);
            search_folder = null;
        }
        
        //if (conversation_find_bar.visible)
        //    fsm.do_post_transition(() => { conversation_find_bar.hide(); }, user, object);
        
        return SearchState.NONE;
    }

    private void on_mark_email(Geary.Email email,
                               Geary.NamedFlag? to_add,
                               Geary.NamedFlag? to_remove) {
        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        ids.add(email.id);
        mark_emails(ids, flag_to_flags(to_add), flag_to_flags(to_remove));
    }

    private void on_mark_email_from(Geary.Email email,
                                    Geary.NamedFlag? to_add,
                                    Geary.NamedFlag? to_remove) {
        Gee.Collection<Geary.EmailIdentifier> ids =
            new Gee.LinkedList<Geary.EmailIdentifier>();
        ids.add(email.id);
        foreach (Geary.Email other in this.emails) {
            if (Geary.Email.compare_sent_date_ascending(email, other) < 0) {
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
        search_folder.search_query_changed.connect(on_search_text_changed);
        
        return SearchState.SEARCH_FOLDER;
    }

    private ConversationEmail? conversation_email_for_id(Geary.EmailIdentifier id) {
        return (ConversationEmail) email_to_row.get(id).get_child();
    }

}
