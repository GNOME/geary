/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays the messages in a conversation and in-window composers.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-viewer.ui")]
public class ConversationViewer : Gtk.Stack {

    private const int SELECT_CONVERSATION_TIMEOUT_MSEC = 100;

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

    /**
     * The current conversation listbox, if any.
     */
    public ConversationListBox? current_list {
        get; private set; default = null;
    }

    /**
     * Specifies if a full-height composer is currently shown.
     */
    public bool is_composer_visible {
        get { return (get_visible_child() == this.composer_page); }
    }

    // Stack pages
    [GtkChild]
    private Gtk.Spinner loading_page;
    [GtkChild]
    private Gtk.Grid no_conversations_page;
    [GtkChild]
    private Gtk.Grid conversation_page;
    [GtkChild]
    private Gtk.Grid multiple_conversations_page;
    [GtkChild]
    private Gtk.Grid empty_folder_page;
    [GtkChild]
    private Gtk.Grid empty_search_page;
    [GtkChild]
    private Gtk.Grid composer_page;

    [GtkChild]
    internal Gtk.ScrolledWindow conversation_scroller;

    [GtkChild]
    internal Gtk.SearchBar conversation_find_bar;

    [GtkChild]
    internal Gtk.SearchEntry conversation_find_entry;

    [GtkChild]
    private Gtk.Button conversation_find_next;

    [GtkChild]
    private Gtk.Button conversation_find_prev;

    // State machine setup for search/find modes.
    private Geary.State.MachineDescriptor search_machine_desc = new Geary.State.MachineDescriptor(
        "ConversationViewer search", SearchState.NONE, SearchState.COUNT, SearchEvent.COUNT, null, null); 
    private Geary.State.Machine fsm;

    private uint conversation_timeout_id = 0;

    /* Emitted when a new conversation list was added to this view. */
    public signal void conversation_added(ConversationListBox list);

    /* Emitted when a new conversation list was removed from this view. */
    public signal void conversation_removed(ConversationListBox list);

    /**
     * Constructs a new conversation view instance.
     */
    public ConversationViewer() {
        EmptyPlaceholder no_conversations = new EmptyPlaceholder();
        no_conversations.title = _("No conversations selected");
        no_conversations.subtitle = _(
            "Selecting a conversation from the list will display it here"
        );
        this.no_conversations_page.add(no_conversations);

        EmptyPlaceholder multi_conversations = new EmptyPlaceholder();
        multi_conversations.title = _("Multiple conversations selected");
        multi_conversations.subtitle = _(
            "Choosing an action will apply to all selected conversations"
        );
        this.multiple_conversations_page.add(multi_conversations);

        EmptyPlaceholder empty_folder = new EmptyPlaceholder();
        empty_folder.title = _("No conversations found");
        empty_folder.subtitle = _(
            "This folder does not contain any conversations"
        );
        this.empty_folder_page.add(empty_folder);

        EmptyPlaceholder empty_search = new EmptyPlaceholder();
        empty_search.title = _("No conversations found");
        empty_search.subtitle = _(
            "Your search returned no results, try refining your search terms"
        );
        this.empty_search_page.add(empty_search);

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

        this.conversation_find_bar.notify["search-mode-enabled"].connect(
            on_find_search_started
         );
        // XXX Do this in Glade when possible.
        this.conversation_find_bar.connect_entry(this.conversation_find_entry);

        //conversation_find_bar = new ConversationFindBar(web_view);
        //conversation_find_bar.no_show_all = true;
        //conversation_find_bar.close.connect(() => { fsm.issue(SearchEvent.CLOSE_FIND_BAR); });
        //pack_start(conversation_find_bar, false);
    }

    /**
     * Puts the view into composer mode, showing a full-height composer.
     */
    public void do_compose(ComposerWidget composer) {
        ComposerBox box = new ComposerBox(composer);

        // XXX move the ConversationListView management code into
        // GearyController or somewhere more appropriate
        ConversationListView conversation_list_view =
            ((MainWindow) GearyApplication.instance.controller.main_window).conversation_list_view;
        Gee.Set<Geary.App.Conversation>? prev_selection = conversation_list_view.get_selected_conversations();
        conversation_list_view.get_selection().unselect_all();
        box.vanished.connect((box) => {
                set_visible_child(this.conversation_page);
                if (prev_selection.is_empty) {
                    conversation_list_view.conversations_selected(prev_selection);
                } else {
                    conversation_list_view.select_conversations(prev_selection);
                }
            });
        this.composer_page.add(box);
        set_visible_child(this.composer_page);
    }

    /**
     * Shows the loading UI.
     */
    public void show_loading() {
        set_visible_child(this.loading_page);
    }

    /**
     * Shows the UI when no conversations have been selected
     */
    public void show_none_selected() {
        set_visible_child(this.no_conversations_page);
    }

    /**
     * Shows the UI when multiple conversations have been selected
     */
    public void show_multiple_selected() {
        set_visible_child(this.multiple_conversations_page);
    }

    /**
     * Shows the empty folder UI.
     */
    public void show_empty_folder() {
        set_visible_child(this.empty_folder_page);
    }

   /**
     * Shows the empty search UI.
     */
    public void show_empty_search() {
        set_visible_child(this.empty_search_page);
    }

    /**
     * Shows a conversation in the viewer.
     */
    public async void load_conversation(Geary.App.Conversation conversation,
                                        Geary.Folder location)
        throws Error {
        // If the load is taking too long, display the spinner
        if (this.conversation_timeout_id != 0) {
            Source.remove(this.conversation_timeout_id);
        }
        this.conversation_timeout_id =
            Timeout.add(SELECT_CONVERSATION_TIMEOUT_MSEC, () => {
                if (this.conversation_timeout_id != 0) {
                    debug("Loading timed out\n");
                    // XXX should disable message buttons here, so
                    // need to move this timer to the controller.
                    show_loading();
                }
                this.conversation_timeout_id = 0;
                return false;
            });

        Geary.Account account = location.account;
        ConversationListBox new_list = new ConversationListBox(
            conversation,
            account.get_contact_store(),
            new Geary.App.EmailStore(account),
            account.information,
            location.special_folder_type == Geary.SpecialFolderType.DRAFTS,
            conversation_scroller.get_vadjustment()
        );

        // Need to fire this signal early so the the controller
        // can hook in to its signals to catch any emails added
        // during loading.
        this.conversation_added(new_list);

        yield new_list.load_conversation();

        remove_current_list();
        add_new_list(new_list);
        set_visible_child(this.conversation_page);
        this.conversation_timeout_id = 0;
        if (location is Geary.SearchFolder) {
            yield new_list.load_search_terms((Geary.SearchFolder) location);
        }
    }

    /**
     * Sets the currently visible page of the stack.
     */
    private new void set_visible_child(Gtk.Widget widget) {
        debug("Showing: %s\n", widget.get_name());
        base.set_visible_child(widget);
    }

    // Add a new conversation list to the UI
    private void add_new_list(ConversationListBox list) {
        this.current_list = list;
        list.show();

        // Manually create a Viewport rather than letting
        // ScrolledWindow do it so Container.set_focus_{h,v}adjustment
        // are not set on the list - it makes changing focus jumpy
        // when a row or its web_view are larger than the viewport.
        Gtk.Viewport viewport = new Gtk.Viewport(null, null);
        viewport.show();
        viewport.add(list);

        this.conversation_scroller.add(viewport);
    }

    // Remove any existing conversation list, cancelling its loading
    private void remove_current_list() {
        Gtk.Widget? scrolled_child = this.conversation_scroller.get_child();
        if (scrolled_child != null) {
            scrolled_child.destroy();
        }
        if (this.current_list != null) {
            this.conversation_removed(this.current_list);
            this.current_list = null;
        }
    }

    // State reset.
    private uint on_reset(uint state, uint event, void *user, Object? object) {
        //if (conversation_find_bar.visible)
        //    fsm.do_post_transition(() => { conversation_find_bar.hide(); }, user, object);
        return SearchState.NONE;
    }

    // Search folder entered.
    private uint on_enter_search_folder(uint state, uint event, void *user, Object? object) {
        //search_folder = current_folder as Geary.SearchFolder;
        //assert(search_folder != null);
        return SearchState.SEARCH_FOLDER;
    }

    // Find bar opened.
    private uint on_open_find_bar(uint state, uint event, void *user, Object? object) {
        //if (!conversation_find_bar.visible)
        //    conversation_find_bar.show();
        
        //conversation_find_bar.focus_entry();
        //web_view.allow_collapsing(false);
        
        return SearchState.FIND;
    }
    
    // Find bar closed.
    private uint on_close_find_bar(uint state, uint event, void *user, Object? object) {
        // if (current_folder is Geary.SearchFolder) {
        //     highlight_search_terms.begin();
            
        //     return SearchState.SEARCH_FOLDER;
        // } else {
        //     //web_view.allow_collapsing(true);
            
             return SearchState.NONE;
        // } 
    }

    private void on_find_search_started(Object obj, ParamSpec param) {
        if (this.conversation_find_bar.get_search_mode()) {
            if (this.current_list != null) {
                ConversationEmail? email_view =
                    this.current_list.get_selection_view();
                if (email_view != null) {
                    string text = email_view.get_selection_for_find();
                    if (text != null) {
                        this.conversation_find_entry.set_text(text);
                        this.conversation_find_entry.select_region(0, -1);
                    }
                }
            }
        }
    }

    [GtkCallback]
    private void on_find_search_changed(Gtk.SearchEntry entry) {
        string search = entry.get_text().strip();
        bool have_matches = false;
        if (this.current_list != null) {
            if (search.length > 0) {
                // Have a search string
                Gee.Set<string> search_matches = new Gee.HashSet<string>();
                search_matches.add(search);
                have_matches =
                    this.current_list.highlight_search_terms(search_matches);
            } else {
                // Have no search string
                // if (location is Geary.SearchFolder) {
                //     // Re-display the search results
                //     yield this.current_list.load_search_terms(
                //         (Geary.SearchFolder) location
                //     );
                // } else {
                    this.current_list.unmark_search_terms();
                // }
            }
        }
        this.conversation_find_next.set_sensitive(have_matches);
        this.conversation_find_prev.set_sensitive(have_matches);
    }

    [GtkCallback]
    private void on_find_next(Gtk.Widget entry) {
        if (this.current_list != null) {
            //this.current_list.show_prev_search_term();
        }
    }

    [GtkCallback]
    private void on_find_prev(Gtk.Widget entry) {
        if (this.current_list != null) {
            //this.current_list.show_next_search_term();
        }
    }

}

