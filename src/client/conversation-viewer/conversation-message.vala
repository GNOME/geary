/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an {@link Geary.RFC822.Message}.
 *
 * This view corresponds to {@link Geary.RFC822.Message}, displaying
 * both the message's headers and body. Any attachments and sub
 * messages are handled by {@link ConversationEmail}, which typically
 * embeds at least one instance of this class.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-message.ui")]
public class ConversationMessage : Gtk.Grid {


    private const string FROM_CLASS = "geary-from";


    internal static inline bool has_distinct_name(
        Geary.RFC822.MailboxAddress address) {
        return (
            !Geary.String.is_empty(address.name) &&
            address.name != address.address
        );
    }


    // Widget used to display sender/recipient email addresses in
    // message header Gtk.FlowBox instances.
    private class AddressFlowBoxChild : Gtk.FlowBoxChild {

        private const string PRIMARY_CLASS = "geary-primary";
        private const string MATCH_CLASS = "geary-match";

        public enum Type { FROM, OTHER; }

        public Geary.RFC822.MailboxAddress address { get; private set; }

        private string search_value;

        public AddressFlowBoxChild(Geary.RFC822.MailboxAddress address,
                                   Type type = Type.OTHER) {
            this.address = address;
            this.search_value = address.address.casefold();

            // We use two label instances here when address has
            // distinct parts so we can dim the secondary part, if
            // any. Ideally, it would be just one label instance in
            // both cases, but we can't yet include CSS classes in
            // Pango markup. See Bug 766763.

            Gtk.Grid address_parts = new Gtk.Grid();

            Gtk.Label primary = new Gtk.Label(null);
            primary.ellipsize = Pango.EllipsizeMode.END;
            primary.set_xalign(0.0f);
            primary.get_style_context().add_class(PRIMARY_CLASS);
            if (type == Type.FROM) {
                primary.get_style_context().add_class(FROM_CLASS);
            }
            address_parts.add(primary);

            if (has_distinct_name(address)) {
                primary.set_text(address.name);

                Gtk.Label secondary = new Gtk.Label(null);
                secondary.ellipsize = Pango.EllipsizeMode.END;
                secondary.set_xalign(0.0f);
                secondary.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                secondary.set_text(address.address);
                address_parts.add(secondary);

                this.search_value = address.name.casefold() + this.search_value;
            } else {
                primary.set_text(address.address);
            }

            // Update prelight state when mouse-overed.
            Gtk.EventBox events = new Gtk.EventBox();
            events.add_events(
                Gdk.EventMask.ENTER_NOTIFY_MASK |
                Gdk.EventMask.LEAVE_NOTIFY_MASK
            );
            events.set_visible_window(false);
            events.enter_notify_event.connect(on_prelight_in_event);
            events.leave_notify_event.connect(on_prelight_out_event);
            events.add(address_parts);

            add(events);
            set_halign(Gtk.Align.START);
            show_all();
        }

        public bool highlight_search_term(string term) {
            bool found = this.search_value.contains(term);
            if (found) {
                get_style_context().add_class(MATCH_CLASS);
            } else {
                get_style_context().remove_class(MATCH_CLASS);
            }
            return found;
        }

        public void unmark_search_terms() {
            get_style_context().remove_class(MATCH_CLASS);
        }

        private bool on_prelight_in_event(Gdk.Event event) {
            set_state_flags(Gtk.StateFlags.PRELIGHT, false);
            return Gdk.EVENT_STOP;
        }

        private bool on_prelight_out_event(Gdk.Event event) {
            unset_state_flags(Gtk.StateFlags.PRELIGHT);
            return Gdk.EVENT_STOP;
        }

    }

    // Internal class to associate inline image buffers (replaced by
    // rotated scaled versions of them) so they can be saved intact if
    // the user requires it
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
    private const string QUOTE_CONTAINER_CLASS = "geary_quote_container";
    private const string QUOTE_CONTROLLABLE_CLASS = "controllable";
    private const string QUOTE_HIDE_CLASS = "hide";
    private const string SIGNATURE_CONTAINER_CLASS = "geary_signature";
    private const string REPLACED_IMAGE_CLASS = "geary_replaced_inline_image";
    private const string DATA_IMAGE_CLASS = "geary_data_inline_image";
    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;
    private const float QUOTE_SIZE_THRESHOLD = 2.0f;

    private const string ACTION_COPY_EMAIL = "copy_email";
    private const string ACTION_COPY_LINK = "copy_link";
    private const string ACTION_COPY_SELECTION = "copy_selection";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";
    private const string ACTION_OPEN_LINK = "open_link";
    private const string ACTION_SAVE_IMAGE = "save_image";
    private const string ACTION_SEARCH_FROM = "search_from";
    private const string ACTION_SELECT_ALL = "select_all";


    /** The specific RFC822 message displayed by this view. */
    public Geary.RFC822.Message message { get; private set; }

    /** Box containing the preview and full header widgets.  */
    [GtkChild]
    internal Gtk.Grid summary;

    /** Box that InfoBar widgets should be added to. */
    [GtkChild]
    internal Gtk.Grid infobars;

    /** HTML view that displays the message body. */
    internal ConversationWebView web_view { get; private set; }

    [GtkChild]
    private Gtk.Image avatar;

    [GtkChild]
    private Gtk.Revealer preview_revealer;
    [GtkChild]
    private Gtk.Label preview_from;
    [GtkChild]
    private Gtk.Label preview_date;
    [GtkChild]
    private Gtk.Label preview_body;

    [GtkChild]
    private Gtk.Revealer header_revealer;
    [GtkChild]
    private Gtk.FlowBox from;
    [GtkChild]
    private Gtk.Label subject;
    [GtkChild]
    private Gtk.Label date;

    [GtkChild]
    private Gtk.Grid sender_header;
    [GtkChild]
    private Gtk.FlowBox sender_address;

    [GtkChild]
    private Gtk.Grid reply_to_header;
    [GtkChild]
    private Gtk.FlowBox reply_to_addresses;

    [GtkChild]
    private Gtk.Grid to_header;
    [GtkChild]
    private Gtk.Grid cc_header;
    [GtkChild]
    private Gtk.Grid bcc_header;

    [GtkChild]
    private Gtk.Revealer body_revealer;
    [GtkChild]
    public Gtk.Box body; // WebKit.WebView crashes when added to a Grid

    [GtkChild]
    private Gtk.Popover link_popover;
    [GtkChild]
    private Gtk.Label good_link_label;
    [GtkChild]
    private Gtk.Label bad_link_label;

    [GtkChild]
    private Gtk.InfoBar remote_images_infobar;

    // The web_view's context menu
    private Gtk.Menu? context_menu = null;

    // Menu models for creating the context menu
    private MenuModel context_menu_link;
    private MenuModel context_menu_email;
    private MenuModel context_menu_image;
    private MenuModel context_menu_main;
    private MenuModel context_menu_contact;
    private MenuModel? context_menu_inspector = null;

    // Last known DOM element under the context menu
    private WebKit.DOM.HTMLElement? context_menu_element = null;

    // Contains the current mouse-over'ed link URL, if any
    private string? hover_url = null;

    // The contacts for the message's account
    private Geary.ContactStore contact_store;

    // Address fields that can be search through
    private Gee.List<AddressFlowBoxChild> searchable_addresses =
        new Gee.LinkedList<AddressFlowBoxChild>();

    // Should any remote messages be always loaded and displayed?
    private bool always_load_remote_images;

    private int next_replaced_buffer_number = 0;
    private Gee.HashMap<string, ReplacedImage> replaced_images = new Gee.HashMap<string, ReplacedImage>();
    private Gee.HashSet<string> replaced_content_ids = new Gee.HashSet<string>();


    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    /** Fired when an attachment is added for inline display. */
    public signal void attachment_displayed_inline(string id);

    /** Fired when the user requests remote images be loaded. */
    public signal void flag_remote_images();

    /** Fired when the user clicks a link in the email. */
    public signal void link_activated(string link);

    /** Fired when the user requests remote images be always loaded. */
    public signal void remember_remote_images();

    /** Fired when the user saves an inline displayed image. */
    public signal void save_image(string? filename, Geary.Memory.Buffer buffer);

    /** Fired when the user activates a specific search shortcut. */
    public signal void search_activated(string operator, string value);


    /**
     * Constructs a new view to display an RFC 823 message headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage(Geary.RFC822.Message message,
                               Geary.ContactStore contact_store,
                               bool always_load_remote_images) {
        this.message = message;
        this.contact_store = contact_store;
        this.always_load_remote_images = always_load_remote_images;

        // Actions

        add_action(ACTION_COPY_EMAIL, true, VariantType.STRING)
            .activate.connect(on_copy_email_address);
        add_action(ACTION_COPY_LINK, true, VariantType.STRING)
            .activate.connect(on_copy_link);
        add_action(ACTION_COPY_SELECTION, false).activate.connect(() => {
                web_view.copy_clipboard();
            });
        add_action(ACTION_OPEN_INSPECTOR, Args.inspector).activate.connect(() => {
                web_view.web_inspector.inspect_node(this.context_menu_element);
                this.context_menu_element = null;
            });
        add_action(ACTION_OPEN_LINK, true, VariantType.STRING)
            .activate.connect((param) => {
                link_activated(param.get_string());
            });
        add_action(ACTION_SAVE_IMAGE, true).activate.connect((param) => {
                ReplacedImage? replaced_image = get_replaced_image();
                save_image(replaced_image.filename, replaced_image.buffer);
            });
        add_action(ACTION_SEARCH_FROM, true, VariantType.STRING)
            .activate.connect((param) => {
                search_activated("from", param.get_string());
            });
        add_action(ACTION_SELECT_ALL, true).activate.connect(() => {
                web_view.select_all();
            });

        insert_action_group("msg", message_actions);

        // Context menu

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menus.ui"
        );
        context_menu_link = (MenuModel) builder.get_object("context_menu_link");
        context_menu_email = (MenuModel) builder.get_object("context_menu_email");
        context_menu_image = (MenuModel) builder.get_object("context_menu_image");
        context_menu_main = (MenuModel) builder.get_object("context_menu_main");
        context_menu_contact = (MenuModel) builder.get_object("context_menu_contact");
        if (Args.inspector) {
            context_menu_inspector =
                (MenuModel) builder.get_object("context_menu_inspector");
        }

        // Preview headers

        // Translators: This is displayed in place of the from address
        // when the message has no from address.
        string empty_from = _("No sender");

        this.preview_from.set_text(format_originator_preview(empty_from));
        this.preview_from.get_style_context().add_class(FROM_CLASS);

        string date_text = "";
        string date_tooltip = "";
        if (this.message.date != null) {
            Date.ClockFormat clock_format =
                GearyApplication.instance.config.clock_format;
            date_text = Date.pretty_print(
                this.message.date.value, clock_format
            );
            date_tooltip = Date.pretty_print_verbose(
                this.message.date.value, clock_format
            );
        }
        this.preview_date.set_text(date_text);
        this.preview_date.set_tooltip_text(date_tooltip);

        this.preview_body.set_text(
            Geary.String.reduce_whitespace(this.message.get_preview()) + "…"
        );

        // Full headers

        fill_originator_addresses(empty_from);

        this.date.set_text(date_text);
        this.date.set_tooltip_text(date_tooltip);
        if (this.message.subject != null) {
            this.subject.set_text(this.message.subject.value);
            this.subject.set_visible(true);
        }
        fill_header_addresses(this.to_header, this.message.to);
        fill_header_addresses(this.cc_header, this.message.cc);
        fill_header_addresses(this.bcc_header, this.message.bcc);

        // Web view

        this.web_view = new ConversationWebView();
        // Suppress default context menu.
        this.web_view.context_menu.connect(() => { return true; });
        this.web_view.hovering_over_link.connect(on_hovering_over_link);
        this.web_view.link_selected.connect((link) => {
                link_activated(link);
            });
        this.web_view.selection_changed.connect(on_selection_changed);
        this.web_view.show();

        this.body.set_has_tooltip(true); // Used to show link URLs
        this.body.pack_start(this.web_view, true, true, 0);
    }

    public override void destroy() {
        this.context_menu_element = null;
        this.searchable_addresses.clear();
        base.destroy();
    }

    /**
     * Shows the complete message and hides the preview headers.
     */
    public void show_message_body(bool include_transitions=true) {
        set_revealer(this.preview_revealer, false, include_transitions);
        set_revealer(this.header_revealer, true, include_transitions);
        set_revealer(this.body_revealer, true, include_transitions);
    }

    /**
     * Hides the complete message and shows the preview headers.
     */
    public void hide_message_body() {
        preview_revealer.set_reveal_child(true);
        header_revealer.set_reveal_child(false);
        body_revealer.set_reveal_child(false);
    }

    /**
     * Starts loading the avatar for the message's sender.
     */
    public async void load_avatar(Soup.Session session, Cancellable load_cancelled) {
        Geary.RFC822.MailboxAddress? primary = message.get_primary_originator();
        if (primary != null) {
            int window_scale = get_scale_factor();
            int pixel_size = this.avatar.get_pixel_size();
            Soup.Message message = new Soup.Message(
                "GET",
                Gravatar.get_image_uri(
                    primary, Gravatar.Default.NOT_FOUND, pixel_size * window_scale
                )
            );

            try {
                InputStream data =
                    yield session.send_async(message, load_cancelled);
                if (data != null && message.status_code == 200) {
                    yield set_avatar(data, load_cancelled);
                }
            } catch (Error err) {
                debug("Error loading Gravatar response: %s", err.message);
            }
        }
    }

    /**
     * Starts loading the message body in the HTML view.
     */
    public async void load_message_body(Cancellable load_cancelled) {
        string? body_text = null;
        try {
            body_text = (this.message.has_html_body())
                ? this.message.get_html_body(inline_image_replacer)
                : this.message.get_plain_body(true, inline_image_replacer);
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        bool load_images = false;
        body_text = clean_html_markup(
            body_text ?? "", this.message, out load_images
        );

        if (load_images) {
            bool contact_load = false;
            Geary.Contact contact = this.contact_store.get_by_rfc822(
                message.get_primary_originator()
            );
            if (contact != null)
                contact_load = contact.always_load_remote_images();
            if (!contact_load && !this.always_load_remote_images) {
                remote_images_infobar.show();
                load_images = false;
            }
        }

        load_cancelled.cancelled.connect(() => { web_view.stop_loading(); });
        // XXX Hook up unset_controllable_quotes() to size_allocate
        // and check is_height_valid since we need to accurately know
        // what the sizes of the quote and its container is to
        // determine if it should be unhidden. However this means that
        // when the user expands a hidden quote, this handler gets
        // executed again and since the expanded quote will meet the
        // criteria for being unset as controllable, that will
        // happen. That's actually okay for now though, because if the
        // user could collapse the quote again the space wouldn't be
        // reclaimed, which is worse than this.
        this.web_view.size_allocate.connect(() => {
                if (this.web_view.load_status == WebKit.LoadStatus.FINISHED &&
                    this.web_view.is_height_valid) {
                    WebKit.DOM.HTMLElement html = (
                        this.web_view.get_dom_document().document_element as
                        WebKit.DOM.HTMLElement
                    );
                    if (html != null) {
                        try {
                            unset_controllable_quotes(html);
                        } catch (Error error) {
                            warning("Error unsetting controllable_quotes: %s",
                                    error.message);
                        }
                    }
                }
            });
        this.web_view.notify["load-status"].connect((source, param) => {
                if (this.web_view.load_status == WebKit.LoadStatus.FINISHED) {
                    if (load_images) {
                        show_images(false);
                    }
                    Util.DOM.bind_event(
                        this.web_view, "html", "contextmenu",
                        (Callback) on_context_menu, this
                    );
                    Util.DOM.bind_event(
                        this.web_view, "body a", "click",
                        (Callback) on_link_clicked, this
                    );
                    Util.DOM.bind_event(
                        this.web_view, ".%s > .shower".printf(QUOTE_CONTAINER_CLASS),
                        "click",
                        (Callback) on_show_quote_clicked, this);
                    Util.DOM.bind_event(
                        this.web_view, ".%s > .hider".printf(QUOTE_CONTAINER_CLASS),
                        "click",
                        (Callback) on_hide_quote_clicked, this);
                }
            });

        // Only load it after we've hooked up the signals above
        this.web_view.load_string(body_text, "text/html", "UTF-8", "");
    }

    /**
     * Highlights user search terms in the message view.
     &
     * Returns the number of matching search terms.
     */
    public uint highlight_search_terms(Gee.Set<string> search_matches) {
        // Remove existing highlights
        this.web_view.unmark_text_matches();

        uint headers_found = 0;
        uint webkit_found = 0;
        foreach(string raw_match in search_matches) {
            string match = raw_match.casefold();

            debug("Matching: %s", match);

            foreach (AddressFlowBoxChild address in this.searchable_addresses) {
                if (address.highlight_search_term(match)) {
                    ++headers_found;
                }
            }

            webkit_found += this.web_view.mark_text_matches(raw_match, false, 0);
        }

        if (webkit_found > 0) {
            this.web_view.set_highlight_text_matches(true);
        }

        return headers_found + webkit_found;
    }

    /**
     * Disables highlighting of any search terms in the message view.
     */
    public void unmark_search_terms() {
        foreach (AddressFlowBoxChild address in this.searchable_addresses) {
            address.unmark_search_terms();
        }
        web_view.set_highlight_text_matches(false);
        web_view.unmark_text_matches();
    }

    internal string? get_selection_for_quoting() {
        string? quote = null;
        WebKit.DOM.Document document = this.web_view.get_dom_document();
        WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
        if (!selection.is_collapsed) {
            try {
                WebKit.DOM.Range range = selection.get_range_at(0);
                WebKit.DOM.HTMLElement dummy =
                    (WebKit.DOM.HTMLElement) document.create_element("div");
                bool include_dummy = false;
                WebKit.DOM.Node ancestor_node = range.get_common_ancestor_container();
                WebKit.DOM.Element? ancestor = ancestor_node as WebKit.DOM.Element;
                if (ancestor == null)
                    ancestor = ancestor_node.get_parent_element();
                // If the selection is part of a plain text message,
                // we have to stick it in an appropriately styled div,
                // so that new lines are preserved.
                if (Util.DOM.is_descendant_of(ancestor, ".plaintext")) {
                    dummy.get_class_list().add("plaintext");
                    dummy.set_attribute("style", "white-space: pre-wrap;");
                    include_dummy = true;
                }
                dummy.append_child(range.clone_contents());

                // Remove the chrome we put around quotes, leaving
                // only the blockquote element.
                WebKit.DOM.NodeList quotes =
                    dummy.query_selector_all("." + QUOTE_CONTAINER_CLASS);
                for (int i = 0; i < quotes.length; i++) {
                    WebKit.DOM.Element div = (WebKit.DOM.Element) quotes.item(i);
                    WebKit.DOM.Element blockquote = div.query_selector("blockquote");
                    div.get_parent_element().replace_child(blockquote, div);
                }

                quote = include_dummy ? dummy.get_outer_html() : dummy.get_inner_html();
            } catch (Error error) {
                debug("Problem getting selected text: %s", error.message);
            }
        }
        return quote;
    }

    /**
     * Returns the current selection as a string, suitable for find.
     */
    internal string? get_selection_for_find() {
        string? value = null;
        WebKit.DOM.Document document = web_view.get_dom_document();
        WebKit.DOM.DOMWindow window = document.get_default_view();
        WebKit.DOM.DOMSelection selection = window.get_selection();

        if (selection.get_range_count() > 0) {
            try {
                WebKit.DOM.Range range = selection.get_range_at(0);
                value = range.get_text().strip();
                if (value.length <= 0)
                    value = null;
            } catch (Error e) {
                warning("Could not get selected text from web view: %s", e.message);
            }
        }
        return value;
    }

    private SimpleAction add_action(string name, bool enabled, VariantType? type = null) {
        SimpleAction action = new SimpleAction(name, type);
        action.set_enabled(enabled);
        message_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.message_actions.lookup(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private Menu set_action_param_string(MenuModel existing, string value) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            item.set_action_and_target(
                action.get_string(),
                VariantType.STRING.dup_string(),
                value
            );
            menu.append_item(item);
        }
        return menu;
    }

    private Menu set_action_param_strings(MenuModel existing,
                                          Gee.Map<string,string> values) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            string fq_name = action.get_string();
            string name = fq_name.substring(fq_name.index_of(".") + 1);
            item.set_action_and_target(
                fq_name, VariantType.STRING.dup_string(), values[name]
            );
            menu.append_item(item);
        }
        return menu;
    }

    private string format_originator_preview(string empty_from_text) {
        string text = "";
        if (this.message.from != null && this.message.from.size > 0) {
            int i = 0;
            Gee.List<Geary.RFC822.MailboxAddress> list =
                this.message.from.get_all();
            foreach (Geary.RFC822.MailboxAddress addr in list) {
                text += has_distinct_name(addr) ? addr.name : addr.address;

                if (++i < list.size)
                    // Translators: This separates multiple 'from'
                    // addresses in the header preview for a message.
                    text += _(", ");
            }
        } else {
            text = empty_from_text;
        }

        return text;
    }

    private void fill_originator_addresses(string empty_from_text)  {
        // Show any From header addresses
        if (this.message.from != null && this.message.from.size > 0) {
            foreach (Geary.RFC822.MailboxAddress address in this.message.from) {
                AddressFlowBoxChild child = new AddressFlowBoxChild(
                    address, AddressFlowBoxChild.Type.FROM
                );
                this.searchable_addresses.add(child);
                this.from.add(child);
            }
        } else {
            Gtk.Label label = new Gtk.Label(null);
            label.set_text(empty_from_text);

            Gtk.FlowBoxChild child = new Gtk.FlowBoxChild();
            child.add(label);
            child.set_halign(Gtk.Align.START);
            child.show_all();
            this.from.add(child);
        }

        // Show the Sender header addresses if present, but only if
        // not already in the From header.
        if (this.message.sender != null &&
            (this.message.from == null ||
             !this.message.from.contains_normalized(this.message.sender.address))) {
            AddressFlowBoxChild child = new AddressFlowBoxChild(this.message.sender);
            this.searchable_addresses.add(child);
            this.sender_header.show();
            this.sender_address.add(child);
        }

        // Show any Reply-To header addresses if present, but only if
        // each is not already in the From header.
        if (this.message.reply_to != null) {
            foreach (Geary.RFC822.MailboxAddress address in this.message.reply_to) {
                if (this.message.from == null ||
                    !this.message.from.contains_normalized(address.address)) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    this.reply_to_addresses.add(child);
                    this.reply_to_header.show();
                }
            }
        }
    }

    private void fill_header_addresses(Gtk.Grid header,
                                       Geary.RFC822.MailboxAddresses? addresses) {
        if (addresses != null && addresses.size > 0) {
            Gtk.FlowBox box = header.get_children().nth(0).data as Gtk.FlowBox;
            if (box != null) {
                foreach (Geary.RFC822.MailboxAddress address in addresses) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    box.add(child);
                }
            }
            header.set_visible(true);
        }
    }

    private async void set_avatar(InputStream data,
                                  Cancellable load_cancelled)
    throws Error {
        Gdk.Pixbuf avatar_buf =
            yield Gdk.Pixbuf.new_from_stream_async(data, load_cancelled);

        if (avatar_buf != null && !load_cancelled.is_cancelled()) {
            int window_scale = get_scale_factor();
            int avatar_size = this.avatar.pixel_size * window_scale;
            if (avatar_buf.width != avatar_size) {
                avatar_buf = avatar_buf.scale_simple(
                    avatar_size, avatar_size, Gdk.InterpType.BILINEAR
                );
            }
            this.avatar.set_from_surface(
                Gdk.cairo_surface_create_from_pixbuf(
                    avatar_buf, window_scale, get_window()
                )
            );
        }
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

    private string clean_html_markup(string text, Geary.RFC822.Message message, out bool remote_images) {
        remote_images = false;
        try {
            WebKit.DOM.HTMLElement html = (WebKit.DOM.HTMLElement)
                this.web_view.get_dom_document().document_element;

            // If the message has a HTML element, get its inner
            // markup. We can't just set this on a temp container div
            // (the old approach) using set_inner_html() will refuse
            // to parse any HTML, HEAD and BODY elements that are out
            // of place in the structure. We can't use
            // set_outer_html() on the document element since it
            // throws an error.
            GLib.Regex html_regex = new GLib.Regex("<html([^>]*)>(.*)</html>",
                GLib.RegexCompileFlags.DOTALL);
            GLib.MatchInfo matches;
            if (html_regex.match(text, 0, out matches)) {
                // Set the existing HTML element's content. Here, HEAD
                // and BODY elements will be parsed fine.
                html.set_inner_html(matches.fetch(2));
                // Copy email HTML element attrs across to the
                // existing HTML element
                string attrs = matches.fetch(1);
                if (attrs != "") {
                    WebKit.DOM.HTMLElement container =
                        this.web_view.create("div");
                    container.set_inner_html(@"<div$attrs></div>");
                    WebKit.DOM.HTMLElement? attr_element =
                        Util.DOM.select(container, "div");
                    WebKit.DOM.NamedNodeMap html_attrs =
                        attr_element.get_attributes();
                    for (int i = 0; i < html_attrs.get_length(); i++) {
                        WebKit.DOM.Node attr = html_attrs.item(i);
                        html.set_attribute(attr.node_name, attr.text_content);
                    }
                }
            } else {
                html.set_inner_html(text);
            }

            // Set dir="auto" if not already set possibly get a
            // slightly better RTL experience.
            string? dir = html.get_dir();
            if (dir == null || dir.length == 0) {
                html.set_dir("auto");
            }

            // Add application CSS to the document
            WebKit.DOM.HTMLElement? head = Util.DOM.select(html, "head");
            if (head == null) {
                head = this.web_view.create("head");
                html.insert_before(head, html.get_first_child());
            }
            WebKit.DOM.HTMLElement style_element = this.web_view.create("style");
            string css_text = GearyApplication.instance.read_resource("conversation-web-view.css");
            WebKit.DOM.Text text_node = this.web_view.get_dom_document().create_text_node(css_text);
            style_element.append_child(text_node);
            head.insert_before(style_element, head.get_first_child());

            // Get all the top level block quotes and stick them into a hide/show controller.
            WebKit.DOM.NodeList blockquote_list = html.query_selector_all("blockquote");
            for (int i = 0; i < blockquote_list.length; ++i) {
                // Get the nodes we need.
                WebKit.DOM.Node blockquote_node = blockquote_list.item(i);
                WebKit.DOM.Node? next_sibling = blockquote_node.get_next_sibling();
                WebKit.DOM.Node parent = blockquote_node.get_parent_node();

                // Make sure this is a top level blockquote.
                if (Util.DOM.node_is_child_of(blockquote_node, "BLOCKQUOTE")) {
                    continue;
                }

                WebKit.DOM.Element quote_container = create_quote_container();
                Util.DOM.select(quote_container, ".quote").append_child(blockquote_node);
                if (next_sibling == null) {
                    parent.append_child(quote_container);
                } else {
                    parent.insert_before(quote_container, next_sibling);
                }
            }

            // Now look for the signature.
            wrap_html_signature(ref html);

            // Then look for all <img> tags. Inline images are replaced with
            // data URLs.
            WebKit.DOM.NodeList inline_list = html.query_selector_all("img");
            Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();
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
                    img.class_list.add(DATA_IMAGE_CLASS);
                    if (!Geary.String.is_empty(filename))
                        img.set_attribute("alt", filename);
                    
                    // stash here so inlined image isn't listed as attachment (esp. if it has no
                    // Content-Disposition)
                    inlined_content_ids.add(content_id);
                    attachment_displayed_inline(content_id);
                } else {
                    // replaced by data: URI, remove this tag and let the inserted one shine through
                    img.parent_element.remove_child(img);
                }
            }
            
            // Remove any inline images that were referenced through Content-ID
            foreach (string cid in inlined_content_ids) {
                try {
                    string escaped_cid = Geary.HTML.escape_markup(cid);
                    WebKit.DOM.Element? img = html.query_selector(@"[cid='$escaped_cid']");
                    if (img != null)
                        img.parent_element.remove_child(img);
                } catch (Error error) {
                    debug("Error removing inlined image: %s", error.message);
                }
            }
            
            // Now return the whole message.
            return html.get_outer_html();
        } catch (Error e) {
            debug("Error modifying HTML message: %s", e.message);
            return text;
        }
    }

    private WebKit.DOM.HTMLElement create_quote_container() throws Error {
        WebKit.DOM.HTMLElement quote_container = web_view.create("div");
        quote_container.class_list.add(QUOTE_CONTAINER_CLASS);
        quote_container.class_list.add(QUOTE_CONTROLLABLE_CLASS);
        quote_container.class_list.add(QUOTE_HIDE_CLASS);
        // New lines are preserved within blockquotes, so this string
        // needs to be new-line free.
        quote_container.set_inner_html("""<div class="shower"><input type="button" value="▼        ▼        ▼" /></div><div class="hider"><input type="button" value="▲        ▲        ▲" /></div><div class="quote"></div>""");
        return quote_container;
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
        WebKit.DOM.HTMLElement signature_container = web_view.create("div");
        signature_container.class_list.add(SIGNATURE_CONTAINER_CLASS);
        do {
            // Get its sibling _before_ we move it into the signature div.
            WebKit.DOM.Node? sibling = elem.get_next_sibling();
            signature_container.append_child(elem);
            elem = sibling;
        } while (elem != null);
        parent.append_child(signature_container);
    }

    private void unset_controllable_quotes(WebKit.DOM.HTMLElement element) throws GLib.Error {
        WebKit.DOM.NodeList quote_list = element.query_selector_all(
            ".%s.%s".printf(QUOTE_CONTAINER_CLASS, QUOTE_CONTROLLABLE_CLASS)
        );
        for (int i = 0; i < quote_list.length; ++i) {
            WebKit.DOM.Element quote_container = quote_list.item(i) as WebKit.DOM.Element;
            long outer_client_height = quote_container.client_height;
            long scroll_height = quote_container.query_selector(".quote").scroll_height;
            // If the message is hidden, scroll_height will be
            // 0. Otherwise, unhide the full quote if there is not a
            // substantial amount hidden.
            if (scroll_height > 0 &&
                scroll_height <= outer_client_height * QUOTE_SIZE_THRESHOLD) {
                quote_container.class_list.remove(QUOTE_CONTROLLABLE_CLASS);
                quote_container.class_list.remove(QUOTE_HIDE_CLASS);
            }
        }
    }

    private void show_images(bool remember) {
        try {
            WebKit.DOM.Element body = Util.DOM.select(
                web_view.get_dom_document(), "body"
            );
            if (body == null) {
                warning("Could not find message body");
            } else {
                WebKit.DOM.NodeList nodes = body.get_elements_by_tag_name("img");
                for (ulong i = 0; i < nodes.length; i++) {
                    WebKit.DOM.Element? element = nodes.item(i) as WebKit.DOM.Element;
                    if (element == null || !element.has_attribute("src"))
                        continue;

                    string src = element.get_attribute("src");
                    // Don't prefix empty src strings since it will
                    // cause e.g. 0px images (commonly found in
                    // commercial mailouts) to be rendered as broken
                    // images instead of empty elements.
                    if (src.length > 0 && !web_view.is_always_loaded(src)) {
                        // Workaround a WebKitGTK+ 2.4.10 crash. See Bug 763933
                        element.remove_attribute("src");
                        element.set_attribute("src", web_view.allow_prefix + src);
                    }
                }
            }
        } catch (Error error) {
            warning("Error showing images: %s", error.message);
        }

        if (remember) {
            flag_remote_images();
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

    private ReplacedImage? get_replaced_image() {
        ReplacedImage? image = null;
        string? replaced_id = this.context_menu_element.get_attribute(
            "replaced-id"
        );
        this.context_menu_element = null;
        if (!Geary.String.is_empty(replaced_id)) {
            image = replaced_images.get(replaced_id);
        }
        return image;
    }

    private inline void set_revealer(Gtk.Revealer revealer,
                                     bool expand,
                                     bool use_transition) {
        Gtk.RevealerTransitionType transition = revealer.get_transition_type();
        if (!use_transition) {
            revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        revealer.set_reveal_child(expand);
        revealer.set_transition_type(transition);
    }

    [GtkCallback]
    private void on_address_box_child_activated(Gtk.FlowBox box,
                                                Gtk.FlowBoxChild child) {
        AddressFlowBoxChild address_child = child as AddressFlowBoxChild;
        if (address_child != null) {
            address_child.set_state_flags(Gtk.StateFlags.ACTIVE, false);

            Geary.RFC822.MailboxAddress address = address_child.address;
            Gee.Map<string,string> values = new Gee.HashMap<string,string>();
            values[ACTION_OPEN_LINK] =
                Geary.ComposedEmail.MAILTO_SCHEME + address.address;
            values[ACTION_COPY_EMAIL] = address.get_full_address();
            values[ACTION_SEARCH_FROM] = address.address;

            Menu model = new Menu();
            model.append_section(
                null, set_action_param_strings(this.context_menu_email, values)
            );
            model.append_section(
                null, set_action_param_strings(this.context_menu_contact, values)
            );
            Gtk.Popover popover = new Gtk.Popover.from_model(child, model);
            popover.set_position(Gtk.PositionType.BOTTOM);
            popover.closed.connect(() => {
                    address_child.unset_state_flags(Gtk.StateFlags.ACTIVE);
                });
            popover.show();
        }
    }

    private static void on_show_quote_clicked(WebKit.DOM.Element element,
                                              WebKit.DOM.Event event) {
        try {
            ((WebKit.DOM.HTMLElement) element.parent_node).class_list.remove(
                QUOTE_HIDE_CLASS
            );
        } catch (Error error) {
            warning("Error showing quote: %s", error.message);
        }
    }

    private static void on_hide_quote_clicked(WebKit.DOM.Element element,
                                              WebKit.DOM.Event event,
                                              ConversationMessage message) {
        try {
            ((WebKit.DOM.HTMLElement) element.parent_node).class_list.add(
                QUOTE_HIDE_CLASS
            );
            message.web_view.queue_resize();
        } catch (Error error) {
            warning("Error toggling quote: %s", error.message);
        }
    }

    private static void on_context_menu(WebKit.DOM.Element element,
                                        WebKit.DOM.Event event,
                                        ConversationMessage message) {
        message.on_context_menu_self(element, event);
        event.prevent_default();
    }

    private void on_context_menu_self(WebKit.DOM.Element element,
                                      WebKit.DOM.Event event) {
        this.context_menu_element =
             event.get_target() as WebKit.DOM.HTMLElement;
        if (context_menu != null) {
            context_menu.detach();
        }

        // Build a new context menu every time the user clicks because
        // at the moment under GTK+3.20 it's far easier to selectively
        // build a new menu model from pieces as we do here, then to
        // have a single menu model and disable the parts we don't
        // need.
        Menu model = new Menu();
        if (this.hover_url != null) {
            MenuModel link_menu =
                this.hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)
                ? context_menu_email
                : context_menu_link;
            model.append_section(
                null, set_action_param_string(link_menu, this.hover_url)
            );
        }
        if (this.context_menu_element.local_name.down() == "img") {
            ReplacedImage image = get_replaced_image();
            set_action_enabled(ACTION_SAVE_IMAGE, image != null);
            model.append_section(null, context_menu_image);
        }
        model.append_section(null, context_menu_main);
        if (context_menu_inspector != null) {
            model.append_section(null, context_menu_inspector);
        }

        context_menu = new Gtk.Menu.from_model(model);
        context_menu.attach_to_widget(this, null);
        context_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }

    private static void on_link_clicked(WebKit.DOM.Element element,
                                        WebKit.DOM.Event event,
                                        ConversationMessage message) {
        if (message.on_link_clicked_self(element)) {
            event.prevent_default();
        }
    }

    // Check for possible phishing links, displays a popover if found.
    // If not, lets it go through to the default handler.
    private bool on_link_clicked_self(WebKit.DOM.Element element) {
        string? href = element.get_attribute("href");
        if (Geary.String.is_empty(href))
            return false;
        string text = ((WebKit.DOM.HTMLElement) element).get_inner_text();
        string href_short, text_short;
        if (!deceptive_text(href, ref text, out href_short, out text_short))
            return false;

        // Escape text and especially URLs since we got them from the
        // HREF, and Gtk.Label.set_markup is a strict parser.
        good_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", text, text_short)
        );
        bad_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", href, href_short)
        );

        // Work out the link's position, update the popover.
        Gdk.Rectangle link_rect = Gdk.Rectangle();
        web_view.get_allocation(out link_rect);
        WebKit.DOM.Element? offset_parent = element;
        while (offset_parent != null) {
            link_rect.x += (int) offset_parent.offset_left;
            link_rect.y += (int) offset_parent.offset_top;
            offset_parent = offset_parent.offset_parent;
        }
        link_rect.width = (int) element.offset_width;
        link_rect.height = (int) element.offset_height;
        link_popover.set_pointing_to(link_rect);

        link_popover.show();
        return true;
    }

    private void on_hovering_over_link(string? title, string? url) {
        this.hover_url = (url != null) ? Uri.unescape_string(url) : null;

        // Use tooltip on the containing box since the web_view
        // doesn't want to pay ball.
        this.body.set_tooltip_text(this.hover_url);
        this.body.trigger_tooltip_query();
    }

    [GtkCallback]
    private bool on_link_popover_activated() {
        this.link_popover.hide();
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_selection_changed() {
        bool has_selection = false;
        if (web_view.has_selection()) {
            WebKit.DOM.Document document = web_view.get_dom_document();
            has_selection = !document.default_view.get_selection().is_collapsed;
        }
        set_action_enabled(ACTION_COPY_SELECTION, has_selection);
    }

    [GtkCallback]
    private void on_remote_images_response(Gtk.InfoBar info_bar, int response_id) {
        switch (response_id) {
        case 1:
            // Show images for the message
            show_images(true);
            break;
        case 2:
            // Show images for sender
            show_images(false);
            remember_remote_images();
            break;
        default:
            // Pass
            break;
        }

        remote_images_infobar.hide();
    }

    private void on_copy_link(Variant? param) {
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(param.get_string(), -1);
        clipboard.store();
    }

    private void on_copy_email_address(Variant? param) {
        string value = param.get_string();
        if (value.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            value = value.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1);
        }
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(value, -1);
        clipboard.store();
    }

}
