/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016,2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays the messages in a conversation and in-window composers.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-viewer.ui")]
public class ConversationViewer : Gtk.Stack, Geary.BaseInterface {

    /**
     * The current conversation listbox, if any.
     */
    public ConversationListBox? current_list {
        get; private set; default = null;
    }

    /** Returns the currently displayed composer if any. */
    public Composer.Widget? current_composer {
        get; private set; default = null;
    }

    /**
     * The most recent web view created in this viewer.
     *
     * Keep the last created web view around so others can share the
     * same WebKitGTK WebProcess.
     */
    internal ConversationWebView? previous_web_view { get; set; default = null; }

    private Application.Configuration config;

    private Gee.Set<Geary.App.Conversation>? selection_while_composing = null;
    private GLib.Cancellable? find_cancellable = null;

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

    private Gtk.ScrolledWindow conversation_scroller;

    [GtkChild]
    internal Gtk.SearchBar conversation_find_bar;

    [GtkChild]
    internal Gtk.SearchEntry conversation_find_entry;
    private Components.EntryUndo conversation_find_undo;

    [GtkChild]
    private Gtk.Button conversation_find_next;

    [GtkChild]
    private Gtk.Button conversation_find_prev;


    /* Emitted when a new conversation list was added to this view. */
    public signal void conversation_added(ConversationListBox list);

    /* Emitted when a new conversation list was removed from this view. */
    public signal void conversation_removed(ConversationListBox list);


    /**
     * Constructs a new conversation view instance.
     */
    public ConversationViewer(Application.Configuration config) {
        base_ref();
        this.config = config;

        Components.PlaceholderPane no_conversations =
            new Components.PlaceholderPane();
        no_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been selected.
        no_conversations.title = _("No conversations selected");
        // Translators: Sub-title label for placeholder when no
        // conversations have been selected.
        no_conversations.subtitle = _(
            "Selecting a conversation from the list will display it here"
        );
        this.no_conversations_page.add(no_conversations);

        Components.PlaceholderPane multi_conversations =
            new Components.PlaceholderPane();
        multi_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.title = _("Multiple conversations selected");
        // Translators: Sub-title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.subtitle = _(
            "Choosing an action will apply to all selected conversations"
        );
        this.multiple_conversations_page.add(multi_conversations);

        Components.PlaceholderPane empty_folder =
            new Components.PlaceholderPane();
        empty_folder.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.title = _("No conversations found");
        // Translators: Sub-title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.subtitle = _(
            "This folder does not contain any conversations"
        );
        this.empty_folder_page.add(empty_folder);

        Components.PlaceholderPane empty_search =
            new Components.PlaceholderPane();
        empty_search.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been found in a search.
        empty_search.title = _("No conversations found");
        // Translators: Sub-title label for placeholder when no
        // conversations have been found in a search.
        empty_search.subtitle = _(
            "Your search returned no results, try refining your search terms"
        );
        this.empty_search_page.add(empty_search);

        this.conversation_find_undo = new Components.EntryUndo(
            this.conversation_find_entry
        );

        // XXX GTK+ Bug 778190 workaround
        new_conversation_scroller();

        // XXX Do this in Glade when possible.
        this.conversation_find_bar.connect_entry(this.conversation_find_entry);
    }

    ~ConversationViewer() {
        base_unref();
    }

    /**
     * Puts the view into composer mode, showing a full-height composer.
     */
    public void do_compose(Composer.Widget composer) {
        var main_window = get_toplevel() as Application.MainWindow;
        if (main_window != null) {
            Composer.Box box = new Composer.Box(
                composer, main_window.main_toolbar
            );
            this.current_composer = composer;

            // XXX move the ConversationListView management code into
            // MainWindow or somewhere more appropriate
            ConversationListView conversation_list = main_window.conversation_list_view;
            this.selection_while_composing = conversation_list.copy_selected();
            conversation_list.get_selection().unselect_all();

            box.vanished.connect(on_composer_closed);
            this.composer_page.add(box);
            set_visible_child(this.composer_page);
            composer.update_window_title();
        }
    }

    /**
     * Puts the view into composer mode, showing an embedded composer.
     */
    public void do_compose_embedded(Composer.Widget composer,
                                    Geary.Email? referred) {
        this.current_composer = composer;
        Composer.Embed embed = new Composer.Embed(
            referred,
            composer,
            this.conversation_scroller
        );
        embed.vanished.connect(on_composer_closed);

        // We need to disable kinetic scrolling so that if it still
        // has some momentum when the composer is inserted and
        // scrolled to, it won't jump away again. See Bug 778027.
        conversation_scroller.kinetic_scrolling = false;

        if (this.current_list != null) {
            this.current_list.add_embedded_composer(
                embed,
                composer.current_draft_id != null
            );
            composer.update_window_title();
        }

        conversation_scroller.kinetic_scrolling = true;
    }

    /**
     * Shows the loading UI.
     */
    public void show_loading() {
        this.loading_page.start();
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

    /** Shows and focuses the find entry. */
    public void enable_find() {
        this.conversation_find_bar.set_search_mode(true);
        this.conversation_find_entry.grab_focus();
    }

    /**
     * Shows a conversation in the viewer.
     */
    public async void load_conversation(Geary.App.Conversation conversation,
                                        Gee.Collection<Geary.EmailIdentifier> scroll_to,
                                        Geary.App.EmailStore store,
                                        Application.ContactStore contacts,
                                        bool start_mark_timer)
        throws GLib.Error {
        // Keep the old ScrolledWindow around long enough for its
        // descendant web views to be kept so their WebProcess can be
        // re-used.
        var old_scroller = remove_current_list();

        ConversationListBox new_list = new ConversationListBox(
            conversation,
            !start_mark_timer,
            store,
            contacts,
            this.config,
            this.conversation_scroller.get_vadjustment()
        );

        // Need to fire this signal early so the the controller
        // can hook in to its signals to catch any emails added
        // during loading.
        this.conversation_added(new_list);

        // Also set up find infrastructure early so matching emails
        // are expanded and highlighted as they are added.
        this.conversation_find_next.set_sensitive(false);
        this.conversation_find_prev.set_sensitive(false);
        new_list.search.matches_updated.connect((count) => {
                bool found = count > 0;
                this.conversation_find_entry.set_icon_from_icon_name(
                    Gtk.EntryIconPosition.PRIMARY,
                    found || Geary.String.is_empty(this.conversation_find_entry.text)
                    ? "edit-find-symbolic" : "computer-fail-symbolic"
                );
                this.conversation_find_next.set_sensitive(found);
                this.conversation_find_prev.set_sensitive(found);
            });
        add_new_list(new_list);
        set_visible_child(this.conversation_page);

        // Highlight matching terms from find if active, otherwise
        // from the search folder if that's where we are at
        Geary.SearchQuery? query = yield get_find_search_query(
            conversation.base_folder.account, null
        );
        if (query == null) {
            var search_folder = conversation.base_folder as Geary.SearchFolder;
            if (search_folder != null) {
                query = search_folder.query;
            }
        }

        yield new_list.load_conversation(scroll_to, query);

        // Not strictly necessary, but keeps the compiler happy
        old_scroller.destroy();
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
    private Gtk.ScrolledWindow remove_current_list() {
        if (this.find_cancellable != null) {
            this.find_cancellable.cancel();
            this.find_cancellable = null;
        }

        if (this.current_list != null) {
            this.current_list.cancel_conversation_load();
            this.conversation_removed(this.current_list);
            this.current_list = null;
        }

        var old_scroller = this.conversation_scroller;
        // XXX GTK+ Bug 778190 workaround
        this.conversation_page.remove(old_scroller);
        new_conversation_scroller();
        return old_scroller;
    }

    private void new_conversation_scroller() {
        // XXX Work around for GTK+ Bug 778190: Instead of replacing
        // the Viewport that contains the current list, replace the
        // complete ScrolledWindow. Need to remove this method and
        // put the settings back into conversation-viewer.ui when we
        // can rely on it being fixed again.
        Gtk.ScrolledWindow scroller = new Gtk.ScrolledWindow(null, null);
        scroller.get_style_context().add_class("geary-conversation-scroller");
        scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scroller.set_hexpand(true);
        scroller.set_vexpand(true);
        scroller.show();
        scroller.scroll_event.connect(
            on_conversation_scroll
        );
        scroller.get_vscrollbar().button_release_event.connect(
            on_conversation_scroll
        );
        this.conversation_scroller = scroller;
        this.conversation_page.add(scroller);

    }

    /**
     * Sets the currently visible page of the stack.
     */
    private new void set_visible_child(Gtk.Widget widget) {
        debug("Showing: %s", widget.get_name());
        Gtk.Widget current = get_visible_child();
        if (current == this.conversation_page) {
            if (widget != this.conversation_page) {
                // By removing the current list, any load it is currently
                // performing is also cancelled, which is important to
                // avoid a possible crit warning when switching folders,
                // etc.
                remove_current_list();
            }
        } else if (current == this.loading_page) {
            // Stop the spinner running so it doesn't trigger repaints
            // and wake up Geary even when idle. See Bug 783025.
            this.loading_page.stop();
        }
        base.set_visible_child(widget);
    }

    private async void update_find_results() {
        ConversationListBox? list = this.current_list;
        if (list != null) {
            if (this.find_cancellable != null) {
                this.find_cancellable.cancel();
            }
            GLib.Cancellable cancellable = new GLib.Cancellable();
            cancellable.cancelled.connect(() => {
                    list.search.cancel();
                });
            this.find_cancellable = cancellable;
            try {
                Geary.SearchQuery? query = yield get_find_search_query(
                    list.conversation.base_folder.account,
                    cancellable
                );
                if (query != null) {
                    yield list.search.highlight_matching_email(query, true);
                }
            } catch (GLib.Error err) {
                warning("Error updating find results: %s", err.message);
            }
        }
    }

    private async Geary.SearchQuery? get_find_search_query(Geary.Account account,
                                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.SearchQuery? query = null;
        if (this.conversation_find_bar.get_search_mode()) {
            string text = this.conversation_find_entry.get_text().strip();
            // Require find string of at least two chars to avoid
            // opening every message in the conversation as soon as
            // the user presses a key
            if (text.length >= 2) {
                var strategy = this.config.get_search_strategy();
                query = yield account.new_search_query(
                    text,
                    strategy,
                    cancellable
                );
            }
        }
        return query;
    }

    [GtkCallback]
    private void on_find_mode_changed(Object obj, ParamSpec param) {
        if (this.current_list != null) {
            if (this.conversation_find_bar.get_search_mode()) {
                // Find became enabled
                ConversationEmail? email_view =
                    this.current_list.get_selection_view();
                if (email_view != null) {
                    email_view.get_selection_for_find.begin((obj, res) => {
                            string text = email_view.get_selection_for_find.end(res);
                            if (text != null) {
                                this.conversation_find_entry.set_text(text);
                                this.conversation_find_entry.select_region(0, -1);
                            }
                        });
                }
            } else {
                // Find became disabled, re-show search terms if any
                this.current_list.search.unmark_terms();
                Geary.SearchFolder? search_folder = (
                    this.current_list.conversation.base_folder
                    as Geary.SearchFolder
                );
                this.conversation_find_undo.reset();
                if (search_folder != null) {
                    Geary.SearchQuery? query = search_folder.query;
                    if (query != null) {
                        this.current_list.search.highlight_matching_email.begin(
                            query,
                            true
                        );
                    }
                }
            }
        }
    }

    [GtkCallback]
    private void on_find_text_changed(Gtk.SearchEntry entry) {
        this.conversation_find_next.set_sensitive(false);
        this.conversation_find_prev.set_sensitive(false);
        this.update_find_results.begin();
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

    private bool on_conversation_scroll() {
        if (this.current_list != null) {
            this.current_list.mark_visible_read();
        }
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_composer_closed() {
        this.current_composer = null;
        if (get_visible_child() == this.composer_page) {
            set_visible_child(this.conversation_page);

            // Restore the old selection
            var main_window = get_toplevel() as Application.MainWindow;
            if (main_window != null) {
                main_window.update_title();

                if (this.selection_while_composing != null) {
                    var conversation_list = main_window.conversation_list_view;
                    if (this.selection_while_composing.is_empty) {
                        conversation_list.conversations_selected(
                            this.selection_while_composing
                        );
                    } else {
                        conversation_list.select_conversations(
                            this.selection_while_composing
                        );
                    }

                    this.selection_while_composing = null;
                }
            }
        }
    }

}
