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
 
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
    // Fired when the user clicks "reply" in the message menu.
    public signal void reply_to_message(Geary.Email message);

    // Fired when the user clicks "reply all" in the message menu.
    public signal void reply_all_message(Geary.Email message);

    // Fired when the user clicks "forward" in the message menu.
    public signal void forward_message(Geary.Email message);

    // Fired when the user mark messages.
    public signal void mark_messages(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    // Fired when the user opens an attachment.
    public signal void open_attachment(Geary.Attachment attachment);

    // Fired when the user wants to save one or more attachments.
    public signal void save_attachments(Gee.List<Geary.Attachment> attachment);
    
    // Fired when the user wants to save an image buffer to disk
    public signal void save_buffer_to_file(string? filename, Geary.Memory.Buffer buffer);
    
    // Fired when the user clicks the edit draft button.
    public signal void edit_draft(Geary.Email message);
    
    // Fired when the viewer has been cleared.
    public signal void cleared();
    
    // Current conversation, or null if none.
    public Geary.App.Conversation? current_conversation = null;
    
    // Overlay containing any inline composers.
    public ScrollableOverlay compose_overlay;

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

    // Conversation messages list
    [GtkChild]
    private Gtk.ListBox conversation_listbox;

    // Label for displaying messages in the main pane.
    [GtkChild]
    private Gtk.Label user_message_label;

    // List of emails in this view.
    private Gee.TreeSet<Geary.Email> messages { get; private set; default = 
        new Gee.TreeSet<Geary.Email>(Geary.Email.compare_sent_date_ascending); }
    
    // Maps emails to their corresponding ListBoxRow.
    private Gee.HashMap<Geary.EmailIdentifier, Gtk.ListBoxRow> email_to_row = new
        Gee.HashMap<Geary.EmailIdentifier, Gtk.ListBoxRow>();
    
    // State machine setup for search/find modes.
    private Geary.State.MachineDescriptor search_machine_desc = new Geary.State.MachineDescriptor(
        "ConversationViewer search", SearchState.NONE, SearchState.COUNT, SearchEvent.COUNT, null, null); 
   
    private ViewState state = ViewState.CONVERSATION;
    private weak Geary.Folder? current_folder = null;
    private weak Geary.SearchFolder? search_folder = null;
    private Geary.App.EmailStore? email_store = null;
    private Geary.AccountInformation? current_account_information = null;
    private ConversationFindBar conversation_find_bar;
    private Cancellable cancellable_fetch = new Cancellable();
    private Geary.State.Machine fsm;
    private uint select_conversation_timeout_id = 0;
    private bool have_conversations = false;
    
    public ConversationViewer() {
        // Setup the conversation list box
        conversation_listbox.set_sort_func((row1, row2) => {
                return Geary.Email.compare_sent_date_ascending(
                    ((ConversationMessage) row1.get_child()).email,
                    ((ConversationMessage) row2.get_child()).email
                );
            });
        conversation_listbox.row_activated.connect((box, row) => {
                if (email_to_row.size > 1) {
                    toggle_show_message(row);
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
        
        //compose_overlay = new ScrollableOverlay(web_view);
        //conversation_viewer_scrolled.add(compose_overlay);

        //conversation_find_bar = new ConversationFindBar(web_view);
        //conversation_find_bar.no_show_all = true;
        //conversation_find_bar.close.connect(() => { fsm.issue(SearchEvent.CLOSE_FIND_BAR); });
        //pack_start(conversation_find_bar, false);

        do_conversation();
    }
    
    public Geary.Email? get_last_message() {
        return messages.is_empty ? null : messages.last();
    }
    
    public Geary.Email? get_selected_message(out string? quote) {
        // XXX
        quote = "";
        return null;
    }
    
    public void check_mark_read() {
        Gee.ArrayList<Geary.EmailIdentifier> emails = new Gee.ArrayList<Geary.EmailIdentifier>();
        // foreach (Geary.Email message in messages) {
        //  try {
        //      if (message.email_flags.is_unread()) {
        //          ConversationMessage row = conversation_message_for_id(message.id);
        //          if (!row.is_manual_read() &&
        //              body.offset_top + body.offset_height > scroll_top &&
        //              body.offset_top + 28 < scroll_top + scroll_height) {  // 28 = 15 padding + 13 first line of text
        //              emails.add(message.id);
                        
        //              // since it can take some time for the new flags
        //              // to round-trip back to ConversationViewer's
        //              // signal handlers, mark as manually read here
        //              mark_manual_read(message.id);
        //          }
        //      }
        //  } catch (Error error) {
        //      debug("Problem checking email class: %s", error.message);
        //  }
        // }

        if (emails.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            mark_messages(emails, null, flags);
        }
    }

    // Use this when an email has been marked read through manual (user) intervention
    public void mark_manual_read(Geary.EmailIdentifier id) {
        ConversationMessage? row = conversation_message_for_id(id);
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
                    // Need to trigger "No messages selected"
                    conversation_list_view.conversations_selected(prev_selection);
                } else {
                    conversation_list_view.select_conversations(prev_selection);
                }
            });
        composer_page.pack_start(box);
        set_visible_child(composer_page);
    }
    
    // Removes all displayed e-mails from the view.
    private void clear() {
        foreach (Gtk.Widget child in conversation_listbox.get_children()) {
            conversation_listbox.remove(child);
        }
        email_to_row.clear();
        messages.clear();
        current_conversation = null;
        cleared();
    }

    private void on_folder_selected(Geary.Folder? folder) {
        cancel_load();
        current_folder = folder;
        have_conversations = false;
        email_store = (current_folder == null ? null : new Geary.App.EmailStore(current_folder.account));
        fsm.issue(SearchEvent.RESET);
        
        if (folder == null) {
            clear();
            current_account_information = null;
        }

        if (state == ViewState.CONVERSATION) {
            set_visible_child(loading_page);
        }
        
        if (current_folder is Geary.SearchFolder) {
            fsm.issue(SearchEvent.ENTER_SEARCH_FOLDER);
            //web_view.allow_collapsing(false);
        } else {
            //web_view.allow_collapsing(true);
        }
    }
    
    private void on_conversation_count_changed(int count) {
        if (state == ViewState.CONVERSATION) {
            if (count > 0) {
                have_conversations = true;
                set_visible_child(conversation_page);
            } else {
                user_message_label.set_text(state == ViewState.CONVERSATION
                                            ? _("No conversations in folder.")
                                            : _("No search results found."));
                set_visible_child(user_message_page);
            }
        }
    }
    
    private void on_conversations_selected(Gee.Set<Geary.App.Conversation> conversations,
        Geary.Folder current_folder) {
        if (state == ViewState.CONVERSATION) {
        
            cancel_load();

            if (current_conversation != null) {
                current_conversation.appended.disconnect(on_conversation_appended);
                current_conversation.trimmed.disconnect(on_conversation_trimmed);
                current_conversation.email_flags_changed.disconnect(update_flags);
                current_conversation = null;
            }
        
            // Disable message buttons until conversation loads.
            GearyApplication.instance.controller.enable_message_buttons(false);

            if (!(current_folder is Geary.SearchFolder) &&
                have_conversations &&
                conversations.size == 0) {
                set_visible_child(splash_page);
                return;
            }

            if (conversations.size == 1) {
                clear();
                //web_view.scroll_reset();
            
                if (select_conversation_timeout_id != 0)
                    Source.remove(select_conversation_timeout_id);
            
                // If the load is taking too long, display a spinner.
                select_conversation_timeout_id =
                Timeout.add(SELECT_CONVERSATION_TIMEOUT_MSEC, () => {
                        if (select_conversation_timeout_id != 0) {
                            set_visible_child(loading_page);
                        }
                        return false;
                    });
            
                current_conversation = Geary.Collection.get_first(conversations);
            
                select_conversation_async.begin(current_conversation, current_folder,
                                                on_select_conversation_completed);
            
                current_conversation.appended.connect(on_conversation_appended);
                current_conversation.trimmed.connect(on_conversation_trimmed);
                current_conversation.email_flags_changed.connect(update_flags);
                
                GearyApplication.instance.controller.enable_message_buttons(true);
            } else if (conversations.size > 1) {
                show_multiple_selected(conversations.size);
                GearyApplication.instance.controller.enable_multiple_message_buttons();
            }
        }
    }
    
    private async void select_conversation_async(Geary.App.Conversation conversation,
        Geary.Folder current_folder) throws Error {
        // Load this once, so if it's cancelled, we cancel the WHOLE load.
        Cancellable cancellable = cancellable_fetch;

        // Fetch full messages.
        Gee.Collection<Geary.Email>? messages_to_add
            = yield list_full_messages_async(conversation.get_emails(
            Geary.App.Conversation.Ordering.SENT_DATE_ASCENDING), cancellable);

        if (cancellable.is_cancelled()) {
            return;
        }
        
        // Add messages.
        if (messages_to_add != null) {
            foreach (Geary.Email email in messages_to_add)
                add_message(email, conversation.is_in_current_folder(email.id));
        }

        if (current_folder is Geary.SearchFolder) {
            yield highlight_search_terms();
        } else {
            compress_emails();
            // Ensure the last message is always shown
            show_message(conversation_listbox.get_row_at_index(messages.size - 1),
                         false);
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

    private void show_multiple_selected(uint selected_count) {
        user_message_label.set_text(
            ngettext("%u conversation selected.",
                     "%u conversations selected.",
                     selected_count).printf(selected_count));
        set_visible_child(user_message_page);
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
        foreach (Geary.Email email in messages)
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
    private async Gee.Collection<Geary.Email>? list_full_messages_async(
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
    private async Geary.Email fetch_full_message_async(Geary.Email email,
        Cancellable? cancellable) throws Error {
        Geary.Email.Field required_fields = ConversationViewer.REQUIRED_FIELDS |
            Geary.ComposedEmail.REQUIRED_REPLY_FIELDS;
        
        return yield email_store.fetch_email_async(email.id, required_fields,
            Geary.Folder.ListFlags.NONE, cancellable);
    }
    
    // Cancels the current message load, if in progress.
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
        add_message(yield fetch_full_message_async(email, cancellable_fetch),
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
        remove_message(email);
    }
    
    private void add_message(Geary.Email email, bool is_in_folder) {
        // Ensure the message container is showing and the multi-message counter hidden.
        set_visible_child(conversation_page);
        
        if (messages.contains(email))
            return;

        ConversationMessage message = new ConversationMessage(email, current_folder);
        message.link_selected.connect((link) => { link_selected(link); });
        message.web_view.button_release_event.connect_after((event) => {
                // Consume all non-consumed clicks so the row is not
                // inadvertently activated after clicking on the
                // message body.
                return true;
            });

        Gtk.ListBoxRow row = new Gtk.ListBoxRow();
        row.get_style_context().add_class("frame");
        row.show();
        row.add(message);
        conversation_listbox.add(row);

        messages.add(email);
        email_to_row.set(email.id, row);

        if (email.is_unread() == Geary.Trillian.TRUE) {
            show_message(row, false);
        }
        
        // Update the search results
        //if (conversation_find_bar.visible)
        //    conversation_find_bar.commence_search();
    }
    
    private void remove_message(Geary.Email email) {
        conversation_listbox.remove(email_to_row.get(email.id));
        email_to_row.get(email.id);
        messages.remove(email);
    }

    private void show_message(Gtk.ListBoxRow row, bool include_transitions=true) {
        row.get_style_context().add_class("show-message");
        ((ConversationMessage) row.get_child()).show_message(include_transitions);
    }

    private void hide_message(Gtk.ListBoxRow row) {
        row.get_style_context().remove_class("show-message");
        ((ConversationMessage) row.get_child()).hide_message();
    }

    private void toggle_show_message(Gtk.ListBoxRow row) {
        if (row.get_style_context().has_class("show-message")) {
            hide_message(row);
        } else {
            show_message(row);
        }
    }

    private void compress_emails() {
        conversation_listbox.get_style_context().add_class("compressed");
    }
    
    //private void decompress_emails() {
    //  conversation_listbox.get_style_context().remove_class("compressed");
    //}
    
    private void update_flags(Geary.Email email) {
        // Nothing to do if we aren't displaying this email.
        if (!email_to_row.has_key(email.id)) {
            return;
        }

        Geary.EmailFlags flags = email.email_flags;
        
        // Update the flags in our message set.
        foreach (Geary.Email message in messages) {
            if (message.id.equal_to(email.id)) {
                message.set_flags(flags);
                break;
            }
        }

        // Get the convo message and update its state.
        Gtk.ListBoxRow row = email_to_row.get(email.id);
        ((ConversationMessage) row.get_child()).update_flags(email);
    }
    
    public void show_find_bar() {
        fsm.issue(SearchEvent.OPEN_FIND_BAR);
        conversation_find_bar.focus_entry();
    }
    
    public void find(bool forward) {
        if (!conversation_find_bar.visible)
            show_find_bar();
        
        conversation_find_bar.find(forward);
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

    private ConversationMessage? conversation_message_for_id(Geary.EmailIdentifier id) {
        return (ConversationMessage) email_to_row.get(id).get_child();
    }

}
