/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A WebKit view displaying all the emails in a {@link Geary.App.Conversation}.
 *
 * Unlike ConversationListStore (which sorts by date received), ConversationViewer sorts by the
 * {@link Geary.Email.date} field (the Date: header), as that's the date displayed to the user.
 */

public class ConversationViewer : Gtk.Box {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.FLAGS
        | Geary.Email.Field.PREVIEW;
    
    private const string[] INLINE_MIME_TYPES = {
        "image/png",
        "image/gif",
        "image/jpeg",
        "image/pjpeg",
        "image/bmp",
        "image/x-icon",
        "image/x-xbitmap",
        "image/x-xbm"
    };
    
    private const int ATTACHMENT_PREVIEW_SIZE = 50;
    private const int SELECT_CONVERSATION_TIMEOUT_MSEC = 100;
    private const string MESSAGE_CONTAINER_ID = "message_container";
    private const string SELECTION_COUNTER_ID = "multiple_messages";
    private const string SPINNER_ID = "spinner";
    private const string REPLACED_IMAGE_CLASS = "replaced_inline_image";
    private const string DATA_IMAGE_CLASS = "data_inline_image";
    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;
    private const int QUOTE_SIZE_THRESHOLD = 120;
    
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
    
    // Main display mode.
    private enum DisplayMode {
        NONE = 0,     // Nothing is shown (ni
        CONVERSATION, // Email conversation
        MULTISELECT,  // Message indicating that <> 1 conversations are selected
        LOADING,      // Loading spinner
        
        COUNT;
        
        // Returns the CSS id associated with this mode's DIV container.
        public string get_id() {
            switch (this) {
                case CONVERSATION:
                    return MESSAGE_CONTAINER_ID;
                
                case MULTISELECT:
                    return SELECTION_COUNTER_ID;
                
                case LOADING:
                    return SPINNER_ID;
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    // Internal class to associate inline image buffers (replaced by rotated scaled versions of
    // them) so they can be saved intact if the user requires it
    private class ReplacedImage : Geary.BaseObject {
        public string id;
        public string filename;
        public Geary.Memory.Buffer buffer;
        
        public ReplacedImage(int replaced_number, string filename, Geary.Memory.Buffer buffer) {
            id = "%X".printf(replaced_number);
            this.filename = filename;
            this.buffer = buffer;
        }
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
    
    // List of emails in this view.
    public Gee.TreeSet<Geary.Email> messages { get; private set; default = 
        new Gee.TreeSet<Geary.Email>(Geary.Email.compare_sent_date_ascending); }
    
    // The HTML viewer to view the emails.
    public ConversationWebView web_view { get; private set; }
    
    // Current conversation, or null if none.
    public Geary.App.Conversation? current_conversation = null;
    
    // Overlay consisting of a label in front of a webpage
    private Gtk.Overlay message_overlay;
    
    // Label for displaying overlay messages.
    private Gtk.Label message_overlay_label;
    
    // Overlay containing any inline composers.
    public ScrollableOverlay compose_overlay;
    
    // Paned for holding any paned composers.
    private Gtk.Box composer_boxes;
    
    // Maps emails to their corresponding elements.
    private Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement> email_to_element = new
        Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement>();
    
    // State machine setup for search/find modes.
    private Geary.State.MachineDescriptor search_machine_desc = new Geary.State.MachineDescriptor(
        "ConversationViewer search", SearchState.NONE, SearchState.COUNT, SearchEvent.COUNT, null, null);
    
    private string? hover_url = null;
    private Gtk.Menu? context_menu = null;
    private Gtk.Menu? message_menu = null;
    private Gtk.Menu? attachment_menu = null;
    private Gtk.Menu? image_menu = null;
    private weak Geary.Folder? current_folder = null;
    private weak Geary.SearchFolder? search_folder = null;
    private Geary.App.EmailStore? email_store = null;
    private Geary.AccountInformation? current_account_information = null;
    private ConversationFindBar conversation_find_bar;
    private Cancellable cancellable_fetch = new Cancellable();
    private Geary.State.Machine fsm;
    private DisplayMode display_mode = DisplayMode.NONE;
    private uint select_conversation_timeout_id = 0;
    private Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();
    private int next_replaced_buffer_number = 0;
    private Gee.HashMap<string, ReplacedImage> replaced_images = new Gee.HashMap<string, ReplacedImage>();
    private Gee.HashSet<string> replaced_content_ids = new Gee.HashSet<string>();
    private Gee.HashSet<string> blacklist_ids = new Gee.HashSet<string>();
    
    public ConversationViewer() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        
        web_view = new ConversationWebView();
        
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
        
        web_view.hovering_over_link.connect(on_hovering_over_link);
        web_view.context_menu.connect(() => { return true; }); // Suppress default context menu.
        web_view.realize.connect( () => { web_view.get_vadjustment().value_changed.connect(mark_read); });
        web_view.size_allocate.connect(mark_read);

        web_view.link_selected.connect((link) => { link_selected(link); });
        
        compose_overlay = new ScrollableOverlay(web_view);
        
        Gtk.ScrolledWindow conversation_viewer_scrolled = new Gtk.ScrolledWindow(null, null);
        conversation_viewer_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        conversation_viewer_scrolled.add(compose_overlay);
        
        message_overlay = new Gtk.Overlay();
        message_overlay.add(conversation_viewer_scrolled);
        
        Gtk.Paned composer_paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
        composer_paned.pack1(message_overlay, true, false);
        composer_boxes = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        composer_boxes.no_show_all = true;
        composer_paned.pack2(composer_boxes, true, false);
        Configuration config = GearyApplication.instance.config;
        config.bind(Configuration.COMPOSER_PANE_POSITION_KEY, composer_paned, "position");
        pack_start(composer_paned);
        composer_boxes.notify["visible"].connect(() => {
            if (!composer_boxes.visible && !message_overlay.visible)
                message_overlay.show();
            });
        
        conversation_find_bar = new ConversationFindBar(web_view);
        conversation_find_bar.no_show_all = true;
        conversation_find_bar.close.connect(() => { fsm.issue(SearchEvent.CLOSE_FIND_BAR); });
        
        pack_start(conversation_find_bar, false);
    }
    
    public void set_paned_composer(ComposerWidget composer) {
        ComposerBox container = new ComposerBox(composer);
        composer_boxes.pack_start(container);
        composer_boxes.show();
        if (composer.state == ComposerWidget.ComposerState.NEW)
            message_overlay.hide();
    }
    
    public Geary.Email? get_last_message() {
        return messages.is_empty ? null : messages.last();
    }
    
    public Geary.Email? get_selected_message(out string? quote) {
        quote = null;
        WebKit.DOM.Document document = web_view.get_dom_document();
        WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
        if (selection.is_collapsed)
            return get_last_message();
        
        WebKit.DOM.Element? anchor_element = selection.anchor_node as WebKit.DOM.Element;
        Geary.Email? anchor_email = null;
        if (anchor_element == null)
            anchor_element = selection.anchor_node.parent_element;
        if (anchor_element != null)
            anchor_email = get_email_from_element(anchor_element);
        
        WebKit.DOM.Element? focus_element = selection.focus_node as WebKit.DOM.Element;
        Geary.Email? focus_email = null;
        if (focus_element == null)
            focus_element = selection.focus_node.parent_element;
        if (focus_element != null)
            focus_email = get_email_from_element(focus_element);
        
        if (anchor_email != null && anchor_email == focus_email) {
            try {
                WebKit.DOM.Range range = selection.get_range_at(0);
                WebKit.DOM.HTMLElement dummy = (WebKit.DOM.HTMLElement) document.create_element("div");
                bool include_dummy = false;
                WebKit.DOM.Node ancestor_node = range.get_common_ancestor_container();
                WebKit.DOM.Element? ancestor = ancestor_node as WebKit.DOM.Element;
                if (ancestor == null)
                    ancestor = ancestor_node.get_parent_element();
                // If the selection is part of a plain text message, we have to stick it in
                // an appropriately styled div, so that new lines are preserved.
                if (Util.DOM.is_descendant_of(ancestor, ".plaintext")) {
                    dummy.get_class_list().add("plaintext");
                    dummy.set_attribute("style", "white-space: pre-wrap;");
                    include_dummy = true;
                }
                dummy.append_child(range.clone_contents());
                
                // Remove the chrome we put around quotes, leaving only the blockquote element.
                WebKit.DOM.NodeList quotes = dummy.query_selector_all(".quote_container");
                for (int i = 0; i < quotes.length; i++) {
                    WebKit.DOM.Element div = (WebKit.DOM.Element) quotes.item(i);
                    WebKit.DOM.Element blockquote = div.query_selector("blockquote");
                    div.get_parent_element().replace_child(blockquote, div);
                }
                
                quote = include_dummy ? dummy.get_outer_html() : dummy.get_inner_html();
                return anchor_email;
            } catch (Error error) {
                debug("Problem getting selected text: %s", error.message);
            }
        }
        
        return get_last_message();
    }
    
    // Removes all displayed e-mails from the view.
    private void clear(Geary.Folder? new_folder, Geary.AccountInformation? account_information) {
        // Remove all messages from DOM.
        try {
            foreach (WebKit.DOM.HTMLElement element in email_to_element.values) {
                if (element.get_parent_element() != null)
                    element.get_parent_element().remove_child(element);
            }
        } catch (Error e) {
            debug("Error clearing message viewer: %s", e.message);
        }
        email_to_element.clear();
        messages.clear();
        inlined_content_ids.clear();
        replaced_images.clear();
        replaced_content_ids.clear();
        blacklist_ids.clear();
        blacklist_css();
        
        current_account_information = account_information;
        cleared();
    }
    
    // Converts an email ID into HTML ID used by the <div> for the email.
    public string get_div_id(Geary.EmailIdentifier id) {
        return "message_%s".printf(id.to_string());
    }
    
    public void blacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null)
            return;
        blacklist_ids.add(get_div_id(id));
        blacklist_css();
    }
    
    public void unblacklist_by_id(Geary.EmailIdentifier? id) {
        if (id == null)
            return;
        blacklist_ids.remove(get_div_id(id));
        blacklist_css();
    }
    
    private void blacklist_css() {
        GLib.StringBuilder rule = new GLib.StringBuilder();
        bool first = true;
        foreach (string id in blacklist_ids) {
            if (!first)
                rule.append(", ");
            else
                first = false;
            rule.append("div[id=\"" + id + "\"]");
        }
        if (!first)
            rule.append(" { display: none; }");
        
        WebKit.DOM.HTMLElement? style_element = web_view.get_dom_document()
            .get_element_by_id("blacklist_ids") as WebKit.DOM.HTMLElement;
        if (style_element != null) {
            try {
                style_element.set_inner_html(rule.str);
            } catch (Error error) {
                debug("Error setting blaklist CSS: %s", error.message);
            }
        }
    }
    
    private void show_special_message(string msg) {
        // Remove any messages and hide the message container, then show the special message.
        clear(current_folder, current_account_information);
        set_mode(DisplayMode.MULTISELECT);
        
        try {
            // Update the counter's count.
            WebKit.DOM.HTMLElement counter =
                web_view.get_dom_document().get_element_by_id("selection_counter") as WebKit.DOM.HTMLElement;
            counter.set_inner_html(msg);
        } catch (Error e) {
            debug("Error updating counter: %s", e.message);
        }
    }
    
    private void hide_special_message() {
        if (display_mode != DisplayMode.MULTISELECT)
            return;
        
        clear(current_folder, current_account_information);
        set_mode(DisplayMode.NONE);
    }
    
    private void show_multiple_selected(uint selected_count) {
        if (selected_count == 0) {
            show_special_message(_("No conversations selected."));
        } else {
            show_special_message(ngettext("%u conversation selected.", "%u conversations selected.",
                selected_count).printf(selected_count));
        }
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        hide_special_message();
        cancel_load();
        
        current_folder = folder;
        email_store = (current_folder == null ? null : new Geary.App.EmailStore(current_folder.account));
        fsm.issue(SearchEvent.RESET);
        
        if (folder == null) {
            clear(null, null);
            current_conversation = null;
        }
        
        if (current_folder is Geary.SearchFolder) {
            fsm.issue(SearchEvent.ENTER_SEARCH_FOLDER);
            web_view.allow_collapsing(false);
        } else {
            web_view.allow_collapsing(true);
        }
    }
    
    private void on_conversation_count_changed(int count) {
        if (count != 0)
            hide_special_message();
        else if (current_folder is Geary.SearchFolder)
            show_special_message(_("No search results found."));
        else
            show_special_message(_("No conversations in folder."));
    }
    
    private void on_conversations_selected(Gee.Set<Geary.App.Conversation>? conversations,
        Geary.Folder? current_folder) {
        cancel_load();
        // Clear the URL overlay
        on_hovering_over_link(null, null);
        if (current_conversation != null) {
            current_conversation.appended.disconnect(on_conversation_appended);
            current_conversation.trimmed.disconnect(on_conversation_trimmed);
            current_conversation.email_flags_changed.disconnect(update_flags);
            current_conversation = null;
        }
        
        // Disable message buttons until conversation loads.
        GearyApplication.instance.controller.enable_message_buttons(false);
        
        if (conversations == null || conversations.size == 0 || current_folder == null) {
            show_multiple_selected(0);
            return;
        }
        
        if (conversations.size == 1) {
            clear(current_folder, current_folder.account.information);
            web_view.scroll_reset();
            
            if (select_conversation_timeout_id != 0)
                Source.remove(select_conversation_timeout_id);
            
            // If the load is taking too long, display a spinner.
            select_conversation_timeout_id = Timeout.add(SELECT_CONVERSATION_TIMEOUT_MSEC, () => {
                if (select_conversation_timeout_id != 0)
                    set_mode(DisplayMode.LOADING);
                
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
            unhide_last_email();
            compress_emails();
        }
    }
    
    private void on_select_conversation_completed(Object? source, AsyncResult result) {
        try {
            select_conversation_async.end(result);
            
            mark_read();
        } catch (Error err) {
            debug("Unable to select conversation: %s", err.message);
        }
    }

    private async void highlight_search_terms() {
        Geary.SearchQuery? query = (this.search_folder != null)
            ? search_folder.search_query
            : null;
        if (query == null)
            return;

        // Remove existing highlights.
        web_view.unmark_text_matches();

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
            foreach(string match in ordered_matches)
                web_view.mark_text_matches(match, false, 0);

            web_view.set_highlight_text_matches(true);
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
        // Make sure the message container is showing and the multi-message counter hidden.
        set_mode(DisplayMode.CONVERSATION);
        
        if (messages.contains(email))
            return;
        
        string message_id = get_div_id(email.id);
        
        WebKit.DOM.Node insert_before = web_view.container.get_last_child();
        
        messages.add(email);
        Geary.Email? higher = messages.higher(email);
        if (higher != null)
            insert_before = web_view.get_dom_document().get_element_by_id(get_div_id(higher.id));
        
        WebKit.DOM.HTMLElement div_message;
        
        try {
            div_message = make_email_div();
            div_message.set_attribute("id", message_id);
            web_view.container.insert_before(div_message, insert_before);
            if (email.is_unread() == Geary.Trillian.FALSE) {
                div_message.get_class_list().add("hide");
            }
            // Update to use all addresses on the account. Bug 768779
            if (email.from != null && email.from.contains_normalized(current_account_information.primary_mailbox.address)) {
                div_message.get_class_list().add("sent");
            }
        } catch (Error setup_error) {
            warning("Error setting up webkit: %s", setup_error.message);
            
            return;
        }
        email_to_element.set(email.id, div_message);
        
        bool remote_images = false;
        try {
            set_message_html(email.get_message(), div_message, out remote_images);
        } catch (Error error) {
            warning("Error getting message from email: %s", error.message);
        }
        
        if (remote_images) {
            Geary.Contact contact = current_folder.account.get_contact_store().get_by_rfc822(
                email.get_primary_originator());
            bool always_load = contact != null && contact.always_load_remote_images();
            
            if (always_load || email.load_remote_images().is_certain()) {
                show_images_email(div_message, false);
            } else {
                WebKit.DOM.HTMLElement remote_images_bar =
                    Util.DOM.select(div_message, ".remote_images");
                try {
                    ((WebKit.DOM.Element) remote_images_bar).get_class_list().add("show");
                    remote_images_bar.set_inner_html("""%s %s
                        <input type="button" value="%s" class="show_images" />
                        <input type="button" value="%s" class="show_from" />""".printf(
                        remote_images_bar.get_inner_html(),
                        _("This message contains remote images."), _("Show Images"),
                        _("Always Show From Sender")));
                } catch (Error error) {
                    warning("Error showing remote images bar: %s", error.message);
                }
            }
        }
        
        // Set attachment icon and add the attachments container if there are displayed attachments.
        int displayed = displayed_attachments(email);
        set_attachment_icon(div_message, displayed > 0);
        if (displayed > 0) {
            insert_attachments(div_message, email.attachments);
        }
        
        // Add classes according to the state of the email.
        update_flags(email);
        
        // Edit draft button for drafts folder.
        if (in_drafts_folder() && is_in_folder) {
            WebKit.DOM.HTMLElement draft_edit_container = Util.DOM.select(div_message, ".draft_edit");
            WebKit.DOM.HTMLElement draft_edit_button =
                Util.DOM.select(div_message, ".draft_edit_button");
            try {
                draft_edit_container.set_attribute("style", "display:block");
                draft_edit_button.set_inner_html(_("Edit Draft"));
            } catch (Error e) {
                warning("Error setting draft button: %s", e.message);
            }
        }
        
        // Add animation class after other classes set, to avoid initial animation.
        Idle.add(() => {
            try {
                div_message.get_class_list().add("animate");
                // This will only affect any open emails.  Those in the hidden state will have
                // their quotes set when they're opened.
                unset_controllable_quotes(div_message);
            } catch (Error error) {
                debug("Could not enable animation class: %s", error.message);
            }
            return false;
        });
        
        // Attach to the click events for hiding/showing quotes, opening the menu, and so forth.
        Util.DOM.bind_event(web_view, ".email", "contextmenu",
                (Callback) on_context_menu, this);
        Util.DOM.bind_event(web_view, ".quote_container > .hider", "click",
                (Callback) on_hide_quote_clicked);
        Util.DOM.bind_event(web_view, ".quote_container > .shower", "click",
                (Callback) on_show_quote_clicked);
        Util.DOM.bind_event(web_view, ".email_container .menu", "click",
                (Callback) on_menu_clicked, this);
        Util.DOM.bind_event(web_view, ".email_container .starred", "click",
                (Callback) on_unstar_clicked, this);
        Util.DOM.bind_event(web_view, ".email_container .unstarred", "click",
                (Callback) on_star_clicked, this);
        Util.DOM.bind_event(web_view, ".email_container .draft_edit .button", "click",
                (Callback) on_draft_edit_menu, this);
        Util.DOM.bind_event(web_view, ".header .field .value", "click",
                (Callback) on_value_clicked, this);
        Util.DOM.bind_event(web_view, ".email:not(:only-of-type) .header_container, .email .email .header_container","click",
                (Callback) on_body_toggle_clicked, this);
        Util.DOM.bind_event(web_view, ".email .compressed_note", "click",
                (Callback) on_body_toggle_clicked, this);
        Util.DOM.bind_event(web_view, ".attachment_container .attachment", "click",
                (Callback) on_attachment_clicked, this);
        Util.DOM.bind_event(web_view, ".attachment_container .attachment", "contextmenu",
                (Callback) on_attachment_menu, this);
        Util.DOM.bind_event(web_view, "." + DATA_IMAGE_CLASS, "contextmenu",
                (Callback) on_data_image_menu_handler, this);
        Util.DOM.bind_event(web_view, ".remote_images .show_images", "click",
                (Callback) on_show_images, this);
        Util.DOM.bind_event(web_view, ".remote_images .show_from", "click",
                (Callback) on_show_images_from, this);
        Util.DOM.bind_event(web_view, ".remote_images .close_show_images", "click",
                (Callback) on_close_show_images, this);
        Util.DOM.bind_event(web_view, ".body a", "click",
                (Callback) on_link_clicked, this);
        
        // Update the search results
        if (conversation_find_bar.visible)
            conversation_find_bar.commence_search();
    }
    
    private WebKit.DOM.HTMLElement make_email_div() {
        // The HTML is like this:
        // <div id="$MESSAGE_ID" class="email">
        //     <div class="geary_spacer"></div>
        //     <div class="email_container">
        //         <div class="email_warning"></div>
        //         <div class="button_bar">
        //             <div class="starred button"><img class="icon" /></div>
        //             <div class="unstarred button"><img class="icon" /></div>
        //             <div class="menu button"><img class="icon" /></div>
        //         </div>
        //         <table>$HEADER</table>
        //         <span>
        //             $EMAIL_BODY
        //
        //             <div class="signature">$SIGNATURE</div>
        //
        //             <div class="quote_container controllable">
        //                 <div class="shower">[show]</div>
        //                 <div class="hider">[hide]</div>
        //                 <div class="quote">$QUOTE</div>
        //             </div>
        //         </span>
        //     </div>
        // </div>
        return Util.DOM.clone_select(web_view.get_dom_document(), "#email_template");
    }
    
    private void set_message_html(Geary.RFC822.Message message, WebKit.DOM.HTMLElement div_message,
        out bool remote_images) {
        string header = "";
        WebKit.DOM.HTMLElement div_email_container = Util.DOM.select(div_message, "div.email_container");
        
        insert_header_address(ref header, _("From:"), message.from, true);
        
        if (message.to != null)
             insert_header_address(ref header, _("To:"), message.to);
        
        if (message.cc != null)
            insert_header_address(ref header, _("Cc:"), message.cc);
        
        if (message.bcc != null)
            insert_header_address(ref header, _("Bcc:"), message.bcc);
        
        if (message.subject != null)
            insert_header(ref header, _("Subject:"), message.subject.value);
        
        if (message.date != null)
            insert_header_date(ref header, _("Date:"), message.date.value, true);

        // Add the avatar.
        Geary.RFC822.MailboxAddress? primary = message.sender;
        if (primary != null) {
            try {
                WebKit.DOM.HTMLImageElement icon = Util.DOM.select(div_message, ".avatar")
                    as WebKit.DOM.HTMLImageElement;
                icon.set_attribute("src",
                    Gravatar.get_image_uri(primary, Gravatar.Default.MYSTERY_MAN, 48));
            } catch (Error error) {
                debug("Failed to inject avatar URL: %s", error.message);
            }
        }
        
        // Insert the preview text.
        try {
            WebKit.DOM.HTMLElement preview =
                Util.DOM.select(div_message, ".header_container .preview");
            string preview_str = message.get_preview();
            if (preview_str.length == Geary.Email.MAX_PREVIEW_BYTES) {
                preview_str += "…";
            }
            preview.set_inner_text(Geary.String.reduce_whitespace(preview_str));
        } catch (Error error) {
            debug("Failed to add preview text: %s", error.message);
        }
        
        //
        // Build an HTML document from the email with two passes:
        //
        // * Geary.RFC822.Message.get_body() recursively walks the message's MIME structure looking
        //   for text MIME parts and assembles them sequentially.  If non-text MIME parts are
        //   discovered within a multipart/mixed container, it calls inline_image_replacer(), which
        //   converts them to an IMG tag with a data: URI if they are a supported image type.
        //   Otherwise, the MIME part is dropped.
        //
        // * insert_html_markup() then strips everything outside the BODY, turning the BODY tag
        //   itself into a DIV, and performs other massaging of the HTML.  It also looks for IMG
        //   tags that refer to other MIME parts via their Content-ID, converts them to data: URIs,
        //   and inserts them into the document.
        //
        // Attachments are generated and added in add_message(), which calls this method before
        // building the HTML for them.  The above two steps take steps to avoid inlining images
        // that are actually attachments (in particular, get_body() considers their
        // Content-Disposition)
        //

        string? body_text = null;
        remote_images = false;
        try {
            if (message.has_html_body()) {
                body_text = message.get_html_body(inline_image_replacer);
            } else {
                body_text = message.get_plain_body(true, inline_image_replacer);
            }
            body_text = insert_html_markup(body_text ?? "", message, out remote_images);
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        // Graft header and email body into the email container.
        try {
            WebKit.DOM.HTMLElement table_header =
                Util.DOM.select(div_email_container, ".header_container .header");
            table_header.set_inner_html(header);
            
            WebKit.DOM.HTMLElement span_body = Util.DOM.select(div_email_container, ".body");
            span_body.set_inner_html(body_text);
        } catch (Error html_error) {
            warning("Error setting HTML for message: %s", html_error.message);
        }
        
        // Scope <style> tags
        try {
            WebKit.DOM.StyleSheetList style_sheets = web_view.get_dom_document().style_sheets;
            string div_id = div_message.get_attribute("id");
            for (int i = 0; i < style_sheets.length; i++) {
                WebKit.DOM.StyleSheet style_sheet = style_sheets.item(i);
                WebKit.DOM.Element style_element = (WebKit.DOM.Element) style_sheet.owner_node;
                if (Util.DOM.closest_ancestor(style_element, ".email") == div_message)
                    style_element.set_text_content(scope_style_sheet(style_sheet, div_id));
            }
        } catch (Error error) {
            warning("Error scoping style nodes: %s", error.message);
        }

        // Look for any attached emails
        Gee.List<Geary.RFC822.Message> sub_messages = message.get_sub_messages();
        foreach (Geary.RFC822.Message sub_message in sub_messages) {
            WebKit.DOM.HTMLElement div_sub_message = make_email_div();
            bool sub_remote_images = false;
            try {
                div_sub_message.set_attribute("id", "");
                div_sub_message.get_class_list().add("read");
                div_sub_message.get_class_list().add("hide");
                div_message.append_child(div_sub_message);
                set_message_html(sub_message, div_sub_message, out sub_remote_images);
                remote_images = remote_images || sub_remote_images;
            } catch (Error error) {
                debug("Error adding message: %s", error.message);
            }
        }
    }
    
    private static bool is_content_type_supported_inline(Geary.Mime.ContentType content_type) {
        foreach (string mime_type in INLINE_MIME_TYPES) {
            try {
                if (content_type.is_mime_type(mime_type))
                    return true;
            } catch (Error err) {
                debug("Unable to compare MIME type %s: %s", mime_type, err.message);
            }
        }
        
        return false;
    }
    
    // This delegate is called from within Geary.RFC822.Message.get_body while assembling the plain
    // or HTML document when a non-text MIME part is encountered within a multipart/mixed container.
    // If this returns null, the MIME part is dropped from the final returned document; otherwise,
    // this returns HTML that is placed into the document in the position where the MIME part was
    // found
    private string? inline_image_replacer(string filename, Geary.Mime.ContentType? content_type,
        Geary.Mime.ContentDisposition? disposition, string? content_id, Geary.Memory.Buffer buffer) {
        if (content_type == null) {
            debug("Not displaying inline: no Content-Type");
            
            return null;
        }
        
        if (!is_content_type_supported_inline(content_type)) {
            debug("Not displaying %s inline: unsupported Content-Type", content_type.to_string());
            
            return null;
        }
        
        // Even if the image doesn't need to be rotated, there's a win here: by reducing the size
        // of the image at load time, it reduces the amount of work that has to be done to insert
        // it into the HTML and then decoded and displayed for the user ... note that we currently
        // have the doucment set up to reduce the size of the image to fit in the viewport, and a
        // scaled load-and-deode is always faster than load followed by scale.
        Geary.Memory.Buffer rotated_image = buffer;
        string mime_type = content_type.get_mime_type();
        try {
            Gdk.PixbufLoader loader = new Gdk.PixbufLoader();
            loader.size_prepared.connect(on_inline_image_size_prepared);
            
            Geary.Memory.UnownedBytesBuffer? unowned_buffer = buffer as Geary.Memory.UnownedBytesBuffer;
            if (unowned_buffer != null)
                loader.write(unowned_buffer.to_unowned_uint8_array());
            else
                loader.write(buffer.get_uint8_array());
            loader.close();
            
            Gdk.Pixbuf? pixbuf = loader.get_pixbuf();
            if (pixbuf != null) {
                pixbuf = pixbuf.apply_embedded_orientation();
                
                // trade-off here between how long it takes to compress the data and how long it
                // takes to turn it into Base-64 (coupled with how long it takes WebKit to then
                // Base-64 decode and uncompress it)
                uint8[] image_data;
                pixbuf.save_to_buffer(out image_data, "png", "compression", "5");
                
                // Save length before transferring ownership (which frees the array)
                int image_length = image_data.length;
                rotated_image = new Geary.Memory.ByteBuffer.take((owned) image_data, image_length);
                mime_type = "image/png";
            }
        } catch (Error err) {
            debug("Unable to load and rotate image %s for display: %s", filename, err.message);
        }
        
        // store so later processing of the message doesn't replace this element with the original
        // MIME part
        string? escaped_content_id = null;
        if (!Geary.String.is_empty(content_id)) {
            replaced_content_ids.add(content_id);
            escaped_content_id = Geary.HTML.escape_markup(content_id);
        }
        
        // Store the original buffer and its filename in a local map so they can be recalled later
        // (if the user wants to save it) ... note that Content-ID is optional and there's no
        // guarantee that filename will be unique, even in the same message, so need to generate
        // a unique identifier for each object
        ReplacedImage replaced_image = new ReplacedImage(next_replaced_buffer_number++, filename,
            buffer);
        replaced_images.set(replaced_image.id, replaced_image);
        
        return "<img alt=\"%s\" class=\"%s %s\" src=\"%s\" replaced-id=\"%s\" %s />".printf(
            Geary.HTML.escape_markup(filename),
            DATA_IMAGE_CLASS, REPLACED_IMAGE_CLASS,
            Util.DOM.assemble_data_uri(mime_type, rotated_image),
            Geary.HTML.escape_markup(replaced_image.id),
            escaped_content_id != null ? @"cid=\"$escaped_content_id\"" : "");
    }
    
    // Called by Gdk.PixbufLoader when the image's size has been determined but not loaded yet ...
    // this allows us to load the image scaled down, for better performance when manipulating and
    // writing the data URI for WebKit
    private static void on_inline_image_size_prepared(Gdk.PixbufLoader loader, int width, int height) {
        // easier to use as local variable than have the const listed everywhere in the code
        // IN ALL SCREAMING CAPS
        int scale = MAX_INLINE_IMAGE_MAJOR_DIM;
        
        // Borrowed liberally from Shotwell's Dimensions.get_scaled() method
        
        // check for existing fit
        if (width <= scale && height <= scale)
            return;
        
        int adj_width, adj_height;
        if ((width - scale) > (height - scale)) {
            double aspect = (double) scale / (double) width;
            
            adj_width = scale;
            adj_height = (int) Math.round((double) height * aspect);
        } else {
            double aspect = (double) scale / (double) height;
            
            adj_width = (int) Math.round((double) width * aspect);
            adj_height = scale;
        }
        
        loader.set_size(adj_width, adj_height);
    }
    
    /*
     * Go through a style sheet and modify the selectors of style rules so that
     * they only apply to elements in the email identified by div_id.  Certain
     * other rules (font faces, for example) are passed through unaltered, while
     * the rest (like @media rules) are removed, since WebKitGTK doesn't implement
     * the API we'd need to parse them.  WebKitGTK is also missing the API to
     * alter the style sheet in place, so we return a string that will replace the
     * contents of the style sheet in question.
     */
    private string scope_style_sheet(WebKit.DOM.StyleSheet style_sheet, string div_id) {
        string scope = @"div[id='$div_id'] > .email_container > .body ";
        StringBuilder new_style = new StringBuilder();
        WebKit.DOM.CSSRuleList rules = ((WebKit.DOM.CSSStyleSheet) style_sheet).rules;
        try {
            // Remove "html", "body", "html body", and "html > body" from the start of selectors
            GLib.Regex body_html = new Regex("^(\\s*html(\\s*>)?)?(\\s*body)?");
            for (int i = 0; i < rules.length; i++) {
                WebKit.DOM.CSSRule rule = rules.item(i);
                switch (rule.type) {
                    // See https://developer.mozilla.org/en-US/docs/Web/API/CSSRule
                    case 1:   // Style rule
                        new_style.append(body_html.replace_literal(rule.css_text, -1, 0, scope) + "\n");
                    break;
                    
                    case 5:   // Font face rule
                    case 7:   // Keyframes rule
                    case 8:   // Keyframe rule
                    case 10:  // Namespace rule
                    case 11:  // Counter style rule
                    case 14:  // Font feature values rule
                        new_style.append(rule.css_text + "\n");
                    break;
                    
                    // All other rules are omitted.
                }
            }
        } catch (Error error) {
            warning("Regex error in CSS scoping: %s", error.message);
        }
        return new_style.str;
    }
    
    private void unhide_last_email() {
        WebKit.DOM.HTMLElement last_email = (WebKit.DOM.HTMLElement) web_view.container.get_last_child().previous_sibling;
        if (last_email != null) {
            WebKit.DOM.DOMTokenList class_list = last_email.get_class_list();
            try {
                class_list.remove("hide");
            } catch (Error error) {
                // Expected, if not hidden
            }
        }
    }
    
    private void compress_emails() {
        if (messages.size == 0)
            return;
        
        WebKit.DOM.Document document = web_view.get_dom_document();
        WebKit.DOM.Element first_compressed = null, prev_message = null,
            curr_message = document.get_element_by_id("message_container").get_first_element_child(),
            next_message = curr_message.next_element_sibling;
        int compress_count = 0;
        bool prev_hidden = false, curr_hidden = false, next_hidden = false;
        try {
            next_hidden = curr_message.get_class_list().contains("hide");
            // The first step of the loop is to advance the hidden statuses.
        } catch (Error error) {
            debug("Error checking hidden status: %s", error.message);
        }
        
        // Note that next_message = span#placeholder when current_message is last in conversation.
        while (next_message != null) {
            try {
                prev_hidden = curr_hidden;
                curr_hidden = next_hidden;
                next_hidden = next_message.get_class_list().contains("hide");
                if (curr_hidden && prev_hidden && next_hidden ||
                    curr_message.get_class_list().contains("compressed")) {
                    curr_message.get_class_list().add("compressed");
                    compress_count += 1;
                    if (first_compressed == null)
                        first_compressed = curr_message;
                } else if (compress_count > 0) {
                    if (compress_count == 1) {
                        prev_message.get_class_list().remove("compressed");
                    } else {
                        WebKit.DOM.HTMLElement span =
                            first_compressed.first_element_child.first_element_child
                            as WebKit.DOM.HTMLElement;
                        span.set_inner_html(
                            ngettext("%u read message", "%u read messages", compress_count).printf(compress_count));
                        // We need to set the display to get an accurate offset_height
                        span.set_attribute("style", "display:inline-block;");
                        span.set_attribute("style", "display:inline-block; top:%ipx".printf(
                            (int) (curr_message.offset_top - first_compressed.offset_top
                            - span.offset_height) / 2));
                    }
                    compress_count = 0;
                    first_compressed = null;
                }
            } catch (Error error) {
                debug("Error compressing emails: %s", error.message);
            }
            prev_message = curr_message;
            curr_message = next_message;
            next_message = curr_message.next_element_sibling;
        }
    }
    
    private void decompress_emails(WebKit.DOM.Element email_element) {
        WebKit.DOM.Element iter_element = email_element;
        try {
            while ((iter_element != null) && iter_element.get_class_list().contains("compressed")) {
                iter_element.get_class_list().remove("compressed");
                iter_element.first_element_child.first_element_child.set_attribute("style", "display:none");
                iter_element = iter_element.previous_element_sibling;
            }
        } catch (Error error) {
            debug("Error decompressing emails: %s", error.message);
        }
        iter_element = email_element.next_element_sibling;
        try {
            while ((iter_element != null) && iter_element.get_class_list().contains("compressed")) {
                iter_element.get_class_list().remove("compressed");
                iter_element.first_element_child.first_element_child.set_attribute("style", "display:none");
                iter_element = iter_element.next_element_sibling;
            }
        } catch (Error error) {
            debug("Error decompressing emails: %s", error.message);
        }
    }
    
    private Geary.Email? get_email_from_element(WebKit.DOM.Element element) {
        // First get the email container.
        WebKit.DOM.Element? email_element = null;
        try {
            if (element.webkit_matches_selector(".email")) {
                email_element = element;
            } else {
                email_element = Util.DOM.closest_ancestor(element, ".email");
            }
        } catch (Error error) {
            debug("Failed to find div.email from element: %s", error.message);
            return null;
        }
        
        if (email_element == null)
            return null;
        
        // Next find the ID in the email-to-element map.
        Geary.EmailIdentifier? email_id = null;
        foreach (var entry in email_to_element.entries) {
            if (entry.value == email_element) {
                email_id = entry.key;
                break;
            }
        }
        
        if (email_id == null)
            return null;

        // Now lookup the email in our messages set.
        foreach (Geary.Email message in messages) {
            if (message.id == email_id)
                return message;
        }
        
        return null;
    }
    
    private Geary.Attachment? get_attachment_from_element(WebKit.DOM.Element element) {
        Geary.Email? email = get_email_from_element(element);
        if (email == null)
            return null;
         
        try {
            return email.get_attachment(element.get_attribute("data-attachment-id"));
        } catch (Geary.EngineError err) {
            return null;
        }
    }

    private void set_attachment_icon(WebKit.DOM.HTMLElement container, bool show) {
        try {
            WebKit.DOM.DOMTokenList class_list = container.get_class_list();
            Util.DOM.toggle_class(class_list, "attachment", show);
        } catch (Error e) {
            warning("Failed to set attachment icon: %s", e.message);
        }
    }

    private void update_flags(Geary.Email email) {
        // Nothing to do if we aren't displaying this email.
        if (!email_to_element.has_key(email.id)) {
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
        
        // Get the email div and update its state.
        WebKit.DOM.HTMLElement container = email_to_element.get(email.id);
        try {
            WebKit.DOM.DOMTokenList class_list = container.get_class_list();
            Util.DOM.toggle_class(class_list, "read", !flags.is_unread());
            Util.DOM.toggle_class(class_list, "starred", flags.is_flagged());
        } catch (Error e) {
            warning("Failed to set classes on .email: %s", e.message);
        }
        
        try {
            WebKit.DOM.HTMLElement email_warning = Util.DOM.select(container, ".email_warning");
            Util.DOM.toggle_class(email_warning.get_class_list(), "show", email.email_flags.is_outbox_sent());
            if (email.email_flags.is_outbox_sent()) {
                email_warning.set_inner_html(
                    _("This message was sent successfully, but could not be saved to %s.").printf(
                    Geary.SpecialFolderType.SENT.get_display_name()));
            }
        } catch (Error e) {
            warning("Error showing outbox warning bar: %s", e.message);
        }
    }

    private static void on_context_menu(WebKit.DOM.Element clicked_element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        Geary.Email email = conversation_viewer.get_email_from_element(clicked_element);
        if (email != null)
            conversation_viewer.show_context_menu(email, clicked_element);
    }
    
    private void show_context_menu(Geary.Email email, WebKit.DOM.Element clicked_element) {
        context_menu = build_context_menu(email, clicked_element);
        context_menu.show_all();
        context_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }
    
    private Gtk.Menu build_context_menu(Geary.Email email, WebKit.DOM.Element clicked_element) {
        Gtk.Menu menu = new Gtk.Menu();
        
        if (web_view.can_copy_clipboard()) {
            // Add a menu item for copying the current selection.
            Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("_Copy"));
            item.activate.connect(on_copy_text);
            menu.append(item);
        }
        
        if (hover_url != null) {
            if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                // Add a menu item for copying the address.
                Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Email Address"));
                item.activate.connect(on_copy_email_address);
                menu.append(item);
            } else {
                // Add a menu item for copying the link.
                Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Link"));
                item.activate.connect(on_copy_link);
                menu.append(item);
            }
        }
        
        // Select message.
        if (!is_hidden_email(clicked_element)) {
            Gtk.MenuItem select_message_item = new Gtk.MenuItem.with_mnemonic(_("Select _Message"));
            select_message_item.activate.connect(() => {on_select_message(clicked_element);});
            menu.append(select_message_item);
        }
        
        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
        select_all_item.activate.connect(on_select_all);
        menu.append(select_all_item);
        
        // Inspect.
        if (Args.inspector) {
            Gtk.MenuItem inspect_item = new Gtk.MenuItem.with_mnemonic(_("_Inspect"));
            inspect_item.activate.connect(() => {web_view.web_inspector.inspect_node(clicked_element);});
            menu.append(inspect_item);
        }
        
        return menu;
    }

    private static void on_hide_quote_clicked(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.Element parent = element.get_parent_element();
            parent.set_attribute("class", "quote_container controllable hide");
        } catch (Error error) {
            warning("Error hiding quote: %s", error.message);
        }
    }

    private static void on_show_quote_clicked(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.Element parent = element.get_parent_element();
            parent.set_attribute("class", "quote_container controllable show");
        } catch (Error error) {
            warning("Error hiding quote: %s", error.message);
        }
    }

    private static void on_menu_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.show_message_menu(email);
    }

    private static void on_unstar_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.unflag_message(email);
    }

    private static void on_star_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.flag_message(email);
    }

    private static void on_value_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        if (!conversation_viewer.is_hidden_email(element))
            event.stop_propagation();  // Don't allow toggle
    }

    private bool is_hidden_email(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.HTMLElement? email_element = Util.DOM.closest_ancestor(element, ".email");
            if (email_element == null)
                return false;
            
            WebKit.DOM.DOMTokenList class_list = email_element.get_class_list();
            return class_list.contains("hide");
        } catch (Error error) {
            warning("Error getting hidden status: %s", error.message);
            return false;
        }
    }

    private static void on_body_toggle_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        conversation_viewer.on_body_toggle_clicked_self(element);
    }

    private void on_body_toggle_clicked_self(WebKit.DOM.Element element) {
        try {
            if (web_view.get_dom_document().get_body().get_class_list().contains("nohide"))
                return;
            
            WebKit.DOM.HTMLElement? email_element = Util.DOM.closest_ancestor(element, ".email");
            if (email_element == null)
                return;
            
            WebKit.DOM.DOMTokenList class_list = email_element.get_class_list();
            if (class_list.contains("compressed")) {
                decompress_emails(email_element);
            } else if (class_list.contains("hide")) {
                class_list.remove("hide");
                unset_controllable_quotes(email_element);
            } else {
                class_list.add("hide");
            }
        } catch (Error error) {
            warning("Error toggling message: %s", error.message);
        }

        mark_read();
    }

    private static void on_show_images(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        WebKit.DOM.HTMLElement? email_element = Util.DOM.closest_ancestor(element, ".email");
        if (email_element != null)
            conversation_viewer.show_images_email(email_element, true);
    }
    
    private static void on_show_images_from(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email == null)
            return;
        
        Geary.ContactStore contact_store =
            conversation_viewer.current_folder.account.get_contact_store();
        Geary.Contact? contact = contact_store.get_by_rfc822(email.get_primary_originator());
        if (contact == null) {
            debug("Couldn't find contact for %s", email.from.to_string());
            return;
        }
        
        Geary.ContactFlags flags = new Geary.ContactFlags();
        flags.add(Geary.ContactFlags.ALWAYS_LOAD_REMOTE_IMAGES);
        Gee.ArrayList<Geary.Contact> contact_list = new Gee.ArrayList<Geary.Contact>();
        contact_list.add(contact);
        contact_store.mark_contacts_async.begin(contact_list, flags, null);
        
        WebKit.DOM.Document document = conversation_viewer.web_view.get_dom_document();
        try {
            WebKit.DOM.NodeList nodes = document.query_selector_all(".email");
            for (ulong i = 0; i < nodes.length; i ++) {
                WebKit.DOM.Element? email_element = nodes.item(i) as WebKit.DOM.Element;
                if (email_element != null) {
                    string? address = null;
                    WebKit.DOM.Element? address_el = email_element.query_selector(".address_value");
                    if (address_el != null) {
                        address = ((WebKit.DOM.HTMLElement) address_el).get_inner_text();
                    } else {
                        address_el = email_element.query_selector(".address_name");
                        if (address_el != null)
                            address = ((WebKit.DOM.HTMLElement) address_el).get_inner_text();
                    }
                    if (address != null && address.normalize().casefold() == contact.normalized_email)
                        conversation_viewer.show_images_email(email_element, false);
                }
            }
        } catch (Error error) {
            debug("Error showing images: %s", error.message);
        }
    }
    
    private void show_images_email(WebKit.DOM.Element email_element, bool remember) {
        try {
            WebKit.DOM.Element body = Util.DOM.select(email_element, ".body");
            if (body == null) {
                warning("Could not find message body");
            } else {
                WebKit.DOM.NodeList nodes = body.query_selector_all("img");
                for (ulong i = 0; i < nodes.length; i++) {
                    WebKit.DOM.Element? element = nodes.item(i) as WebKit.DOM.Element;
                    if (element == null || !element.has_attribute("src"))
                        continue;
                    
                    string src = element.get_attribute("src");
                    if (!web_view.is_always_loaded(src)) {
                        // Workaround a WebKitGTK+ 2.4.10 crash. See Bug 763933
                        element.remove_attribute("src");
                        element.set_attribute("src", web_view.allow_prefix + src);
                    }
                }
            }
            
            WebKit.DOM.Element? remote_images = Util.DOM.select(email_element, ".remote_images");
            if (remote_images != null)
                remote_images.get_class_list().remove("show");
        } catch (Error error) {
            warning("Error showing images: %s", error.message);
        }
        
        if (remember) {
            // only add flag to load remote images if not already present
            Geary.Email? message = get_email_from_element(email_element);
            if (message != null && !message.load_remote_images().is_certain()) {
                Geary.EmailFlags flags = new Geary.EmailFlags();
                flags.add(Geary.EmailFlags.LOAD_REMOTE_IMAGES);
                mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), flags, null);
            }
        }
    }
    
    private static void on_close_show_images(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        WebKit.DOM.HTMLElement? remote_images = Util.DOM.closest_ancestor(element, ".remote_images");
        if (remote_images != null) {
            try {
                remote_images.get_class_list().remove("show");
            } catch (Error error) {
                warning("Error hiding \"Show images\" bar: %s", error.message);
            }
        }
    }
    
    private static void on_link_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        if (conversation_viewer.on_link_clicked_self(element))
            event.prevent_default();
    }
    
    private bool on_link_clicked_self(WebKit.DOM.Element element) {
        if (!Geary.String.is_empty(element.get_attribute("warning"))) {
            // A warning is open, so ignore clicks.
            return true;
        }
        
        string? href = element.get_attribute("href");
        if (Geary.String.is_empty(href))
            return false;
        string text = ((WebKit.DOM.HTMLElement) element).get_inner_text();
        string href_short, text_short;
        if (!deceptive_text(href, ref text, out href_short, out text_short))
            return false;
        
        WebKit.DOM.HTMLElement div = Util.DOM.clone_select(web_view.get_dom_document(),
            "#link_warning_template");
        try {
            div.set_inner_html("""%s %s <span><a href="%s">%s</a></span> %s
                <span><a href="%s">%s</a></span>""".printf(div.get_inner_html(),
                _("This link appears to go to"), text, text_short,
                _("but actually goes to"), href, href_short));
            div.remove_attribute("id");
            element.parent_node.insert_before(div, element);
            element.set_attribute("warning", "open");
            
            long overhang = div.get_offset_left() + div.get_offset_width() -
                web_view.get_dom_document().get_body().get_offset_width();
            if (overhang > 0)
                div.set_attribute("style", @"margin-left: -$(overhang)px;");
        } catch (Error error) {
            warning("Error showing link warning dialog: %s", error.message);
        }
        Util.DOM.bind_event(web_view, ".link_warning .close_link_warning, .link_warning a", "click",
            (Callback) on_close_link_warning, this);
        return true;
    }
    
    private static void on_draft_edit_menu(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email == null)
            return;
        
        conversation_viewer.edit_draft(email);
    }
    
    /*
     * Test whether text looks like a URI that leads somewhere other than href.  The text
     * will have a scheme prepended if it doesn't already have one, and the short versions
     * have the scheme skipped and long paths truncated.
     */
    private bool deceptive_text(string href, ref string text, out string href_short,
        out string text_short) {
        href_short = "";
        text_short = "";
        // mailto URLs have a different form, and the worst they can do is pop up a composer,
        // so we don't trigger on them.
        if (href.has_prefix("mailto:"))
            return false;
        
        // First, does text look like a URI?  Right now, just test whether it has
        // <string>.<string> in it.  More sophisticated tests are possible.
        GLib.MatchInfo text_match, href_match;
        try {
            GLib.Regex domain = new GLib.Regex(
                "([a-z]*://)?"                  // Optional scheme
                + "([^\\s:/]+\\.[^\\s:/\\.]+)"  // Domain
                + "(/[^\\s]*)?"                 // Optional path
                );
            if (!domain.match(text, 0, out text_match))
                return false;
            if (!domain.match(href, 0, out href_match)) {
                // If href doesn't look like a URL, something is fishy, so warn the user
                href_short = href + _(" (Invalid?)");
                text_short = text;
                return true;
            }
        } catch (Error error) {
            warning("Error in Regex text for deceptive urls: %s", error.message);
            return false;
        }
        
        // Second, do the top levels of the two domains match?  We compare the top n levels,
        // where n is the minimum of the number of levels of the two domains.
        string[] href_parts = href_match.fetch_all();
        string[] text_parts = text_match.fetch_all();
        string[] text_domain = text_parts[2].down().reverse().split(".");
        string[] href_domain = href_parts[2].down().reverse().split(".");
        for (int i = 0; i < text_domain.length && i < href_domain.length; i++) {
            if (text_domain[i] != href_domain[i]) {
                if (href_parts[1] == "")
                    href_parts[1] = "http://";
                if (text_parts[1] == "")
                    text_parts[1] = href_parts[1];
                string temp;
                assemble_uris(href_parts, out temp, out href_short);
                assemble_uris(text_parts, out text, out text_short);
                return true;
            }
        }
        return false;
    }
    
    private void assemble_uris(string[] parts, out string full, out string short_) {
        full = parts[1] + parts[2];
        short_ = parts[2];
        if (parts.length == 4 && parts[3] != "/") {
            full += parts[3];
            if (parts[3].length > 20)
                short_ += parts[3].substring(0, 20) + "…";
            else
                short_ += parts[3];
        }
    }
    
    private static void on_close_link_warning(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        try {
            WebKit.DOM.Element warning_div = Util.DOM.closest_ancestor(element, ".link_warning");
            WebKit.DOM.Element link = (WebKit.DOM.Element) warning_div.get_next_sibling();
            link.remove_attribute("warning");
            warning_div.parent_node.remove_child(warning_div);
        } catch (Error error) {
            warning("Error removing link warning dialog: %s", error.message);
        }
    }

    private static void on_attachment_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        conversation_viewer.on_attachment_clicked_self(element);
    }

    private void on_attachment_clicked_self(WebKit.DOM.Element element) {
        string attachment_id = element.get_attribute("data-attachment-id");
        Geary.Email? email = get_email_from_element(element);
        if (email == null)
            return;
        
        Geary.Attachment? attachment = null;
        try {
            attachment = email.get_attachment(attachment_id);
        } catch (Error error) {
            warning("Error opening attachment: %s", error.message);
        }
        
        if (attachment != null)
            open_attachment(attachment);
    }

    private static void on_attachment_menu(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        Geary.Attachment? attachment = conversation_viewer.get_attachment_from_element(element);
        if (email != null && attachment != null)
            conversation_viewer.show_attachment_menu(email, attachment);
    }
    
    private static void on_data_image_menu_handler(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        conversation_viewer.on_data_image_menu(element, event);
    }
    
    private void on_data_image_menu(WebKit.DOM.Element element, WebKit.DOM.Event event) {
        event.stop_propagation();
        
        string? replaced_id = element.get_attribute("replaced-id");
        if (Geary.String.is_empty(replaced_id))
            return;
        
        ReplacedImage? replaced_image = replaced_images.get(replaced_id);
        if (replaced_image == null)
            return;
        
        image_menu = new Gtk.Menu();
        image_menu.selection_done.connect(() => {
            image_menu = null;
         });
        
        Gtk.MenuItem save_image_item = new Gtk.MenuItem.with_mnemonic(_("_Save Image As..."));
        save_image_item.activate.connect(() => {
            save_buffer_to_file(replaced_image.filename, replaced_image.buffer);
        });
        image_menu.append(save_image_item);
        
        image_menu.show_all();
        
        image_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }
    
    private void on_message_menu_selection_done() {
        message_menu = null;
    }
    
    private void on_attachment_menu_selection_done() {
        attachment_menu = null;
    }

    private void save_attachment(Geary.Attachment attachment) {
        Gee.List<Geary.Attachment> attachments = new Gee.ArrayList<Geary.Attachment>();
        attachments.add(attachment);
        save_attachments(attachments);
    }
    
    private void on_mark_read_message(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), null, flags);
        mark_manual_read(message.id);
    }

    private void on_mark_unread_message(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), flags, null);
        mark_manual_read(message.id);
    }
    
    private void on_mark_unread_from_here(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        
        Gee.Iterator<Geary.Email>? iter = messages.iterator_at(message);
        if (iter == null) {
            warning("Email not found in message list");
            
            return;
        }
        
        // Build a list of IDs to mark.
        Gee.ArrayList<Geary.EmailIdentifier> to_mark = new Gee.ArrayList<Geary.EmailIdentifier>();
        to_mark.add(message.id);
        while (iter.next())
            to_mark.add(iter.get().id);
        
        mark_messages(to_mark, flags, null);
        foreach(Geary.EmailIdentifier id in to_mark)
            mark_manual_read(id);
    }
    
    // Use this when an email has been marked read through manual (user) intervention
    public void mark_manual_read(Geary.EmailIdentifier id) {
        if (email_to_element.has_key(id)) {
            try {
                email_to_element.get(id).get_class_list().add("manual_read");
            } catch (Error error) {
                debug("Adding manual_read class failed: %s", error.message);
            }
        }
    }

    private void on_print_message(Geary.Email message) {
        try {
            email_to_element.get(message.id).get_class_list().add("print");
            web_view.get_main_frame().print();
            email_to_element.get(message.id).get_class_list().remove("print");
        } catch (GLib.Error error) {
            debug("Hiding elements for printing failed: %s", error.message);
        }
    }
    
    private void flag_message(Geary.Email email) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), flags, null);
    }

    private void unflag_message(Geary.Email email) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), null, flags);
    }

    private void show_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
        attachment_menu = build_attachment_menu(email, attachment);
        attachment_menu.show_all();
        attachment_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }
    
    private Gtk.Menu build_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
        Gtk.Menu menu = new Gtk.Menu();
        menu.selection_done.connect(on_attachment_menu_selection_done);
        
        Gtk.MenuItem save_attachment_item = new Gtk.MenuItem.with_mnemonic(_("_Save As..."));
        save_attachment_item.activate.connect(() => save_attachment(attachment));
        menu.append(save_attachment_item);
        
        if (displayed_attachments(email) > 1) {
            Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(_("Save All A_ttachments..."));
            save_all_item.activate.connect(() => save_attachments(email.attachments));
            menu.append(save_all_item);
        }
        
        return menu;
    }
    
    private void show_message_menu(Geary.Email email) {
        message_menu = build_message_menu(email);
        message_menu.show_all();
        message_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }
    
    private Gtk.Menu build_message_menu(Geary.Email email) {
        Gtk.Menu menu = new Gtk.Menu();
        menu.selection_done.connect(on_message_menu_selection_done);
        
        int displayed = displayed_attachments(email);
        if (displayed > 0) {
            string mnemonic = ngettext("Save A_ttachment...", "Save All A_ttachments...",
                displayed);
            Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(mnemonic);
            save_all_item.activate.connect(() => save_attachments(email.attachments));
            menu.append(save_all_item);
            menu.append(new Gtk.SeparatorMenuItem());
        }
        
        if (!in_drafts_folder()) {
            // Reply to a message.
            Gtk.MenuItem reply_item = new Gtk.MenuItem.with_mnemonic(_("_Reply"));
            reply_item.activate.connect(() => reply_to_message(email));
            menu.append(reply_item);

            // Reply to all on a message.
            Gtk.MenuItem reply_all_item = new Gtk.MenuItem.with_mnemonic(_("Reply to _All"));
            reply_all_item.activate.connect(() => reply_all_message(email));
            menu.append(reply_all_item);

            // Forward a message.
            Gtk.MenuItem forward_item = new Gtk.MenuItem.with_mnemonic(_("_Forward"));
            forward_item.activate.connect(() => forward_message(email));
            menu.append(forward_item);
        }
        
        if (menu.get_children().length() > 0) {
            // Separator.
            menu.append(new Gtk.SeparatorMenuItem());
        }
        
        // Mark as read/unread.
        if (email.is_unread().to_boolean(false)) {
            Gtk.MenuItem mark_read_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Read"));
            mark_read_item.activate.connect(() => on_mark_read_message(email));
            menu.append(mark_read_item);
        } else {
            Gtk.MenuItem mark_unread_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Unread"));
            mark_unread_item.activate.connect(() => on_mark_unread_message(email));
            menu.append(mark_unread_item);
            
            if (messages.size > 1 && messages.last() != email) {
                Gtk.MenuItem mark_unread_from_here_item = new Gtk.MenuItem.with_mnemonic(
                    _("Mark Unread From _Here"));
                mark_unread_from_here_item.activate.connect(() => on_mark_unread_from_here(email));
                menu.append(mark_unread_from_here_item);
            }
        }
        
        // Print a message.
        Gtk.MenuItem print_item = new Gtk.MenuItem.with_mnemonic(Stock._PRINT_MENU);
        print_item.activate.connect(() => on_print_message(email));
        menu.append(print_item);

        // Separator.
        menu.append(new Gtk.SeparatorMenuItem());

        // View original message source.
        Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("_View Source"));
        view_source_item.activate.connect(() => on_view_source(email));
        menu.append(view_source_item);

        return menu;
    }

    private WebKit.DOM.HTMLDivElement create_quote_container() throws Error {
        WebKit.DOM.HTMLDivElement quote_container = web_view.create_div();
        quote_container.set_attribute("class", "quote_container controllable hide");
        quote_container.set_inner_html(
            """<div class="shower"><input type="button" value="▼        ▼        ▼" /></div>""" +
            """<div class="hider"><input type="button" value="▲        ▲        ▲" /></div>""" +
            """<div class="quote"></div>""");
        return quote_container;
    }

    private void unset_controllable_quotes(WebKit.DOM.HTMLElement element) throws GLib.Error {
        WebKit.DOM.NodeList quote_list = element.query_selector_all(".quote_container.controllable");
        for (int i = 0; i < quote_list.length; ++i) {
            WebKit.DOM.Element quote_container = quote_list.item(i) as WebKit.DOM.Element;
            long scroll_height = quote_container.query_selector(".quote").scroll_height;
            // If the message is hidden, scroll_height will be 0.
            if (scroll_height > 0 && scroll_height < QUOTE_SIZE_THRESHOLD) {
                quote_container.set_attribute("class", "quote_container");
            }
        }
    }
    
    private string insert_html_markup(string text, Geary.RFC822.Message message, out bool remote_images) {
        remote_images = false;
        try {
            string inner_text = text;
            
            // If email HTML has a BODY, use only that
            GLib.Regex body_regex = new GLib.Regex("<body([^>]*)>(.*)</body>",
                GLib.RegexCompileFlags.DOTALL);
            GLib.MatchInfo matches;
            if (body_regex.match(text, 0, out matches)) {
                inner_text = matches.fetch(2);
                string attrs = matches.fetch(1);
                if (attrs != "")
                    inner_text = @"<div$attrs>$inner_text</div>";
            }
            
            // Create a workspace for manipulating the HTML.
            WebKit.DOM.HTMLElement container = web_view.create_div();
            container.set_inner_html(inner_text);
            
            // Get all the top level block quotes and stick them into a hide/show controller.
            WebKit.DOM.NodeList blockquote_list = container.query_selector_all("blockquote");
            for (int i = 0; i < blockquote_list.length; ++i) {
                // Get the nodes we need.
                WebKit.DOM.Node blockquote_node = blockquote_list.item(i);
                WebKit.DOM.Node? next_sibling = blockquote_node.get_next_sibling();
                WebKit.DOM.Node parent = blockquote_node.get_parent_node();

                // Make sure this is a top level blockquote.
                if (Util.DOM.node_is_child_of(blockquote_node, "BLOCKQUOTE")) {
                    continue;
                }

                // parent
                //     quote_container
                //         blockquote
                //     sibling
                WebKit.DOM.Element quote_container = create_quote_container();
                Util.DOM.select(quote_container, ".quote").append_child(blockquote_node);
                if (next_sibling == null) {
                    parent.append_child(quote_container);
                } else {
                    parent.insert_before(quote_container, next_sibling);
                }
            }

            // Now look for the signature.
            wrap_html_signature(ref container);

            // Then look for all <img> tags. Inline images are replaced with
            // data URLs.
            WebKit.DOM.NodeList inline_list = container.query_selector_all("img");
            for (ulong i = 0; i < inline_list.length; ++i) {
                // Get the MIME content for the image.
                WebKit.DOM.HTMLImageElement img = (WebKit.DOM.HTMLImageElement) inline_list.item(i);
                string? src = img.get_attribute("src");
                if (Geary.String.is_empty(src))
                    continue;
                
                // if no Content-ID, then leave as-is, but note if a non-data: URI is being used for
                // purposes of detecting remote images
                string? content_id = src.has_prefix("cid:") ? src.substring(4) : null;
                if (Geary.String.is_empty(content_id)) {
                    remote_images = remote_images || !src.has_prefix("data:");
                    
                    continue;
                }
                
                // if image has a Content-ID and it's already been replaced by the image replacer,
                // drop this tag, otherwise fix up this one with the Base-64 data URI of the image
                if (!replaced_content_ids.contains(content_id)) {
                    string? filename = message.get_content_filename_by_mime_id(content_id);
                    Geary.Memory.Buffer image_content = message.get_content_by_mime_id(content_id);
                    Geary.Memory.UnownedBytesBuffer? unowned_buffer =
                        image_content as Geary.Memory.UnownedBytesBuffer;
                    
                    // Get the content type.
                    string guess;
                    if (unowned_buffer != null)
                        guess = ContentType.guess(null, unowned_buffer.to_unowned_uint8_array(), null);
                    else
                        guess = ContentType.guess(null, image_content.get_uint8_array(), null);
                    
                    string mimetype = ContentType.get_mime_type(guess);
                    
                    // Replace the SRC to a data URI, the class to a known label for the popup menu,
                    // and the ALT to its filename, if supplied
                    img.remove_attribute("src");  // Work around a WebKitGTK+ crash. Bug 764152
                    img.set_attribute("src", Util.DOM.assemble_data_uri(mimetype, image_content));
                    img.set_attribute("class", DATA_IMAGE_CLASS);
                    if (!Geary.String.is_empty(filename))
                        img.set_attribute("alt", filename);
                    
                    // stash here so inlined image isn't listed as attachment (esp. if it has no
                    // Content-Disposition)
                    inlined_content_ids.add(content_id);
                } else {
                    // replaced by data: URI, remove this tag and let the inserted one shine through
                    img.parent_element.remove_child(img);
                }
            }
            
            // Remove any inline images that were referenced through Content-ID
            foreach (string cid in inlined_content_ids) {
                try {
                    string escaped_cid = Geary.HTML.escape_markup(cid);
                    WebKit.DOM.Element? img = container.query_selector(@"[cid='$escaped_cid']");
                    if (img != null)
                        img.parent_element.remove_child(img);
                } catch (Error error) {
                    debug("Error removing inlined image: %s", error.message);
                }
            }
            
            // Now return the whole message.
            return container.get_inner_html();
        } catch (Error e) {
            debug("Error modifying HTML message: %s", e.message);
            return text;
        }
    }
    
    private void wrap_html_signature(ref WebKit.DOM.HTMLElement container) throws Error {
        // Most HTML signatures fall into one of these designs which are handled by this method:
        //
        // 1. GMail:            <div>-- </div>$SIGNATURE
        // 2. GMail Alternate:  <div><span>-- </span></div>$SIGNATURE
        // 3. Thunderbird:      <div>-- <br>$SIGNATURE</div>
        //
        WebKit.DOM.NodeList div_list = container.query_selector_all("div,span,p");
        int i = 0;
        Regex sig_regex = new Regex("^--\\s*$");
        Regex alternate_sig_regex = new Regex("^--\\s*(?:<br|\\R)");
        for (; i < div_list.length; ++i) {
            // Get the div and check that it starts a signature block and is not inside a quote.
            WebKit.DOM.HTMLElement div = div_list.item(i) as WebKit.DOM.HTMLElement;
            string inner_html = div.get_inner_html();
            if ((sig_regex.match(inner_html) || alternate_sig_regex.match(inner_html)) &&
                !Util.DOM.node_is_child_of(div, "BLOCKQUOTE")) {
                break;
            }
        }

        // If we have a signature, move it and all of its following siblings that are not quotes
        // inside a signature div.
        if (i == div_list.length) {
            return;
        }
        WebKit.DOM.Node elem = div_list.item(i) as WebKit.DOM.Node;
        WebKit.DOM.Element parent = elem.get_parent_element();
        WebKit.DOM.HTMLElement signature_container = web_view.create_div();
        signature_container.set_attribute("class", "signature");
        do {
            // Get its sibling _before_ we move it into the signature div.
            WebKit.DOM.Node? sibling = elem.get_next_sibling();
            signature_container.append_child(elem);
            elem = sibling;
        } while (elem != null);
        parent.append_child(signature_container);
    }
    
    private void remove_message(Geary.Email email) {
        if (!messages.contains(email))
            return;
        
        WebKit.DOM.HTMLElement element = email_to_element.get(email.id);
        email_to_element.unset(email.id);
        
        try {
            if (element.get_parent_element() != null)
                element.get_parent_element().remove_child(element);
        } catch (Error err) {
            debug("Could not remove message: %s", err.message);
        }
    }

    private string create_header_row(string title, string value, bool important) {
        return """
            <div class="field %s">
                <div class="title">%s</div>
                <div class="value">%s</div>
            </div>""".printf(important ? "important" : "", title, value);
    }

    // Appends a header field to header_text
    private void insert_header(ref string header_text, string _title, string? _value,
        bool important = false) {
        if (Geary.String.is_empty(_value))
            return;
        
        header_text += create_header_row(Geary.HTML.escape_markup(_title),
            Geary.HTML.escape_markup(_value), important);
    }

    private void insert_header_date(ref string header_text, string _title, DateTime _value,
        bool important = false){

        Date.ClockFormat clock_format = GearyApplication.instance.config.clock_format;
        string title = Geary.HTML.escape_markup(_title);
        string value = """
                <span class="hidden_only">%s</span>
                <span class="not_hidden_only">%s</span>
            """.printf(Date.pretty_print(_value, clock_format),
                Date.pretty_print_verbose(_value, clock_format));
        header_text += create_header_row(title, value, important);
    }

    // Appends email address fields to the header.
    private void insert_header_address(ref string header_text, string title,
        Geary.RFC822.MailboxAddresses? addresses, bool important = false) {
        if (addresses == null)
            return;

        int i = 0;
        string value = "";
        Gee.List<Geary.RFC822.MailboxAddress> list = addresses.get_all();
        foreach (Geary.RFC822.MailboxAddress a in list) {
            value += "<a href='mailto:%s'>".printf(Uri.escape_string(a.to_rfc822_string()));
            if (!Geary.String.is_empty(a.name)) {
                value += "<span class='address_name'>%s</span> ".printf(Geary.HTML.escape_markup(a.name));
                value += "<span class='address_value'>%s</span>".printf(Geary.HTML.escape_markup(a.address));
            } else {
                value += "<span class='address_name'>%s</span>".printf(Geary.HTML.escape_markup(a.address));
            }
            value += "</a>";
            
            if (++i < list.size)
                value += ", ";
        }

        header_text += create_header_row(Geary.HTML.escape_markup(title), value, important);
    }
    
    private bool should_show_attachment(Geary.Attachment attachment) {
        // if displayed inline, don't include in attachment list
        if (attachment.content_id in inlined_content_ids)
            return false;
        
        switch (attachment.content_disposition.disposition_type) {
            case Geary.Mime.DispositionType.ATTACHMENT:
                return true;
            
            case Geary.Mime.DispositionType.INLINE:
                return !is_content_type_supported_inline(attachment.content_type);
            
            default:
                assert_not_reached();
        }
    }
    
    private int displayed_attachments(Geary.Email email) {
        int ret = 0;
        foreach (Geary.Attachment attachment in email.attachments) {
            if (should_show_attachment(attachment)) {
                ret++;
            }
        }
        return ret;
    }
    
    private void insert_attachments(WebKit.DOM.HTMLElement email_container,
        Gee.List<Geary.Attachment> attachments) {

        // <div class="attachment_container">
        //     <div class="top_border"></div>
        //     <table class="attachment" data-attachment-id="">
        //         <tr>
        //             <td class="preview">
        //                 <img src="" />
        //             </td>
        //             <td class="info">
        //                 <div class="filename"></div>
        //                 <div class="filesize"></div>
        //             </td>
        //         </tr>
        //     </table>
        // </div>

        try {
            // Prepare the dom for our attachments.
            WebKit.DOM.Document document = web_view.get_dom_document();
            WebKit.DOM.HTMLElement attachment_container =
                Util.DOM.clone_select(document, "#attachment_template");
            WebKit.DOM.HTMLElement attachment_template =
                Util.DOM.select(attachment_container, ".attachment");
            attachment_container.remove_attribute("id");
            attachment_container.remove_child(attachment_template);

            // Create an attachment table for each attachment.
            foreach (Geary.Attachment attachment in attachments) {
                if (!should_show_attachment(attachment)) {
                    continue;
                }
                // Generate the attachment table.
                WebKit.DOM.HTMLElement attachment_table = Util.DOM.clone_node(attachment_template);
                string filename = !attachment.has_supplied_filename ? _("none") : attachment.file.get_basename();
                Util.DOM.select(attachment_table, ".info .filename")
                    .set_inner_text(filename);
                Util.DOM.select(attachment_table, ".info .filesize")
                    .set_inner_text(Files.get_filesize_as_string(attachment.filesize));
                attachment_table.set_attribute("data-attachment-id", attachment.id);

                // Set the image preview and insert it into the container.
                WebKit.DOM.HTMLImageElement img =
                    Util.DOM.select(attachment_table, ".preview img") as WebKit.DOM.HTMLImageElement;
                web_view.set_attachment_src(img, attachment.content_type, attachment.file.get_path(),
                    ATTACHMENT_PREVIEW_SIZE);
                attachment_container.append_child(attachment_table);
            }

            // Append the attachments to the email.
            email_container.append_child(attachment_container);
        } catch (Error error) {
            debug("Failed to insert attachments: %s", error.message);
        }
    }
    
    private void build_message_overlay_label(string? url) {
        message_overlay_label = new Gtk.Label(url);
        message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        message_overlay_label.halign = Gtk.Align.START;
        message_overlay_label.valign = Gtk.Align.END;
        message_overlay_label.realize.connect(on_message_overlay_label_realize);
        message_overlay.add_overlay(message_overlay_label);
    }
    
    // This ensures the overlay's background color matches the background color of the
    // main window
    private void update_message_overlay_label_style() {
        Gtk.Window main_window = GearyApplication.instance.controller.main_window;
        Gdk.RGBA window_background = main_window.get_style_context()
            .get_background_color(Gtk.StateFlags.NORMAL);
        Gdk.RGBA label_background = message_overlay_label.get_style_context()
            .get_background_color(Gtk.StateFlags.NORMAL);
        
        // To prevent an event loop situation, only update the background if it actually changed.
        if (label_background == window_background)
            return;
        
        message_overlay_label.get_style_context().changed.disconnect(
            on_message_overlay_label_style_changed);
        
        message_overlay_label.override_background_color(Gtk.StateFlags.NORMAL, window_background);
        
        message_overlay_label.get_style_context().changed.connect(
            on_message_overlay_label_style_changed);
    }
    
    private void on_message_overlay_label_realize() {
        update_message_overlay_label_style();
    }
    
    private void on_message_overlay_label_style_changed() {
        // The Gtk theme has probably changed - update the label background.
        update_message_overlay_label_style();
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        // Copy the link the user is hovering over.  Note that when the user mouses-out, 
        // this signal is called again with null for both parameters.
        hover_url = url != null ? Uri.unescape_string(url) : null;
        
        if (message_overlay_label == null) {
            if (url == null)
                return;
            build_message_overlay_label(Uri.unescape_string(url));
            message_overlay_label.show();
            return;
        }
        
        if (url == null) {
            message_overlay_label.hide();
            message_overlay_label.label = null;
        } else {
            message_overlay_label.show();
            message_overlay_label.label = Uri.unescape_string(url);
        }
    }
    
    private void on_copy_text() {
        web_view.copy_clipboard();
    }
    
    private void on_copy_link() {
        // Put the current link in clipboard.
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(hover_url, -1);
        clipboard.store();
    }

    private void on_copy_email_address() {
        // Put the current email address in clipboard.
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME))
            clipboard.set_text(hover_url.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1), -1);
        else
            clipboard.set_text(hover_url, -1);
        clipboard.store();
    }
    
    private void on_select_all() {
        web_view.select_all();
    }
    
    private void on_select_message(WebKit.DOM.Element email_element) {
        try {
            web_view.get_dom_document().get_default_view().get_selection().select_all_children(email_element);
        } catch (Error error) {
            warning("Could not make selection: %s", error.message);
        }
    }
    
    private void on_view_source(Geary.Email message) {
        string source = message.header.buffer.to_string() + message.body.buffer.to_string();
        
        try {
            string temporary_filename;
            int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
                out temporary_filename);
            FileUtils.set_contents(temporary_filename, source);
            FileUtils.close(temporary_handle);
            
            // ensure this file is only readable by the user ... this needs to be done after the
            // file is closed
            FileUtils.chmod(temporary_filename, (int) (Posix.S_IRUSR | Posix.S_IWUSR));
            
            string temporary_uri = Filename.to_uri(temporary_filename, null);
            Gtk.show_uri(web_view.get_screen(), temporary_uri, Gdk.CURRENT_TIME);
        } catch (Error error) {
            ErrorDialog dialog = new ErrorDialog(GearyApplication.instance.controller.main_window,
                _("Failed to open default text editor."), error.message);
            dialog.run();
        }
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
    
    public void mark_read() {
        Gee.ArrayList<Geary.EmailIdentifier> emails = new Gee.ArrayList<Geary.EmailIdentifier>();
        WebKit.DOM.Document document = web_view.get_dom_document();
        long scroll_top = document.body.scroll_top;
        long scroll_height = document.document_element.scroll_height;

        foreach (Geary.Email message in messages) {
            try {
                if (message.email_flags.is_unread()) {
                    WebKit.DOM.HTMLElement element = email_to_element.get(message.id);
                    WebKit.DOM.HTMLElement body = (WebKit.DOM.HTMLElement) element.get_elements_by_class_name("body").item(0);
                    if (!element.get_class_list().contains("manual_read") &&
                            body.offset_top + body.offset_height > scroll_top &&
                            body.offset_top + 28 < scroll_top + scroll_height) {  // 28 = 15 padding + 13 first line of text
                        emails.add(message.id);
                        
                        // since it can take some time for the new flags to round-trip back to
                        // ConversationViewer's signal handlers, mark as manually read here
                        mark_manual_read(message.id);
                    }
                }
            } catch (Error error) {
                debug("Problem checking email class: %s", error.message);
            }
        }

        if (emails.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            mark_messages(emails, null, flags);
        }
    }
    
    // State reset.
    private uint on_reset(uint state, uint event, void *user, Object? object) {
        web_view.set_highlight_text_matches(false);
        web_view.allow_collapsing(true);
        web_view.unmark_text_matches();
        
        if (search_folder != null) {
            search_folder = null;
        }
        
        if (conversation_find_bar.visible)
            fsm.do_post_transition(() => { conversation_find_bar.hide(); }, user, object);
        
        return SearchState.NONE;
    }
    
    // Find bar opened.
    private uint on_open_find_bar(uint state, uint event, void *user, Object? object) {
        if (!conversation_find_bar.visible)
            conversation_find_bar.show();
        
        conversation_find_bar.focus_entry();
        web_view.allow_collapsing(false);
        
        return SearchState.FIND;
    }
    
    // Find bar closed.
    private uint on_close_find_bar(uint state, uint event, void *user, Object? object) {
        if (current_folder is Geary.SearchFolder) {
            highlight_search_terms.begin();
            
            return SearchState.SEARCH_FOLDER;
        } else {
            web_view.allow_collapsing(true);
            
            return SearchState.NONE;
        } 
    }
    
    // Search folder entered.
    private uint on_enter_search_folder(uint state, uint event, void *user, Object? object) {
        search_folder = current_folder as Geary.SearchFolder;
        assert(search_folder != null);
        
        return SearchState.SEARCH_FOLDER;
    }
    
    // Sets the current display mode by displaying only the corresponding DIV.
    private void set_mode(DisplayMode mode) {
        select_conversation_timeout_id = 0; // Cancel select timers.
        
        display_mode = mode;
        
        try {
            for(int i = DisplayMode.NONE + 1; i < DisplayMode.COUNT; i++) {
                if ((int) mode != i)
                    web_view.hide_element_by_id(((DisplayMode) i).get_id());
            }
            
            if (mode != DisplayMode.NONE)
                web_view.show_element_by_id(mode.get_id());
        } catch (Error e) {
            debug("Error updating counter: %s", e.message);
        }
    }
    
    private bool in_drafts_folder() {
        return current_folder != null && current_folder.special_folder_type
            == Geary.SpecialFolderType.DRAFTS;
    }
}

