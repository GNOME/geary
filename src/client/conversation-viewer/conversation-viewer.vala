/*
 * Copyright 2022 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
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
     * The current conversation list.
     */
    public ConversationEmailList current_list;

    /** Returns the currently displayed composer if any. */
    public Composer.Widget? current_composer {
        get; private set; default = null;
    }

    private ConversationEmailList? email_list = null;

    private Application.Configuration config;

    private GLib.Cancellable? load_cancellable = null;

    private ulong load_changed_handler_id = 0;

    // Stack pages
    [GtkChild] private unowned Gtk.Spinner loading_page;
    [GtkChild] private unowned Gtk.Grid no_conversations_page;
    [GtkChild] private unowned Gtk.Grid conversation_page;
    [GtkChild] private unowned Gtk.Grid multiple_conversations_page;
    [GtkChild] private unowned Gtk.Grid empty_folder_page;
    [GtkChild] private unowned Gtk.Grid empty_search_page;
    [GtkChild] private unowned Gtk.Grid composer_page;

    [GtkChild] internal unowned Gtk.SearchBar conversation_find_bar;

    [GtkChild] internal unowned Gtk.SearchEntry conversation_find_entry;
    private Components.EntryUndo conversation_find_undo;

    [GtkChild] private unowned Gtk.Button conversation_find_next;

    [GtkChild] private unowned Gtk.Button conversation_find_prev;


    /* Emitted when a new conversation list was added to this view. */
    public signal void conversation_added(ConversationEmailList list);

    /* Emitted when a new conversation list was removed from this view. */
    public signal void conversation_removed(ConversationEmailList list);

    static construct {
        set_css_name("geary-conversation-viewer");
    }

    /**
     * Constructs a new conversation view instance.
     */
    public ConversationViewer(Application.Configuration config) {
        base_ref();
        this.config = config;

        Hdy.StatusPage no_conversations =
            new Hdy.StatusPage();
        no_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been selected.
        no_conversations.title = _("No Conversations Selected");
        // Translators: Sub-title label for placeholder when no
        // conversations have been selected.
        no_conversations.description = _(
            "Selecting a conversation from the list will display it here."
        );
        no_conversations.hexpand = true;
        no_conversations.vexpand = true;
        no_conversations.show ();
        this.no_conversations_page.add(no_conversations);

        Hdy.StatusPage multi_conversations =
            new Hdy.StatusPage();
        multi_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.title = _("Multiple Conversations Selected");
        // Translators: Sub-title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.description = _(
            "Choosing an action will apply to all selected conversations."
        );
        multi_conversations.hexpand = true;
        multi_conversations.vexpand = true;
        multi_conversations.show ();
        this.multiple_conversations_page.add(multi_conversations);

        Hdy.StatusPage empty_folder =
            new Hdy.StatusPage();
        empty_folder.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.title = _("No Conversations Found");
        // Translators: Sub-title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.description = _(
            "This folder does not contain any conversations."
        );
        empty_folder.hexpand = true;
        empty_folder.vexpand = true;
        empty_folder.show ();
        this.empty_folder_page.add(empty_folder);

        Hdy.StatusPage empty_search =
            new Hdy.StatusPage();
        empty_search.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been found in a search.
        empty_search.title = _("No Conversations Found");
        // Translators: Sub-title label for placeholder when no
        // conversations have been found in a search.
        empty_search.description = _(
            "Your search returned no results, try refining your search terms."
        );
        empty_search.hexpand = true;
        empty_search.vexpand = true;
        empty_search.show ();
        this.empty_search_page.add(empty_search);

        this.conversation_find_undo = new Components.EntryUndo(
            this.conversation_find_entry
        );


        this.email_list = new ConversationEmailList(
            this.config
        );
        this.email_list.hexpand = true;
        this.email_list.vexpand = true;
        this.email_list.show();
        this.conversation_page.add(this.email_list);

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
                composer, main_window.conversation_headerbar
            );
            this.current_composer = composer;

            // XXX move the ConversationEmailListView management code into
            // MainWindow or somewhere more appropriate
            /*ConversationEmailList.View conversation_list = main_window.conversation_list_view;
            this.selection_while_composing = conversation_list.selected;
            conversation_list.unselect_all();
*/
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
        /*this.current_composer = composer;
        Composer.Embed embed = new Composer.Embed(
            referred,
            composer,
            this.conversation_scroller
        );
        embed.vanished.connect(on_composer_closed);

        if (this.current_list != null) {
            this.current_list.add_embedded_composer(
                embed,
                composer.saved_id != null
            );
            composer.update_window_title();
        }

        if (kinetic) this.conversation_scroller.kinetic_scrolling = true;

        // Set a minimal composer height
        composer.set_size_request(
            -1, this.conversation_scroller.get_allocated_height() / 3 * 2
        );*/
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

        if (this.load_cancellable != null) {
            this.load_cancellable.cancel();
        }
        this.load_cancellable = new GLib.Cancellable();

        if (this.load_changed_handler_id != 0) {
            this.email_list.disconnect(this.load_changed_handler_id);
        }

        set_visible_child(this.conversation_page);

        this.load_changed_handler_id = this.email_list.load_changed.connect(
            (event) => {
                if (event == WebKit.LoadEvent.FINISHED) {
                    this.email_list.load_conversation.begin(
                        conversation,
                        store,
                        contacts,
                        start_mark_timer,
                        scroll_to,
                        this.load_cancellable,
                        null
                    );
                }
            }
        );

        this.email_list.load_html(
            GioUtil.read_resource("conversation-viewer.html")
        );
    }

    [GtkCallback]
    private void on_find_mode_changed(Object obj, ParamSpec param) {
    }

    [GtkCallback]
    private void on_find_text_changed(Gtk.SearchEntry entry) {
        this.conversation_find_next.set_sensitive(false);
        this.conversation_find_prev.set_sensitive(false);
    }

    [GtkCallback]
    private void on_find_next(Gtk.Widget entry) {
    }

    [GtkCallback]
    private void on_find_prev(Gtk.Widget entry) {
    }

    private void on_composer_closed() {
    }
}


